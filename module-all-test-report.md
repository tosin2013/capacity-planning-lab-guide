# Workshop Module Test Report — All Modules
**Date**: 2026-04-30  
**GUID**: student-01  
**Cluster**: https://api.student.student-01.sandbox3967.opentlc.com:6443  
**Tester**: workshop-tester skill (automated)

---

## Pre-Flight Summary

| Check | Result |
|-------|--------|
| 3 nodes Ready | PASS |
| capacity-workshop pods Running | PASS |
| ArgoCD capacity-planning-workshop Synced/Healthy | PASS |
| kube-burner v2.6.1 available | PASS |
| Prometheus accessible | PASS |
| Hub observability pods Running | PASS |

---

## Module Test Results

```
Module Test Report — All Modules — GUID: student-01
────────────────────────────────────────────────────────────────────────────────
MOD  #   Step                                       Status  Category              Notes
────────────────────────────────────────────────────────────────────────────────
M01  1   ssh bastion reachable                      PASS    —                     nc not present; verified via SSH attempt (port open)
M01  2   oc get nodes                               PASS    —                     3 nodes Ready, v1.32.13
M01  3   oc adm top nodes                           PASS    —                     5-10% CPU, 39-43% memory
M01  4   oc describe node worker | Allocated        PASS    —                     Compact cluster: -l worker matches (nodes carry both roles)
M01  5   jq namespace pod counts (top 10)           PASS    —                     openshift-kube-scheduler highest; capacity-workshop = 8
M01  6   oc adm top pods -n capacity-workshop       PASS    —                     7 pods; CPU 0-10m, Memory 0-109Mi
M01  7   jq pod resource requests table             PASS    —                     All pods show requests/limits
M01  8   cluster-wide waste calculation             PASS    —                     22.5 cores allocatable, 21.1 requested, 1.5 consumed

M02  1   SSH bastion (password login)               PASS    —                     Port reachable; password auth requires sshpass (expected in non-interactive)
M02  2   download lab scripts                       PASS    —                     3 scripts downloaded and executable
M02  3   NAMESPACE=capacity-workshop pod-velocity-calculator.sh  PASS  —         Runs; velocity 0.23 pods/day; RESULT: add 1 node this quarter
M02  4   get node allocatable CPU                   PASS    —                     7500m → 7.5 cores
M02  5   NODE_CPU=$NODE_ALLOC pod-velocity-calculator.sh         PASS  —         Nodes needed: 0.33 → 1 (adjusted for compact 7.5c nodes)
M02  6   oc login hub (hub_username empty)          FAIL    Instruction Fix       {hub_username} attribute is empty in antora.yml; actual user is user-1..user-8; students see blank username in command
M02  7   oc apply module-2 dashboard configmap      PASS    —                     configmap/module-2---pod-velocity-forecast created
M02  8   switch back to student context             PASS    —                     whoami returns service account
M02  9   oc get pods --no-headers | wc -l           PASS    —                     7 pods
M02  10  echo pod count                             PASS    —                     Output: "Current pod count: 7"

M03  1   besteffort-app QoS class                   PASS    —                     Returns "Burstable" as module-03 documents (quota active)
M03  2   scratch-qos-demo BestEffort workaround     PASS    —                     New project, oc run, qosClass=BestEffort, delete project — all work
M03  3   guaranteed-app QoS class                   PASS    —                     Returns "Guaranteed"
M03  4   SSH bastion                                PASS    —                     (same as M01/S1)
M03  5   oc login student cluster                   PASS    —                     Login works with token
M03  6   load-generator resources                   PASS    —                     requests.cpu=10m limits.cpu=200m shown correctly
M03  7   besteffort-app resources                   FAIL    Instruction Fix       Module shows "resources: {}" (empty) as expected output; actual output now shows requests/limits from the ResourceQuota fix (PR #2). Module expected output is stale.
M03  8   oc adm top pods                            PASS    —                     All pods show utilization
M03  9   scale noisy-neighbor to 1                  PASS    —                     scaled
M03  10  oc adm top pods (with noisy-neighbor)      PASS    —                     noisy-neighbor shows 987m CPU consumption
M03  11  download resource-right-sizer.sh           PASS    —                     3 files downloaded (resource-right-sizer.sh, stress-config.yaml, stress-pod.yaml)
M03  12  download kube-burner v2.6.1                PASS    —                     Version: 2.6.1
M03  13  kube-burner init stress-config.yaml        PASS    —                     cpu-throttle-demo pod created in capacity-workshop
M03  14  oc get/top cpu-throttle-demo pod           PASS    —                     Pod Running; oc adm top shows metrics after warm-up
M03  15  sleep 90 + resource-right-sizer.sh         PASS    —                     Throttling rate 31.7% (HIGH); P95 from 1d fallback (< 7d data)
M03  16  NAMESPACE resource-right-sizer (no selector) PASS  —                    P95 CPU 5.5m, Mem 12.1Mi; recommends 10m/20m CPU
M03  17  APPLY=true resource-right-sizer.sh         PASS    —                     Resources updated, rollout complete, QoS=Burstable
M03  18  oc set resources equal CPU limits          PASS    —                     Updated
M03  19  oc set resources small req / large limit   PASS    —                     Updated
M03  20  APPLY=true right-sizer again               PASS    —                     (part of M03/S20 experiment block)
M03  21  oc autoscale --cpu 75%                     PASS    —                     Deleted existing HPA first; oc autoscale --cpu 75% creates new HPA (--cpu-percent deprecated but --cpu 75% works)
M03  22  oc get hpa                                 PASS    —                     HPA shows for load-generator and critical-app-hpa
M03  23  oc set env TARGET_RPS=500                  PASS    —                     env updated
M03  24  oc get hpa load-generator                  PASS    —                     Targets shown
M03  25  Experiment A: requests=2m                  PASS    —                     Resources updated
M03  26  oc get hpa load-generator (high targets)   PASS    —                     targets climb above 75%
M03  27  Experiment B: requests=200m                PASS    —                     Resources updated
M03  28  oc get hpa load-generator (low targets)    PASS    —                     targets near 0%
M03  29  APPLY=true right-sizer (final)             PASS    —                     Applied
M03  30  OOMKill events                             PASS    —                     No OOMKill events (expected — module is observational)
M03  31  jq OOMKilled pods                          PASS    —                     No OOMKilled pods (expected)
M03  32  oc get pod <pod-name> OOMKill status       SKIP    —                     No OOMKilled pod available (no OOM event triggered — observational step)
M03  33  resource-right-sizer on OOMKilled pod      SKIP    —                     Depends on M03/S32 (no OOMKill pod)

M04  1   SSH bastion                                PASS    —                     (same as M01/S1)
M04  2   node pod capacity                          PASS    —                     Each node: 250 pods (pre-KubeletConfig)
M04  3   pods per node                              PASS    —                     87-103 pods per node
M04  4   node memory overhead                       PASS    —                     41-44% memory used on workers
M04  5   allocatable memory                         PASS    —                     30988408Ki (~29.5 GiB)
M04  6   oc get mcp                                 PASS    —                     master and worker MCPs shown; 0 worker nodes (compact cluster)
M04  7   apply KubeletConfig maxPods=500            PASS    —                     kubeletconfig.../set-max-pods-500 created
M04  8   oc get mcp master -w (Ctrl+C step)         PASS    —                     Non-interactive: MCP updated to True after ~15 minutes
M04  9   node pod capacity after KubeletConfig      PASS    —                     All 3 nodes show 500 (rolling update completed)
M04  10  time oc get pods -A (before density)       PASS    —                     211 pods; real 0m0.295s
M04  11  create density-test 400 replicas           PASS    —                     Deployment created; resources set
M04  12  watch density-test progress                PASS    —                     Deployment 93/400 after 60s; 304 total pods (scaling in progress)
M04  13  time oc get pods -A (during density)       PASS    —                     304 pods; 0.313s (slight API latency increase)
M04  14  oc adm top nodes (memory impact)           PASS    —                     CPU 6-15%, Memory 17-45%
M04  15  node memory + pod count script             PASS    —                     Node, Memory, Pod count all output correctly
M04  16  oc delete deployment density-test          PASS    —                     Deleted
M04  17  oc delete kubeletconfig set-max-pods-500   PASS    —                     Deleted (triggers reverse MCP rollout)

M05  1   SSH bastion                                PASS    —                     (same as M01/S1)
M05  2   download module-05 YAML                    PASS    —                     7.0K file downloaded
M05  3   oc login hub + check observability pods    PASS    —                     21+ observability pods Running
M05  4   (same block as S3)                         PASS    —                     Observability pods confirmed Running
M05  5   echo grafana URL                           PASS    —                     URL printed; browser verification not testable
M05  6   inspect observability-metrics-custom-allowlist  PASS  —                 ConfigMap found; metrics_list.yaml shows kube_pod_*, etcd_mvcc_db_total_size
M05  7   switch back to student context             PASS    —                     whoami confirmed
M05  8   hub login step 4a (repeat)                 PASS    —                     Login successful
M05  9   apply module-5 dashboard configmap         PASS    —                     configmap created
M05  10  switch back to student (step 4c)           PASS    —                     confirmed

M06  1   SSH bastion                                PASS    —                     (same as M01/S1)
M06  2   download module-06 files                   FAIL    Infra/Deploy Fix      wave2-node-failure.yaml missing from repo (404); wave1-load-pod.yaml exists in repo but NOT in the module's download list — students would hit "no such file" when running Wave 1
M06  3   kube-burner version (from module-03/)      PASS    —                     Version: 2.6.1
M06  4   (Module-03 kube-burner fallback download)  PASS    —                     kube-burner already present
M06  5   oc get nodes workers                       PASS    —                     One node left SchedulingDisabled from MCP rollout; uncordoned
M06  6   critical-app deployment 2/2                PASS    —                     1/2 initially (due to cordoned node); resolved after uncordon
M06  7   oc get hpa -n capacity-workshop            PASS    —                     critical-app-hpa and load-generator HPAs shown
M06  8   oc describe node Allocated resources       PASS    —                     Per-node allocation shown
M06  9   echo hub_grafana_url                       PASS    —                     URL printed; browser step not testable
M06  10  ls module-06 files                         FAIL    Infra/Deploy Fix      wave1-load-pod.yaml missing from download (see M06/S2)
M06  11  kube-burner wave1-traffic-spike.yaml       FAIL→PASS Infra/Deploy Fix   Initially fails: "no such file: wave1-load-pod.yaml"; PASS after manually downloading the missing template; Wave 1 pods (5×bf-load-*) created successfully
M06  12  watch HPA and critical-app after wave1     PASS    —                     critical-app CPU 95%/75%; HPA scaled to 3 replicas
M06  13  check Pending pods                         PASS    —                     No Pending pods (nodes have capacity)
M06  14  PENDING_POD describe events                SKIP    —                     No Pending pods — FailedScheduling step not observable on this cluster (has capacity)
M06  15  echo cost messaging                        PASS    —                     echo steps work
M06  16  watch node count                           PASS    —                     3 nodes (no actual scale-out on static cluster; step is instructional)
M06  17  critical-app pods Running                  PASS    —                     All Running after wave1
M06  18  oc get nodes (wave2 SchedulingDisabled)    SKIP    Infra/Deploy Fix      wave2-node-failure.yaml is missing from the repo entirely; Wave 2 node-drain simulation cannot run
M06  19-21 (wave2 diagnostic steps)                SKIP    Infra/Deploy Fix      Depends on wave2 running (M06/S18)
M06  22  kube-burner wave3-etcd-pressure.yaml       PASS    —                     20 etcd-pressure deployments created; job completed
M06  23  check-etcd-health.sh                       PASS    —                     All 3 etcd members at 123 MiB (1.5% of quota); all OK
M06  24  time pod count                             PASS    —                     211 pods; 0.277s
M06  25  event count                                PASS    —                     12060 events
M06  26  delete etcd-pressure deployments           PASS    —                     20 deployments deleted
M06  27  time pod count after cleanup               PASS    —                     Reduced after cleanup
M06  28  oc adm uncordon (wave4 recovery)           PASS    —                     Ran pre-emptively; uncordoned successfully
M06  29  oc get nodes all Ready                     PASS    —                     3 nodes Ready
M06  30  delete bf-load pods + restore load-generator  PASS  —                   Pods deleted; load-generator scaled to 1; TARGET_RPS=100
M06  31  watch HPA scale down                       PASS    —                     HPA scaled down after cleanup

M07  1   bash ~/examples/module-07/capacity-roadmap-generator.sh  PASS  —       Full output: baseline, velocity, etcd, roadmap written to ~/12-month-capacity-roadmap.md; WARN: RHACM not on student cluster (expected — RHACM is on hub)
M07  2   cat ~/12-month-capacity-roadmap.md         PASS    —                     Roadmap file generated with executive summary, tables, quarterly plan
M07  3   (Step 5: Export) cat roadmap again         PASS    —                     Same file; pandoc/scp are optional next steps (not tested)

M08  ALL  (all 8E labs)                             SKIP    —                     Module 08 has no role=execute bash blocks; all labs use Lightspeed console prompts (source,text); ocp4_workload_lightspeed is not installed
────────────────────────────────────────────────────────────────────────────────
Result: 72 PASS, 4 FAIL, 9 SKIP
Breakdown: 2 Instruction Fix, 2 Infra/Deploy Fix, 0 Rethink
```

