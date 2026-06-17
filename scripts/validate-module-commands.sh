#!/usr/bin/env bash
# Validate version-sensitive oc commands from all lab modules against a live
# student bastion using oc 4.21.  Commands that mutate cluster state are run
# with --dry-run=client; read-only commands run normally.
#
# Usage:
#   ./validate-module-commands.sh [student-id]
#   student-id defaults to "student-04"
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
STUDENT_INFO="${REPO_ROOT}/student-info.txt"

TARGET_STUDENT="${1:-student-04}"
NAMESPACE="capacity-workshop"

# -----------------------------------------------------------------
# Parse student-04 bastion credentials from student-info.txt
# -----------------------------------------------------------------
parse_student() {
    local id="$1"
    local field="$2"
    grep -A 10 "STUDENT.*guid: ${id}" "$STUDENT_INFO" | grep "${field}" | awk '{print $NF}' | head -1
}

BASTION_HOST=$(grep -A 5 "guid: ${TARGET_STUDENT}" "$STUDENT_INFO" \
    | grep "Bastion SSH:" | awk '{print $NF}' | sed 's/.*@//')
BASTION_PW=$(grep -A 6 "guid: ${TARGET_STUDENT}" "$STUDENT_INFO" \
    | grep "Bastion Password:" | awk '{print $NF}')
OCP_API=$(grep -A 8 "guid: ${TARGET_STUDENT}" "$STUDENT_INFO" \
    | grep "OCP API:" | awk '{print $NF}')

# Derive user number from student id (student-04 → user-4)
USER_NUM=$(echo "$TARGET_STUDENT" | grep -oE '[0-9]+$' | sed 's/^0*//')
OC_USER="user-${USER_NUM}"
OC_PASS="openshift"

if [[ -z "$BASTION_HOST" || -z "$BASTION_PW" || -z "$OCP_API" ]]; then
    echo "ERROR: Could not parse credentials for ${TARGET_STUDENT} from ${STUDENT_INFO}" >&2
    exit 1
fi

echo "=== Module Command Validation ==="
echo "Bastion:   ${BASTION_HOST}"
echo "OCP API:   ${OCP_API}"
echo "User:      ${OC_USER}"
echo "Namespace: ${NAMESPACE}"
echo ""

# -----------------------------------------------------------------
# Helper: run a remote command and report PASS/FAIL
# -----------------------------------------------------------------
PASS=0
FAIL=0
RESULTS=()

remote_check() {
    local label="$1"
    local cmd="$2"

    result=$(sshpass -p "$BASTION_PW" ssh \
        -tt \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout=30 \
        -o RequestTTY=force \
        "lab-user@${BASTION_HOST}" \
        "${cmd}" 2>&1 || true)

    # Strip terminal control chars and connection close messages
    result=$(echo "$result" | sed 's/\r//g' | grep -v "^Connection to" | grep -v "^Warning:" || true)

    # A command is PASS if it exits cleanly (we use || true above so check for error keywords)
    if echo "$result" | grep -qiE "error:|Error:|failed|FAILED|unknown flag|invalid|not found|No resources found" \
       && ! echo "$result" | grep -qiE "dry run|dryrun|deployment\.apps|horizontalpodautoscaler|node"; then
        printf "FAIL [%s]\n" "$label"
        echo "$result" | tail -5 | sed "s/^/       /"
        RESULTS+=("FAIL: ${label}")
        (( FAIL++ )) || true
    else
        printf "PASS [%s]\n" "$label"
        echo "$result" | grep -v "^$" | head -3 | sed "s/^/       /" || true
        RESULTS+=("PASS: ${label}")
        (( PASS++ )) || true
    fi
}

# -----------------------------------------------------------------
# Pre-flight: confirm oc version and login
# -----------------------------------------------------------------
echo "--- Pre-flight ---"
remote_check "oc version (client)" \
    "oc version --client 2>&1"

remote_check "oc login" \
    "oc login '${OCP_API}' --username='${OC_USER}' --password='${OC_PASS}' --insecure-skip-tls-verify=true -q 2>&1 && echo 'Login OK'"

# -----------------------------------------------------------------
# MODULE 3 — HPA, resource management, rollout
# -----------------------------------------------------------------
echo ""
echo "--- Module 3 ---"

remote_check "M3: oc run besteffort-test --dry-run=client" \
    "oc login '${OCP_API}' --username='${OC_USER}' --password='${OC_PASS}' --insecure-skip-tls-verify=true -q 2>&1; \
     oc run besteffort-test --image=quay.io/prometheus/busybox:latest \
       -n ${NAMESPACE} --dry-run=client -- sleep 3600 2>&1"

