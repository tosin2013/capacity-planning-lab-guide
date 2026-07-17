#!/usr/bin/env bash
# deploy-workshop.sh
# ============================================================
# Idempotent provisioning script for the Capacity Planning
# Workshop hub-student topology.
#
# Safe to re-run: clusters whose provision-user-data.yaml
# already contains the OCP marker field are skipped.
#
# First-run bootstrap: if ~/agnosticd-v2-vars/ is missing or
# empty, this script copies the templates from deploy/vars/ and
# exits with instructions so you can customise them before
# re-running.
#
# Usage:
#   bash scripts/deploy-workshop.sh [OPTIONS]
#
# Options:
#   --account      ACCOUNT      AgnosticD account name (default: sandbox1139)
#   --hub-guid     GUID         Hub GUID              (default: hub-capacity)
#   --students     "01 02 03"   Space-separated slots (default: "01 02 03 04 05")
#   --skip-hub                  Skip hub provision entirely
#   --skip-showroom             Skip the multi-user Showroom deployment step
#   --dry-run                   Print agd commands without executing them
#   -h, --help                  Show this help
#
# Examples:
#   # Full deploy — hub + 5 students
#   bash scripts/deploy-workshop.sh --account sandbox1139
#
#   # Re-run after quota increase (hub already done, fix students only)
#   bash scripts/deploy-workshop.sh --account sandbox1139 --skip-hub
#
#   # Preview what would run without actually running it
#   bash scripts/deploy-workshop.sh --account sandbox1139 --dry-run
# ============================================================

set -euo pipefail

# ── Defaults ─────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
_cfg="${REPO_ROOT}/deploy/config.yml"
_cfg_get() { grep "^${1}:" "$_cfg" 2>/dev/null | awk '{print $2}' || true; }

ACCOUNT="${ACCOUNT:-$(_cfg_get account)}"
ACCOUNT="${ACCOUNT:-sandbox1139}"
HUB_GUID="${HUB_GUID:-$(_cfg_get hub_guid)}"
HUB_GUID="${HUB_GUID:-hub-capacity}"
_num="${NUM_STUDENTS:-$(_cfg_get num_students)}"
STUDENT_SLOTS="${STUDENT_SLOTS:-$(printf '%02d ' $(seq 1 "${_num:-5}") | sed 's/ $//')}"
SKIP_HUB=false
SKIP_SHOWROOM=false
DRY_RUN=false

_agd_root="$(_cfg_get agnosticd_root)"
AGD_DIR="${AGD_DIR:-${_agd_root:-${HOME}/agnosticd-v2}}"
AGD_DIR="${AGD_DIR/#\~/$HOME}"
OUTPUT_ROOT="${HOME}/agnosticd-v2-output"
MAIN_LOG="/tmp/deploy-workshop.log"

# ── Helpers ───────────────────────────────────────────────────
log() {
  local msg="[$(date '+%Y-%m-%d %H:%M:%S UTC')] $*"
  echo "${msg}"
  echo "${msg}" >> "${MAIN_LOG}"
}

log_section() {
  log "====== $* ======"
}

die() {
  log "ERROR: $*"
  exit 1
}

# Check if a cluster output dir has the success marker field
is_provisioned() {
  local guid="$1"
  local marker="$2"
  grep -q "^${marker}:" \
    "${OUTPUT_ROOT}/${guid}/provision-user-data.yaml" 2>/dev/null
}

# Run agd provision (or print if --dry-run)
run_provision() {
  local guid="$1"
  local config="$2"
  local cluster_log="/tmp/deploy-${guid}.log"

  log "Provisioning ${guid} (config: ${config}) — log: ${cluster_log}"

  if [[ "${DRY_RUN}" == true ]]; then
    log "[DRY-RUN] cd ${AGD_DIR} && bin/agd provision --guid ${guid} --config ${config} --account ${ACCOUNT}"
    return 0
  fi

  (cd "${AGD_DIR}" && bin/agd provision \
    --guid "${guid}" \
    --config "${config}" \
    --account "${ACCOUNT}") \
    2>&1 | tee -a "${cluster_log}" | tee -a "${MAIN_LOG}"

  return "${PIPESTATUS[0]}"
}