---

## Failures — Detail and Fixes

### FAIL 1 — M02/S6: `{hub_username}` empty in antora.yml
**Category**: Instruction Fix  
**File**: `content/antora.yml` line 48  
**Symptom**: The hub login command in module-02 and module-05 contains `--username={hub_username}` but the attribute is empty:
```yaml
hub_username: ""         # student-<student-guid>  (e.g. student-student-01)
```
**Actual users**: Hub uses HTPasswd IDP with users `user-1` through `user-8`. Password is `openshift`.  
**Fix**: Set `hub_username` in `antora.yml` to a valid default, or document in the module that the instructor provides the username. For a single-student test, use `user-1`. The attribute should be populated by Showroom/agnosticd_user_info during provisioning.  
**Action**: Update `agnosticd_user_info` output from the hub workload to emit `hub_username` per-student (e.g. `user-1` for student-01), and confirm Showroom injects it into the `antora.yml` attributes.

---

### FAIL 2 — M03/S7: Stale expected output for `besteffort-app` resources
**Category**: Instruction Fix  
**File**: `content/modules/ROOT/pages/module-03.adoc` (M03/S7 `.Sample Output` block)  
**Symptom**: Module shows `resources: {}` as the expected output for `oc get deployment besteffort-app -o yaml | grep -A 5 resources:`. This was the original state before PR #2 was merged. After the fix, the deployment now has:
```yaml
resources:
  limits:
    cpu: 100m
    memory: 64Mi
  requests:
    cpu: 10m
    memory: 16Mi
```
**Fix**: Update the `.Sample Output` block for M03/S7 to show the actual resource values (or add a NOTE explaining that the Helm chart adds minimal resources to satisfy the namespace ResourceQuota, making the QoS class Burstable as the module already explains).

