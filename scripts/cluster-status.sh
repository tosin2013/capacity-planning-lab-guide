#!/usr/bin/env bash
# cluster-status.sh
# ============================================================
# Show provisioning status for all workshop clusters.
# Reads deploy/config.yml for targets and checks output dirs.
#
# Usage:
#   bash scripts/cluster-status.sh
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CONFIG="${REPO_ROOT}/deploy/config.yml"

if [[ ! -f "${CONFIG}" ]]; then
  echo "ERROR: ${CONFIG} not found. Run 'make setup' first."
  exit 1
fi

ACCOUNT=$(grep '^account:' "$CONFIG" | awk '{print $2}')
HUB_GUID=$(grep '^hub_guid:' "$CONFIG" | awk '{print $2}')
NUM_STUDENTS=$(grep '^num_students:' "$CONFIG" | awk '{print $2}')
AGD_DIR=$(grep '^agnosticd_root:' "$CONFIG" | awk '{print $2}')
AGD_DIR="${AGD_DIR/#\~/$HOME}"
OUTPUT_DIR="${HOME}/agnosticd-v2-output"

# ── Status helpers ────────────────────────────────────────────
check_cluster() {
  local guid="$1"
  local config="$2"
  local data="${OUTPUT_DIR}/${guid}/provision-user-data.yaml"
  local status="NOT PROVISIONED"
  local detail=""

  if [[ -d "${OUTPUT_DIR}/${guid}" ]]; then
    if [[ -f "${data}" ]]; then
      if grep -q "^openshift_api_url:" "${data}" 2>/dev/null; then
        status="PROVISIONED"
        detail="$(grep '^openshift_console_url:' "${data}" 2>/dev/null | awk '{print $2}')"
      else
        status="INCOMPLETE"
        detail="output dir exists but missing OCP markers"
      fi
    else
      status="IN PROGRESS / FAILED"
      detail="output dir exists but no provision-user-data.yaml"
    fi
  fi

  printf "  %-16s %-12s %-20s %s\n" "${guid}" "${config}" "${status}" "${detail}"
}

# ── Display ───────────────────────────────────────────────────
echo ""
echo "============================================"
echo "  Workshop Cluster Status"
echo "============================================"
echo ""
echo "  Account:   ${ACCOUNT}"
echo "  Hub GUID:  ${HUB_GUID}"
echo "  Students:  ${NUM_STUDENTS}"
echo "  Output:    ${OUTPUT_DIR}"
echo ""
printf "  %-16s %-12s %-20s %s\n" "GUID" "CONFIG" "STATUS" "CONSOLE"
printf "  %-16s %-12s %-20s %s\n" "----" "------" "------" "-------"

check_cluster "${HUB_GUID}" "hub-aws"

for (( i=1; i<=NUM_STUDENTS; i++ )); do
  SLOT="$(printf '%02d' "$i")"
  check_cluster "student-${SLOT}" "student-${SLOT}"
done

echo ""

if [[ -x "${AGD_DIR}/bin/agd" ]]; then
  echo "  Tip: For live status run:"
  echo "    cd ${AGD_DIR} && bin/agd status --guid <GUID> --config <CONFIG> --account ${ACCOUNT}"
fi
echo "============================================"
