# Hub-Student Deployment Guide

## Overview

The Strategic Capacity Planning & Forecasting workshop uses a **hub-student topology**:

- **Hub cluster** — runs RHACM, MultiClusterObservability (Thanos → S3, Grafana), Showroom (lab guide), cert-manager, and OpenShift GitOps.
- **Student clusters** — each student gets a dedicated compact 3-node OpenShift cluster running sample apps, Prometheus monitoring, and simulation tools. Students register their cluster into the hub's RHACM during **Module 5 ("The God's-Eye Dashboard")** as a hands-on lab exercise.

---

## Architecture

```
Hub Cluster (m7a.2xlarge × 3)
├── cert-manager + Let's Encrypt (Route53 DNS-01)
├── OpenShift GitOps (ArgoCD)
├── RHACM + MultiClusterHub
├── RHACM Observability
│   ├── Thanos → S3 (fleet-wide metrics)
│   └── Grafana (God's-Eye Dashboard)
└── Showroom (lab guide + terminal → student cluster API)

Student Cluster N (m7a.2xlarge × 3)
├── cert-manager + Let's Encrypt (Route53 DNS-01)
├── OpenShift GitOps (ArgoCD)
└── Workshop workloads (hub_mode: false)
    ├── Sample Apps (QoS demos, HPA, load-gen, noisy-neighbor)
    ├── Monitoring config (Prometheus rules, PromQL dashboards)
    └── Simulation toolkit
                  ↓  Module 5 lab exercise
         Registers as RHACM managed cluster on hub
```

**Workload distribution:**

| Workload | Hub | Student |
|---|---|---|
| cert-manager + Let's Encrypt | YES | YES |
| OpenShift GitOps | YES | YES |
| RHACM + MultiClusterHub | **YES** | NO |
| RHACM Observability (Thanos/Grafana) | **YES** | NO |
| Sample apps (QoS, HPA, load-gen) | NO | YES |
| Monitoring config (Prometheus rules) | NO | YES |
| Simulation toolkit | NO | YES |
| Showroom lab guide | YES | NO |

---

## Prerequisites

### 1. AWS Credentials and Quota

Ensure your AWS sandbox has sufficient quota in `us-east-2`:

| Resource | Default | Required (8 students) |
|---|---|---|
| Elastic IPs | 5 | 15 (1 per cluster) |
| VPCs | 5 | 15 |
| NAT Gateways | 5 per AZ | 15 per AZ |
| vCPUs (M7a) | 1,152 | ~220 (hub 24 + 8×24) |

Open a quota increase request for EIPs, VPCs, and NAT GWs to 15 before starting.

### 2. OpenShift Pull Secret

```bash
# Place your pull secret from https://console.redhat.com/openshift/install/pull-secret
cp ~/pull-secret.json ~/agnosticd-v2-secrets/pull-secret.json
```

Verify it is valid JSON:
```bash
python3 -m json.tool ~/agnosticd-v2-secrets/pull-secret.json > /dev/null && echo "Valid"
```

### 3. AgnosticD vars and secrets

Files required:
- `~/agnosticd-v2-vars/hub-aws.yml` — hub cluster config
- `~/agnosticd-v2-vars/student-compact-aws.yml` — student cluster template (change `guid` per student)
- `~/agnosticd-v2-secrets/secrets.yml` — pull secret lookup
- `~/agnosticd-v2-secrets/secrets-sandbox5388.yml` — AWS credentials + `base_domain`

---

## Cost Model (AWS us-east-2 on-demand, 8-hour session)

| Cluster | Instance type | Nodes | vCPU | RAM | ~Cost/8h |
|---|---|---|---|---|---|
| Hub | m7a.2xlarge | 3 | 24 | 96 GB | ~$16 |
| Student (each) | m7a.2xlarge | 3 | 24 | 96 GB | ~$11 |
| **8 students total** | | 24+3 bastion | 192+24 | 768+96 GB | **~$104** |

> **Recommended maximum: 8 students** — balances cost, AWS quota limits, and RHACM observability overhead.

---

## Provisioning Sequence

### Step 1 — Provision hub cluster

```bash
cd ~/agnosticd-v2

nohup ./bin/agd provision \
  --guid hub-capacity \
  --config hub-aws \
  --account sandbox5388 \
  > /tmp/provision-hub.log 2>&1 &

tail -f /tmp/provision-hub.log
```

Hub provisioning takes **~60–90 minutes** (OCP install + cert-manager + GitOps + RHACM + Observability + Showroom).

### Step 2 — Record hub RHACM URL

Once hub provisioning completes, retrieve the hub user-info output:

```bash
cat ~/agnosticd-v2-output/hub-capacity/user-info.yaml
```

