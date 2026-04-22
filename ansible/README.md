# Ansible Provisioning — Capacity Planning Workshop

This directory contains the AgnosticD-compatible workload role and a dev/test
wrapper playbook for the Module 8 OpenShift Lightspeed prerequisite.

## Role: `ocp4_workload_lightspeed`

**Location:** `roles/ocp4_workload_lightspeed/`

Installs and configures **OpenShift Lightspeed** (Module 8 prerequisite).
Follows the standard AgnosticD `ocp4_workload_*` role convention:

| File | Purpose |
|------|---------|
| `tasks/main.yml` | ACTION switch — do not modify |
| `tasks/workload.yml` | Provision: install operator, configure OLSConfig |
| `tasks/remove_workload.yml` | Destroy: delete namespace and OLSConfig |
| `defaults/main.yml` | All defaults prefixed `ocp4_workload_lightspeed_` |
| `meta/main.yml` | Galaxy metadata |

### Provisioning steps (`tasks/workload.yml`)

1. Assert `ocp4_workload_lightspeed_litemaas_api_token` is non-empty
2. Create `openshift-lightspeed` namespace
3. Create OperatorGroup (OwnNamespace mode — required by the operator)
4. Create Subscription (`lightspeed-operator` package, `stable` channel, `redhat-operators`)
5. Wait for `lightspeed-operator-controller-manager` pod Running
6. Wait for `olsconfigs.ols.openshift.io` CRD Established
7. Create `litemaas-credentials` Secret
8. Build model list (primary always; comparison only when `model_comparison` is non-empty)
9. Apply `OLSConfig cluster` CR (provider: litemaas, defaultModel: granite)
10. Wait for `lightspeed-service` pod Running
11. Emit `agnosticd_user_info` with console URL and model info

### Key defaults (`defaults/main.yml`)

| Variable | Default | Notes |
|----------|---------|-------|
| `ocp4_workload_lightspeed_litemaas_api_url` | `https://litellm-prod.apps.maas.redhatworkshops.io/v1` | API endpoint (not -frontend) |
| `ocp4_workload_lightspeed_model_primary` | `granite-3-2-8b-instruct` | No `openai/` prefix — verified live |
| `ocp4_workload_lightspeed_model_comparison` | `""` | qwen3-14b requires custom LiteMaaS package |
| `ocp4_workload_lightspeed_introspection_enabled` | `false` | Tech Preview — set true for cluster interaction |
| `ocp4_workload_lightspeed_channel` | `stable` | OLM channel |

### Production path (RHDP / AgnosticD)

The role lives in both this repo (source of truth) and in
`agnosticd-v2/ansible/roles_ocp_workloads/ocp4_workload_lightspeed/` (production copy).

In `agnosticd-v2-vars/student-compact-aws.yml`:

```yaml
workloads:
  - agnosticd.core_workloads.ocp4_workload_openshift_gitops
  - ocp4_workload_capacity_planning_workshop
  - ocp4_workload_lightspeed

ocp4_workload_lightspeed_litemaas_api_token: "{{ agnosticd_user_info.litemaas_api_key }}"
```

Deploy via:

```bash
cd agnosticd-v2
./bin/agd provision -g student-01 -c openshift-workloads -a sandbox5388
```

### Dev/test wrapper

`setup-lightspeed.yml` wraps the role with `ACTION: provision` for local testing
without `agd`. Requires `KUBECONFIG` pointing at the student cluster.

```bash
# Verify available models first
curl -s -H "Authorization: Bearer $TOKEN" \
  https://litellm-prod.apps.maas.redhatworkshops.io/v1/models | jq '.data[].id'

# Install (granite only)
ansible-galaxy collection install kubernetes.core
KUBECONFIG=/path/to/kubeconfig ansible-playbook setup-lightspeed.yml \
  -e ocp4_workload_lightspeed_litemaas_api_token=$TOKEN \
  -e openshift_cluster_ingress_domain=apps.student.student-01.sandbox5388.opentlc.com

# Verify
oc get olsconfig cluster -o jsonpath='{.status.conditions}' | jq .
oc get pods -n openshift-lightspeed
```

## Keeping in Sync

When updating the role:
1. Edit `roles/ocp4_workload_lightspeed/` in this repo first
2. Copy to `agnosticd-v2/ansible/roles_ocp_workloads/`:
   ```bash
   rsync -av roles/ocp4_workload_lightspeed/ \
     ../agnosticd-v2/ansible/roles_ocp_workloads/ocp4_workload_lightspeed/
   ```