# ── Argument parsing ──────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --account)        ACCOUNT="$2";       shift 2 ;;
    --hub-guid)       HUB_GUID="$2";      shift 2 ;;
    --students)       STUDENT_SLOTS="$2"; shift 2 ;;
    --skip-hub)       SKIP_HUB=true;      shift ;;
    --skip-showroom)  SKIP_SHOWROOM=true; shift ;;
    --dry-run)        DRY_RUN=true;       shift ;;
    -h|--help)
      sed -n '3,25p' "${BASH_SOURCE[0]}"
      exit 0
      ;;
    *)
      die "Unknown argument: $1. Run with --help for usage."
      ;;
  esac
done

# ── Pre-flight checks ─────────────────────────────────────────
log_section "Pre-flight checks"

STUDENT_COUNT=$(echo "${STUDENT_SLOTS}" | wc -w | tr -d ' ')

# 1. Vars files — auto-bootstrap from repo templates if missing.
#    This runs FIRST so a new deployer gets a helpful setup message
#    before any AWS or secrets checks.
VARS_DIR="${HOME}/agnosticd-v2-vars"
TEMPLATE_DIR="${REPO_ROOT}/deploy/vars"
NEEDS_CUSTOMISATION=false

bootstrap_var_file() {
  local src="$1"   # template path in deploy/vars/
  local dst="$2"   # destination path in ~/agnosticd-v2-vars/
  if [[ ! -f "${dst}" ]]; then
    log "Bootstrapping ${dst} from template ${src}"
    mkdir -p "$(dirname "${dst}")"
    cp "${src}" "${dst}"
    NEEDS_CUSTOMISATION=true
  fi
}

if [[ "${SKIP_HUB}" == false ]]; then
  bootstrap_var_file "${TEMPLATE_DIR}/hub-aws.yml" "${VARS_DIR}/hub-aws.yml"
fi

for SLOT in ${STUDENT_SLOTS}; do
  STUDENT_VARS="${VARS_DIR}/student-${SLOT}.yml"
  if [[ ! -f "${STUDENT_VARS}" ]]; then
    bootstrap_var_file "${TEMPLATE_DIR}/student.yml" "${STUDENT_VARS}"
    # Set the correct guid and user slot in the freshly copied file
    # Use a non-anchored end so trailing comments are preserved
    sed -i "s/^guid: student-01/guid: student-${SLOT}/" "${STUDENT_VARS}"
    SLOT_NUM="${SLOT#0}"   # strip leading zero: 01→1, 02→2
    sed -i "s/hub_user_slot: \"user-1\"/hub_user_slot: \"user-${SLOT_NUM}\"/" "${STUDENT_VARS}"
  fi
done

if [[ "${NEEDS_CUSTOMISATION}" == true ]]; then
  # Try to auto-substitute from deploy/config.yml (written by make setup)
  CONFIG_FILE="${REPO_ROOT}/deploy/config.yml"
  if [[ -f "${CONFIG_FILE}" ]]; then
    OWNER_EMAIL=$(grep '^owner_email:' "${CONFIG_FILE}" | awk '{print $2}')
    if [[ -n "${OWNER_EMAIL}" ]]; then
      log "Auto-applying owner_email (${OWNER_EMAIL}) from deploy/config.yml"
      for VAR_FILE in "${VARS_DIR}/hub-aws.yml" "${VARS_DIR}"/student-*.yml; do
        [[ -f "${VAR_FILE}" ]] || continue
        sed -i "s/<YOUR_EMAIL>/${OWNER_EMAIL}/" "${VAR_FILE}"
      done
      log "Var files customized automatically — continuing deployment."
      NEEDS_CUSTOMISATION=false
    fi
  fi
fi

