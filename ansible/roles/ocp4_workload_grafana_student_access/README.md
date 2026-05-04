# ocp4_workload_grafana_student_access

Post-deploy repair role for RHACM Observability Grafana student access on an OpenShift 4.21 hub cluster.

## Purpose

This role is **not** the primary provisioning path. Initial Grafana student access is provisioned by `ocp4_workload_capacity_planning_workshop` (with `hub_mode: true`) during hub cluster provisioning via AgnosticD.

Use this role when, on an already-provisioned hub:

| Symptom | Cause |
|---------|-------|
| Students see HTTP 403 at the Grafana route | Layer 1 ClusterRoleBindings were lost |
| All Grafana panels show "No data" | Layer 2 per-cluster RoleBindings are missing or the Grafana SA RBAC was removed |
| A new student cluster was added to RHACM after hub provisioning | Layer 2 RoleBinding in the new cluster's namespace does not exist yet |
| Per-student CRBs were accidentally deleted | Any of the above |

## RHACM Two-Layer RBAC Model

RHACM Observability Grafana enforces two independent RBAC layers. Both must be correct for dashboards to show data.

```
Student browser
    │
    ▼
oauth-proxy sidecar ──── Layer 1: SubjectAccessReview (list projects, cluster-wide)
    │                    ClusterRole: open-cluster-management:view-aggregate
    │                    Without this: HTTP 403 before Grafana loads
    ▼
Grafana backend (auth.proxy mode — auto-assigns Viewer role)
    │
    ▼
rbac-query-proxy ──────── Layer 2: per-managed-cluster namespace RoleBinding
    │                    ClusterRole: view, scoped to each cluster's namespace on hub
    │                    Without this: proxy injects cluster=~"()" → "No data"
    ▼
Thanos Query
```

`viewers_can_edit=true` is intentional for this workshop. Students create and save dashboards during Modules 2 and 5.

## Usage

### Standalone (direct ansible-playbook)

```bash
# From within the agnosticd-v2 directory
export KUBECONFIG=~/agnosticd-v2-output/hub-capacity/openshift-cluster_hub-capacity_kubeconfig

ansible-playbook -i localhost, \
  -e ACTION=provision \
  -e ocp4_workload_grafana_student_access_student_count=8 \
  -e ocp4_workload_grafana_student_access_student_prefix=user \
  -c local \
  /path/to/repair-playbook.yml
```

Or use the wrapper script (see `scripts/provision-grafana-student-access.sh`):

```bash
bash scripts/provision-grafana-student-access.sh \
  --count 8 \
  --hub-kubeconfig ~/agnosticd-v2-output/hub-capacity/openshift-cluster_hub-capacity_kubeconfig
```

### As an AgnosticD workload (post-deploy run)

```yaml
workloads:
  - ocp4_workload_grafana_student_access

ocp4_workload_grafana_student_access_student_count: 8
ocp4_workload_grafana_student_access_student_prefix: user
ocp4_workload_grafana_student_access_restart_grafana: true
```

## Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `ocp4_workload_grafana_student_access_student_count` | `8` | Number of student users to repair RBAC for |
| `ocp4_workload_grafana_student_access_student_prefix` | `user` | Username prefix (produces `user-1`, `user-2`, …) |
| `ocp4_workload_grafana_student_access_observability_namespace` | `open-cluster-management-observability` | RHACM observability namespace |
| `ocp4_workload_grafana_student_access_restart_grafana` | `true` | Restart `observability-grafana` Deployment after re-applying RBAC to clear token cache |

## What This Role Creates / Updates

| Resource | Scope | Purpose |
|----------|-------|---------|
| `ClusterRoleBinding/workshop-grafana-view-<user>` | Cluster | Binds each student to `open-cluster-management:view-aggregate` (Layer 1 SAR gate) |
| `ClusterRole/workshop-managedcluster-view` | Cluster | Grants `get/list/watch` on `managedclusters` |
| `ClusterRoleBinding/workshop-mcluster-view-<user>` | Cluster | Binds each student to `workshop-managedcluster-view` |
| `ClusterRoleBinding/workshop-grafana-sa-view-aggregate` | Cluster | Grafana ServiceAccount → `open-cluster-management:view-aggregate` |
| `ClusterRoleBinding/workshop-grafana-sa-managedcluster-view` | Cluster | Grafana ServiceAccount → `workshop-managedcluster-view` |
| `RoleBinding/workshop-obs-view-<user>` in each cluster namespace | Namespace | Layer 2: allows rbac-query-proxy to resolve cluster names per student |

## What This Role Does NOT Provision

- HTPasswd user creation and OAuth CR patching — handled by the primary workload
- Grafana dashboard ConfigMaps — applied by students during the lab exercises
- Grafana folder-level permissions — managed by Grafana's internal RBAC via its API (`/api/folders/:uid/permissions`), not via Kubernetes RBAC; requires direct Grafana API interaction and is not idempotent without state tracking

## Verification

The role automatically verifies the two RBAC layers at the end of a repair run using `oc auth can-i`. If either check fails the role exits non-zero and prints the diagnostic steps.

Manual verification:

```bash
# Layer 1 — user-1 must be able to list projects
oc auth can-i list projects --as=user-1

# Layer 2 — Grafana SA must be able to list managed clusters
oc auth can-i list managedclusters \
  --as=system:serviceaccount:open-cluster-management-observability:grafana

# Confirm student is not over-privileged
oc auth can-i delete nodes --as=user-1   # must return 'no'
```

## Troubleshooting

**"403 Forbidden" at the Grafana route after repair**
- Confirm the `workshop-students` IDP is configured: `oc get oauth cluster -o yaml`
- If the IDP is missing, the HTPasswd provisioning in the primary workload did not run. Re-run the hub workload with `hub_mode: true`.

**"No data" persists after repair**
1. Confirm student clusters are imported: `oc get managedclusters`
2. The per-cluster-namespace RoleBindings only exist for clusters present at repair time. If a cluster was added afterward, re-run this role.
3. Wait 2–5 minutes for the `rbac-query-proxy` to pick up new bindings, then hard-refresh the Grafana browser tab.
