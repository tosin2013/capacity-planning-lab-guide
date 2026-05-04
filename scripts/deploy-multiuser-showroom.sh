#!/usr/bin/env bash
# scripts/deploy-multiuser-showroom.sh
#
# Creates per-student Showroom instances on the hub cluster.
# Each student gets a dedicated namespace (showroom-hub-capacity-user-N) with:
#   - wetty SSH auto-login pointing to their own bastion
#   - showroom-userdata configmap with their own OCP + bastion credentials
#   - A unique route at showroom-showroom-hub-capacity-user-N.apps.hub.*
#
# Idempotent: uses "oc apply" so it is safe to re-run.
#
# Usage:
#   ./scripts/deploy-multiuser-showroom.sh [--hub-guid HUB_GUID] [--students N] [--dry-run]

set -euo pipefail

# ── Defaults ──────────────────────────────────────────────────────────────────
HUB_GUID="${HUB_GUID:-hub-capacity}"
SANDBOX="${SANDBOX:-sandbox3967}"
STUDENT_COUNT="${STUDENT_COUNT:-3}"
DRY_RUN=false

OUTPUT_DIR="${HOME}/agnosticd-v2-output"

# ── Argument parsing ───────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --hub-guid)  HUB_GUID="$2";     shift 2 ;;
    --sandbox)   SANDBOX="$2";      shift 2 ;;
    --students)  STUDENT_COUNT="$2"; shift 2 ;;
    --dry-run)   DRY_RUN=true;      shift   ;;
    *) echo "Unknown flag: $1"; exit 1 ;;
  esac
done

HUB_KC="${OUTPUT_DIR}/${HUB_GUID}/openshift-cluster_${HUB_GUID}_kubeconfig"
HUB_BASE_NS="showroom-${HUB_GUID}"
HUB_INGRESS_DOMAIN="apps.hub.${HUB_GUID}.${SANDBOX}.opentlc.com"

# ── Helper: extract a field from a YAML file ─────────────────────────────────
yaml_get() {
  local file="$1"
  local key="$2"
  { grep -m1 "^${key}:" "${file}" 2>/dev/null || true; } \
    | sed "s/^${key}:[[:space:]]*//" \
    | sed "s/^['\"]//;s/['\"]$//" \
    | tr -d '\r'
}

# ── Verify hub kubeconfig ──────────────────────────────────────────────────────
if [[ ! -f "${HUB_KC}" ]]; then
  echo "ERROR: hub kubeconfig not found at ${HUB_KC}"
  exit 1
fi

# ── Read shared hub attributes ────────────────────────────────────────────────
HUB_DATA="${OUTPUT_DIR}/${HUB_GUID}/provision-user-data.yaml"
if [[ ! -f "${HUB_DATA}" ]]; then
  echo "ERROR: hub provision-user-data.yaml not found at ${HUB_DATA}"
  exit 1
fi

HUB_API_URL=$(yaml_get "${HUB_DATA}" "hub_api_url")
HUB_CONSOLE_URL=$(yaml_get "${HUB_DATA}" "openshift_console_url")
HUB_RHACM_URL=$(yaml_get "${HUB_DATA}" "hub_rhacm_url")
HUB_RHACM_CONSOLE=$(yaml_get "${HUB_DATA}" "hub_rhacm_console")
HUB_PASSWORD=$(yaml_get "${HUB_DATA}" "hub_password")
HUB_GITOPS_URL=$(yaml_get "${HUB_DATA}" "openshift_gitops_server")
HUB_INGRESS=$(yaml_get "${HUB_DATA}" "cluster_ingress_domain")
HUB_GRAFANA_URL=$(yaml_get "${HUB_DATA}" "hub_grafana_url")
HUB_DEV_GRAFANA_URL=$(yaml_get "${HUB_DATA}" "hub_dev_grafana_url")
# hub_rhacm_console is the value used for {rhacm_console} in the lab guide
RHACM_CONSOLE="${HUB_RHACM_CONSOLE:-${HUB_RHACM_URL}}"
: "${HUB_API_URL:?hub_api_url not found in ${HUB_DATA}}"

# ── Read container images from existing Showroom deployment ───────────────────
OC="oc --kubeconfig ${HUB_KC}"
NGINX_IMAGE=$(${OC} get deployment showroom -n "${HUB_BASE_NS}" \
  -o jsonpath='{.spec.template.spec.containers[?(@.name=="nginx")].image}')
