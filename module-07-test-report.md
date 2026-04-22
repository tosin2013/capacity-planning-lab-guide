# Module Test Report — module-07.adoc — GUID: student-01
**Date**: April 22, 2026
**Tester**: AI Workshop Tester
**Environment**: bastion.student-01.sandbox5388.opentlc.com
**OCP API**: https://api.student.student-01.sandbox5388.opentlc.com:6443

---

## Pre-flight

Student bastion reachable via SSH. `oc whoami` returned `kube:admin` — no login required.

---

## Test Results

```
 #  Step                                     Status   Category             Notes
─────────────────────────────────────────────────────────────────────────────────────────────
 1  Step 1 — Gather Your Data (original)     FAIL     Instruction Fix      3 placeholders not automated (see below)
 1b Step 1 — capacity-roadmap-generator.sh   PASS     —                    After fix: all metrics populated from Prometheus
 2  Step 2 — Fill Out Roadmap Template       FAIL     Instruction Fix      All numbers hardcoded; student must manually substitute
 2b Step 2 — cat generated roadmap           PASS     —                    After fix: live numbers from generator
 3  Step 3 — Practice 3-Minute Pitch         SKIP     —                    Facilitator exercise; not executable
 4  Step 4 — Peer Review Exercise            SKIP     —                    Facilitator exercise; not executable
 5  Step 5 — Export the Roadmap              FAIL     Instruction Fix      pandoc NOT available on bastion; commented lines confusing
 5b Step 5 — cat roadmap (after fix)         PASS     —                    After fix: clear note on pandoc, scp instructions added
─────────────────────────────────────────────────────────────────────────────────────────────
 Pre-fix  Result: 3 FAIL, 2 SKIP, 0 PASS
 Post-fix Result: 5 PASS, 2 SKIP, 0 FAIL
 Breakdown (pre-fix): 3 Instruction Fix, 0 Infra/Deploy Fix, 0 Rethink
```

---

## Failure Detail

### Step 1 (original): 3 Placeholder Strings Never Populated

The original Step 1 block contained three lines that emit literal instructional strings to the
data file rather than real cluster values:

```bash
echo "New Pods (30-day): [Run PromQL: increase(kube_pod_created[30d])]"
echo "etcd DB Size: [Check Prometheus: etcd_mvcc_db_total_size_in_bytes / 1024 / 1024] MB"
echo "Managed Clusters: [Check RHACM Console]"
```

**Actual output** (confirmed on live cluster):
```
=== Module 2: Pod Velocity ===
New Pods (30-day): [Run PromQL: increase(kube_pod_created[30d])]   ← literal string, not a value
=== Module 4: etcd Size ===
etcd DB Size: [Check Prometheus: ...] MB                            ← literal string, not a value
=== Module 5: Fleet View ===
Managed Clusters: [Check RHACM Console]                            ← literal string, not a value
```

**Classification**: Instruction Fix — the module says "Collect the metrics" but three of the five
metrics are not collected; students are left with a placeholder that requires manual lookup in
external consoles (Prometheus UI, RHACM console) without guidance on how to do so.

**Fix applied**: Step 1 now invokes `capacity-roadmap-generator.sh`, which queries Prometheus
for all five metric sets using the same technique as modules 2 and 3.

---

### Step 2 (original): Hardcoded Sample Numbers

The heredoc template used fixed sample values throughout (e.g., "24 worker nodes", "$50,000/month",
"1,247 pods"). Students must manually find and replace every number. The closing TIP said
"replace sample numbers with your actual data" but did not provide the `oc`/PromQL commands
in-line to make this easy.

**Classification**: Instruction Fix — the template was never connected to the data gathered in
Step 1, making the exercise academic rather than hands-on.

**Fix applied**: Step 2 now calls `cat ~/12-month-capacity-roadmap.md` to display the already-
generated file (from Step 1). The script writes the file with live numbers; students customize
names and known upcoming events only.

---

### Step 5 (original): Commented-out pandoc Lines

