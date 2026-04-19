#!/usr/bin/env bash
# create-acm-dashboard.sh
# Module 2 — The Mathematics of Forecasting
#
# Creates a Pod Velocity Forecast dashboard in the RHACM Grafana instance
# via the Grafana HTTP API.  Students open the printed URL to view the result.
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
command -v oc     &>/dev/null || error "'oc' not found. Run this script on your student bastion."
command -v curl   &>/dev/null || error "'curl' not found."
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

# ── Step 1: Get OCP token for Grafana auth ────────────────────────────────────
echo ""
info "Step 1/3 — Obtaining OpenShift token for Grafana authentication …"
OCP_TOKEN=$(oc create token grafana-sa -n open-cluster-management-observability 2>/dev/null) \
  || OCP_TOKEN=$(oc whoami -t 2>/dev/null) \
  || error "Could not obtain an OCP auth token. Ensure you are logged in with 'oc login'."
success "Token acquired (${#OCP_TOKEN} chars)"

# ── Step 2: Verify Grafana is reachable ───────────────────────────────────────
info "Step 2/3 — Verifying Grafana API is reachable …"
HTTP_STATUS=$(curl -sk -o /dev/null -w "%{http_code}" \
  -H "Authorization: Bearer ${OCP_TOKEN}" \
  "${GRAFANA_URL}/api/health")

