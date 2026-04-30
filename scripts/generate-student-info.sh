#!/usr/bin/env bash
# generate-student-info.sh
# ============================================================
# Reads agnosticd provision-user-data.yaml for the hub and
# each student cluster, then writes student-info.txt in the
# repo root.  student-info.txt is gitignored — never committed.
#
# Usage:
#   bash scripts/generate-student-info.sh [--students 1,2,3]
#
# Defaults:
#   Hub GUID:      hub-capacity
#   Student GUIDs: student-01 student-02 student-03
#   Output:        <repo_root>/student-info.txt
# ============================================================

set -euo pipefail

# ── Configurable defaults ───────────────────────────────────
HUB_GUID="${HUB_GUID:-hub-capacity}"
STUDENT_GUIDS="${STUDENT_GUIDS:-student-01 student-02 student-03}"
OUTPUT_DIR_ROOT="${OUTPUT_DIR_ROOT:-${HOME}/agnosticd-v2-output}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
OUT_FILE="${REPO_ROOT}/student-info.txt"

# ── Helper: extract a field from a YAML file ────────────────
# Uses Python for reliable YAML parsing (avoids awk edge cases)
yaml_get() {
  local file="$1"
  local key="$2"
  python3 -c "
import sys
try:
    import yaml
    with open('${file}') as f:
        d = yaml.safe_load(f)
    val = d.get('${key}', '')
    print(val if val is not None else '')
except Exception:
    print('')
" 2>/dev/null
}

# ── Verify hub output exists ─────────────────────────────────
HUB_DATA="${OUTPUT_DIR_ROOT}/${HUB_GUID}/provision-user-data.yaml"
if [[ ! -f "${HUB_DATA}" ]]; then
  echo "ERROR: Hub provision output not found: ${HUB_DATA}"
  echo "       Ensure 'agd provision --guid ${HUB_GUID}' has completed."
  exit 1
fi

# ── Extract hub fields ───────────────────────────────────────
HUB_SHOWROOM="$(yaml_get "${HUB_DATA}" lab_ui_url)"
HUB_RHACM="$(yaml_get "${HUB_DATA}" hub_rhacm_console)"
HUB_API="$(yaml_get "${HUB_DATA}" hub_api_url)"
HUB_GRAFANA="$(yaml_get "${HUB_DATA}" hub_grafana_url)"
HUB_PASSWORD="$(yaml_get "${HUB_DATA}" hub_password)"

# ── Build output ─────────────────────────────────────────────
{
  echo "=================================================="
  echo "Capacity Planning Workshop — Student Access Sheet"
  echo "Generated: $(date '+%Y-%m-%d %H:%M %Z')"
  echo "=================================================="
  echo ""
  echo "HUB CLUSTER"
  echo "  Showroom (Lab Guide):  ${HUB_SHOWROOM:-<not available>}"
  echo "  RHACM Console:         ${HUB_RHACM:-<not available>}"
  echo "  Hub API:               ${HUB_API:-<not available>}"
  echo "  Grafana:               ${HUB_GRAFANA:-<not available>}"
  echo "  Hub Admin Password:    ${HUB_PASSWORD:-openshift}"
  echo ""
  echo "Students share the same Showroom URL above."
  echo "Each student uses their own OCP cluster (listed below)"
  echo "and their assigned hub login to access RHACM / Grafana."
  echo ""

  SLOT=1
  for SGUID in ${STUDENT_GUIDS}; do
    SDATA="${OUTPUT_DIR_ROOT}/${SGUID}/provision-user-data.yaml"

    echo "--------------------------------------------------"
    printf "STUDENT %02d  (hub login: user-%d / %s)\n" \
      "${SLOT}" "${SLOT}" "${HUB_PASSWORD:-openshift}"

    if [[ ! -f "${SDATA}" ]]; then
      echo "  WARNING: provision output not found: ${SDATA}"
      echo "           Run 'agd provision --guid ${SGUID}' first."
    else
      BASTION_HOST="$(yaml_get "${SDATA}" bastion_public_hostname)"
      BASTION_USER="$(yaml_get "${SDATA}" bastion_ssh_user_name)"
      OCP_CONSOLE="$(yaml_get "${SDATA}" openshift_console_url)"
      OCP_API="$(yaml_get "${SDATA}" openshift_api_url)"
      HUB_USER="$(yaml_get "${SDATA}" hub_username)"
      HUB_PASS="$(yaml_get "${SDATA}" hub_password)"
      HUB_API_URL="$(yaml_get "${SDATA}" hub_api_url)"
      NAMESPACE="$(yaml_get "${SDATA}" namespace)"

      echo "  Bastion SSH:       ssh ${BASTION_USER:-lab-user}@${BASTION_HOST:-<unknown>}"
      echo "  OCP Console:       ${OCP_CONSOLE:-<not available>}"
      echo "  OCP API:           ${OCP_API:-<not available>}"
      echo "  Lab Namespace:     ${NAMESPACE:-capacity-workshop}"
      echo "  Hub Login:"
      echo "    oc login ${HUB_API_URL:-${HUB_API}} \\"
      echo "      --username=${HUB_USER:-user-${SLOT}} \\"
      echo "      --password=${HUB_PASS:-${HUB_PASSWORD:-openshift}}"
    fi
    echo ""

    SLOT=$(( SLOT + 1 ))
  done

  echo "=================================================="
  echo "NOTE: This file contains passwords. Do not share"
  echo "publicly or commit to version control."
  echo "=================================================="
} > "${OUT_FILE}"

echo "Written: ${OUT_FILE}"
echo ""
cat "${OUT_FILE}"