if [[ "${NEEDS_CUSTOMISATION}" == true ]]; then
  log ""
  log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  log "  FIRST-RUN SETUP: var file templates have been copied to:"
  log "    ${VARS_DIR}/"
  log ""
  log "  Run 'make setup' to configure automatically, or manually:"
  log "    1. Edit each file and replace <YOUR_EMAIL> with your email."
  log "    2. After provisioning the hub, update the hub_rhacm_url in each"
  log "       student-NN.yml (paste from hub provision-user-data.yaml)."
  log ""
  log "  Once all files are customised, re-run:"
  log "    bash scripts/deploy-workshop.sh --account ${ACCOUNT}"
  log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  exit 0
fi

# All var files present — auto-fix placeholders from config if possible
CONFIG_FILE="${REPO_ROOT}/deploy/config.yml"
OWNER_EMAIL=""
if [[ -f "${CONFIG_FILE}" ]]; then
  OWNER_EMAIL=$(grep '^owner_email:' "${CONFIG_FILE}" | awk '{print $2}')
fi

for VAR_FILE in "${VARS_DIR}/hub-aws.yml" "${VARS_DIR}"/student-*.yml; do
  [[ -f "${VAR_FILE}" ]] || continue
  if grep -q "<YOUR_EMAIL>" "${VAR_FILE}" 2>/dev/null; then
    if [[ -n "${OWNER_EMAIL}" ]]; then
      sed -i "s/<YOUR_EMAIL>/${OWNER_EMAIL}/" "${VAR_FILE}"
      log "Auto-fixed <YOUR_EMAIL> in ${VAR_FILE}"
    else
      log "WARNING: ${VAR_FILE} still contains placeholder values."
      log "         Run 'make setup' or edit it manually before provisioning."
    fi
  fi
done
log "Vars files: all present — OK"

# 2. agnosticd-v2 directory
[[ -x "${AGD_DIR}/bin/agd" ]] \
  || die "agd not found at ${AGD_DIR}/bin/agd. Clone agnosticd-v2 first."

# 3. AWS credentials
aws sts get-caller-identity --output text > /dev/null 2>&1 \
  || die "AWS credentials invalid or not configured. Check ~/.aws/credentials."
log "AWS credentials: OK"

# 4. Secrets file
SECRETS_FILE="${HOME}/agnosticd-v2-secrets/secrets-${ACCOUNT}.yml"
[[ -f "${SECRETS_FILE}" ]] \
  || die "Secrets file not found: ${SECRETS_FILE}"
log "Secrets file: ${SECRETS_FILE} — OK"

# 4a. Pull secret check — must be present and not the placeholder value.
#     agd loads TWO secrets files (account-specific first, then secrets.yml).
#     Both must have a real pull secret; secrets.yml is loaded last and wins
#     if it still has the placeholder, overriding the account-specific value.
#     The OCP installer fails ~7 min in with a cryptic error — catch it here.
GENERIC_SECRETS="${HOME}/agnosticd-v2-secrets/secrets.yml"
for _sf in "${SECRETS_FILE}" "${GENERIC_SECRETS}"; do
  [[ -f "${_sf}" ]] || continue
  if ! grep -q "^ocp4_pull_secret:" "${_sf}"; then
    log ""
    log "ERROR: ocp4_pull_secret is missing from ${_sf}"
    log ""
    log "  Get your pull secret at: https://console.redhat.com/openshift/install/pull-secret"
    log "  Then add this line to ${_sf}:"
    log "    ocp4_pull_secret: '<paste full JSON here>'"
    log ""
    exit 1
  fi
  if grep -q "ocp4_pull_secret: '<YOUR_PULL_SECRET_JSON>'\|ocp4_pull_secret: '<Add Your Pull Secret here>'" "${_sf}"; then
    log ""
    log "ERROR: ocp4_pull_secret in ${_sf} is still the placeholder value."
    log ""
    log "  Get your pull secret at: https://console.redhat.com/openshift/install/pull-secret"
    log "  Replace the placeholder with the full JSON blob."
    log ""
    exit 1
  fi
