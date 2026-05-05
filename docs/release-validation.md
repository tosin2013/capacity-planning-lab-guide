# Release Validation Guide

This document describes how to validate all workshop `oc` commands whenever a new OpenShift Container Platform (OCP) release is targeted. Run this process before updating `host_ocp4_installer_version` in the deploy vars, or after updating that version and provisioning a test environment.

---

## When to run this

- Before bumping `host_ocp4_installer_version` in `deploy/vars/hub-aws.yml` or `deploy/vars/student.yml`
- After provisioning a fresh test environment at the new OCP version
- When the `oc` CLI introduces deprecation warnings or removes flags
- After any change to the lab module `.adoc` content that adds new `oc` commands

---

## Step 1 — Update `oc` on existing bastions

If you have an existing workshop environment provisioned at an older version and want to test the newer `oc` CLI against it, run:

```bash
# Defaults to stable-4.21; override with OC_VERSION env var
OC_VERSION=stable-4.22 bash scripts/update-oc-clients.sh
```

The script reads bastion hostnames and passwords from `student-info.txt`, connects to all bastions in parallel, downloads the OpenShift client tarball from the Red Hat mirror, and reports the installed version.

Expected output:
```
=== OC Client Update: stable-4.21 ===
Bastions: bastion.student-01... bastion.student-02...
...
PASS [bastion.student-01.sandbox1784.opentlc.com]
       Client Version: 4.21.12
PASS [bastion.student-02.sandbox1784.opentlc.com]
       Client Version: 4.21.12
...
=== Summary: 4 PASS  0 FAIL ===
```

> **Note:** New deployments pick up the correct `oc` version automatically via `host_ocp4_installer_version` — this script is only needed for in-place bastion upgrades.

---

## Step 2 — Dry-run module command validation

Run the validation script against a single student bastion (defaults to `student-04`):

```bash
bash scripts/validate-module-commands.sh [student-id]

# Examples:
bash scripts/validate-module-commands.sh student-04
bash scripts/validate-module-commands.sh student-01
```

The script:
1. Reads bastion credentials from `student-info.txt`
2. SSHes to the target bastion
3. Runs every version-sensitive `oc` command from modules 3, 4, and 6 using `--dry-run=client` where applicable
4. Prints `PASS`/`FAIL` per command and a summary

Expected output (all green):
```
=== Module Command Validation ===
...
--- Module 3 ---
PASS [M3: oc run besteffort-test --dry-run=client]
PASS [M3: oc autoscale --cpu 75% --dry-run=client]
PASS [M3: oc set resources (check flag exists)]
...
=== Summary: N PASS  0 FAIL ===
```

---

## Step 3 — Investigate any failures

If a command fails or shows a deprecation warning, check `oc <command> --help` for the new flag syntax and update the corresponding `.adoc` file in `content/modules/ROOT/pages/`.

---

## Version history of CLI changes

| OCP version | Command affected | Old syntax | New syntax | Module |
|-------------|-----------------|------------|------------|--------|
| 4.19 | `oc autoscale` | `--cpu 75%` (new style, not yet in 4.19 oc) | `--cpu-percent=75` | module-03 |
| 4.21 | `oc autoscale` | `--cpu-percent=75` (deprecated) | `--cpu 75%` | module-03 |

> The `--cpu-percent` flag still works in 4.21 but shows a deprecation warning. The preferred syntax is `--cpu <value>%`.

---

## Module command inventory

The table below lists every version-sensitive `oc` command in the lab modules. Check these first when upgrading to a new OCP release.

### Module 3 — QoS, HPA, Right-Sizing

| Command | File:Line | Notes |
|---------|-----------|-------|
| `oc run besteffort-test --image=... -- sleep 3600` | `module-03.adoc:81` | `oc run` behavior may narrow in future releases; validates with `--dry-run=client` |
| `oc autoscale deployment load-generator --min=1 --max=5 --cpu 75%` | `module-03.adoc:464` | CPU flag syntax — watch for changes each release |
| `oc set resources deployment ... --requests=... --limits=...` | `module-03.adoc:400,416,424,515,537` | Stable; flag names unchanged since OCP 4.x |
| `oc set env deployment/... TARGET_RPS=500` | `module-03.adoc:479` | Stable |
| `oc rollout status deployment/... --timeout=60s` | `module-03.adoc:523,545` | Stable |
| `oc adm top pods -n ...` / `oc adm top pod -l ...` | `module-03.adoc:178,289` | Depends on metrics-server; output columns may vary |

### Module 4 — Node Density

| Command | File:Line | Notes |
|---------|-----------|-------|
| `oc create deployment density-test --image=... --replicas=400 -- sleep infinity` | `module-04.adoc:579` | `-- sleep infinity` argument separator; validates with `--dry-run=client` |
| `oc set resources deployment density-test --requests=... --limits=...` | `module-04.adoc:580` | Stable |
| `oc adm top nodes -l node-role.kubernetes.io/worker` | `module-04.adoc` | Depends on metrics-server |

### Module 6 — Node Lifecycle / Scaling

| Command | File:Line | Notes |
|---------|-----------|-------|
| `oc adm cordon <node>` | `module-06.adoc:489` | Stable |
| `oc adm drain <node> --ignore-daemonsets --delete-emptydir-data --force --grace-period=30` | `module-06.adoc:493` | `--delete-emptydir-data` replaced `--delete-local-data` in OCP 4.8; verify flag name each release |
| `oc adm uncordon <node>` | `module-06.adoc:869` | Stable |
| `oc scale machineset <name> -n openshift-machine-api --replicas=N` | `module-06.adoc:414` | Stable; validates with `--dry-run=client` |
| `oc adm top nodes` | `module-06.adoc` | Stable |

---

## Adding new commands to the inventory

When adding new `oc` commands to any module `.adoc` file:

1. Add the command to the table in the relevant module section above.
2. If the command mutates cluster state, add a `--dry-run=client` check for it in `scripts/validate-module-commands.sh`.
3. Run the validation script to confirm it passes before merging.