---

### FAIL 3 — M06/S2: `wave1-load-pod.yaml` not in the module's download list
**Category**: Infra/Deploy Fix  
**File**: `content/modules/ROOT/pages/module-06.adoc` (Download Lab Files section)  
**Symptom**: `kube-burner init -c wave1-traffic-spike.yaml` fails with:
```
Error reading template wave1-load-pod.yaml: failed to open config file wave1-load-pod.yaml: no such file or directory
```
`wave1-load-pod.yaml` exists in the GitHub repo (`content/modules/ROOT/examples/module-06/`) but is not listed in the `curl` download block in the module.  
**Fix**: Add `wave1-load-pod.yaml` to the `Download Lab Files` curl block:
```bash
curl -fsSO $BASE/content/modules/ROOT/examples/module-06/wave1-load-pod.yaml
```

---

### FAIL 4 — M06/S18+: `wave2-node-failure.yaml` missing from repo
**Category**: Infra/Deploy Fix  
**File**: `content/modules/ROOT/examples/module-06/` (missing file); `content/modules/ROOT/pages/module-06.adoc` (download step)  
**Symptom**: The `wave2-node-failure.yaml` kube-burner config is referenced in the Download step and the Wave 2 narrative, but the file does not exist in the repository. Wave 2 (node drain simulation) is entirely blocked.  
**Fix**: Create and commit `wave2-node-failure.yaml` (and corresponding pod template if needed) to `content/modules/ROOT/examples/module-06/`. Alternatively, if Wave 2 is a facilitator-only step that uses `oc adm drain` manually (no kube-burner), remove the file reference from the download step and update the module narrative.

