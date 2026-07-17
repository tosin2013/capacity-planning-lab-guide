#!/usr/bin/env bash
# teardown-workshop.sh
# ============================================================
# Idempotent teardown script for the Capacity Planning Workshop.
# Reads deploy/config.yml for account, hub_guid, and num_students.
# Destroys student clusters first (parallel-safe), then the hub.
#
# Usage:
#   bash scripts/teardown-workshop.sh              # interactive confirm
#   bash scripts/teardown-workshop.sh --confirm    # skip confirmation prompt
#   bash scripts/teardown-workshop.sh --dry-run    # show what would be destroyed
#   bash scripts/teardown-workshop.sh --students-only  # keep the hub
#   bash scripts/teardown-workshop.sh --hub-only       # keep students
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CONFIG="${REPO_ROOT}/deploy/config.yml"

DRY_RUN=false
CONFIRMED=false
STUDENTS_ONLY=false
HUB_ONLY=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)        DRY_RUN=true; shift ;;
    --confirm|-y)     CONFIRMED=true; shift ;;
    --students-only)  STUDENTS_ONLY=true; shift ;;
    --hub-only)       HUB_ONLY=true; shift ;;
    -h|--help)
      sed -n '3,15p' "${BASH_SOURCE[0]}"
      exit 0
      ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# ── Load config ───────────────────────────────────────────────
if [[ ! -f "${CONFIG}" ]]; then
  echo "ERROR: ${CONFIG} not found. Run 'make setup' first."
  exit 1
fi

ACCOUNT=$(grep '^account:' "$CONFIG" | awk '{print $2}')
HUB_GUID=$(grep '^hub_guid:' "$CONFIG" | awk '{print $2}')
NUM_STUDENTS=$(grep '^num_students:' "$CONFIG" | awk '{print $2}')
AGD_DIR=$(grep '^agnosticd_root:' "$CONFIG" | awk '{print $2}')
AGD_DIR="${AGD_DIR/#\~/$HOME}"

if [[ -z "$ACCOUNT" || -z "$HUB_GUID" || -z "$NUM_STUDENTS" ]]; then
  echo "ERROR: Could not read required values from ${CONFIG}"
  exit 1
fi

if [[ ! -x "${AGD_DIR}/bin/agd" ]]; then
  echo "ERROR: agd not found at ${AGD_DIR}/bin/agd"
  exit 1
fi

# ── Build list of targets ─────────────────────────────────────
# Each entry is "guid:config_name"
TARGETS=()

if [[ "$HUB_ONLY" != true ]]; then
  for (( i=1; i<=NUM_STUDENTS; i++ )); do
    SLOT="$(printf '%02d' "$i")"
    TARGETS+=("student-${SLOT}:student-${SLOT}")
  done
fi

if [[ "$STUDENTS_ONLY" != true ]]; then
  TARGETS+=("${HUB_GUID}:hub-aws")
fi

# ── Display plan ──────────────────────────────────────────────
echo ""
echo "============================================"
echo "  Workshop Teardown"
echo "============================================"
echo ""
echo "  Account:    ${ACCOUNT}"
echo "  Hub GUID:   ${HUB_GUID}"
echo "  Students:   ${NUM_STUDENTS}"
echo "  AgnosticD:  ${AGD_DIR}"
echo ""
echo "  Will destroy (in order):"
for ENTRY in "${TARGETS[@]}"; do
  echo "    - ${ENTRY%%:*}"
done
echo ""

if [[ "$DRY_RUN" == true ]]; then
  echo "[DRY-RUN] Commands that would run:"
  echo ""
  for ENTRY in "${TARGETS[@]}"; do
    local_guid="${ENTRY%%:*}"
    local_config="${ENTRY##*:}"
    echo "  cd ${AGD_DIR} && bin/agd destroy --guid ${local_guid} --config ${local_config} --account ${ACCOUNT}"
  done
  echo ""
  exit 0
fi

# ── Confirm ───────────────────────────────────────────────────
if [[ "$CONFIRMED" != true ]]; then
  echo "  WARNING: This will permanently delete all AWS resources for these clusters."
  echo ""
  read -rp "  Type 'yes' to confirm: " answer
  if [[ "$answer" != "yes" ]]; then
    echo "  Aborted."
    exit 0
  fi
  echo ""
fi

# ── Destroy ───────────────────────────────────────────────────
FAILED=()

for ENTRY in "${TARGETS[@]}"; do
  T="${ENTRY%%:*}"
  CFG="${ENTRY##*:}"
  echo "[$(date '+%Y-%m-%d %H:%M:%S UTC')] Destroying ${T} (config: ${CFG})..."
  if (cd "${AGD_DIR}" && bin/agd destroy --guid "${T}" --config "${CFG}" --account "${ACCOUNT}"); then
    echo "[$(date '+%Y-%m-%d %H:%M:%S UTC')] ${T}: destroyed OK"
  else
    echo "[$(date '+%Y-%m-%d %H:%M:%S UTC')] ${T}: destroy FAILED (exit $?)"
    FAILED+=("${T}")
  fi
  echo ""
done

# ── Summary ───────────────────────────────────────────────────
echo "============================================"
if [[ ${#FAILED[@]} -eq 0 ]]; then
  echo "  All clusters destroyed successfully."
else
  echo "  FAILED to destroy: ${FAILED[*]}"
  echo "  Check AWS console for orphaned resources."
  exit 1
fi
echo "============================================"