done
log "Pull secret: present in all secrets files — OK"

# 5. VPC quota check
# Each cluster needs 2 VPCs (bastion + OCP); calculate required minimum
CLUSTERS=$(( 1 + STUDENT_COUNT ))
REQUIRED_VPCS=$(( CLUSTERS * 2 ))

CURRENT_VPC_QUOTA=$(aws service-quotas get-service-quota \
  --region us-east-2 \
  --service-code vpc \
  --quota-code L-F678F1CE \
  --query 'Quota.Value' \
  --output text 2>/dev/null || echo "0")

CURRENT_VPC_QUOTA="${CURRENT_VPC_QUOTA%.*}"  # strip decimal

if (( CURRENT_VPC_QUOTA < REQUIRED_VPCS )); then
  log "ERROR: VPC quota is ${CURRENT_VPC_QUOTA}, but ${REQUIRED_VPCS} are needed"
  log "       for ${CLUSTERS} clusters (hub + ${STUDENT_COUNT} students)."
  log ""
  log "Request a quota increase to at least ${REQUIRED_VPCS} via AWS CLI:"
  log "  aws service-quotas request-service-quota-increase \\"
  log "    --region us-east-2 --service-code vpc --quota-code L-F678F1CE \\"
  log "    --desired-value ${REQUIRED_VPCS}"
  log ""
  log "Also increase EC2-VPC Elastic IPs (need ${REQUIRED_VPCS} × 2 = $(( REQUIRED_VPCS * 2 ))):"
  log "  aws service-quotas request-service-quota-increase \\"
  log "    --region us-east-2 --service-code ec2 --quota-code L-0263D0A3 \\"
  log "    --desired-value $(( REQUIRED_VPCS * 2 ))"
  exit 1
fi
log "VPC quota: ${CURRENT_VPC_QUOTA} (need ${REQUIRED_VPCS}) — OK"

log "Pre-flight passed. DRY_RUN=${DRY_RUN}"
log ""

# ── Hub provisioning ──────────────────────────────────────────
log_section "Hub cluster (${HUB_GUID})"

if [[ "${SKIP_HUB}" == true ]]; then
  log "Hub: --skip-hub flag set, skipping."
elif is_provisioned "${HUB_GUID}" "hub_api_url"; then
  log "Hub: already provisioned (hub_api_url found). Skipping."
else
  log "Hub: provisioning now (90–120 min expected)..."
  if run_provision "${HUB_GUID}" "hub-aws"; then
    log "Hub: provision complete."
  else
    die "Hub provision failed. Check /tmp/deploy-${HUB_GUID}.log for details."
  fi
fi

# ── Student provisioning ──────────────────────────────────────
FAILED_STUDENTS=()

for SLOT in ${STUDENT_SLOTS}; do
  SGUID="student-${SLOT}"
  log_section "Student cluster (${SGUID})"

  if is_provisioned "${SGUID}" "openshift_console_url"; then
    log "${SGUID}: already provisioned (openshift_console_url found). Skipping."
    continue
  fi

  log "${SGUID}: provisioning now (60–75 min expected)..."
  if run_provision "${SGUID}" "student-${SLOT}"; then
    log "${SGUID}: provision complete."
  else
    log "WARNING: ${SGUID} provision failed (exit $?). Check /tmp/deploy-${SGUID}.log."
    FAILED_STUDENTS+=("${SGUID}")
  fi
done

# ── Post-provision: verify sample-apps ArgoCD sync ───────────
# Ensures the capacity-planning-workshop-sample-apps Application on each
# student cluster has synced and all deployments are healthy.  The Helm
# chart now sets automated.selfHeal=false so ArgoCD auto-deploys on first
# provision but never reverts student exercise changes.  This step is a
# safety net for environments where the chart is still at the old revision
# (no automated sync) or where the first sync hasn't completed yet.
log_section "Verifying sample-apps ArgoCD sync on all student clusters"