CONTENT_IMAGE=$(${OC} get deployment showroom -n "${HUB_BASE_NS}" \
  -o jsonpath='{.spec.template.spec.containers[?(@.name=="content")].image}')
WETTY_IMAGE=$(${OC} get deployment showroom -n "${HUB_BASE_NS}" \
  -o jsonpath='{.spec.template.spec.containers[?(@.name=="wetty")].image}')
GIT_REPO_URL=$(${OC} get deployment showroom -n "${HUB_BASE_NS}" \
  -o jsonpath='{.spec.template.spec.containers[?(@.name=="content")].env[?(@.name=="GIT_REPO_URL")].value}')
GIT_REPO_REF=$(${OC} get deployment showroom -n "${HUB_BASE_NS}" \
  -o jsonpath='{.spec.template.spec.containers[?(@.name=="content")].env[?(@.name=="GIT_REPO_REF")].value}')
ANTORA_PLAYBOOK=$(${OC} get deployment showroom -n "${HUB_BASE_NS}" \
  -o jsonpath='{.spec.template.spec.containers[?(@.name=="content")].env[?(@.name=="ANTORA_PLAYBOOK")].value}')

echo "=== deploy-multiuser-showroom.sh ==="
echo "Hub GUID        : ${HUB_GUID}"
echo "Students        : ${STUDENT_COUNT}"
echo "Hub API         : ${HUB_API_URL}"
echo "Git repo        : ${GIT_REPO_URL} @ ${GIT_REPO_REF}"
echo "Dry run         : ${DRY_RUN}"
echo ""

# ── Deploy per-student Showroom ────────────────────────────────────────────────
for i in $(seq 1 "${STUDENT_COUNT}"); do
  STUDENT_GUID="student-$(printf '%02d' "${i}")"
  USER_NUM="${i}"
  NAMESPACE="${HUB_BASE_NS}-user-${USER_NUM}"
  HUB_USERNAME="user-${USER_NUM}"
  SHOWROOM_HOST="showroom-${NAMESPACE}.${HUB_INGRESS_DOMAIN}"
  SHOWROOM_URL="https://${SHOWROOM_HOST}/"

  echo "──────────────────────────────────────────────────────────────────────"
  echo "Student ${USER_NUM}: ${STUDENT_GUID} → namespace ${NAMESPACE}"
  echo "  Showroom URL: ${SHOWROOM_URL}"

  # Read per-student data
  STUDENT_DATA="${OUTPUT_DIR}/${STUDENT_GUID}/provision-user-data.yaml"
  if [[ ! -f "${STUDENT_DATA}" ]]; then
    echo "  WARNING: ${STUDENT_DATA} not found — skipping student ${USER_NUM}"
    continue
  fi

  BASTION_HOST=$(yaml_get "${STUDENT_DATA}" "bastion_public_hostname")
  BASTION_USER=$(yaml_get "${STUDENT_DATA}" "bastion_ssh_user_name")
  BASTION_PASS=$(yaml_get "${STUDENT_DATA}" "bastion_ssh_password")
  OCP_API_URL=$(yaml_get "${STUDENT_DATA}" "openshift_api_url")
  OCP_CONSOLE_URL=$(yaml_get "${STUDENT_DATA}" "openshift_console_url")
  OCP_INGRESS=$(yaml_get "${STUDENT_DATA}" "openshift_cluster_ingress_domain")

  if [[ -z "${BASTION_HOST}" ]]; then
    echo "  WARNING: bastion_public_hostname empty in ${STUDENT_DATA} — skipping"
    continue
  fi

  echo "  Bastion     : ${BASTION_HOST} (user: ${BASTION_USER})"
  echo "  OCP API     : ${OCP_API_URL}"

  if [[ "${DRY_RUN}" == "true" ]]; then
    echo "  [dry-run] would create namespace ${NAMESPACE} and deploy Showroom"
    continue
  fi

  # ── 1. Namespace ──────────────────────────────────────────────────────────
  ${OC} apply -f - <<YAML
apiVersion: v1
kind: Namespace
metadata:
  name: ${NAMESPACE}
  labels:
    app.kubernetes.io/managed-by: deploy-multiuser-showroom
YAML

  # ── 2. showroom-proxy-config (nginx.conf — same for all, uses localhost) ──
  ${OC} apply -f - <<YAML
