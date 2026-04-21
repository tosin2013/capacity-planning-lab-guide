# Ansible Provisioning — Capacity Planning Workshop

This directory contains the Ansible playbook and roles that configure workshop
infrastructure beyond what the base cluster provides.

## Playbooks

### `setup-lightspeed.yml`

Installs and configures **OpenShift Lightspeed** (Module 8 prerequisite).

Runs on `localhost` against the target cluster using `kubernetes.core.k8s`.
Requires OCP 4.21+ and `cluster-admin` access.

#### Prerequisites

```bash
ansible-galaxy collection install kubernetes.core
oc login <student-cluster-api> -u kubeadmin -p <password>
```

#### RHDP / AgnosticD token provisioning

In the AgnosticD workload role, the `rhpds.litellm_virtual_keys` Ansible
collection creates a per-lab virtual key named `virtkey-{{ guid }}` using the
`lab-prod` package (Granite + Mistral, 90 days). Pass the key like this:

```yaml
- name: Configure Lightspeed
  ansible.builtin.include_role:
    name: lightspeed_setup
  vars:
    litemaas_api_token: "{{ agnosticd_user_info.litemaas_api_key }}"
    litemaas_model_comparison: "openai/qwen3-14b"   # requires custom package
    lightspeed_introspection_enabled: true
```

#### Standalone usage (development / testing)

```bash
# Confirm available model IDs first
TOKEN=sk-your-virtual-key
curl -s -H "Authorization: Bearer $TOKEN" \
  https://litellm-prod-frontend.apps.maas.redhatworkshops.io/v1/models \
  | jq '.data[].id'

# Install with granite only (standard lab-prod package)
ansible-playbook setup-lightspeed.yml \
  -e litemaas_api_token=$TOKEN

# Install with both models (requires qwen3 in allowed_models)
ansible-playbook setup-lightspeed.yml \
  -e litemaas_api_token=$TOKEN \
  -e litemaas_model_comparison=openai/qwen3-14b \
  -e lightspeed_introspection_enabled=true
```

#### Model IDs

| Model | Expected LiteMaaS ID | RHDP Package |
|---|---|---|
| IBM Granite 3.2 8B Instruct | `openai/granite-3-2-8b-instruct` | `lab-prod` (default) |
| Qwen 3 14B | `openai/qwen3-14b` | Custom — verify with MaaS team |

> **Important**: Verify exact model ID strings by calling `GET /v1/models`
> with a valid token before running the playbook. The IDs above are based on
> the RHDP LiteMaaS naming convention but must be confirmed against the live
> endpoint.

#### Verifying Lightspeed is ready

```bash
oc get olsconfig cluster -o jsonpath='{.status.conditions}' | jq .
oc get pods -n openshift-lightspeed
```

Expected: one `lightspeed-operator-*` pod and one `lightspeed-service-*` pod,
both `Running`.

## Roles

| Role | Purpose |
|---|---|
| `lightspeed_setup` | Installs Lightspeed Operator via OLM and applies `OLSConfig` CR |