for SLOT in ${STUDENT_SLOTS}; do
  SGUID="student-${SLOT}"
  SKC="${OUTPUT_ROOT}/${SGUID}/openshift-cluster_${SGUID}_kubeconfig"

  if [[ ! -f "${SKC}" ]]; then
    log "${SGUID}: kubeconfig not found — skipping ArgoCD check"
    continue
  fi

  APP="capacity-planning-workshop-sample-apps"
  NS_GITOPS="openshift-gitops"

  # Ensure the Application has automated sync (idempotent patch)
  if [[ "${DRY_RUN}" == "true" ]]; then
    log "${SGUID}: [dry-run] would patch ${APP} to add automated sync"
    continue
  fi

  log "${SGUID}: ensuring ${APP} has automated sync policy..."
  oc patch application "${APP}" -n "${NS_GITOPS}" \
    --kubeconfig "${SKC}" \
    --type merge \
    -p '{"spec":{"syncPolicy":{"automated":{"prune":false,"selfHeal":false},"syncOptions":["CreateNamespace=true"]}}}' \
    2>/dev/null || log "  WARNING: could not patch ${APP} on ${SGUID}"

  # Trigger a hard refresh so ArgoCD re-evaluates immediately
  oc annotate application "${APP}" -n "${NS_GITOPS}" \
    --kubeconfig "${SKC}" \
    argocd.argoproj.io/refresh=hard --overwrite \
    2>/dev/null || true

  # Wait up to 3 minutes for the Application to become Healthy
  log "${SGUID}: waiting for ${APP} to become Healthy (up to 3 min)..."
  DEADLINE=$(( $(date +%s) + 180 ))
  HEALTH=""
  while [[ $(date +%s) -lt ${DEADLINE} ]]; do
    HEALTH=$(oc get application "${APP}" -n "${NS_GITOPS}" \
      --kubeconfig "${SKC}" \
      -o jsonpath='{.status.health.status}' 2>/dev/null || echo "")
    [[ "${HEALTH}" == "Healthy" ]] && break
    sleep 10
  done

  if [[ "${HEALTH}" == "Healthy" ]]; then
    log "${SGUID}: ${APP} is Healthy ✓"
  else
    log "WARNING: ${SGUID}: ${APP} health=${HEALTH:-unknown} after timeout."
    log "         Run: oc get application ${APP} -n ${NS_GITOPS} --kubeconfig ${SKC}"
    FAILED_STUDENTS+=("${SGUID}-argocd")
  fi
done

# ── Post-provision: RHACM import ─────────────────────────────
# Imports each student cluster as a ManagedCluster on the hub so that
# RHACM Observability can collect metrics and populate Grafana dashboards.
# This is idempotent: already-joined clusters are detected and skipped.
log_section "Importing student clusters into RHACM"

HKC="${OUTPUT_ROOT}/${HUB_GUID}/openshift-cluster_${HUB_GUID}_kubeconfig"

if [[ ! -f "${HKC}" ]]; then
  log "WARNING: hub kubeconfig not found (${HKC}) — skipping RHACM import"
else
  for SLOT in ${STUDENT_SLOTS}; do
    SGUID="student-${SLOT}"
    SKC="${OUTPUT_ROOT}/${SGUID}/openshift-cluster_${SGUID}_kubeconfig"

    if [[ ! -f "${SKC}" ]]; then
      log "${SGUID}: kubeconfig missing — skipping RHACM import"
      continue
    fi

    JOINED=$(oc get managedcluster "${SGUID}" \
      --kubeconfig "${HKC}" \
      -o jsonpath='{.status.conditions[?(@.type=="ManagedClusterConditionAvailable")].status}' \
      2>/dev/null || true)

    if [[ "${JOINED}" == "True" ]]; then
      log "${SGUID}: already joined RHACM ✓"
      continue
    fi

    if [[ "${DRY_RUN}" == "true" ]]; then
      log "${SGUID}: [dry-run] would create ManagedCluster and apply import YAML"
      continue
    fi

    log "${SGUID}: creating ManagedCluster on hub..."
    oc apply -f - --kubeconfig "${HKC}" 2>/dev/null <<YAML
