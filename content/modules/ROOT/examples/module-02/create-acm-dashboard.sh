#!/usr/bin/env bash
# create-acm-dashboard.sh
# Module 2 — The Mathematics of Forecasting
#
# Creates a Pod Velocity Forecast dashboard in the RHACM Grafana instance
# using Kubernetes ConfigMap provisioning (the supported RHACM approach).
# The RHACM grafana-dashboard-loader sidecar automatically imports ConfigMaps
# labelled "general-folder: true" from the observability namespace.
#
# Usage:
#   GRAFANA_URL=https://grafana-open-cluster-management-observability.apps.hub.example.com \
#     ./create-acm-dashboard.sh
#
# Environment variables:
#   GRAFANA_URL   Full https URL of the RHACM Grafana instance  (required)
#   NAMESPACE     Namespace to scope the dashboard panels        (default: capacity-workshop)
#   NODE_CPU      Allocatable cores per worker node              (default: 8)

set -euo pipefail

NAMESPACE="${NAMESPACE:-capacity-workshop}"
NODE_CPU="${NODE_CPU:-8}"

# ── colours ───────────────────────────────────────────────────────────────────
BOLD='\033[1m'; CYAN='\033[0;36m'; GREEN='\033[0;32m'
YELLOW='\033[1;33m'; RED='\033[0;31m'; RESET='\033[0m'

info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; exit 1; }
header()  { echo -e "\n${BOLD}${CYAN}══════════════════════════════════════════════════${RESET}"; \
            echo -e "${BOLD}${CYAN}  $*${RESET}"; \
            echo -e "${BOLD}${CYAN}══════════════════════════════════════════════════${RESET}"; }

# ── pre-flight ────────────────────────────────────────────────────────────────
command -v oc      &>/dev/null || error "'oc' not found. Run this script on your student bastion."
command -v python3 &>/dev/null || error "'python3' not found."

if [[ -z "${GRAFANA_URL:-}" ]]; then
  error "GRAFANA_URL is not set.

  This script requires the RHACM Observability Grafana URL from the hub cluster.
  It is injected into your Showroom terminal as the {hub_grafana_url} attribute.

  Set it and retry:
    export GRAFANA_URL={hub_grafana_url}
    ./create-acm-dashboard.sh

  If {hub_grafana_url} is still empty, RHACM Observability may not yet be
  configured on the hub cluster. This topic is covered in depth in Module 5."
fi

# Strip trailing slash
GRAFANA_URL="${GRAFANA_URL%/}"

header "Module 2 — Create ACM Grafana Dashboard"
info "Grafana URL : ${GRAFANA_URL}"
info "Namespace   : ${NAMESPACE}"
info "Node CPU    : ${NODE_CPU} cores"

# ── Step 1: Confirm oc login and get current user ─────────────────────────────
echo ""
info "Step 1/3 — Confirming hub cluster login …"
HUB_USER=$(oc whoami 2>/dev/null) \
  || error "Not logged in. Run 'oc login <hub_api_url>' first."
OCP_TOKEN=$(oc whoami -t 2>/dev/null) \
  || error "Could not obtain an OCP auth token. Ensure you are logged in with 'oc login'."
success "Logged in as : ${HUB_USER}"
success "Token acquired (${#OCP_TOKEN} chars)"

# ── Step 2: Verify Grafana is reachable ───────────────────────────────────────
echo ""
info "Step 2/3 — Verifying Grafana is reachable …"
HTTP_STATUS=$(curl -sk -o /dev/null -w "%{http_code}" \
  -H "Authorization: Bearer ${OCP_TOKEN}" \
  "${GRAFANA_URL}/api/health")

