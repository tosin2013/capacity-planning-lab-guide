#!/usr/bin/env bash
# fix-grafana-rbac.sh
# ============================================================
# Fixes "No data" in RHACM Grafana dashboards by granting
# the Grafana ServiceAccount the RBAC needed for the
# rbac-query-proxy to resolve ManagedCluster names.
#
# Root cause: with auth.proxy + forwardHeaders in some RHACM
# versions, the user's bearer token is not reliably forwarded
# from Grafana to the rbac-query-proxy. The proxy receives no
# token, computes an empty cluster set, and injects
# cluster=~"()" into every PromQL query → "No data".
#
# Fix: bind the Grafana SA to the same cluster-view roles so
# the proxy can see all ManagedClusters when it uses the SA
# token. In a workshop all students should see all clusters.
#
# Usage: bash scripts/fix-grafana-rbac.sh
# ============================================================

set -euo pipefail

HKC="${HOME}/agnosticd-v2-output/hub-capacity/openshift-cluster_hub-capacity_kubeconfig"
NS="open-cluster-management-observability"

if [[ ! -f "${HKC}" ]]; then
  echo "ERROR: hub kubeconfig not found: ${HKC}"
  exit 1
fi

echo "=== Granting Grafana SA view access to ManagedClusters ==="

oc apply -f - --kubeconfig "${HKC}" <<YAML
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
    namespace: ${NS}
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
    namespace: ${NS}
YAML

echo ""
echo "=== Verifying Grafana SA can now see ManagedClusters ==="
oc auth can-i list managedclusters \
  --as="system:serviceaccount:${NS}:grafana" \
  --kubeconfig "${HKC}" 2>&1

echo ""
echo "=== Rolling Grafana pod to clear any cached token state ==="
oc rollout restart deployment/observability-grafana -n "${NS}" \
  --kubeconfig "${HKC}" 2>&1

echo ""
echo "=== Waiting for Grafana rollout ==="
oc rollout status deployment/observability-grafana -n "${NS}" \
  --kubeconfig "${HKC}" --timeout=120s 2>&1

echo ""
echo "=== Done. Grafana should now show data for all users. ==="
echo "    Ask users to refresh their Grafana browser tab."