apiVersion: cluster.open-cluster-management.io/v1
kind: ManagedCluster
metadata:
  name: ${SGUID}
  labels:
    cloud: Amazon
    vendor: OpenShift
    demo.redhat.com/application: capacity-workshop
spec:
  hubAcceptsClient: true
  leaseDurationSeconds: 60
YAML

    # Wait up to 60s for RHACM to auto-create the cluster namespace
    NS_READY=false
    for i in {1..12}; do
      NS=$(oc get namespace "${SGUID}" --kubeconfig "${HKC}" \
        -o jsonpath='{.status.phase}' 2>/dev/null || true)
      [[ "${NS}" == "Active" ]] && NS_READY=true && break
      sleep 5
    done

    if [[ "${NS_READY}" != "true" ]]; then
      log "WARNING: ${SGUID}: namespace not Active after 60s — skipping addon config"
      FAILED_STUDENTS+=("${SGUID}-rhacm-ns")
      continue
    fi

    oc apply -f - --kubeconfig "${HKC}" 2>/dev/null <<YAML
apiVersion: agent.open-cluster-management.io/v1
kind: KlusterletAddonConfig
metadata:
  name: ${SGUID}
  namespace: ${SGUID}
spec:
  clusterName: ${SGUID}
  clusterNamespace: ${SGUID}
  clusterLabels:
    cloud: Amazon
    vendor: OpenShift
  applicationManager:
    enabled: false
  certPolicyController:
    enabled: false
  iamPolicyController:
    enabled: false
  policyController:
    enabled: false
  searchCollector:
    enabled: false
  observabilityController:
    enabled: true
YAML

    # Wait up to 90s for the import secret
    IMPORT_SECRET=""
    for i in {1..18}; do
      IMPORT_SECRET=$(oc get secret "${SGUID}-import" -n "${SGUID}" \
        --kubeconfig "${HKC}" \
        -o jsonpath='{.data.import\.yaml}' 2>/dev/null || true)
      [[ -n "${IMPORT_SECRET}" ]] && break
      sleep 5
    done

    if [[ -z "${IMPORT_SECRET}" ]]; then
      log "WARNING: ${SGUID}: import secret not ready after 90s"
      FAILED_STUDENTS+=("${SGUID}-rhacm-secret")
      continue
    fi

    # Apply CRDs then import to student cluster
    CRDS_B64=$(oc get secret "${SGUID}-import" -n "${SGUID}" \
      --kubeconfig "${HKC}" \
      -o jsonpath='{.data.crds\.yaml}' 2>/dev/null || true)

    [[ -n "${CRDS_B64}" ]] && \
      echo "${CRDS_B64}" | base64 -d | oc apply -f - --kubeconfig "${SKC}" 2>/dev/null || true

    sleep 5

    echo "${IMPORT_SECRET}" | base64 -d | oc apply -f - --kubeconfig "${SKC}" 2>/dev/null || true

    log "${SGUID}: import applied — waiting for cluster to join (up to 3 min)..."
    DEADLINE=$(( $(date +%s) + 180 ))
    AVAIL=""
    while [[ $(date +%s) -lt ${DEADLINE} ]]; do
      AVAIL=$(oc get managedcluster "${SGUID}" \
        --kubeconfig "${HKC}" \
        -o jsonpath='{.status.conditions[?(@.type=="ManagedClusterConditionAvailable")].status}' \
        2>/dev/null || true)
      [[ "${AVAIL}" == "True" ]] && break
      sleep 10
    done

    if [[ "${AVAIL}" == "True" ]]; then
      log "${SGUID}: joined RHACM ✓"
    else
      log "WARNING: ${SGUID}: not Available after timeout — may need manual re-import"
      FAILED_STUDENTS+=("${SGUID}-rhacm-join")
    fi
  done
