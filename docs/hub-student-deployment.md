# Hub-Student Deployment Guide

Operator reference for deploying the Strategic Capacity Planning workshop on Red Hat Demo Platform (RHDP) using AgnosticD v2 in a hub-student topology.

---

## Quick Start

Use the idempotent deploy script for all provisioning. It handles pre-flight quota checks, skips clusters that are already healthy, bootstraps var file templates on first run, and deploys multi-user Showroom at the end.

```bash
# Step A — First time on a new jumpbox: bootstrap var file templates and get instructions.
# The script exits immediately with a setup checklist — no clusters are provisioned yet.
cd ~/capacity-planning-lab-guide
bash scripts/deploy-workshop.sh --account sandbox<N>

# Step B — Edit the bootstrapped files (~5 min):
#   ~/agnosticd-v2-vars/hub-aws.yml               replace <YOUR_EMAIL>
#   ~/agnosticd-v2-vars/student-{01,02,03}.yml     replace <YOUR_EMAIL>
#                                                  (leave hub_rhacm_url placeholder for now)
#   ~/agnosticd-v2-secrets/secrets-sandbox<N>.yml  fill in AWS keys + base_domain
#                                                  + ocp4_pull_secret (from console.redhat.com)

# Step C — Provision hub + students in one run (~3–4 hours total):
bash scripts/deploy-workshop.sh --account sandbox<N>
# The hub provisions first (~90 min), then students run in sequence (~60–75 min each).

# Step D — After the run completes, update hub_rhacm_url in each student-NN.yml:
#   The correct URL is in ~/agnosticd-v2-output/hub-capacity/provision-user-data.yaml
HUB_RHACM=$(grep "^hub_rhacm_url:" \
  ~/agnosticd-v2-output/hub-capacity/provision-user-data.yaml | awk '{print $2}')
echo "Paste this into each student-NN.yml: $HUB_RHACM"
#   Then edit ~/agnosticd-v2-vars/student-{01,02,03}.yml and replace the placeholder line.

# Step E — Re-run to apply the corrected URL to all student clusters (hub is skipped):
bash scripts/deploy-workshop.sh --account sandbox<N> --skip-hub
```

> **Why update hub_rhacm_url after the initial run?** The `hub_rhacm_url` in each student var file pre-populates the Module 5 RHACM console link in the AgnosticD provision output. It cannot be filled in before the hub exists. The Showroom lab guide itself always uses the correct URL (injected by `deploy-multiuser-showroom.sh` from the actual hub output), so student clusters are fully functional after Step C — Step E just ensures the `agnosticd_user_info` log output is also correct.

```bash
# Re-run safely after a failure (already-healthy clusters are skipped):
bash scripts/deploy-workshop.sh --account sandbox<N>

# Skip the Showroom deployment step (e.g. already done):
bash scripts/deploy-workshop.sh --account sandbox<N> --skip-showroom

# Preview what would run without executing:
bash scripts/deploy-workshop.sh --account sandbox<N> --dry-run
```

Access information for all clusters is written to `student-info.txt` (gitignored) after each run.

The manual step-by-step instructions below remain useful for understanding the topology or performing individual operations.

---

## Architecture

```
┌─────────────────────────────────────┐
│  Hub cluster (hub-capacity)         │
│  ├── RHACM + Observability          │
│  ├── Grafana (read-only + dev)      │
│  └── Showroom lab guide             │
└─────────────┬───────────────────────┘
              │  RHACM import (Module 5)
┌─────────────▼───────────────────────┐
│  Student cluster (student-NN)       │
│  ├── sample apps (capacity-workshop)│
│  ├── cert-manager (ingress TLS)     │
│  └── OpenShift GitOps (ArgoCD)      │
└─────────────────────────────────────┘
```

One hub cluster hosts Showroom and RHACM. Each student gets a dedicated compact 3-node OCP cluster with sample workloads pre-deployed via ArgoCD.

---

## AWS Environment Options

You can deploy this workshop using either a **Red Hat Demo Platform (RHDP) Open Environment** (recommended for Red Hat associates and partners) or your **own AWS account**.

