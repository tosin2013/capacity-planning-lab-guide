#!/usr/bin/env bash
# oom-demo.sh
# Module 3 — The "Zero Request" Myth
#
# Triggers a real OOMKill, waits for it to happen, then walks through
# the standard debugging workflow so students experience exit code 137
# first-hand rather than reading about it.
#
# Usage:
#   ~/module-03/oom-demo.sh
#   NAMESPACE=my-namespace ~/module-03/oom-demo.sh
#
# Environment variables (all optional):
#   NAMESPACE   Namespace to use  (default: capacity-workshop)

set -euo pipefail

NAMESPACE="${NAMESPACE:-capacity-workshop}"
POD_NAME="oom-demo"

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
command -v oc &>/dev/null || error "'oc' not found. Run this script on your student bastion."

# Clean up any previous run
oc delete pod "${POD_NAME}" -n "${NAMESPACE}" --ignore-not-found &>/dev/null

header "Module 3 — OOM Kill Demo"
info "Namespace : ${NAMESPACE}"
info "Pod name  : ${POD_NAME}"

# ── Step 1: Deploy ────────────────────────────────────────────────────────────
echo ""
info "Step 1/4 — Deploying oom-demo pod (4Mi memory limit) …"

oc apply -f - -n "${NAMESPACE}" &>/dev/null <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: ${POD_NAME}
  namespace: ${NAMESPACE}
  labels:
    app: oom-demo
    demo.redhat.com/application: capacity-workshop
spec:
  restartPolicy: Never
  containers:
  - name: oom
    image: quay.io/prometheus/busybox:latest
    command: ["/bin/sh", "-c"]
    args: ["dd if=/dev/zero bs=1M count=100 2>/dev/null || true"]
    resources:
      requests:
        cpu: 10m
        memory: 4Mi
      limits:
        cpu: 100m
        memory: 4Mi
EOF

success "Pod created — it will try to allocate 100MB against a 4Mi limit."

# ── Step 2: Wait for OOMKill ──────────────────────────────────────────────────
echo ""
info "Step 2/4 — Waiting for OOMKill (up to 30s) …"

for i in $(seq 1 30); do
  REASON=$(oc get pod "${POD_NAME}" -n "${NAMESPACE}" \
    -o jsonpath='{.status.containerStatuses[0].state.terminated.reason}' 2>/dev/null || true)
  LAST_REASON=$(oc get pod "${POD_NAME}" -n "${NAMESPACE}" \
    -o jsonpath='{.status.containerStatuses[0].lastState.terminated.reason}' 2>/dev/null || true)
  if [[ "${REASON}" == "OOMKilled" || "${LAST_REASON}" == "OOMKilled" ]]; then
    success "OOMKilled confirmed after ~${i}s."
    break
  fi
  sleep 1
done

# Verify we actually got an OOMKill
FINAL_REASON=$(oc get pod "${POD_NAME}" -n "${NAMESPACE}" \
  -o jsonpath='{.status.containerStatuses[0].state.terminated.reason}' 2>/dev/null || \
  oc get pod "${POD_NAME}" -n "${NAMESPACE}" \
  -o jsonpath='{.status.containerStatuses[0].lastState.terminated.reason}' 2>/dev/null || echo "unknown")

if [[ "${FINAL_REASON}" != "OOMKilled" ]]; then
  warn "Pod did not OOMKill within 30s (status: ${FINAL_REASON}). Showing current state:"
  oc get pod "${POD_NAME}" -n "${NAMESPACE}" 2>&1 || true
fi

# ── Step 3: Show the OOMKilling event ─────────────────────────────────────────
echo ""
info "Step 3/4 — Checking OOMKilling events …"
sleep 2
oc get events -n "${NAMESPACE}" \
  --field-selector "involvedObject.name=${POD_NAME}" \
  --sort-by='.lastTimestamp' 2>/dev/null | tail -10 \
  || warn "No events found yet — they may appear within 30s in 'oc get events -n ${NAMESPACE}'"

# ── Step 4: Debug the termination state ───────────────────────────────────────
echo ""
info "Step 4/4 — Inspecting last termination state …"

EXIT_CODE=$(oc get pod "${POD_NAME}" -n "${NAMESPACE}" \
  -o jsonpath='{.status.containerStatuses[0].state.terminated.exitCode}' 2>/dev/null || echo "")
if [[ -z "${EXIT_CODE}" ]]; then
  EXIT_CODE=$(oc get pod "${POD_NAME}" -n "${NAMESPACE}" \
    -o jsonpath='{.status.containerStatuses[0].lastState.terminated.exitCode}' 2>/dev/null || echo "unknown")
fi

MEM_LIMIT=$(oc get pod "${POD_NAME}" -n "${NAMESPACE}" \
  -o jsonpath='{.spec.containers[0].resources.limits.memory}' 2>/dev/null || echo "unknown")

echo ""
echo -e "  ${BOLD}Exit code   :${RESET} ${RED}${EXIT_CODE}${RESET}  (128 + 9 SIGKILL = 137 means OOMKilled)"
echo -e "  ${BOLD}Memory limit:${RESET} ${MEM_LIMIT}  (the container was killed for exceeding this)"
echo ""

success "This is the same signature you will see on real production OOMKills."
echo ""
echo -e "  ${BOLD}Standard debug workflow:${RESET}"
echo    "  1. oc get events -n <namespace> --field-selector reason=OOMKilling"
echo    "  2. oc get pod <pod> -o jsonpath='{.status.containerStatuses[0].lastState.terminated}'"
echo    "  3. NAMESPACE=<ns> POD_SELECTOR=<pod> ~/module-03/resource-right-sizer.sh  ← P95 memory"
echo    "  4. Raise the memory limit by the P95 + 50% buffer the right-sizer recommends."
echo ""

# Clean up
info "Cleaning up oom-demo pod …"
oc delete pod "${POD_NAME}" -n "${NAMESPACE}" --ignore-not-found &>/dev/null
success "Done. oom-demo pod removed."
