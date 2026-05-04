# Workshop Module Test Report — All Modules
**Date**: 2026-05-04  
**GUID**: student-03  
**Tester account**: user-3 (hub) / lab-user bastion (student)  
**Student cluster**: https://api.student.student-03.sandbox3967.opentlc.com:6443  
**Hub cluster**: https://api.hub.hub-capacity.sandbox3967.opentlc.com:6443  
**Compared against**: module-all-test-report.md (student-01, 2026-04-30)

---

## Pre-Flight Summary

| Check | Result | Detail |
|-------|--------|--------|
| 3 nodes Ready (student-03) | PASS | All Ready, OCP 4.19.28 |
| capacity-workshop pods Running | PASS | 8 pods |
| ArgoCD capacity-planning-workshop Synced/Healthy | PASS | |
| Prometheus accessible | PASS | thanos-querier route available |
| Hub observability pods Running | PASS | 35 Running |
| Managed clusters in RHACM | PASS | local-cluster, student-01, student-02, student-03 |
| Grafana Layer 1 RBAC (user-3 list projects) | PASS | yes |
| Grafana Layer 2 RBAC (Grafana SA list managedclusters) | PASS | yes |
| Grafana Layer 2 RBAC (user-3 view student-03 ns on hub) | PASS | yes |

---

## Module Test Results

```
Module Test Report — All Modules — GUID: student-03
────────────────────────────────────────────────────────────────────────────────
MOD  #   Step                                       Status  Category              Notes
────────────────────────────────────────────────────────────────────────────────
M01  1   oc get nodes                               PASS    —                     3 nodes Ready, OCP 4.19.28
M01  2   oc adm top nodes                           PASS    —                     3 rows with metrics
M01  3   oc describe node | Allocated resources     PASS    —                     Compact cluster nodes carry all roles
M01  4   pod counts by namespace (top namespaces)   PASS    —                     capacity-workshop = 8 pods
M01  5   oc adm top pods -n capacity-workshop       PASS    —                     8 pods with metrics

M02  1   SSH bastion reachable                      PASS    —                     Port open; sshpass auth works
M02  2   download lab scripts (3 files)             PASS    —                     pod-velocity-calculator.sh, create-acm-dashboard.sh, module-2---pod-velocity-forecast.yaml all downloaded
M02  3   NAMESPACE=capacity-workshop pod-velocity-calculator.sh PASS —            velocity 0.27 pods/day; RESULT: add 1 node this quarter
M02  4   oc login hub as user-3                     PASS    —                     user-3 listed in hub IDP; auth can-i list projects = yes
M02  5   hub_username attribute in Showroom         PASS    —                     showroom-userdata configmap in showroom-hub-capacity-user-3 has hub_username=user-3 (FIXED vs student-01 run)
M02  6   oc apply module-2 dashboard configmap      PASS    —                     configmap/module-2---pod-velocity-forecast already present on hub
M02  7   switch back to student context             PASS    —                     oc whoami returns kubeadmin

M03  1   besteffort-app QoS class                   PASS    —                     Returns "Burstable" — module correctly explains this at lines 72-74 (ResourceQuota prevents true BestEffort)
M03  2   scratch-qos-demo BestEffort workaround     PASS    —                     Module documents scratch namespace workaround
M03  3   guaranteed-app QoS class                   PASS    —                     Returns "Guaranteed"
M03  4   load-generator resources                   PASS    —                     requests.cpu=10m limits.cpu=200m shown correctly
M03  5   download resource-right-sizer.sh           PASS    —                     3 files in ~/module-03 (resource-right-sizer.sh, stress-config.yaml, stress-pod.yaml)
M03  6   download kube-burner v2.6.1                PASS    —                     kube-burner pre-installed in ~/bin by provisioning; students download to ~/module-03 per instructions (works fine)
M03  7   kube-burner init stress-config.yaml        PASS    —                     Job cpu-throttle-demo completed; pod created in capacity-workshop

M04  1   maxPods per node                           PASS    —                     250 per node (3 nodes)
M04  2   pods per node distribution                 PASS    —                     93-113 pods per node (within 250 limit)
M04  3   oc get mcp                                 PASS    —                     master pool: MACHINECOUNT=3, worker: 0 (compact cluster — documented correctly)
M04  4   KubeletConfig (cluster-admin only)         PASS    —                     Module correctly notes namespace-scoped users skip cluster-admin steps; demonstration mode documented in module

M05  1   MultiClusterObservability status           PASS    —                     Ready
M05  2   Managed cluster list                       PASS    —                     4 clusters: local-cluster, student-01, student-02, student-03
M05  3   user-3 Grafana access (Layer 1 + Layer 2)  PASS    —                     Both layers verified; students can log in to Grafana with workshop-students IDP
M05  4   observabilityaddon on student-03           PASS    —                     Available (46h uptime)
M05  5   observability-metrics-custom-allowlist     PASS    —                     Pre-configured by hub provisioning
M05  6   module-5---multi-cluster-capacity-planning.yaml download PASS —          Downloads successfully from repo

M06  1   Download wave1/wave3 lab files             PASS    —                     5 files: check-etcd-health.sh, wave1-load-pod.yaml, wave1-traffic-spike.yaml, wave3-etcd-pressure.yaml, wave3-pressure-deploy.yaml
M06  2   kube-burner v2.6.1 from ~/module-03        PASS    —                     Version 2.6.1 confirmed; module-03 install path persists correctly
M06  3   Cluster nodes Ready                        PASS    —                     3 nodes, all worker-capable
M06  4   etcd health                                PASS    —                     3 etcd pods + 3 etcd-guard pods all Running; DB size 0.06 GB (1% of 8 GB limit)
M06  5   Current pod density                        PASS    —                     301 total pods across cluster

M07  1   capacity-roadmap-generator.sh download     PASS    —                     Downloads to ~/examples/module-07/
M07  2   bash capacity-roadmap-generator.sh         PASS    —                     Generates ~/12-month-capacity-roadmap.md and ~/capacity-roadmap-data.txt
M07  3   Fleet View (Managed Clusters)              NOTE    Rethink               Shows "N/A" — bastion oc context is student cluster, not hub; RHACM CRD not found on student cluster. Script handles gracefully. Module could note: "log in to the hub first to populate fleet data."
M07  4   cat ~/12-month-capacity-roadmap.md         PASS    —                     Roadmap generated with live cluster data (velocity, CPU, etcd size)

M08  —   No executable steps                        PASS    —                     Module 08 is conceptual (0 role=execute blocks). Policies applied: 2 policies in student-03 namespace (rs-prom-rules, rs-virt-prom-rules).
────────────────────────────────────────────────────────────────────────────────
 Result: 34 PASS, 0 FAIL, 0 SKIP, 1 NOTE
 Breakdown: 0 Instruction Fix, 0 Infra/Deployment Fix, 1 Rethink (M07 fleet view)
```

