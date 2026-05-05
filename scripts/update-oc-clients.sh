#!/usr/bin/env bash
# Update the oc/kubectl CLI to OCP 4.21 on all student bastions.
# Reads bastion info from student-info.txt in the repo root.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
STUDENT_INFO="${REPO_ROOT}/student-info.txt"

OC_VERSION="${OC_VERSION:-stable-4.21}"
OC_URL="https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/${OC_VERSION}/openshift-client-linux.tar.gz"
LOG_DIR=$(mktemp -d /tmp/oc-update-XXXX)
trap 'rm -rf "$LOG_DIR"' EXIT

# -----------------------------------------------------------------
# Parse bastions from student-info.txt
# Lines look like:  Bastion SSH:          ssh lab-user@bastion.student-01...
#                   Bastion Password:     zsJAbGHpdm96
# -----------------------------------------------------------------
declare -a BASTIONS=()
declare -A PASSWORDS=()

current_host=""
while IFS= read -r line; do
    if [[ "$line" =~ "Bastion SSH:" ]]; then
        current_host=$(echo "$line" | awk '{print $NF}' | sed 's/.*@//')
        BASTIONS+=("$current_host")
    elif [[ "$line" =~ "Bastion Password:" && -n "$current_host" ]]; then
        PASSWORDS["$current_host"]=$(echo "$line" | awk '{print $NF}')
    fi
done < "$STUDENT_INFO"

if [[ ${#BASTIONS[@]} -eq 0 ]]; then
    echo "ERROR: No bastions found in ${STUDENT_INFO}" >&2
    exit 1
fi

echo "=== OC Client Update: ${OC_VERSION} ==="
echo "Bastions: ${BASTIONS[*]}"
echo "Source:   ${OC_URL}"
echo ""

# -----------------------------------------------------------------
# Launch one SSH session per bastion in parallel; log to file
# -----------------------------------------------------------------
declare -a PIDS=()

for host in "${BASTIONS[@]}"; do
    pw="${PASSWORDS[$host]}"
    logfile="${LOG_DIR}/${host}.log"

    sshpass -p "$pw" ssh \
        -tt \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout=30 \
        "lab-user@${host}" \
        "set -e
         OC_URL='${OC_URL}'
         echo 'Downloading...'
         curl -fsSL \"\$OC_URL\" -o /tmp/oc-client.tar.gz
         sudo tar xz -C /usr/bin oc kubectl < /tmp/oc-client.tar.gz
         rm -f /tmp/oc-client.tar.gz
         echo 'Installed:'
         oc version --client" \
        > "$logfile" 2>&1 &

    PIDS+=($!)
done

# -----------------------------------------------------------------
# Wait for all and report
# -----------------------------------------------------------------
PASS=0
FAIL=0

for i in "${!PIDS[@]}"; do
    host="${BASTIONS[$i]}"
    pid="${PIDS[$i]}"
    logfile="${LOG_DIR}/${host}.log"

    if wait "$pid" 2>/dev/null; then
        echo "PASS [${host}]"
        grep -E "Client Version:|4\." "$logfile" 2>/dev/null | head -3 | sed "s/^/       /" || true
        (( PASS++ )) || true
    else
        echo "FAIL [${host}]"
        tail -20 "$logfile" 2>/dev/null | sed "s/^/       /" || true
        (( FAIL++ )) || true
    fi
done

echo ""
echo "=== Summary: ${PASS} PASS  ${FAIL} FAIL ==="
[[ $FAIL -eq 0 ]]
