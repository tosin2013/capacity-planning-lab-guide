#!/usr/bin/env bash
# request-quotas.sh
# ============================================================
# Automatically request AWS quota increases needed for the
# Capacity Planning Workshop deployment.
#
# Reads deploy/config.yml for region and student count, then
# requests increases for any quota below the required level.
#
# Usage:
#   bash scripts/request-quotas.sh
#   bash scripts/request-quotas.sh --dry-run
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CONFIG="${REPO_ROOT}/deploy/config.yml"
DRY_RUN=false

# ── Parse args ──
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) DRY_RUN=true; shift ;;
        -h|--help)
            echo "Usage: bash scripts/request-quotas.sh [--dry-run]"
            echo "  --dry-run   Print what would be requested without making changes"
            exit 0 ;;
        *) echo "Unknown arg: $1"; exit 1 ;;
    esac
done

# ── Read config ──
if [[ ! -f "$CONFIG" ]]; then
    echo "ERROR: $CONFIG not found. Run 'make setup' first."
    exit 1
fi

AWS_REGION=$(grep '^aws_region:' "$CONFIG" | awk '{print $2}')
NUM_STUDENTS=$(grep '^num_students:' "$CONFIG" | awk '{print $2}')

if [[ -z "$AWS_REGION" || -z "$NUM_STUDENTS" ]]; then
    echo "ERROR: Could not read aws_region or num_students from $CONFIG"
    exit 1
fi

# ── Calculate requirements ──
# Each cluster (hub + N students) needs: 8 vCPUs (m7a.2xlarge), 2 VPCs, 2 EIPs, 2 NAT GWs
CLUSTERS=$(( 1 + NUM_STUDENTS ))
REQUIRED_VCPUS=$(( CLUSTERS * 8 * 3 ))  # 3 nodes per cluster
REQUIRED_EIPS=$(( CLUSTERS * 2 ))
REQUIRED_VPCS=$(( CLUSTERS * 2 ))
REQUIRED_NATS=$(( CLUSTERS * 2 ))

# Desired values (add headroom)
DESIRED_VCPUS=$(( REQUIRED_VCPUS + 32 ))
DESIRED_EIPS=$(( REQUIRED_EIPS + 4 ))
DESIRED_VPCS=$(( REQUIRED_VPCS + 2 ))
DESIRED_NATS=$(( REQUIRED_NATS + 2 ))

echo "=========================================="
echo " AWS Quota Increase Request"
echo "=========================================="
echo ""
echo "Region:       ${AWS_REGION}"
echo "Students:     ${NUM_STUDENTS}"
echo "Clusters:     ${CLUSTERS} (hub + ${NUM_STUDENTS} students)"
echo ""
echo "Required quotas:"
echo "  EC2 vCPUs:      ${REQUIRED_VCPUS} (requesting ${DESIRED_VCPUS})"
echo "  Elastic IPs:    ${REQUIRED_EIPS} (requesting ${DESIRED_EIPS})"
echo "  VPCs:           ${REQUIRED_VPCS} (requesting ${DESIRED_VPCS})"
echo "  NAT Gateways:   ${REQUIRED_NATS} (requesting ${DESIRED_NATS})"
echo ""

# ── Quota definitions ──
declare -A QUOTA_CODES=(
    ["EC2 vCPUs (On-Demand Standard)"]="ec2:L-1216C47A:${DESIRED_VCPUS}"
    ["Elastic IPs"]="ec2:L-0263D0A3:${DESIRED_EIPS}"
    ["VPCs"]="vpc:L-F678F1CE:${DESIRED_VPCS}"
    ["NAT Gateways"]="vpc:L-FE5A380F:${DESIRED_NATS}"
)

declare -A REQUIRED_VALS=(
    ["EC2 vCPUs (On-Demand Standard)"]="${REQUIRED_VCPUS}"
    ["Elastic IPs"]="${REQUIRED_EIPS}"
    ["VPCs"]="${REQUIRED_VPCS}"
    ["NAT Gateways"]="${REQUIRED_NATS}"
)

# ── Process each quota ──
requested=0
skipped=0

for label in "EC2 vCPUs (On-Demand Standard)" "Elastic IPs" "VPCs" "NAT Gateways"; do
    IFS=':' read -r service_code quota_code desired <<< "${QUOTA_CODES[$label]}"
    needed="${REQUIRED_VALS[$label]}"

    current_limit=$(aws service-quotas get-service-quota \
        --service-code "$service_code" \
        --quota-code "$quota_code" \
        --region "$AWS_REGION" \
        --query 'Quota.Value' \
        --output text 2>/dev/null || echo "0")
    current_limit="${current_limit%%.*}"
    current_limit="${current_limit:-0}"

    if (( current_limit >= needed )); then
        echo "  [OK]   ${label}: current ${current_limit} >= needed ${needed}"
        skipped=$((skipped + 1))
        continue
    fi

    if [[ "$DRY_RUN" == true ]]; then
        echo "  [DRY]  ${label}: current ${current_limit} < needed ${needed} — would request ${desired}"
    else
        echo -n "  [REQ]  ${label}: current ${current_limit} < needed ${needed} — requesting ${desired}..."
        if aws service-quotas request-service-quota-increase \
            --service-code "$service_code" \
            --quota-code "$quota_code" \
            --desired-value "$desired" \
            --region "$AWS_REGION" \
            --output text > /dev/null 2>&1; then
            echo " submitted"
        else
            echo " FAILED (may already have pending request)"
        fi
    fi
    requested=$((requested + 1))
done

echo ""
echo "=========================================="
if [[ "$DRY_RUN" == true ]]; then
    echo "DRY RUN: ${requested} increase(s) would be requested, ${skipped} already sufficient."
else
    echo "Done: ${requested} increase(s) requested, ${skipped} already sufficient."
    if (( requested > 0 )); then
        echo ""
        echo "NOTE: Quota increases can take 5-30 minutes to be approved."
        echo "Check status:  aws service-quotas list-requested-service-quota-changes-by-history --region ${AWS_REGION} --query 'RequestedQuotas[].{Quota:QuotaName,Status:Status,Desired:DesiredValue}' --output table"
    fi
fi
echo "=========================================="
