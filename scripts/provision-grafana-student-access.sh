#!/usr/bin/env bash
# provision-grafana-student-access.sh
# ============================================================
# Post-deploy repair script for RHACM Observability Grafana
# student access on an OpenShift 4.21 hub cluster.
#
# This script re-applies the two-layer RBAC model required for
# workshop students to authenticate to Grafana and see dashboard
# data across all managed clusters.
#
# Primary provisioning is done by ocp4_workload_capacity_planning_workshop
# (hub_mode: true) in agnosticd-v2. Run this script when:
#   - Students see HTTP 403 at the Grafana route
#   - All Grafana panels show "No data"
#   - Per-student CRBs were lost after hub provisioning
#   - A new cluster was added to RHACM and needs Layer 2 wiring
#
# Usage:
#   bash scripts/provision-grafana-student-access.sh [OPTIONS]
#
# Options:
#   --count N         Number of workshop students (default: 8)
#   --prefix PREFIX   Username prefix, produces <prefix>-1…N (default: user)
#   --hub-kubeconfig  Path to hub cluster kubeconfig
#                     (default: ~/agnosticd-v2-output/hub-capacity/
#                               openshift-cluster_hub-capacity_kubeconfig)
#   --no-restart      Skip Grafana Deployment restart after repair
#   --dry-run         Print what would be applied without making changes
#   --verify-only     Run verification checks without applying any RBAC
#   -h, --help        Show this help
#
# ============================================================

set -euo pipefail

# ---- Defaults -------------------------------------------------------
COUNT=8
PREFIX="user"
HKC="${HOME}/agnosticd-v2-output/hub-capacity/openshift-cluster_hub-capacity_kubeconfig"
OBS_NS="open-cluster-management-observability"
RESTART_GRAFANA=true
DRY_RUN=false
VERIFY_ONLY=false

# ---- Parse arguments ------------------------------------------------
while [[ $# -gt 0 ]]; do
  case $1 in
    --count)        COUNT="$2";         shift 2 ;;
    --prefix)       PREFIX="$2";        shift 2 ;;
    --hub-kubeconfig) HKC="$2";         shift 2 ;;
    --no-restart)   RESTART_GRAFANA=false; shift ;;
    --dry-run)      DRY_RUN=true;       shift ;;
    --verify-only)  VERIFY_ONLY=true;   shift ;;
    -h|--help)
      sed -n '/^# Usage:/,/^# ===*/p' "$0" | sed 's/^# \{0,3\}//'
      exit 0
      ;;
    *) echo "Unknown argument: $1"; exit 1 ;;
  esac
done

# ---- Prerequisite checks --------------------------------------------
if [[ ! -f "${HKC}" ]]; then
  echo "ERROR: hub kubeconfig not found: ${HKC}"
  echo "  Set --hub-kubeconfig or provision the hub cluster first."
  exit 1
fi

OC="oc --kubeconfig=${HKC}"

if ! ${OC} get namespace "${OBS_NS}" &>/dev/null; then
  echo "ERROR: Namespace ${OBS_NS} not found on hub cluster."
  echo "  RHACM Observability must be deployed before running this script."
  exit 1
fi

apply_or_dry() {
  # Wrapper: print YAML in dry-run mode, apply in live mode
  local yaml="$1"
  if [[ "${DRY_RUN}" == "true" ]]; then
    echo "--- DRY RUN: would apply ---"
    echo "${yaml}"
    echo "----------------------------"
  else
    echo "${yaml}" | ${OC} apply -f -
  fi
}

# ---- Build user list ------------------------------------------------
USERS=()
for i in $(seq 1 "${COUNT}"); do
  USERS+=("${PREFIX}-${i}")
done
echo "=== Repairing Grafana access for: ${USERS[*]} ==="

[[ "${VERIFY_ONLY}" == "true" ]] && { echo "(verify-only mode — skipping RBAC apply)"; }

# ---- Layer 1 — oauth-proxy SAR gate ---------------------------------
# ClusterRole open-cluster-management:view-aggregate lets users LIST projects,
# which is the exact SAR check the oauth-proxy sidecar performs before
# forwarding the request to Grafana.

if [[ "${VERIFY_ONLY}" != "true" ]]; then
  echo ""
  echo "=== Layer 1: Applying per-student ClusterRoleBindings (oauth-proxy gate) ==="
  for USER in "${USERS[@]}"; do
    apply_or_dry "$(cat <<YAML
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: workshop-grafana-view-${USER}
  labels:
    demo.redhat.com/application: capacity-workshop
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: open-cluster-management:view-aggregate
subjects:
  - kind: User
    apiGroup: rbac.authorization.k8s.io
    name: ${USER}
YAML
)"
  done

  # ---- workshop-managedcluster-view ClusterRole -----------------------
  echo ""
  echo "=== Creating workshop-managedcluster-view ClusterRole ==="
  apply_or_dry "$(cat <<YAML
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: workshop-managedcluster-view
  labels:
    demo.redhat.com/application: capacity-workshop