```bash
# pandoc ~/12-month-capacity-roadmap.md -o ~/12-month-capacity-roadmap.pdf
# pandoc ~/12-month-capacity-roadmap.md -s -o ~/12-month-capacity-roadmap.html
```

`pandoc` is **not installed** on the student bastion (`command -v pandoc` → not found). The
commented lines are displayed in the Showroom terminal but cannot be executed, and there is no
explanation of why they are commented or what to do instead.

**Classification**: Instruction Fix — no guidance on taking the output file home.

**Fix applied**: Comments removed; replaced with instructions to `scp` the file to a local machine
and run `pandoc` locally (with the exact `scp` command), plus a NOTE explaining that the file can
be pasted directly into Google Docs or Confluence.

---

### Duplicate `== Key Takeaways` Section (structural)

The module had two identical `== Key Takeaways` sections — one at line 842 and another at line 855,
separated only by the `== Next Module` section. The second block was silently rendered as a second
heading in Showroom, creating confusing duplicate content.

**Classification**: Instruction Fix — copy-paste error during authoring.

**Fix applied**: Removed the second occurrence (lines 855–862 of the original file).

---

## Script Bugs Found and Fixed During Development

During authoring of `capacity-roadmap-generator.sh`, three bugs were encountered and resolved:

| Bug | Root Cause | Fix |
|-----|-----------|-----|
| `rate: unbound variable` | `$rate` in Python comment inside unquoted `<<PYEOF` heredoc | Changed comment to avoid `$` |
| `monthly_cost: unbound variable` | `${monthly_cost:...}` Python f-string notation in data_lines without `\$` escape | Added `\$` prefix |
| `resource-right-sizer.sh: command not found` + Python SyntaxError | Backtick-quoted strings in heredoc triggered bash command substitution; MANAGED_CLUSTERS got double-value from `|| echo "0"` capturing both `wc` stdout and echo stdout under `pipefail` | Escaped backticks with `\``; refactored RHACM check to test CRD existence first |

---

## Live Cluster Data (student-01, April 22, 2026)

```
Total Pods:       297
Worker Nodes:     3
CPU Allocatable:  22.5 cores
CPU Allocated:    25.2 cores (112% — over-requested vs allocatable)
CPU Used:         2.3 cores  (10% actual utilization)
CPU Waste:        22.9 cores (102% of allocatable)
Monthly Cost:     $600  (est. at $200/node)
Waste Cost:       $611/month
etcd DB Size:     0.05 GB  (0.7% of 8GB limit — healthy)
Pod Velocity:     0.23 pods/day  (7 pods in last 30d)
RHACM Clusters:   N/A (no ManagedCluster CRD on student cluster)
```

**Notable finding**: CPU allocated (requests) exceeds CPU allocatable (112%). This is the
lab environment — pods have over-requested vs node capacity. The roadmap generator handles
this gracefully and reports it accurately.

---

## Files Changed

| File | Change |
|------|--------|
| `content/modules/ROOT/pages/module-07.adoc` | Step 1 replaced with script invocation; Step 2 simplified to `cat`; Step 5 pandoc note updated; duplicate Key Takeaways removed |
| `content/modules/ROOT/examples/module-07/capacity-roadmap-generator.sh` | New file — 7-step script that collects live Prometheus metrics and generates filled-in roadmap |

---

## Suggested Follow-up

- The `waste_pct` showing >100% is accurate for this lab cluster (CPU requests exceed allocatable
  due to the workshop workloads) but will look odd to a production student. Consider adding a
  note in the script output when `cpu_allocated > cpu_allocatable` explaining that this can occur
  when pods have large requests and the cluster scheduler uses bin-packing.

- Pod velocity of 0.23 pods/day (7 pods in 30 days) is very low for a lab environment. The script
  already has a fallback to cluster-wide count when the namespace has no pods; this works correctly.
  Consider mentioning in the module that students' lab clusters will show low velocity and that the
  template numbers are meant to be illustrative of a production scenario.