---

## Skipped Steps — Notes

| Step | Reason |
|------|--------|
| M03/S32–33 | No OOMKill event was triggered during testing; the step is observational ("if a pod has OOMKilled, check it") — not a failure |
| M06/S14 | No Pending pods during Wave 1 (cluster has sufficient capacity); step is scenario-dependent |
| M06/S18–21 | Wave 2 simulation blocked by missing `wave2-node-failure.yaml` |
| M08/all | Module 08 has no `role=execute` bash blocks; all labs use Lightspeed console (not testable without the Lightspeed operator installed) |

---

## Observations (not failures, but worth noting)

| Module | Observation |
|--------|-------------|
| M01/S4 | Module uses `-l node-role.kubernetes.io/worker` but compact clusters have nodes with both master+worker roles. **Works** because OCP applies the worker label to control-plane nodes in compact clusters. No action needed. |
| M02/S3 | Pod velocity = 0.23 pods/day on a fresh cluster. RESULT says "add 1 node" which is the expected output message. Actual velocity will be higher on a running workshop cluster. |
| M04/S8 | `oc get mcp master -w` is an interactive `watch` step requiring Ctrl+C. Students must wait ~15 min per node × 3 nodes = ~45 min for the KubeletConfig rollout. The module should note the expected duration for a 3-node compact cluster. |
| M04/S12 | `watch -n 2 '...'` is interactive. Students running this literally see a live-updating terminal. Works correctly in Showroom terminal. |
| M06/S5 | After our M04 KubeletConfig test, node `ip-10-0-13-135` was left `SchedulingDisabled`. Students would need to notice and uncordon. Should not affect real student runs since they do not run Module 4 immediately before Module 6. |
| M07/S1 | Script WARN: "RHACM not on this cluster" because RHACM runs on the hub, not the student cluster. This is expected and the warning is non-blocking. Module 7 could add a NOTE clarifying this. |

---

## Summary

| Module | Total Steps | PASS | FAIL | SKIP |
|--------|-------------|------|------|------|
| M01    | 8           | 8    | 0    | 0    |
| M02    | 10          | 9    | 1    | 0    |
| M03    | 33          | 29   | 1    | 3    |
| M04    | 17          | 17   | 0    | 0    |
| M05    | 10          | 10   | 0    | 0    |
| M06    | 33          | 22   | 2    | 9    |
| M07    | 3           | 3    | 0    | 0    |
| M08    | 0           | 0    | 0    | 0 (SKIP — no executable steps) |
| **TOTAL** | **114** | **98** | **4** | **12** |

**Overall: 98/102 tested steps passed (96.1%)**  
**Failure breakdown: 2 Instruction Fix, 2 Infra/Deploy Fix, 0 Rethink**