rules:
  - apiGroups:
      - cluster.open-cluster-management.io
    resources:
      - managedclusters
    verbs:
      - get
      - list
      - watch
YAML
)"

  for USER in "${USERS[@]}"; do
    apply_or_dry "$(cat <<YAML
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: workshop-mcluster-view-${USER}
  labels:
    demo.redhat.com/application: capacity-workshop
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: workshop-managedcluster-view
subjects:
  - kind: User
    apiGroup: rbac.authorization.k8s.io
    name: ${USER}
YAML
)"
  done

  # ---- Grafana SA RBAC ------------------------------------------------
  echo ""
  echo "=== Applying Grafana ServiceAccount RBAC ==="
  apply_or_dry "$(cat <<YAML
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: workshop-grafana-sa-view-aggregate
  labels:
    demo.redhat.com/application: capacity-workshop
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: open-cluster-management:view-aggregate
subjects:
  - kind: ServiceAccount
    name: grafana
    namespace: ${OBS_NS}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: workshop-grafana-sa-managedcluster-view
  labels:
    demo.redhat.com/application: capacity-workshop
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: workshop-managedcluster-view
subjects:
  - kind: ServiceAccount
    name: grafana
    namespace: ${OBS_NS}
YAML
)"

  # ---- Layer 2 — rbac-query-proxy per-cluster RoleBindings ------------
  echo ""
  echo "=== Layer 2: Discovering managed cluster namespaces ==="
  CLUSTER_NAMES=()
  while IFS= read -r name; do
    CLUSTER_NAMES+=("$name")
  done < <(${OC} get managedclusters -o jsonpath='{.items[*].metadata.name}' | tr ' ' '\n')

  if [[ ${#CLUSTER_NAMES[@]} -eq 0 ]]; then
    echo "WARNING: No managed clusters found. Layer 2 RoleBindings will be created"
    echo "  when clusters are imported. Re-run this script after cluster import."
  else
    echo "Found clusters: ${CLUSTER_NAMES[*]}"
    for CLUSTER_NS in "${CLUSTER_NAMES[@]}"; do
      for USER in "${USERS[@]}"; do
        apply_or_dry "$(cat <<YAML
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: workshop-obs-view-${USER}
  namespace: ${CLUSTER_NS}
  labels:
    demo.redhat.com/application: capacity-workshop
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: view
subjects:
  - kind: User
    apiGroup: rbac.authorization.k8s.io
    name: ${USER}
YAML
)"
      done
    done
  fi

  # ---- Restart Grafana ------------------------------------------------
  if [[ "${RESTART_GRAFANA}" == "true" && "${DRY_RUN}" != "true" ]]; then
    echo ""
    echo "=== Restarting observability-grafana to clear cached token state ==="
    ${OC} rollout restart deployment/observability-grafana -n "${OBS_NS}"
    ${OC} rollout status deployment/observability-grafana -n "${OBS_NS}" --timeout=120s
  fi
fi

# ---- Verification ---------------------------------------------------
echo ""
echo "=== Verifying RBAC ==="

LAYER1_RESULT=$(${OC} auth can-i list projects --as="${PREFIX}-1" 2>&1 || true)
SA_RESULT=$(${OC} auth can-i list managedclusters \
  --as="system:serviceaccount:${OBS_NS}:grafana" 2>&1 || true)
PRIV_RESULT=$(${OC} auth can-i delete nodes --as="${PREFIX}-1" 2>&1 || true)

PASS=true

echo "  Layer 1 (${PREFIX}-1 list projects):        ${LAYER1_RESULT}"
echo "  Grafana SA list managedclusters:           ${SA_RESULT}"
echo "  Privilege check (${PREFIX}-1 delete nodes): ${PRIV_RESULT}"

if [[ "${LAYER1_RESULT}" != "yes" ]]; then
  echo "FAIL: Layer 1 check failed — students will see 403 at Grafana."
  PASS=false
fi
if [[ "${SA_RESULT}" != "yes" ]]; then
  echo "FAIL: Grafana SA check failed — dashboards will show No data."
  PASS=false
fi
if [[ "${PRIV_RESULT}" == "yes" ]]; then
  echo "FAIL: Students have unexpected delete-nodes access — review bindings."
  PASS=false
fi

echo ""
if [[ "${PASS}" == "true" ]]; then
  echo "=== All checks PASSED. Students can log in to Grafana. ==="
  echo ""
  echo "Login instructions:"
  echo "  URL:      \$(${OC} get route grafana -n ${OBS_NS} -o jsonpath='{.spec.host}')"
  echo "  IDP:      workshop-students"
  echo "  Username: ${PREFIX}-1 … ${PREFIX}-${COUNT}"
  echo "  Password: (as set in ocp4_workload_capacity_planning_workshop_hub_password)"
else
  echo "=== One or more checks FAILED. See messages above. ==="
  exit 1
fi