### Option A — RHDP Open Environment (recommended)

Order a sandbox at [catalog.demo.redhat.com — Sandbox Open](https://catalog.demo.redhat.com/catalog/babylon-catalog-prod?item=babylon-catalog-prod/sandboxes-gpte.sandbox-open.prod). This gives you a temporary AWS account with:

- Pre-configured IAM credentials (emailed to you as `ACCESS_KEY` / `SECRET_KEY`)
- A Route 53 hosted zone at `sandbox<N>.opentlc.com` (your `base_domain`)
- Pre-raised quota limits suitable for the hub + 3 student topology

After ordering, your secrets file is just:

```yaml
aws_access_key_id: "<from RHDP email>"
aws_secret_access_key: "<from RHDP email>"
base_domain: sandbox<N>.opentlc.com   # shown in RHDP email subject / body
```

### Option B — Your own AWS account

If you have your own AWS account you must:

1. Have a Route 53 public hosted zone (e.g. `mycompany.example.com`) for cluster DNS.
2. Request quota increases **before** provisioning (see table below).
3. Use your account name as `--account` (any string; the secrets file name must match).

Update `aws_region` in `hub-aws.yml` and `student.yml` if your account is not in `us-east-2`.

## AWS Quota Requirements

> **RHDP sandboxes have these quotas pre-raised.** If using your own AWS account, request increases before running `agd provision`. A 3-node compact OCP cluster consumes **4 Elastic IPs per cluster** (3 NAT gateways + 1 bastion) — the default of 5 EIPs is exhausted by the hub cluster alone.

| Resource | Default | hub + 1 student | hub + 8 students | Per-cluster breakdown |
|---|---|---|---|---|
| Elastic IPs | 5 | **8** | **36** | 3 NAT GWs + 1 bastion |
| VPCs | 5 | **2** | **9** | 1 per cluster |
| NAT Gateways | 5 | **6** | **27** | 3 per cluster (one per AZ) |
| vCPUs (m7a) | varies | **24** | **168** | 8 × m7a.2xlarge per cluster |

Submit quota increases via the [AWS Service Quotas console](https://us-east-2.console.aws.amazon.com/servicequotas/) **before running `agd provision`**.

---

## Prerequisites

| Component | Required version | Check |
|-----------|-----------------|-------|
| Python | 3.12+ | `python3 --version` |
| Podman | 4.0+ | `podman --version` |
| AgnosticD v2 | cloned to `~/agnosticd-v2` | `ls ~/agnosticd-v2/bin/agd` |
| Virtualenv | activated at `~/agnosticd-v2-virtualenv` | `ls ~/agnosticd-v2-virtualenv/bin` |
| AWS credentials | RHDP email or own account keys | `~/.aws/credentials` |

---

## File Layout

```
capacity-planning-lab-guide/deploy/vars/   ← templates committed to this repo
├── hub-aws.yml                            # Hub var file template (copy → ~/agnosticd-v2-vars/)
├── student.yml                            # Student var file template (copy per student)
└── secrets.yml.example                    # Secrets file template (copy → ~/agnosticd-v2-secrets/)

~/agnosticd-v2-vars/                       ← operator-local, NOT committed to git
├── hub-aws.yml                            # Customised hub configuration
├── student-01.yml                         # Per-student configuration
└── student-02.yml                         # ...

~/agnosticd-v2-secrets/                    ← operator-local, NEVER committed
└── secrets-sandbox<N>.yml                 # AWS credentials + base_domain

~/agnosticd-v2-output/                     ← generated by agd provision
├── hub-capacity/        # Hub provision output
│   ├── provision-user-data.yaml   # Hub URLs + credentials
│   └── provision-user-info.yaml   # Human-readable messages
└── student-01/          # Student provision output
    ├── provision-user-data.yaml
    └── provision-user-info.yaml
```

> **New jumpbox?** Run `deploy-workshop.sh --account sandbox<N>` once. It detects missing var files, copies the templates from `deploy/vars/` to `~/agnosticd-v2-vars/`, then exits with a checklist of fields to customise before re-running.

---

## Step 1 — Secrets File

Copy the template and fill in your credentials:

```bash
mkdir -p ~/agnosticd-v2-secrets
cp ~/capacity-planning-lab-guide/deploy/vars/secrets.yml.example \
   ~/agnosticd-v2-secrets/secrets-<ACCOUNT>.yml
# Then edit the file — see examples below.
```

**RHDP Open Environment** (sandbox account from the RHDP email):

```yaml
aws_access_key_id: "<ACCESS_KEY from RHDP email>"
aws_secret_access_key: "<SECRET_KEY from RHDP email>"
base_domain: sandbox<N>.opentlc.com
ocp4_pull_secret: '<full JSON blob from console.redhat.com>'
```

**Own AWS account** (replace with your Route 53 hosted zone domain):

```yaml
aws_access_key_id: "AKIA..."
aws_secret_access_key: "..."
base_domain: mycompany.example.com   # must be a Route 53 public hosted zone
ocp4_pull_secret: '<full JSON blob from console.redhat.com>'
```

> **Pull secret required.** Get yours at [console.redhat.com/openshift/install/pull-secret](https://console.redhat.com/openshift/install/pull-secret). Paste the entire JSON blob on a single line. Without it the OCP installer fails ~7 minutes into provisioning. The deploy script pre-flight check will catch a missing or placeholder value before any AWS resources are created.
>
> **Important:** `agd` loads two secrets files per run — your account-specific `secrets-<ACCOUNT>.yml` **and** the generic `~/agnosticd-v2-secrets/secrets.yml`. The generic file is loaded last and wins on any duplicate key. Set `ocp4_pull_secret` in **both** files, or leave it only in `secrets.yml` (the generic file always wins).

The `--account` value you pass to `deploy-workshop.sh` must match the filename suffix (e.g. `--account sandbox1234` → file is `secrets-sandbox1234.yml`).

---

## Step 2 — Provision the Hub

The hub var file template is committed to this repo at `deploy/vars/hub-aws.yml`.
The deploy script copies it to `~/agnosticd-v2-vars/hub-aws.yml` automatically on first run.
The only field you need to change is `owner` (your email).

```bash
# Let the script bootstrap the template for you:
cd ~/capacity-planning-lab-guide
bash scripts/deploy-workshop.sh --account sandbox<N>
# Follow the printed instructions, then re-run the same command.
```

Or, to provision the hub manually after customising the var file yourself:

```bash
cd ~/agnosticd-v2
./bin/agd provision \
  --guid hub-capacity \
  --config hub-aws \
  --account sandbox<N>
```

**Duration**: 90–120 minutes (OCP install + RHACM + Grafana + Showroom).

When complete, check `~/agnosticd-v2-output/hub-capacity/provision-user-data.yaml` for:

| Key | Description |
|-----|-------------|
| `hub_rhacm_url` | RHACM console URL |
| `hub_grafana_url` | Read-only Grafana |
| `hub_dev_grafana_url` | Interactive Grafana (dev) |
| `lab_ui_url` | Showroom lab guide URL |
| `hub_password` | kubeadmin password |

---

## Step 2.5 — Verify (and Repair) Grafana Student Access

The hub workload provisions Grafana student access automatically. Run this verification immediately after the hub provision completes to confirm both RBAC layers are in place before provisioning student clusters.

### What was provisioned by the hub workload

The `ocp4_workload_capacity_planning_workshop` workload (`hub_mode: true`) creates:

| Resource | Purpose |
|----------|---------|
| HTPasswd Secret + OAuth IDP (`workshop-students`) | Lets students log in to Grafana via OpenShift OAuth |
| `ClusterRoleBinding/workshop-grafana-view-<user>` per student | **Layer 1**: Satisfies the oauth-proxy SubjectAccessReview (list projects) |
| `ClusterRoleBinding/workshop-mcluster-view-<user>` per student | Allows rbac-query-proxy to resolve managed cluster names |
| `ClusterRoleBinding/workshop-grafana-sa-*` | Fixes "No data" when the user token is not forwarded to the proxy |
| `RoleBinding/workshop-obs-view-<user>` in each cluster namespace | **Layer 2**: rbac-query-proxy filter — without this, `cluster=~"()"` is injected and panels show "No data" |

`viewers_can_edit=true` is intentional — students create and save dashboards during Modules 2 and 5.

### Quick verification

```bash
export HKC=~/agnosticd-v2-output/hub-capacity/openshift-cluster_hub-capacity_kubeconfig

# Layer 1 — user-1 must pass the oauth-proxy SAR gate
oc --kubeconfig="${HKC}" auth can-i list projects --as=user-1
# Expected: yes

# Layer 2 — Grafana SA must resolve managed cluster names
oc --kubeconfig="${HKC}" auth can-i list managedclusters \
  --as=system:serviceaccount:open-cluster-management-observability:grafana
# Expected: yes
```

### If either check fails — run the repair script

```bash
cd ~/capacity-planning-lab-guide
bash scripts/provision-grafana-student-access.sh \
  --count 8 \
  --hub-kubeconfig "${HKC}"
```

The script accepts `--dry-run` to preview changes and `--verify-only` to re-run checks without applying RBAC.

When a student cluster is added to RHACM **after** hub provisioning, re-run the repair script to create the Layer 2 RoleBindings in the new cluster's namespace:

```bash
bash scripts/provision-grafana-student-access.sh --count 8 --hub-kubeconfig "${HKC}"
```

---

## Step 3 — Prepare Student Vars

The student var file template is committed to this repo at `deploy/vars/student.yml`.
The deploy script copies it to `~/agnosticd-v2-vars/student-NN.yml` for each student
slot automatically on first run, setting the correct `guid` and `hub_user_slot` per slot.

After the bootstrap copy, update these two fields in each `student-NN.yml`:

```yaml
# 1. Set owner email (same as hub-aws.yml)
cloud_tags:
- owner: <YOUR_EMAIL>

# 2. Paste the hub RHACM URL from hub provision-user-data.yaml -> hub_rhacm_url
ocp4_workload_capacity_planning_workshop_hub_rhacm_url: \
  "https://console-openshift-console.apps.hub.hub-capacity.sandbox<N>.opentlc.com/multicloud"
```

Everything else (workloads, instance type, hub_user_slot mapping) is pre-filled by the template.

---

## Step 4 — Provision a Student Cluster

```bash
cd ~/agnosticd-v2
./bin/agd provision \
  --guid student-01 \
  --config student-01 \
  --account sandbox<N>
```

**Duration**: 60–75 minutes (OCP install ~45 min + workloads ~20 min).

Key output keys in `provision-user-data.yaml`:

| Key | Description |
|-----|-------------|
| `openshift_console_url` | Student OCP console |
| `openshift_api_url` | API endpoint |
| `openshift_cluster_ingress_domain` | Wildcard apps domain |
| `openshift_gitops_server` | ArgoCD console URL |
| `bastion_public_hostname` | SSH jump host |
| `bastion_ssh_password` | SSH password |

---

## Known Behaviors and Workarounds

### Sample App Cold-Start Timeout

**Symptom**: Provision ends with `failed=1` and log shows:

```
fatal: [localhost]: FAILED! => {"api_found": true, "attempts": 30, ...
  "msg": "Task failed: Action failed: Unknown error.", "resources": []}
```

**Cause**: The `[STUDENT] Wait for sample applications to be ready` task previously had a 5-minute (30 × 10 s) timeout — not enough for container images to pull on a cold cluster.

**Status**: Fixed. The timeout is now **25 minutes** (100 × 15 s). Reprovisioning after the fix will succeed.

**Manual workaround** (pre-fix): Wait ~15 minutes after provision completes, then verify via ArgoCD:

```bash
oc get application capacity-planning-workshop -n openshift-gitops \
  --kubeconfig ~/agnosticd-v2-output/student-01/openshift-cluster_student-01_kubeconfig
```

Check `status.health.status == Healthy` and `status.sync.status == Synced`.

---

### ocp4_workload_lightspeed — Role Not Yet Installed

**Symptom**: Provision fails immediately at "Install workloads" with:

```
ERROR: the role 'ocp4_workload_lightspeed' was not found in ...
```

**Cause**: `ocp4_workload_lightspeed` is a workshop-specific role for Module 8 (OpenShift Lightspeed). It does not ship with the standard agnosticd-v2 distribution.

**Fix**: Keep it commented out in `student-NN.yml` until the role is available:

```yaml
workloads:
- agnosticd.core_workloads.ocp4_workload_cert_manager
- agnosticd.core_workloads.ocp4_workload_openshift_gitops
- ocp4_workload_capacity_planning_workshop
# - ocp4_workload_lightspeed   # enable after adding role to requirements_content
```

To enable when the role is ready, add its git repo to `requirements_content` in the vars file and set the required variable:

```yaml
requirements_content:
  collections:
  - name: https://github.com/agnosticd/core_workloads.git
    type: git
    version: "{{ tag }}"
  - name: https://github.com/<org>/ocp4_workload_lightspeed.git   # ← add this
    type: git
    version: main

# Required: obtain from RHDP LiteMaaS portal
ocp4_workload_lightspeed_litemaas_api_token: "sk-..."
```

---

### EIP Quota Exhaustion

**Symptom**: OCP installer fails with:

```
level=error msg=failed to create cluster: infrastructure was not ready within 15m0s:
  client rate limiter Wait returned an error: context deadline exceeded
```

**Cause**: AWS Elastic IP quota hit. Compact clusters use 4 EIPs each (3 NAT GWs + 1 bastion). The default quota of 5 is insufficient even for the hub alone.

**Fix**:
1. Destroy the failed deployment: `./bin/agd destroy --guid <guid> --config <config> --account <account>`
2. Increase EC2-VPC Elastic IP limit in the [AWS Service Quotas console](https://us-east-2.console.aws.amazon.com/servicequotas/home/services/ec2/quotas/L-0263D0A3) — request at least 15 for hub + 1 student, 40 for hub + 8 students
3. Wait for auto-approval (typically < 5 minutes) then re-provision

---

### besteffort-app and critical-app FailedCreate (ResourceQuota Conflict)

**Symptom**: After provision, `besteffort-app` and `critical-app` pods never start. Describe events show:

```
Warning  FailedCreate  pods "besteffort-app-..." is forbidden: failed quota: capacity-workshop-quota:
  must specify limits.cpu for: app; limits.memory for: app; requests.cpu for: app; requests.memory for: app

Warning  FailedCreate  pods "critical-app-..." is forbidden: failed quota: capacity-workshop-quota:
  must specify limits.cpu for: create-index; limits.memory for: create-index; ...
```

**Cause**: The `capacity-workshop-quota` ResourceQuota requires every pod in the namespace to declare `requests.cpu`, `requests.memory`, `limits.cpu`, and `limits.memory`. The upstream Helm chart defines `besteffort-app` without any `resources:` block (intentional for the QoS demo) and the `critical-app` `create-index` init container also has no resources block. Both pods are rejected at admission.

**Upstream fix**: [PR #2 — fix: add resources to besteffort-app and critical-app init container](https://github.com/tosin2013/openshift-capacity-planning-workshop/pull/2). Once merged, ArgoCD will apply the corrected chart and both apps will deploy.

**Temporary workaround** (live clusters before the PR merges):

1. Suspend ArgoCD auto-sync so the quota is not immediately re-created:

```bash
oc patch application capacity-planning-workshop-sample-apps \
  -n openshift-gitops \
  --type=merge \
  -p '{"spec":{"syncPolicy":{"automated":null}}}'
```

2. Delete the ResourceQuota:

```bash
oc delete resourcequota capacity-workshop-quota -n capacity-workshop
```

3. Force a rollout restart of the affected Deployments:

```bash
oc rollout restart deployment/besteffort-app deployment/critical-app -n capacity-workshop
```

Both pods will come up within ~30 seconds. With the quota absent, `besteffort-app` shows `BestEffort` QoS — which is pedagogically accurate.

**After the PR merges**: Re-enable ArgoCD auto-sync and trigger a manual sync. The chart will apply minimal resource specs to `besteffort-app` (making it `Burstable`, consistent with the module-03 narrative about quota-enforced QoS) and to the `create-index` init container.

> **Note for module-03**: The lab guide already explains that `besteffort-app` will show as `Burstable` when the namespace quota is active. The scratch-namespace workaround (`oc new-project scratch-qos-demo`) documented in module-03 remains valid for students who want to observe true `BestEffort` behavior regardless of the workaround state.

---

## Lifecycle Operations

All clusters support stop/start/status for RHDP cost management:

```bash
cd ~/agnosticd-v2

# Stop all EC2 instances (saves cost overnight)
./bin/agd stop   --guid hub-capacity --config hub-aws    --account sandbox<N>
./bin/agd stop   --guid student-01   --config student-01 --account sandbox<N>

# Start clusters (allow 5–15 min for DNS to propagate after start)
./bin/agd start  --guid hub-capacity --config hub-aws    --account sandbox<N>
./bin/agd start  --guid student-01   --config student-01 --account sandbox<N>

# Check current power state
./bin/agd status --guid hub-capacity --config hub-aws    --account sandbox<N>
./bin/agd status --guid student-01   --config student-01 --account sandbox<N>
```

> **DNS note**: After `agd start`, public hostnames (console, API, Showroom) take 5–15 minutes to resolve as AWS re-associates Elastic IPs. The bastion SSH should be reachable within ~2 minutes.

---

## Validation Checklist

After both clusters provision, verify:

- [ ] Hub Showroom loads: `https://showroom-showroom-<guid>.apps.hub.<guid>.<domain>/`
- [ ] Hub RHACM console loads and shows 0 clusters initially
- [ ] Grafana Layer 1: `oc auth can-i list projects --as=user-1` returns `yes`
- [ ] Grafana Layer 2: `oc auth can-i list managedclusters --as=system:serviceaccount:open-cluster-management-observability:grafana` returns `yes`
- [ ] User1 can log into Grafana with `workshop-students` IDP and see dashboards (Module 2/5 prerequisite)
- [ ] Student ArgoCD app `capacity-planning-workshop` is **Healthy + Synced**
- [ ] Student sample apps Deployments are all Available: `oc get deploy -n capacity-workshop`
- [ ] Student can SSH to bastion using credentials from `provision-user-info.yaml`
- [ ] Student can log into OCP console with `kubeadmin` (password in `openshift-cluster_<guid>_kubeadmin-password`)

---

## Troubleshooting Quick Reference

| Symptom | Likely cause | Action |
|---------|-------------|--------|
| EIP quota error during install | Default quota too low | Destroy → request quota increase → re-provision |
| `ocp4_workload_lightspeed` role not found | Role not in ansible path | Comment out from `workloads:` list |
| Sample apps not ready (provision fails) | Cold-start image pull timeout | Verify with `oc get deploy -n capacity-workshop`; wait 15 min; re-run if needed |
| Showroom shows placeholder `{attributes}` | `agnosticd_user_info` keys missing | Check `provision-user-data.yaml` has all required keys |
| Console/API unreachable after `agd start` | DNS propagation delay | Wait 10–15 min for EIP re-association |
| ArgoCD Application shows `OutOfSync` | Git repo unreachable from cluster | Check egress and DNS from student cluster |
| `besteffort-app` / `critical-app` never start (`FailedCreate`) | ResourceQuota blocks pods without resource specs | Apply workaround in "besteffort-app and critical-app FailedCreate" section above; upstream fix in PR #2 |
| Students see 403 at Grafana route | Layer 1 ClusterRoleBindings missing | Run `bash scripts/provision-grafana-student-access.sh --count 8 --hub-kubeconfig <HKC>` |
| Grafana dashboards show "No data" for all users | Layer 2 per-cluster RoleBindings missing or Grafana SA RBAC removed | Run repair script; confirm clusters are imported with `oc get managedclusters` |
| "No data" only for clusters added after hub provision | Layer 2 RoleBindings not yet in new cluster namespace | Re-run repair script after cluster import |
