#!/usr/bin/env bash
# check-etcd-health.sh
# Module 6 — The Integration Challenge: Black Friday Chaos Game
#
# Queries the student cluster Prometheus API to report etcd database size
# across all members and checks against the warning/hard-limit thresholds
# from Module 4.
#
# Usage:
#   bash ~/module-06/check-etcd-health.sh
#
# No environment variables required. Run from any directory on the bastion.

set -euo pipefail

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
command -v oc      &>/dev/null || error "'oc' not found. Run this script on your student bastion."
command -v curl    &>/dev/null || error "'curl' not found."
command -v python3 &>/dev/null || error "'python3' not found."

header "Module 6 — etcd Health Check"

# ── Step 1: Discover Prometheus ───────────────────────────────────────────────
echo ""
info "Step 1/3 — Locating Prometheus route …"
PROM_HOST=$(oc get route -n openshift-monitoring prometheus-k8s \
  -o jsonpath='{.spec.host}' 2>/dev/null) \
  || error "Could not find prometheus-k8s route in openshift-monitoring."
PROM_URL="https://${PROM_HOST}"
success "Prometheus : ${PROM_URL}"

# ── Step 2: Mint a short-lived token ─────────────────────────────────────────
echo ""
info "Step 2/3 — Minting Prometheus service-account token …"
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

# ── Step 3: Query etcd DB size per member ─────────────────────────────────────
echo ""
info "Step 3/3 — Querying etcd database size …"
echo ""

# Thresholds (bytes)
WARN_BYTES=$(( 4 * 1024 * 1024 * 1024 ))   # 4 GiB
HARD_BYTES=$(( 8 * 1024 * 1024 * 1024 ))   # 8 GiB

RAW=$(promql "etcd_mvcc_db_total_size_in_bytes")

python3 - <<PYEOF
import json, sys, os

raw  = '''${RAW}'''
data = json.loads(raw)

if data.get("status") != "success":
    print(f"\033[0;31m[ERROR]\033[0m  Prometheus query failed: {data.get('error','unknown')}")
    sys.exit(1)

results = data["data"]["result"]
if not results:
    print("\033[1;33m[WARN]\033[0m   No etcd metrics found. Is the cluster etcd scrape enabled?")
    sys.exit(0)

WARN_BYTES = ${WARN_BYTES}
HARD_BYTES = ${HARD_BYTES}
WARN_MIB   = WARN_BYTES / 1024 / 1024
HARD_MIB   = HARD_BYTES / 1024 / 1024

# Identify leader (highest raft index, approximated by largest DB size)
sizes = [(r["metric"].get("instance","?"), float(r["value"][1])) for r in results]
sizes.sort(key=lambda x: x[1], reverse=True)
leader_instance = sizes[0][0]

print(f"  {'INSTANCE':<26}  {'SIZE (MiB)':>10}  {'% OF QUOTA':>10}  STATUS")
print(f"  {'-'*26}  {'-'*10}  {'-'*10}  ------")

any_warn = False
any_crit = False

for instance, size_bytes in sorted(sizes, key=lambda x: x[0]):
    size_mib  = size_bytes / 1024 / 1024
    pct_quota = (size_bytes / HARD_BYTES) * 100
    is_leader = " ← leader" if instance == leader_instance else ""

    if size_bytes >= HARD_BYTES:
        status = "\033[0;31mCRITICAL\033[0m"
        any_crit = True
    elif size_bytes >= WARN_BYTES:
        status = "\033[1;33mWARNING\033[0m "
        any_warn = True
    else:
        status = "\033[0;32mOK\033[0m     "

    print(f"  {instance:<26}  {size_mib:>10.1f}  {pct_quota:>9.1f}%  {status}{is_leader}")

print()

# Summary line
if any_crit:
    print("\033[0;31m[CRITICAL]\033[0m  One or more etcd members have reached the 8 GiB hard quota!")
    print("           Run: oc get etcd cluster -o yaml | grep -A5 'defragmentation'")
    print("           Consider etcd defragmentation or object pruning immediately.")
elif any_warn:
    print("\033[1;33m[WARN]\033[0m   One or more etcd members above 4 GiB warning threshold.")
    print("           Monitor closely and plan defragmentation.")
else:
    print("\033[0;32m[OK]\033[0m    All members below 4 GiB warning threshold (8 GiB quota).")

# Context for Wave 3
print()
print("  ┌─────────────────────────────────────────────────────┐")
print("  │               etcd QUOTA REFERENCE                  │")
print("  ├─────────────────────────────────────────────────────┤")
print(f"  │  Warning threshold : {WARN_MIB:>8.0f} MiB  (4 GiB)          │")
print(f"  │  Hard quota        : {HARD_MIB:>8.0f} MiB  (8 GiB)          │")
print("  │  At hard quota     : API server rejects all writes  │")
print("  └─────────────────────────────────────────────────────┘")
print()
print("  The Wave 3 kube-burner job creates 20 Deployments + ReplicaSets")
print("  in rapid succession. Watch the SIZE column tick upward compared")
print("  to the value recorded at the start of the simulation.")
PYEOF