Look for `hub_rhacm_console` — e.g.:
```
hub_rhacm_console: https://multicloud-console.apps.hub.sandbox5388.opentlc.com
```

### Step 3 — Update student vars with hub RHACM URL (optional)

The hub RHACM URL can be injected into `student-compact-aws.yml` so Module 5 instructions are pre-populated:

```yaml
# In student-compact-aws.yml, uncomment and set:
ocp4_workload_capacity_planning_workshop_hub_rhacm_url: "https://multicloud-console.apps.hub.sandbox5388.opentlc.com"
```

> **Note**: This is informational only — the student cluster does NOT auto-register. Students perform the cluster import during Module 5 as a hands-on exercise.

### Step 4 — Provision student clusters (in parallel)

```bash
cd ~/agnosticd-v2

for STUDENT in student-01 student-02; do
  # Update the guid in a temp copy
  sed "s/guid: student-01/guid: ${STUDENT}/" \
    ~/agnosticd-v2-vars/student-compact-aws.yml \
    > /tmp/${STUDENT}-aws.yml

  nohup ./bin/agd provision \
    --guid ${STUDENT} \
    --config /tmp/${STUDENT}-aws \
    --account sandbox5388 \
    > /tmp/provision-${STUDENT}.log 2>&1 &
done

# Monitor progress
tail -f /tmp/provision-student-01.log
```

Student cluster provisioning takes **~45–60 minutes** (OCP install + cert-manager + GitOps + workshop workloads).

---

## Post-Provision: Wire Showroom Terminal

After a student cluster is provisioned, wire the hub's Showroom terminal to that student's API:

```bash
# Get the student API URL from their user-info
cat ~/agnosticd-v2-output/student-01/user-info.yaml | grep student_cluster_api_url
# e.g.: student_cluster_api_url: https://api.student.student-01.sandbox5388.opentlc.com:6443

# Update hub Showroom to point to this student's cluster
# (Re-run hub workloads with updated Showroom terminal target)
```

---

## Module 5: Student Cluster Import into RHACM

During Module 5, students perform the RHACM managed cluster import themselves:

1. Student navigates to the hub RHACM console (`hub_rhacm_console` from user-info)
2. In RHACM → **Infrastructure** → **Clusters** → **Import cluster**
3. Enter the cluster name (their `guid`, e.g., `student-01`)
4. Copy the generated `kubectl apply` command
5. Run the command on their student cluster:
   ```bash
   oc login <student-cluster-api>
   # paste the generated import command
   ```
6. Within ~5 minutes the cluster appears as "Ready" in RHACM
7. The Grafana fleet dashboard (God's-Eye view) now shows metrics from all imported clusters

---

## cert-manager Notes

Both hub and student clusters use cert-manager with Let's Encrypt DNS-01 challenge via Route53. The CloudFormation stack (deployed by `openshift-cluster` config) automatically creates a Route53 IAM user and outputs the credentials as `route53user_access_key` and `route53user_secret_access_key`. The `hub-aws.yml` and `student-compact-aws.yml` reference these via:

```yaml
ocp4_workload_cert_manager_aws_access_key_id: "{{ hostvars['localhost']['route53user_access_key'] }}"
ocp4_workload_cert_manager_aws_secret_access_key: "{{ hostvars['localhost']['route53user_secret_access_key'] }}"
```

No additional credentials are needed — they are provisioned automatically.

---

## Storage Notes (RHACM Observability)

RHACM Observability (Thanos) on the hub uses **AWS S3** as the metrics object store:

- Storage class: `gp3-csi` (for PVCs on the hub compact cluster)
- Thanos object storage: S3 bucket `rhacm-metrics-hub-capacity` in `us-east-2`
- The workload role automatically creates the S3 bucket and configures the Thanos secret

On-prem OCS/NooBaa is **not** used in this topology (no OpenShift Data Foundation on the hub).

---

## Destroy Clusters

```bash
cd ~/agnosticd-v2

# Destroy a student cluster
./bin/agd destroy --guid student-01 --config student-compact-aws --account sandbox5388

# Destroy the hub (do this last)
./bin/agd destroy --guid hub-capacity --config hub-aws --account sandbox5388
```

> **Important**: If an `agd provision` run fails partway through OCP installation, the bastion may have a stale install directory. SSH to the bastion and clear it before re-running:
> ```bash
> # Hub bastion
> ssh ec2-user@bastion.hub-capacity.sandbox5388.opentlc.com "rm -rf ~/hub"
> # Student bastion
> ssh ec2-user@bastion.student-01.sandbox5388.opentlc.com "rm -rf ~/student"
> ```