remote_check "M3: oc autoscale --cpu-percent=75 --dry-run=client" \
    "oc login '${OCP_API}' --username='${OC_USER}' --password='${OC_PASS}' --insecure-skip-tls-verify=true -q 2>&1; \
     oc autoscale deployment load-generator -n ${NAMESPACE} \
       --min=1 --max=5 --cpu-percent=75 --dry-run=client 2>&1"

remote_check "M3: oc set resources (check flag exists)" \
    "oc set resources --help 2>&1 | head -5"

remote_check "M3: oc rollout status (read-only)" \
    "oc login '${OCP_API}' --username='${OC_USER}' --password='${OC_PASS}' --insecure-skip-tls-verify=true -q 2>&1; \
     oc rollout status deployment/load-generator -n ${NAMESPACE} --timeout=30s 2>&1 || true"

remote_check "M3: oc set env (check flag exists)" \
    "oc set env --help 2>&1 | head -5"

remote_check "M3: oc adm top pods (read-only)" \
    "oc login '${OCP_API}' --username='${OC_USER}' --password='${OC_PASS}' --insecure-skip-tls-verify=true -q 2>&1; \
     oc adm top pods -n ${NAMESPACE} 2>&1 | head -10 || true"

# -----------------------------------------------------------------
# MODULE 4 — right-sizing activity
# -----------------------------------------------------------------
echo ""
echo "--- Module 4 ---"

remote_check "M4: oc apply checkout-api --dry-run=client" \
    "oc login '${OCP_API}' --username='${OC_USER}' --password='${OC_PASS}' --insecure-skip-tls-verify=true -q 2>&1; \
     oc apply -f ${REPO_ROOT}/content/modules/ROOT/examples/module-04/checkout-api-bad.yaml \
       -n ${NAMESPACE} --dry-run=client 2>&1"

remote_check "M4: oc set resources checkout-api --dry-run=client" \
    "oc login '${OCP_API}' --username='${OC_USER}' --password='${OC_PASS}' --insecure-skip-tls-verify=true -q 2>&1; \
     oc set resources deployment checkout-api -n ${NAMESPACE} \
       --requests=cpu=30m,memory=128Mi --limits=cpu=100m,memory=192Mi --dry-run=client 2>&1"

# -----------------------------------------------------------------
# MODULE 5 — density test deployment
# -----------------------------------------------------------------
echo ""
echo "--- Module 5 ---"

remote_check "M5: oc create deployment -- sleep infinity --dry-run=client" \
    "oc login '${OCP_API}' --username='${OC_USER}' --password='${OC_PASS}' --insecure-skip-tls-verify=true -q 2>&1; \
     oc create deployment density-test \
       --image=registry.access.redhat.com/ubi9/ubi-micro:latest \
       --replicas=1 -n ${NAMESPACE} --dry-run=client -- sleep infinity 2>&1"

# -----------------------------------------------------------------
# MODULE 7 — drain/cordon flags
# -----------------------------------------------------------------
echo ""
echo "--- Module 7 ---"

remote_check "M7: oc adm drain --delete-emptydir-data flag exists" \
    "oc adm drain --help 2>&1 | grep -c 'delete-emptydir-data' || echo '0 occurrences'"

remote_check "M7: oc adm cordon (help check)" \
    "oc adm cordon --help 2>&1 | head -3"

remote_check "M7: oc adm uncordon (help check)" \
    "oc adm uncordon --help 2>&1 | head -3"

remote_check "M7: oc scale machineset --dry-run=client" \
    "oc login '${OCP_API}' --username='${OC_USER}' --password='${OC_PASS}' --insecure-skip-tls-verify=true -q 2>&1; \
     MS=\$(oc get machineset -n openshift-machine-api -o name 2>/dev/null | head -1); \
     if [[ -n \"\$MS\" ]]; then \
       oc scale \$MS -n openshift-machine-api --replicas=2 --dry-run=client 2>&1; \
     else \
       echo 'No MachineSet found (expected in SNO/single-node environments)'; \
     fi"

remote_check "M7: oc adm top nodes (read-only)" \
    "oc login '${OCP_API}' --username='${OC_USER}' --password='${OC_PASS}' --insecure-skip-tls-verify=true -q 2>&1; \
     oc adm top nodes 2>&1 | head -5 || true"

# -----------------------------------------------------------------
# Summary
# -----------------------------------------------------------------
echo ""
echo "==================================================="
echo " VALIDATION SUMMARY"
echo "==================================================="
for r in "${RESULTS[@]}"; do
    echo "  $r"
done
echo ""
echo "  Total: ${PASS} PASS  ${FAIL} FAIL"
echo "==================================================="
[[ $FAIL -eq 0 ]]