fi

# ── Post-import: Grafana Layer 2 RBAC ────────────────────────
# Creates per-cluster RoleBinding/workshop-obs-view-<user> in each
# managed cluster namespace so rbac-query-proxy includes those clusters
# in student Grafana sessions.  Without this, students only see
# local-cluster in the Grafana cluster dropdown even though metrics
# are flowing correctly to Thanos.
if [[ "${DRY_RUN}" == true ]]; then
  log "[DRY-RUN] would run: bash scripts/provision-grafana-student-access.sh \\"
  log "  --count ${STUDENT_COUNT} --hub-kubeconfig <HKC> --no-restart"
elif [[ ! -f "${HKC}" ]]; then
  log "WARNING: hub kubeconfig not found (${HKC}) — skipping Grafana Layer 2 RBAC"
else
  log_section "Applying Grafana Layer 2 RBAC for student cluster namespaces"
  bash "${REPO_ROOT}/scripts/provision-grafana-student-access.sh" \
    --count          "${STUDENT_COUNT}" \
    --hub-kubeconfig "${HKC}" \
    --no-restart \
  || log "WARNING: provision-grafana-student-access.sh exited non-zero — check output above"
fi

# ── Post-provision: student-info.txt ─────────────────────────
log_section "Generating student-info.txt"
# Pass ACCOUNT as SANDBOX so URL construction uses the correct base domain.
SANDBOX="${ACCOUNT}" \
  HUB_GUID="${HUB_GUID}" \
  STUDENT_GUIDS="$(for S in ${STUDENT_SLOTS}; do printf "student-%s " "$S"; done | sed 's/ $//')" \
  bash "${REPO_ROOT}/scripts/generate-student-info.sh"

# ── Post-provision: multi-user Showroom ──────────────────────
# Deploys per-student Showroom namespaces on the hub and creates the
# showroom-userdata ConfigMaps that inject {hub_username}, {hub_password},
# {hub_grafana_url}, {student-cluster-bastion}, etc. into each student's
# lab guide.  Without this step those attributes render as blank text.
log_section "Deploying multi-user Showroom"

if [[ "${SKIP_SHOWROOM}" == true ]]; then
  log "Showroom: --skip-showroom flag set, skipping."
  log "  To deploy later: bash scripts/deploy-multiuser-showroom.sh \\"
  log "    --hub-guid ${HUB_GUID} --sandbox ${ACCOUNT} --students ${STUDENT_COUNT}"
elif [[ "${DRY_RUN}" == true ]]; then
  log "[DRY-RUN] would run: bash scripts/deploy-multiuser-showroom.sh \\"
  log "  --hub-guid ${HUB_GUID} --sandbox ${ACCOUNT} --students ${STUDENT_COUNT}"
else
  SANDBOX="${ACCOUNT}" \
  HUB_GUID="${HUB_GUID}" \
    bash "${REPO_ROOT}/scripts/deploy-multiuser-showroom.sh" \
      --hub-guid "${HUB_GUID}" \
      --sandbox  "${ACCOUNT}" \
      --students "${STUDENT_COUNT}" \
    || log "WARNING: deploy-multiuser-showroom.sh exited non-zero — check output above."
fi

# ── Summary ───────────────────────────────────────────────────
log_section "Summary"
if [[ ${#FAILED_STUDENTS[@]} -eq 0 ]]; then
  log "All clusters provisioned successfully."
else
  log "The following students failed to provision:"
  for S in "${FAILED_STUDENTS[@]}"; do
    log "  - ${S}  (log: /tmp/deploy-${S}.log)"
  done
  log ""
  log "Re-run this script after resolving errors — already-healthy"
  log "clusters will be skipped automatically."
  exit 1
fi

log "student-info.txt: ${REPO_ROOT}/student-info.txt"
log "Full log: ${MAIN_LOG}"