apiVersion: v1
kind: ConfigMap
metadata:
  name: showroom-proxy-config
  namespace: ${NAMESPACE}
data:
  nginx.conf: |
    #daemon off;
    events {
    }
    error_log /dev/stdout info;
    http {
      include /etc/nginx/mime.types;
      proxy_cache off;
      expires -1;
      proxy_cache_path /dev/null keys_zone=mycache:10m;

      map \$http_upgrade \$connection_upgrade {
          default upgrade;
          '' close;
      }

      server {
        listen 8080;
        absolute_redirect off;

        location / {
          index index.html;
          root /data/www;
        }

        location /content/ {
          proxy_pass http://localhost:8000;
          rewrite ^/content/(.*)\$ /\$1 break;
          expires off;
          proxy_cache off;
          proxy_pass_request_headers on;
          proxy_set_header Accept-Encoding "gzip";
          proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto \$scheme;
        }

        location ^~ /wetty {
          proxy_pass http://localhost:8001/wetty;
          proxy_http_version 1.1;
          proxy_set_header Upgrade \$http_upgrade;
          proxy_set_header Connection "upgrade";
          proxy_read_timeout 43200000;
          proxy_set_header X-Real-IP \$remote_addr;
          proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
          proxy_set_header Host \$http_host;
          proxy_set_header X-NginX-Proxy true;
        }
      }
    }
YAML

  # ── 3. showroom-userdata (per-student credentials injected into Antora) ───
  # Build user_data.yml as a flat quoted YAML map (Antora attribute format).
  # Keys must match the {attribute} names used in the AsciiDoc modules:
  #   {student-cluster-bastion}, {student-cluster-password}, {student-cluster-api},
  #   {student-cluster-console}, {bastion_hostname}, {hub_grafana_url}, etc.
  USER_DATA_YML="# ── Student identity ────────────────────────────────────────────
\"guid\": \"${STUDENT_GUID}\"
\"cluster_domain\": \"${OCP_INGRESS}\"
# ── Student cluster access ({student-cluster-*} AsciiDoc attrs) ─
\"student-cluster-bastion\": \"${BASTION_HOST}\"
\"student-cluster-password\": \"${BASTION_PASS}\"
\"student-cluster-api\": \"${OCP_API_URL}\"
\"student-cluster-console\": \"${OCP_CONSOLE_URL}\"
\"student-cluster-ingress-domain\": \"${OCP_INGRESS}\"
# ── Quick Access Links table attrs ───────────────────────────────
\"openshift_console\": \"${OCP_CONSOLE_URL}\"
\"rhacm_console\": \"${RHACM_CONSOLE}\"
\"grafana_url\": \"${HUB_GRAFANA_URL}\"
# ── Aliases used by older / alternate module references ──────────
\"bastion_hostname\": \"${BASTION_HOST}\"
\"bastion_public_hostname\": \"${BASTION_HOST}\"
\"bastion_ssh_password\": \"${BASTION_PASS}\"
\"bastion_ssh_user_name\": \"${BASTION_USER}\"
\"openshift_api_url\": \"${OCP_API_URL}\"
\"openshift_console_url\": \"${OCP_CONSOLE_URL}\"
\"openshift_cluster_ingress_domain\": \"${OCP_INGRESS}\"
# ── Hub cluster attributes (shared across all students) ──────────
\"hub_api_url\": \"${HUB_API_URL}\"
\"hub_console_url\": \"${HUB_CONSOLE_URL}\"
\"hub_password\": \"${HUB_PASSWORD}\"
\"hub_rhacm_url\": \"${HUB_RHACM_URL}\"
\"hub_username\": \"${HUB_USERNAME}\"
\"hub_grafana_url\": \"${HUB_GRAFANA_URL}\"
\"hub_dev_grafana_url\": \"${HUB_DEV_GRAFANA_URL}\""

  ${OC} create configmap showroom-userdata \
    --namespace "${NAMESPACE}" \
    --from-literal="user_data.yml=${USER_DATA_YML}" \
    --dry-run=client -o yaml | ${OC} apply -f -

  # ── 4. showroom-index (index.html pointing to this student's showroom URL) ─
  ${OC} apply -f - <<YAML
apiVersion: v1
kind: ConfigMap
metadata:
  name: showroom-index
  namespace: ${NAMESPACE}
