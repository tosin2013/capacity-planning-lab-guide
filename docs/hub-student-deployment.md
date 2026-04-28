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

### 0. Bootstrap AgnosticD v2 (first-time setup)

> Skip this section if you already have `~/agnosticd-v2/` cloned and `~/agnosticd-v2-virtualenv/` present.

**Requirements:** Python 3.12+, Podman 4+, AWS CLI, `~/.aws/credentials` populated

**Check Python version:**
```bash
python3 --version   # must be 3.12 or higher
```

If you get 3.9 on RHEL 9, install 3.12 first:
```bash
sudo dnf install -y python3.12
sudo alternatives --set python3 /usr/bin/python3.12
```

**Clone the workshop branch and run setup:**
```bash
git clone --branch workload/capacity-planning-workshop \
  https://github.com/tosin2013/agnosticd-v2.git ~/agnosticd-v2
cd ~/agnosticd-v2
./bin/agd setup
```

`agd setup` creates:
- `~/agnosticd-v2-virtualenv/` — Ansible + ansible-navigator virtualenv
- `~/agnosticd-v2-vars/` — configuration file directory (not a git repo)
- `~/agnosticd-v2-secrets/` — secrets file directory (never committed to git)

---

**Understanding the `--account` parameter**

Every `agd provision` command takes `--account <name>`. This resolves to `~/agnosticd-v2-secrets/secrets-<name>.yml`, which holds the AWS credentials and `base_domain` for your sandbox.

Find your Route53 hosted zone (this becomes `base_domain`):
```bash
aws route53 list-hosted-zones --query 'HostedZones[*].Name' --output text
# Example output: sandbox2784.opentlc.com.   (strip the trailing dot)
```

Create the account secrets file — **do not commit this file to git**:
```bash
cat > ~/agnosticd-v2-secrets/secrets-sandbox2784.yml << 'EOF'
---
aws_access_key_id: <Your AWS Access Key ID>
aws_secret_access_key: <Your AWS Secret Access Key>
base_domain: sandbox2784.opentlc.com
agnosticd_aws_capacity_reservation_enable: false
EOF
```

Also create `~/agnosticd-v2-secrets/secrets.yml` with your OpenShift pull secret:
```bash
cat > ~/agnosticd-v2-secrets/secrets.yml << 'EOF'
---
ocp4_pull_secret: '<paste the full pull-secret JSON here, single-quoted>'
install_satellite_repositories: false
install_rhn_repositories: false
EOF
```

---

### 1. AWS Credentials and Quota

Ensure your AWS sandbox has sufficient quota in `us-east-2`:

| Resource | Default | Required (hub + 1 student) | Required (8 students) |
|---|---|---|---|
| Elastic IPs | 5 | 2 | 15 |
| VPCs | 5 | 2 | 15 |
| NAT Gateways | 5 per AZ | 2 | 15 per AZ |
| vCPUs (M7a) | 1,152 | ~36 | ~220 |

For 8 students, open a quota increase request for EIPs, VPCs, and NAT GWs to 15 before starting. A single hub + 1 student test falls within default quotas.

### 2. OpenShift Pull Secret

Download your pull secret from https://console.redhat.com/openshift/install/pull-secret.

Set `ocp4_pull_secret` in `~/agnosticd-v2-secrets/secrets.yml` (created above in Step 0). The value must be the raw JSON content, single-quoted on one line:

```yaml
ocp4_pull_secret: '{"auths": {"cloud.openshift.com": {...}, ...}}'
```

Verify it is valid JSON before provisioning:
```bash
python3 -c "import json,sys; json.load(open('/dev/stdin'))" \
  <<< "$(grep ocp4_pull_secret ~/agnosticd-v2-secrets/secrets.yml | cut -d"'" -f2)" \
  && echo "Pull secret is valid JSON"
```

### 3. AgnosticD vars files

Create the following files in `~/agnosticd-v2-vars/`. These files live **outside** the git repository and are never committed.

**`~/agnosticd-v2-vars/hub-aws.yml`** — hub cluster (RHACM + Observability + Showroom):

