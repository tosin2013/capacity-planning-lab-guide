#!/usr/bin/env bash
# resource-right-sizer.sh
# Module 3 — The "Zero Request" Myth
#
# Queries the student cluster Prometheus API to:
#   1. Measure current CPU throttling rate for a workload
#   2. Calculate 95th-percentile CPU and memory usage over the past N days
#   3. Output right-sized resource requests/limits and the exact oc set resources command
#
# Usage:
#   ./resource-right-sizer.sh
#   NAMESPACE=my-namespace ./resource-right-sizer.sh
#   NAMESPACE=my-namespace POD_SELECTOR="my-app.*" ./resource-right-sizer.sh
#
# Environment variables (all optional):
#   NAMESPACE     Namespace to analyse    (default: capacity-workshop)
#   POD_SELECTOR  Pod name regex pattern  (default: load-generator.*)
#   WINDOW_DAYS   Lookback window in days (default: 7, falls back to 1d if data unavailable)

set -euo pipefail

NAMESPACE="${NAMESPACE:-capacity-workshop}"
POD_SELECTOR="${POD_SELECTOR:-load-generator.*}"
WINDOW_DAYS="${WINDOW_DAYS:-7}"

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
command -v oc     &>/dev/null || error "'oc' not found. Run this script on your student bastion."
command -v curl   &>/dev/null || error "'curl' not found."
command -v python3 &>/dev/null || error "'python3' not found."

header "Module 3 — Resource Right-Sizer"
info "Namespace    : ${NAMESPACE}"
info "Pod selector : ${POD_SELECTOR}"
info "Window       : ${WINDOW_DAYS} days"

# ── Step 1: Discover Prometheus ───────────────────────────────────────────────
echo ""
info "Step 1/4 — Locating Prometheus route …"
PROM_HOST=$(oc get route -n openshift-monitoring prometheus-k8s \
  -o jsonpath='{.spec.host}' 2>/dev/null) || error "Could not find prometheus-k8s route in openshift-monitoring."
PROM_URL="https://${PROM_HOST}"
success "Prometheus : ${PROM_URL}"

# ── Step 2: Mint a short-lived token ─────────────────────────────────────────
info "Step 2/4 — Minting Prometheus service-account token …"
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

# ── Step 3: CPU Throttling Rate ───────────────────────────────────────────────
echo ""
info "Step 3/4 — Measuring CPU throttling rate …"

THROTTLE_RATE=$(promql \
  "max(rate(container_cpu_cfs_throttled_seconds_total{namespace=\"${NAMESPACE}\", pod=~\"${POD_SELECTOR}\"}[5m]))" \
  | scalar_result 2>/dev/null || echo "0")

python3 - <<PYEOF
throttle = float("${THROTTLE_RATE}")
pct = throttle * 100
if pct < 5:
    severity = "healthy"
    color    = "\033[0;32m"
elif pct < 25:
    severity = "MODERATE"
    color    = "\033[1;33m"
elif pct < 50:
    severity = "HIGH"
    color    = "\033[0;31m"
else:
    severity = "SEVERE"
    color    = "\033[0;31m"

reset = "\033[0m"
green = "\033[0;32m"
print(f"{green}[OK]{reset}    Throttling rate : {color}{throttle:.3f}  ({pct:.1f}% of CPU time throttled \u2014 {severity}){reset}")
if pct >= 5:
    print(f"\033[1;33m[WARN]{reset}  Throttling above 5% indicates the CPU limit is too low for this workload.")
    print(        "        Kernel CFS is pausing the container to stay within its CPU limit.")
PYEOF

# ── Step 4: P95 CPU and Memory Right-Sizing ───────────────────────────────────
echo ""
info "Step 4/4 — Calculating 95th-percentile resource usage (${WINDOW_DAYS}d window) …"

# P95 CPU — try full window first, fall back to 1d if no data
P95_CPU=$(promql \
  "max(quantile_over_time(0.95, rate(container_cpu_usage_seconds_total{namespace=\"${NAMESPACE}\", pod=~\"${POD_SELECTOR}\", container!=\"\"}[5m])[${WINDOW_DAYS}d:5m]))" \
  | scalar_result 2>/dev/null || echo "0")