data:
  index.html: |
    <!DOCTYPE html>
    <html>
      <head>
        <title>Strategic Capacity Planning &amp; Forecasting for OpenShift — Student ${USER_NUM}</title>
        <meta http-equiv="content-type" content="text/html; charset=UTF-8" />
        <link rel="stylesheet" type="text/css" href="split.css">
        <link rel="stylesheet" type="text/css" href="tabs.css">
      </head>
      <body>
        <div class="content">
          <div class="split left">
            <iframe id="doc" src="https://${SHOWROOM_HOST}/content" width="100%" style="border:none;"></iframe>
          </div>
          <div class="split right">
            <div class="tab">
              <button class="tablinks" onclick="openTerminal(event, 'wetty_tab1')" id="defaultOpen" tabindex="0">Login Terminal 1</button>
            </div>
            <div id="wetty_tab1" class="tabcontent">
              <iframe id="terminal_01" src="https://${SHOWROOM_HOST}/wetty" width="100%" style="border:none;"></iframe>
            </div>
          </div>
        </div>
        <script>
          document.getElementById("defaultOpen").click();
          function openTerminal(evt, tabName) {
            var i, tabcontent, tablinks;
            tabcontent = document.getElementsByClassName("tabcontent");
            for (i = 0; i < tabcontent.length; i++) { tabcontent[i].style.display = "none"; }
            tablinks = document.getElementsByClassName("tablinks");
            for (i = 0; i < tablinks.length; i++) { tablinks[i].className = tablinks[i].className.replace(" active", ""); }
            document.getElementById(tabName).style.display = "block";
            evt.currentTarget.className += "active";
          }
        </script>
        <script src="https://unpkg.com/split.js/dist/split.min.js"></script>
        <script>
          Split(['.left', '.right'], { sizes: [45,55] });
          Split(['.top', '.bottom'], { sizes: [65,35], direction: 'vertical' });
        </script>
      </body>
    </html>
  split.css: |
    * { box-sizing: border-box; height:100%; }
    body { margin: 0; height:100%; }
    .content { width:100%; height:100%; padding:0; display:flex; justify-items:center; align-items:center; border-top:1px solid; border-color:Gainsboro; border-top-width:thin; margin-top:0; }
    .split { width:100%; height:100%; padding:5px; }
    .left { height:100% }
    .right { height:100% }
    .gutter { height:98%; background-color:#eee; background-repeat:no-repeat; background-position:50%; }
    .gutter.gutter-horizontal { background-image:url('data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAUAAAAeCAYAAADkftS9AAAAIklEQVQoU2M4c+bMfxAGAgYYmwGrIIiDjrELjpo5aiZeMwF+yNnOs5KSvgAAAABJRU5ErkJggg=='); cursor:col-resize; }
    .gutter.gutter-vertical { background-image:url('data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAB4AAAAFAQMAAABo7865AAAABlBMVEVHcEzMzMzyAv2sAAAAAXRSTlMAQObYZgAAABBJREFUeF5jOAMEEAIEEFwAn3kMwcB6I2AAAAAASUVORK5CYII='); cursor:row-resize; }
  tabs.css: |
    .tab { overflow:hidden; border:1px solid #ccc; background-color:#f1f1f1; height:50px; }
    .tab button { background-color:inherit; float:left; border:none; outline:none; cursor:pointer; padding:14px 16px; transition:0.3s; }
    .tab button:hover { background-color:#ddd; }
    .tab button.active { background-color:#ccc; }
    .tabcontent { display:none; padding:6px 12px; border:1px solid #ccc; border-top:none; height:calc(100% - 50px); }
YAML

  # ── 5. Deployment ─────────────────────────────────────────────────────────
  ${OC} apply -f - <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: showroom
  namespace: ${NAMESPACE}
  labels:
    app.kubernetes.io/name: showroom
spec:
  replicas: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: showroom
  template:
    metadata:
      labels:
        app.kubernetes.io/name: showroom
    spec:
      containers:
        - name: nginx
          image: ${NGINX_IMAGE}
          imagePullPolicy: IfNotPresent
          env:
            - name: NAMESPACE
              valueFrom:
                fieldRef:
                  fieldPath: metadata.namespace
          ports:
            - containerPort: 8080
          resources:
            requests:
              cpu: 50m
              memory: 64Mi
            limits:
              cpu: 200m
              memory: 256Mi
          volumeMounts:
            - name: nginx-config
              mountPath: /etc/nginx/nginx.conf
              subPath: nginx.conf
            - name: content
              mountPath: /data/www
            - name: nginx-cache
              mountPath: /var/cache/nginx
            - name: nginx-pid
              mountPath: /var/run
        - name: content
          image: ${CONTENT_IMAGE}
          imagePullPolicy: IfNotPresent
          env:
            - name: GIT_REPO_URL
              value: "${GIT_REPO_URL}"
            - name: GIT_REPO_REF
              value: "${GIT_REPO_REF}"
            - name: ANTORA_PLAYBOOK
              value: "${ANTORA_PLAYBOOK}"
          resources:
            requests:
              cpu: 50m
              memory: 128Mi
            limits:
              cpu: 500m
              memory: 512Mi
          volumeMounts:
            - name: user-data
              mountPath: /user_data/
            - name: showroom
              mountPath: /showroom/
        - name: wetty
          image: ${WETTY_IMAGE}
          imagePullPolicy: IfNotPresent
          args:
            - "--base=/wetty/"
            - "--port=8001"
            - "--ssh-host=${BASTION_HOST}"
            - "--ssh-port=22"
            - "--ssh-user=${BASTION_USER}"
            - "--ssh-auth=password"
            - "--ssh-pass=${BASTION_PASS}"
          env:
            - name: NAMESPACE
              valueFrom:
                fieldRef:
                  fieldPath: metadata.namespace
            - name: GUID
              value: "${HUB_GUID}"
          ports:
            - containerPort: 8001
          resources:
            requests:
              cpu: 50m
              memory: 256Mi
            limits:
              cpu: 500m
              memory: 1Gi
      volumes:
        - name: showroom
          emptyDir: {}
        - name: user-data
          configMap:
            name: showroom-userdata
        - name: content
          configMap:
            name: showroom-index
        - name: nginx-config
          configMap:
            name: showroom-proxy-config
        - name: nginx-pid
          emptyDir: {}
        - name: nginx-cache
          emptyDir: {}
YAML

  # ── 6. Service ────────────────────────────────────────────────────────────
  ${OC} apply -f - <<YAML
apiVersion: v1
kind: Service
metadata:
  name: showroom
  namespace: ${NAMESPACE}
spec:
  selector:
    app.kubernetes.io/name: showroom
  ports:
    - port: 8080
      targetPort: 8080
      protocol: TCP
YAML

  # ── 7. Route ──────────────────────────────────────────────────────────────
  ${OC} apply -f - <<YAML
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: showroom
  namespace: ${NAMESPACE}
spec:
  host: ${SHOWROOM_HOST}
  port:
    targetPort: 8080
  tls:
    insecureEdgeTerminationPolicy: Redirect
    termination: edge
  to:
    kind: Service
    name: showroom
    weight: 100
  wildcardPolicy: None
YAML

  echo "  ✓ Resources applied for student ${USER_NUM}"
done

echo ""
echo "=== Waiting for Showroom pods to become Ready ==="
for i in $(seq 1 "${STUDENT_COUNT}"); do
  NAMESPACE="${HUB_BASE_NS}-user-${i}"
  if [[ "${DRY_RUN}" == "true" ]]; then
    echo "  [dry-run] would wait for ${NAMESPACE}"
    continue
  fi
  echo -n "  Waiting for ${NAMESPACE} ... "
  if ${OC} rollout status deployment/showroom -n "${NAMESPACE}" --timeout=120s 2>/dev/null; then
    echo "Ready"
  else
    echo "WARNING: deployment not ready within 120s — check 'oc get pods -n ${NAMESPACE}'"
  fi
done

echo ""
echo "=== Per-Student Showroom URLs ==="
for i in $(seq 1 "${STUDENT_COUNT}"); do
  STUDENT_GUID="student-$(printf '%02d' "${i}")"
  NAMESPACE="${HUB_BASE_NS}-user-${i}"
  SHOWROOM_URL="https://showroom-${NAMESPACE}.${HUB_INGRESS_DOMAIN}/"
  echo "  Student ${i} (${STUDENT_GUID} / user-${i}):  ${SHOWROOM_URL}"
done

echo ""
echo "Done. Run scripts/generate-student-info.sh to update student-info.txt with new URLs."