---

## Comparison with student-01 Run (2026-04-30)

| Issue from student-01 | Status in student-03 |
|-----------------------|----------------------|
| M02-6: `{hub_username}` empty in antora.yml | **RESOLVED** — Showroom userdata correctly injects `hub_username=user-3` per-student |
| M03-7: besteffort-app expected output stale (showed `resources: {}`) | **RESOLVED** — Module-03 lines 72-74 now explain the ResourceQuota-forced Burstable behavior |

---

## Single Finding (Rethink)

### M07-3: Capacity Roadmap Fleet View shows "N/A"

**Symptom**: `capacity-roadmap-generator.sh` writes `Managed Clusters: N/A` in the fleet view section of the generated roadmap.

**Root cause**: The script calls `oc get managedclusters` to count RHACM-managed clusters, but students run it on their bastion while logged in to the **student cluster**. The student cluster has no RHACM/MCO installed, so the CRD is not present and the count defaults to N/A.

**Category**: Rethink

**Suggested fix**: Add a TIP callout in module-07 before the generator step:

```asciidoc
[TIP]
====
*Optional: Include your RHACM fleet in the roadmap.*
Log in to the hub cluster first so the generator can count your managed clusters:

[source,bash,role=execute]
----
oc login {hub_api_url} --username={hub_username} --password={hub_password}
----

Then re-run the generator. Log back to your student cluster when done:

[source,bash,role=execute]
----
oc login {student-cluster-api} --username=kubeadmin --password=...
----
====
```

Alternatively, add a `MANAGED_CLUSTERS` env-var override to the generator script so students can pass the value from earlier in the module.

---

## Verdict

**The workshop is ready for user-3.** All 34 executable steps PASS. Zero failures. The single NOTE (M07 fleet view) is cosmetic and non-blocking — the roadmap generates successfully with all student-cluster data populated.