```yaml
---
guid: hub-capacity
tag: main
cloud_provider: aws
config: openshift-cluster

requirements_content:
  collections:
  - name: https://github.com/agnosticd/core_workloads.git
    type: git
    version: "{{ tag }}"

aws_region: us-east-2
cluster_name: hub
host_ocp4_installer_version: "4.19"
host_ocp4_installer_root_url: https://mirror.openshift.com/pub/openshift-v4/clients
host_ocp4_installer_set_user_data_kubeadmin_password: true
openshift_cluster_admin_service_account_enable: true
worker_instance_count: 0   # compact 3-node: control-plane nodes also run workloads

# Replace with your own SSH public key
host_ssh_authorized_keys:
- key: "ssh-ed25519 AAAA... user@host"

install_satellite_repositories: false
install_rhn_repositories: false

workloads:
- agnosticd.core_workloads.ocp4_workload_cert_manager
- agnosticd.core_workloads.ocp4_workload_openshift_gitops
- ocp4_workload_capacity_planning_workshop

ocp4_workload_cert_manager_channel: stable-v1.15
ocp4_workload_cert_manager_aws_region: "{{ aws_region }}"
ocp4_workload_cert_manager_aws_access_key_id: "{{ hostvars.localhost.route53user_access_key }}"
ocp4_workload_cert_manager_aws_secret_access_key: "{{ hostvars.localhost.route53user_secret_access_key }}"
ocp4_workload_cert_manager_use_catalog_snapshot: false
ocp4_workload_cert_manager_install_ingress_certificates: true
ocp4_workload_cert_manager_install_api_certificates: false

ocp4_workload_capacity_planning_workshop_hub_mode: true
ocp4_workload_capacity_planning_workshop_deploy_rhacm: true
ocp4_workload_capacity_planning_workshop_deploy_monitoring: false
ocp4_workload_capacity_planning_workshop_deploy_sample_apps: false
ocp4_workload_capacity_planning_workshop_deploy_showroom: true
ocp4_workload_capacity_planning_workshop_rhacm_channel: release-2.16
ocp4_workload_capacity_planning_workshop_rhacm_storage_class: gp3-csi
ocp4_workload_capacity_planning_workshop_rhacm_thanos_bucket: "rhacm-metrics-hub-capacity"
```

**`~/agnosticd-v2-vars/student-compact-aws.yml`** — student cluster (sample apps + Prometheus):

```yaml
---
guid: student-01   # increment per student: student-01, student-02, ...
tag: main
cloud_provider: aws
config: openshift-cluster

requirements_content:
  collections:
  - name: https://github.com/agnosticd/core_workloads.git
    type: git
    version: "{{ tag }}"

aws_region: us-east-2
cluster_name: student
host_ocp4_installer_version: "4.19"
host_ocp4_installer_root_url: https://mirror.openshift.com/pub/openshift-v4/clients
host_ocp4_installer_set_user_data_kubeadmin_password: true
openshift_cluster_admin_service_account_enable: true
worker_instance_count: 0
control_plane_instance_type: m7a.2xlarge   # 24 vCPU / 96 GB RAM

host_ssh_authorized_keys:
- key: "ssh-ed25519 AAAA... user@host"

install_satellite_repositories: false
install_rhn_repositories: false

workloads:
- agnosticd.core_workloads.ocp4_workload_cert_manager
- agnosticd.core_workloads.ocp4_workload_openshift_gitops
- ocp4_workload_capacity_planning_workshop

ocp4_workload_cert_manager_channel: stable-v1.15
ocp4_workload_cert_manager_aws_region: "{{ aws_region }}"
ocp4_workload_cert_manager_aws_access_key_id: "{{ hostvars.localhost.route53user_access_key }}"
ocp4_workload_cert_manager_aws_secret_access_key: "{{ hostvars.localhost.route53user_secret_access_key }}"
ocp4_workload_cert_manager_use_catalog_snapshot: false
ocp4_workload_cert_manager_install_ingress_certificates: true
ocp4_workload_cert_manager_install_api_certificates: false

ocp4_workload_capacity_planning_workshop_hub_mode: false
ocp4_workload_capacity_planning_workshop_deploy_rhacm: false
ocp4_workload_capacity_planning_workshop_deploy_monitoring: true
ocp4_workload_capacity_planning_workshop_deploy_sample_apps: true
ocp4_workload_capacity_planning_workshop_deploy_showroom: false
# After hub provisions, set this to the RHACM console URL (pre-populates Module 5):
# ocp4_workload_capacity_planning_workshop_hub_rhacm_url: "https://multicloud-console.apps.hub.hub-capacity.<base_domain>"
```

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
