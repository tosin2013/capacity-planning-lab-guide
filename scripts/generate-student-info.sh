#!/usr/bin/env bash
# generate-student-info.sh
# ============================================================
# Reads agnosticd provision-user-data.yaml for the hub and
# each student cluster, then writes student-info.txt in the
# repo root.  student-info.txt is gitignored — never committed.
#
# Each student row includes their own per-student Showroom URL
# (queried live from the hub cluster; falls back to derived URL).
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
SANDBOX="${SANDBOX:-sandbox3967}"
STUDENT_GUIDS="${STUDENT_GUIDS:-student-01 student-02 student-03}"
OUTPUT_DIR_ROOT="${OUTPUT_DIR_ROOT:-${HOME}/agnosticd-v2-output}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
OUT_FILE="${REPO_ROOT}/student-info.txt"
HUB_KC="${OUTPUT_DIR_ROOT}/${HUB_GUID}/openshift-cluster_${HUB_GUID}_kubeconfig"

# ── Helper: extract a field from a YAML file ────────────────
# Uses grep/sed on simple "key: value" lines (no PyYAML required)
yaml_get() {
  local file="$1"
  local key="$2"
  { grep -m1 "^${key}:" "${file}" 2>/dev/null || true; } \
    | sed "s/^${key}:[[:space:]]*//" \
    | sed "s/^['\"]//;s/['\"]$//" \
    | tr -d '\r'
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
HUB_INGRESS_DOMAIN="apps.hub.${HUB_GUID}.${SANDBOX}.opentlc.com"

# ── Helper: get per-student Showroom URL ─────────────────────
# Queries the hub cluster for the route in namespace showroom-<hub>-user-N.
# Falls back to the derived pattern if kubeconfig is unavailable.
get_student_showroom_url() {
  local slot="$1"
  local ns="showroom-${HUB_GUID}-user-${slot}"
  local fallback="https://showroom-${ns}.${HUB_INGRESS_DOMAIN}/"
  if [[ -f "${HUB_KC}" ]]; then
    local host
    host=$(oc get route showroom -n "${ns}" \
      --kubeconfig "${HUB_KC}" \
      -o jsonpath='{.spec.host}' 2>/dev/null || true)
    if [[ -n "${host}" ]]; then
      echo "https://${host}/"
      return
    fi
  fi
  echo "${fallback}"
}

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
  echo ""

  SLOT=1
  for SGUID in ${STUDENT_GUIDS}; do
    SDATA="${OUTPUT_DIR_ROOT}/${SGUID}/provision-user-data.yaml"

    echo "--------------------------------------------------"
    printf "STUDENT %02d  (guid: %s)\n" "${SLOT}" "${SGUID}"

    if [[ ! -f "${SDATA}" ]]; then
      echo "  WARNING: provision output not found: ${SDATA}"
      echo "           Run 'agd provision --guid ${SGUID}' first."
    else
      BASTION_HOST="$(yaml_get "${SDATA}" bastion_public_hostname)"
      BASTION_USER="$(yaml_get "${SDATA}" bastion_ssh_user_name)"
      BASTION_PASS="$(yaml_get "${SDATA}" bastion_ssh_password)"
      OCP_CONSOLE="$(yaml_get "${SDATA}" openshift_console_url)"
      OCP_API="$(yaml_get "${SDATA}" openshift_api_url)"
      NAMESPACE="$(yaml_get "${SDATA}" namespace)"

      # Hub login — prefer fields emitted by workload; fall back to derived values
      # (workload may not have emitted these if sample-app wait timed out)
      HUB_USER="$(yaml_get "${SDATA}" hub_username)"
      HUB_PASS="$(yaml_get "${SDATA}" hub_password)"
      HUB_API_URL="$(yaml_get "${SDATA}" hub_api_url)"
      HUB_USER="${HUB_USER:-user-${SLOT}}"
      HUB_PASS="${HUB_PASS:-${HUB_PASSWORD:-openshift}}"
      HUB_API_URL="${HUB_API_URL:-${HUB_API}}"

      STUDENT_SHOWROOM="$(get_student_showroom_url "${SLOT}")"
      echo "  Showroom (Lab Guide): ${STUDENT_SHOWROOM:-<not available>}"
      echo "  Bastion SSH:          ssh ${BASTION_USER:-lab-user}@${BASTION_HOST:-<unknown>}"
      echo "  Bastion Password:     ${BASTION_PASS:-<unknown>}"
      echo "  OCP Console:          ${OCP_CONSOLE:-<not available>}"
      echo "  OCP API:              ${OCP_API:-<not available>}"
      echo "  Lab Namespace:        ${NAMESPACE:-capacity-workshop}"
      echo "  Hub Login:"
      echo "      oc login ${HUB_API_URL} \\"
      echo "        --username=${HUB_USER} \\"
      echo "        --password=${HUB_PASS}"
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
