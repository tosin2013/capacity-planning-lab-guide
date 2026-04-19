#!/usr/bin/env bash
# pod-velocity-calculator.sh
# Module 2 — The Mathematics of Forecasting
#
# Queries the student cluster Prometheus API to calculate pod velocity,
# average resource requests, and project quarterly node requirements.
#
# Usage:
#   ./pod-velocity-calculator.sh
#   NAMESPACE=my-namespace ./pod-velocity-calculator.sh
#   NODE_CPU=16 ./pod-velocity-calculator.sh
#
# Environment variables (all optional):
#   NAMESPACE   Namespace to analyse  (default: capacity-workshop)
#   WINDOW_DAYS Lookback window       (default: 30, falls back if beyond retention)
#   NODE_CPU    Allocatable cores per worker node (default: 8)

set -euo pipefail

NAMESPACE="${NAMESPACE:-capacity-workshop}"
WINDOW_DAYS="${WINDOW_DAYS:-30}"
NODE_CPU="${NODE_CPU:-8}"

# ── colours ──────────────────────────────────────────────────────────────────
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
command -v oc    &>/dev/null || error "'oc' not found. Run this script on your student bastion."
command -v curl  &>/dev/null || error "'curl' not found."
command -v python3 &>/dev/null || error "'python3' not found."

header "Module 2 — Pod Velocity Calculator"
info "Namespace : ${NAMESPACE}"
info "Window    : ${WINDOW_DAYS} days"
info "Node CPU  : ${NODE_CPU} cores (allocatable)"

# ── Step 1: Discover Prometheus ───────────────────────────────────────────────
echo ""
info "Step 1/5 — Locating Prometheus route …"
PROM_HOST=$(oc get route -n openshift-monitoring prometheus-k8s \
  -o jsonpath='{.spec.host}' 2>/dev/null) || error "Could not find prometheus-k8s route in openshift-monitoring."
PROM_URL="https://${PROM_HOST}"
success "Prometheus : ${PROM_URL}"

# ── Step 2: Mint a short-lived token ─────────────────────────────────────────
info "Step 2/5 — Minting Prometheus service-account token …"
TOKEN=$(oc create token prometheus-k8s -n openshift-monitoring 2>/dev/null) \
  || error "Could not create token for prometheus-k8s service account."
success "Token acquired (${#TOKEN} chars)"

# ── helper: run a PromQL instant query ───────────────────────────────────────
promql() {
  local query="$1"
  curl -sk -H "Authorization: Bearer ${TOKEN}" \
    --data-urlencode "query=${query}" \
    "${PROM_URL}/api/v1/query"
}

scalar_result() {
  python3 -c "
import sys, json
d = json.load(sys.stdin)
if d.get('status') != 'success':
    print('ERROR:' + d.get('error','unknown'))
    sys.exit(1)
rt = d['data']['resultType']
r  = d['data']['result']
if rt == 'scalar':
    print(d['data']['result'][1])
elif r:
    print(r[0]['value'][1])
else:
    print('0')
"
}

# ── Step 3: Pod Velocity (pods started within window) ────────────────────────
echo ""
info "Step 3/5 — Calculating pod velocity …"

WINDOW_SECS=$(( WINDOW_DAYS * 86400 ))

# Count pods that started within the lookback window
PODS_STARTED=$(promql "count(kube_pod_start_time{namespace=\"${NAMESPACE}\"} > (time() - ${WINDOW_SECS}))" | scalar_result 2>/dev/null || echo "0")

# If result is 0, the namespace may be new — fall back to total pod count
if [[ "$PODS_STARTED" == "0" ]]; then
  warn "No pods found within ${WINDOW_DAYS}d window — using current pod count as baseline."
  PODS_STARTED=$(promql "count(kube_pod_info{namespace=\"${NAMESPACE}\"})" | scalar_result 2>/dev/null || echo "0")
fi