if [[ "$HTTP_STATUS" != "200" ]]; then
  error "Grafana returned HTTP ${HTTP_STATUS} at ${GRAFANA_URL}/api/health.
  Check that:
    1. GRAFANA_URL is correct (no trailing slash, full https:// URL)
    2. RHACM Observability is installed on the hub cluster"
fi
success "Grafana is reachable (HTTP 200)"

# ── Step 3: Create dashboard via ConfigMap provisioning ───────────────────────
# RHACM Grafana uses a dashboard-loader sidecar that watches ConfigMaps
# labelled "general-folder: true" in the observability namespace and imports
# them automatically. This is the supported method — the Grafana HTTP API
# requires Editor/Admin role which the oauth-proxy maps only to cluster-admin.
echo ""
info "Step 3/3 — Creating Pod Velocity Forecast dashboard …"

UID_SUFFIX=$(date +%s)
DASHBOARD_UID="pod-velocity-${UID_SUFFIX}"
CM_NAME="grafana-dashboard-module-02-pod-velocity"

# PromQL expressions used in the panels
# JSON-escape them with Python to safely embed inside a JSON string
# (PromQL contains {resource="cpu"} which has bare double quotes)
PANEL_VELOCITY_RAW='sum by (cluster) (rate(kube_pod_start_time[30d])) * 2592000'
PANEL_NODES_RAW="ceil( ( sum by (cluster) (rate(kube_pod_start_time[30d])) * 7776000 * scalar(avg(kube_pod_container_resource_requests{resource=\"cpu\"})) ) / ${NODE_CPU} )"
POD_COUNT_RAW="count(kube_pod_info{namespace=\"${NAMESPACE}\"})"
DEPL_COUNT_RAW="count(kube_deployment_spec_replicas{namespace=\"${NAMESPACE}\"}) or vector(0)"

# Python produces a JSON-safe string (without surrounding quotes)
json_escape() { python3 -c "import json,sys; print(json.dumps(sys.argv[1])[1:-1])" "$1"; }
PANEL_VELOCITY_EXPR=$(json_escape "${PANEL_VELOCITY_RAW}")
PANEL_NODES_EXPR=$(json_escape "${PANEL_NODES_RAW}")
POD_COUNT_EXPR=$(json_escape "${POD_COUNT_RAW}")
DEPL_COUNT_EXPR=$(json_escape "${DEPL_COUNT_RAW}")
NS_JSON=$(json_escape "${NAMESPACE}")
CPU_JSON=$(json_escape "${NODE_CPU}")

# Build the raw Grafana dashboard JSON using Python (avoids bash quoting pitfalls)
DASHBOARD_JSON=$(python3 - <<PYEOF
import json

uid       = "${DASHBOARD_UID}"
ns        = "${NAMESPACE}"
node_cpu  = "${NODE_CPU}"

vel_expr  = "${PANEL_VELOCITY_EXPR}"
node_expr = "${PANEL_NODES_EXPR}"
pod_expr  = "${POD_COUNT_EXPR}"
dep_expr  = "${DEPL_COUNT_EXPR}"

dash = {
  "uid": uid,
  "title": "Module 2 \u2014 Pod Velocity Forecast",
  "tags": ["capacity-planning", "module-02", "workshop"],
  "timezone": "browser",
  "schemaVersion": 36,
  "version": 1,
  "refresh": "5m",
  "panels": [
    {
      "id": 1, "type": "stat",
      "title": "Pod Velocity Forecast \u2014 Monthly Growth",
      "description": "Rate of pod creation (pods/month). Formula: rate(kube_pod_start_time[30d]) x 2592000 s/month.",
      "gridPos": {"h": 8, "w": 12, "x": 0, "y": 0},
      "datasource": {"type": "prometheus", "uid": "\${datasource}"},
      "targets": [{"expr": vel_expr, "legendFormat": "{{cluster}}", "refId": "A"}],
      "options": {"reduceOptions": {"calcs": ["lastNotNull"]}, "orientation": "auto", "textMode": "auto", "colorMode": "background"},
      "fieldConfig": {"defaults": {"unit": "short", "displayName": "\${__series.name} pods/month",
        "thresholds": {"mode": "absolute", "steps": [
          {"color": "green", "value": None}, {"color": "yellow", "value": 100}, {"color": "red", "value": 500}
        ]}}}
    },
    {
      "id": 2, "type": "gauge",
      "title": "Projected Nodes Needed (Next Quarter)",
      "description": "Estimated additional worker nodes required over the next 90 days. Assumes " + node_cpu + "-core nodes.",
      "gridPos": {"h": 8, "w": 12, "x": 12, "y": 0},
      "datasource": {"type": "prometheus", "uid": "\${datasource}"},
      "targets": [{"expr": node_expr, "legendFormat": "{{cluster}}", "refId": "A"}],
      "options": {"reduceOptions": {"calcs": ["lastNotNull"]}, "orientation": "auto", "showThresholdLabels": True, "showThresholdMarkers": True},
      "fieldConfig": {"defaults": {"unit": "short", "min": 0, "max": 20, "displayName": "\${__series.name}",
        "thresholds": {"mode": "absolute", "steps": [
          {"color": "green", "value": None}, {"color": "yellow", "value": 5}, {"color": "red", "value": 10}
        ]}}}
    },
    {
      "id": 3, "type": "timeseries",
      "title": "Pod Count Over Time \u2014 " + ns,
      "description": "Historical pod count in the " + ns + " namespace to visualise growth trends.",
      "gridPos": {"h": 8, "w": 24, "x": 0, "y": 8},
      "datasource": {"type": "prometheus", "uid": "\${datasource}"},
      "targets": [
        {"expr": pod_expr, "legendFormat": "Running pods", "refId": "A"},
        {"expr": dep_expr, "legendFormat": "Deployments",  "refId": "B"}
      ],
      "options": {"tooltip": {"mode": "multi"}, "legend": {"displayMode": "list", "placement": "bottom"}},
      "fieldConfig": {"defaults": {"unit": "short"}}
    }
  ],
  "templating": {"list": [{"name": "datasource", "type": "datasource", "query": "prometheus", "label": "Prometheus datasource", "current": {}}]}
}
print(json.dumps(dash, indent=2))
PYEOF
)

# Validate JSON before applying
echo "${DASHBOARD_JSON}" | python3 -m json.tool > /dev/null \
  || error "Dashboard JSON is invalid — this is a script bug, please report it."

# Apply the ConfigMap (create or update)
oc apply -f - <<YAMLEOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: ${CM_NAME}
  namespace: open-cluster-management-observability
  labels:
    general-folder: "true"
data:
  module-02-pod-velocity-forecast.json: |
$(echo "${DASHBOARD_JSON}" | sed 's/^/    /')
YAMLEOF

DASHBOARD_URL="${GRAFANA_URL}/dashboards"

echo ""
success "Dashboard ConfigMap applied successfully!"
echo ""
echo -e "  ${BOLD}${GREEN}Open Grafana and browse to:${RESET}"
echo -e "  ${BOLD}${CYAN}${DASHBOARD_URL}${RESET}"
echo ""
echo "  Dashboard title : Module 2 — Pod Velocity Forecast"
echo "  Folder          : General"
echo "  ConfigMap       : ${CM_NAME}"
echo "  Namespace       : open-cluster-management-observability"
echo ""
echo "  The dashboard has three panels:"
echo "    1. Pod Velocity Forecast — Monthly Growth  (Stat, per cluster)"
echo "    2. Projected Nodes Needed (Next Quarter)   (Gauge, per cluster)"
echo "    3. Pod Count Over Time in ${NAMESPACE}     (Time series)"
echo ""
warn "RHACM Observability aggregates metrics from ALL managed clusters."
warn "If you see data for only one cluster, additional student clusters"
warn "may not yet be registered as RHACM managed clusters (covered in Module 5)."
warn "Allow 30-60 seconds for the Grafana dashboard loader to import the ConfigMap."