if [[ "$HTTP_STATUS" != "200" ]]; then
  error "Grafana API returned HTTP ${HTTP_STATUS} at ${GRAFANA_URL}/api/health.
  Check that:
    1. GRAFANA_URL is correct (no trailing slash, full https:// URL)
    2. RHACM Observability is installed on the hub cluster
    3. Your token has Grafana viewer or editor access"
fi
success "Grafana API is reachable (HTTP 200)"

# ── Step 3: POST dashboard ────────────────────────────────────────────────────
echo ""
info "Step 3/3 — Creating Pod Velocity Forecast dashboard …"

# Timestamps for unique dashboard uid
UID_SUFFIX=$(date +%s)
DASHBOARD_UID="pod-velocity-${UID_SUFFIX}"

# PromQL expressions used in the panels
# These use multi-cluster label if available, fall back to single-cluster data.
PANEL_VELOCITY_EXPR="sum by (cluster) (rate(kube_pod_start_time[30d])) * 2592000"
PANEL_NODES_EXPR="ceil( ( sum by (cluster) (rate(kube_pod_start_time[30d])) * 7776000 * scalar(avg(kube_pod_container_resource_requests{resource=\"cpu\"})) ) / ${NODE_CPU} )"

DASHBOARD_JSON=$(cat <<DASHEOF
{
  "dashboard": {
    "uid": "${DASHBOARD_UID}",
    "title": "Module 2 — Pod Velocity Forecast",
    "tags": ["capacity-planning", "module-02", "workshop"],
    "timezone": "browser",
    "schemaVersion": 36,
    "version": 0,
    "refresh": "5m",
    "panels": [
      {
        "id": 1,
        "type": "stat",
        "title": "Pod Velocity Forecast — Monthly Growth",
        "description": "Rate of pod creation (pods/month) aggregated across all managed clusters. Formula: rate(kube_pod_start_time[30d]) × 2592000 seconds/month.",
        "gridPos": { "h": 8, "w": 12, "x": 0, "y": 0 },
        "datasource": { "type": "prometheus", "uid": "\${datasource}" },
        "targets": [
          {
            "expr": "${PANEL_VELOCITY_EXPR}",
            "legendFormat": "{{cluster}}",
            "refId": "A"
          }
        ],
        "options": {
          "reduceOptions": { "calcs": ["lastNotNull"] },
          "orientation": "auto",
          "textMode": "auto",
          "colorMode": "background"
        },
        "fieldConfig": {
          "defaults": {
            "unit": "short",
            "displayName": "${__series.name} pods/month",
            "thresholds": {
              "mode": "absolute",
              "steps": [
                { "color": "green", "value": null },
                { "color": "yellow", "value": 100 },
                { "color": "red",    "value": 500 }
              ]
            }
          }
        }
      },
      {
        "id": 2,
        "type": "gauge",
        "title": "Projected Nodes Needed (Next Quarter)",
        "description": "Estimated additional worker nodes required over the next 90 days based on current pod creation velocity and average CPU requests. Assumes ${NODE_CPU}-core nodes.",
        "gridPos": { "h": 8, "w": 12, "x": 12, "y": 0 },
        "datasource": { "type": "prometheus", "uid": "\${datasource}" },
        "targets": [
          {
            "expr": "${PANEL_NODES_EXPR}",
            "legendFormat": "{{cluster}}",
            "refId": "A"
          }
        ],
        "options": {
          "reduceOptions": { "calcs": ["lastNotNull"] },
          "orientation": "auto",
          "showThresholdLabels": true,
          "showThresholdMarkers": true
        },
        "fieldConfig": {
          "defaults": {
            "unit": "short",
            "min": 0,
            "max": 20,
            "displayName": "${__series.name}",
            "thresholds": {
              "mode": "absolute",
              "steps": [
                { "color": "green",  "value": null },
                { "color": "yellow", "value": 5 },
                { "color": "red",    "value": 10 }
              ]
            }
          }
        }
      },
      {
        "id": 3,
        "type": "timeseries",
        "title": "Pod Count Over Time — ${NAMESPACE}",
        "description": "Historical pod count in the ${NAMESPACE} namespace to visualise growth trends.",
        "gridPos": { "h": 8, "w": 24, "x": 0, "y": 8 },
        "datasource": { "type": "prometheus", "uid": "\${datasource}" },
        "targets": [
          {
            "expr": "count(kube_pod_info{namespace=\"${NAMESPACE}\"})",
            "legendFormat": "Running pods",
            "refId": "A"
          },
          {
            "expr": "count(kube_deployment_spec_replicas{namespace=\"${NAMESPACE}\"}) or vector(0)",
            "legendFormat": "Deployments",
            "refId": "B"
          }
        ],
        "options": {
          "tooltip": { "mode": "multi" },
          "legend": { "displayMode": "list", "placement": "bottom" }
        },
        "fieldConfig": {
          "defaults": { "unit": "short" }
        }
      }
    ],
    "templating": {
      "list": [
        {
          "name": "datasource",
          "type": "datasource",
          "query": "prometheus",
          "label": "Prometheus datasource",
          "current": {}
        }
      ]
    }
  },
  "folderId": 0,
  "overwrite": true
}
DASHEOF
)

RESPONSE=$(curl -sk \
  -X POST \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${OCP_TOKEN}" \
  -d "${DASHBOARD_JSON}" \
  "${GRAFANA_URL}/api/dashboards/db")

# Parse response
STATUS=$(python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(d.get('status','unknown'))" <<< "${RESPONSE}" 2>/dev/null || echo "unknown")
SLUG=$(python3  -c "import sys,json; d=json.loads(sys.stdin.read()); print(d.get('slug',''))"   <<< "${RESPONSE}" 2>/dev/null || echo "")
URL_PATH=$(python3  -c "import sys,json; d=json.loads(sys.stdin.read()); print(d.get('url',''))"    <<< "${RESPONSE}" 2>/dev/null || echo "")

if [[ "$STATUS" == "success" ]]; then
  DASHBOARD_URL="${GRAFANA_URL}${URL_PATH}"
  echo ""
  success "Dashboard created successfully!"
  echo ""
  echo -e "  ${BOLD}${GREEN}Open this URL in your browser:${RESET}"
  echo -e "  ${BOLD}${CYAN}${DASHBOARD_URL}${RESET}"
  echo ""
  echo "  Dashboard UID : ${DASHBOARD_UID}"
  echo "  Folder        : General"
  echo ""
  echo "  The dashboard has three panels:"
  echo "    1. Pod Velocity Forecast — Monthly Growth  (Stat, per cluster)"
  echo "    2. Projected Nodes Needed (Next Quarter)   (Gauge, per cluster)"
  echo "    3. Pod Count Over Time in ${NAMESPACE}     (Time series)"
  echo ""
  warn "RHACM Observability aggregates metrics from ALL managed clusters."
  warn "If you see data for only one cluster, additional student clusters"
  warn "may not yet be registered as RHACM managed clusters (covered in Module 5)."
else
  ERROR_MSG=$(python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(d.get('message',''))" <<< "${RESPONSE}" 2>/dev/null || echo "see raw response below")
  echo ""
  warn "Grafana API response: ${RESPONSE}"
  error "Dashboard creation failed (status: ${STATUS}): ${ERROR_MSG}"
fi