if [[ "${P95_CPU}" == "0" || "${P95_CPU}" == ERROR* ]]; then
  warn "No ${WINDOW_DAYS}d CPU data found — falling back to 1d window."
  P95_CPU=$(promql \
    "max(quantile_over_time(0.95, rate(container_cpu_usage_seconds_total{namespace=\"${NAMESPACE}\", pod=~\"${POD_SELECTOR}\", container!=\"\"}[5m])[1d:5m]))" \
    | scalar_result 2>/dev/null || echo "0")
fi

# P95 memory — try full window first, fall back to 1d if no data
P95_MEM_MIB=$(promql \
  "max(quantile_over_time(0.95, container_memory_working_set_bytes{namespace=\"${NAMESPACE}\", pod=~\"${POD_SELECTOR}\", container!=\"\"}[${WINDOW_DAYS}d:5m])) / 1024 / 1024" \
  | scalar_result 2>/dev/null || echo "0")

if [[ "${P95_MEM_MIB}" == "0" || "${P95_MEM_MIB}" == ERROR* ]]; then
  warn "No ${WINDOW_DAYS}d memory data found — falling back to 1d window."
  P95_MEM_MIB=$(promql \
    "max(quantile_over_time(0.95, container_memory_working_set_bytes{namespace=\"${NAMESPACE}\", pod=~\"${POD_SELECTOR}\", container!=\"\"}[1d:5m])) / 1024 / 1024" \
    | scalar_result 2>/dev/null || echo "0")
fi

python3 - <<PYEOF
import math

p95_cpu_cores = float("${P95_CPU}")
p95_mem_mib   = float("${P95_MEM_MIB}")
namespace     = "${NAMESPACE}"

def ceil_to_10m(cores):
    """Round cores up to the nearest 10m (0.010 cores)."""
    m = math.ceil(cores * 1000 / 10) * 10
    return max(m, 10)

def ceil_to_8mi(mib):
    """Round MiB up to the nearest 8Mi increment."""
    return max(math.ceil(mib / 8) * 8, 8)

cpu_req_m  = ceil_to_10m(p95_cpu_cores)
cpu_lim_m  = ceil_to_10m(p95_cpu_cores * 2)
mem_req_mi = ceil_to_8mi(p95_mem_mib * 1.2)
mem_lim_mi = ceil_to_8mi(p95_mem_mib * 1.5)

print()
print("  \u250c\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2510")
print("  \u2502              RIGHT-SIZING RECOMMENDATIONS                  \u2502")
print("  \u251c\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2524")
print(f"  \u2502 P95 CPU usage (raw)       : {p95_cpu_cores*1000:>8.1f}m cores                 \u2502")
print(f"  \u2502 P95 Memory usage (raw)    : {p95_mem_mib:>8.1f}Mi                        \u2502")
print("  \u251c\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2524")
print(f"  \u2502 Recommended CPU request   : {cpu_req_m:>6}m  (= P95, rounded up)       \u2502")
print(f"  \u2502 Recommended CPU limit     : {cpu_lim_m:>6}m  (= 2\u00d7 request)             \u2502")
print(f"  \u2502 Recommended Memory request: {mem_req_mi:>5}Mi  (= P95 + 20% buffer)     \u2502")
print(f"  \u2502 Recommended Memory limit  : {mem_lim_mi:>5}Mi  (= P95 + 50% buffer)     \u2502")
print("  \u2514\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2518")
print()

bold  = "\033[1m"
green = "\033[0;32m"
reset = "\033[0m"
print(f"{bold}  Apply with:{reset}")
print(f"{green}  oc set resources deployment load-generator -n {namespace} \\")
print(f"    --requests=cpu={cpu_req_m}m,memory={mem_req_mi}Mi \\")
print(f"    --limits=cpu={cpu_lim_m}m,memory={mem_lim_mi}Mi{reset}")
print()
print("  NOTE: CPU limit is set to 2\u00d7 request to allow burst capacity.")
print("        Reduce the memory limit if OOMKills stop after right-sizing.")
PYEOF