PODS_STARTED_INT=$(python3 -c "print(round(float('${PODS_STARTED}')))")
POD_VELOCITY=$(python3 -c "print(round(float('${PODS_STARTED}') / ${WINDOW_DAYS}, 2))")
success "Pods started in last ${WINDOW_DAYS}d  : ${PODS_STARTED_INT}"
success "Pod velocity                    : ${POD_VELOCITY} pods/day"

# ── Step 4: Resource averages ─────────────────────────────────────────────────
echo ""
info "Step 4/5 — Querying average resource requests …"

DEPLOY_COUNT=$(promql "count(kube_deployment_spec_replicas{namespace=\"${NAMESPACE}\"})" | scalar_result 2>/dev/null || echo "0")
AVG_REPLICAS=$(promql "avg(kube_deployment_spec_replicas{namespace=\"${NAMESPACE}\"})"    | scalar_result 2>/dev/null || echo "1")
AVG_CPU=$(promql "avg(kube_pod_container_resource_requests{resource=\"cpu\",namespace=\"${NAMESPACE}\"})"    | scalar_result 2>/dev/null || echo "0")
AVG_MEM=$(promql "avg(kube_pod_container_resource_requests{resource=\"memory\",namespace=\"${NAMESPACE}\"}) / 1024 / 1024 / 1024" | scalar_result 2>/dev/null || echo "0")

AVG_CPU_M=$(python3 -c "print(round(float('${AVG_CPU}') * 1000))")
AVG_MEM_MI=$(python3 -c "print(round(float('${AVG_MEM}') * 1024))")

success "Active deployments              : ${DEPLOY_COUNT}"
success "Avg replicas per deployment     : $(python3 -c "print(round(float('${AVG_REPLICAS}'),2))")"
success "Avg CPU request per container   : ${AVG_CPU_M}m  ($(python3 -c "print(round(float('${AVG_CPU}'),3))")  cores)"
success "Avg Memory request per container: ${AVG_MEM_MI}Mi ($(python3 -c "print(round(float('${AVG_MEM}'),3))")  GiB)"

# ── Step 5: Quarterly forecast ────────────────────────────────────────────────
echo ""
info "Step 5/5 — Projecting quarterly node requirements …"

python3 - <<PYEOF
pod_velocity   = float("${POD_VELOCITY}")       # pods/day
avg_replicas   = float("${AVG_REPLICAS}")
avg_cpu        = float("${AVG_CPU}")             # cores per container
node_cpu       = float("${NODE_CPU}")            # allocatable cores per node
window_days    = int("${WINDOW_DAYS}")

quarterly_new_pods = pod_velocity * 90           # project 90 days
total_cpu_needed   = quarterly_new_pods * avg_cpu
nodes_needed       = total_cpu_needed / node_cpu

# Present the working
print()
print("  ┌─────────────────────────────────────────────────────┐")
print("  │           QUARTERLY FORECASTING MODEL               │")
print("  ├─────────────────────────────────────────────────────┤")
print(f"  │ Pod velocity (last {window_days}d)      : {pod_velocity:>8.2f} pods/day       │")
print(f"  │ Quarterly new pods (×90)  : {quarterly_new_pods:>8.1f}                 │")
print(f"  │ Avg CPU request/container : {avg_cpu*1000:>8.0f}m                  │")
print(f"  │ Total CPU needed (new)    : {total_cpu_needed:>8.2f} cores             │")
print(f"  │ Node allocatable CPU      : {node_cpu:>8.2f} cores/node         │")
print(f"  ├─────────────────────────────────────────────────────┤")
print(f"  │ Nodes needed next quarter : {nodes_needed:>8.2f}  → ceil = {int(nodes_needed)+1 if nodes_needed > int(nodes_needed) else int(nodes_needed)} nodes │")
print("  └─────────────────────────────────────────────────────┘")
print()

import math
ceiling = math.ceil(nodes_needed)
print(f"\033[1m\033[32m  RESULT: Add {ceiling} worker node(s) this quarter to accommodate forecasted growth.\033[0m")
print()
print("  NOTE: This model assumes your team's deployment cadence continues at")
print(f"        the same rate observed over the last {window_days} days.")
print("        Adjust NODE_CPU env var if your nodes have different capacity.")
PYEOF
