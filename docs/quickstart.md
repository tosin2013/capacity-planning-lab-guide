# Quick Start

Get up and running in 5 minutes. For the full operator runbook, see [Hub-Student Deployment Guide](hub-student-deployment.md).

---

## For End Users (Deploy a Workshop)

1. **Clone the repo and run onboarding:**

   ```bash
   git clone https://github.com/tosin2013/capacity-planning-lab-guide.git
   cd capacity-planning-lab-guide
   make setup
   ```

   This installs prerequisites, prompts for your AWS account info and credentials,
   populates the secrets file, and validates readiness.

2. **Re-validate anytime** (after fixing issues or changing credentials):

   ```bash
   make check
   ```

3. **Preview what would deploy** (no clusters created):

   ```bash
   make dry-run
   ```

4. **Deploy the full workshop** (hub + student clusters, ~3-4 hours):

   ```bash
   make deploy
   ```

5. **Get student access info:**

   ```bash
   make student-info
   cat student-info.txt
   ```

---

## For Maintainers (Local Content Development)

1. **Set up the dev environment:**

   ```bash
   make setup-dev
   ```

   Installs base prerequisites plus shellcheck, yamllint, and Node.js for local Antora builds.

2. **Build and preview the lab guide locally:**

   ```bash
   make build
   make serve
   # Open http://localhost:8080
   ```

3. **Validate Showroom attribute substitution:**

   ```bash
   make validate
   ```

4. **Stop the preview server when done:**

   ```bash
   make stop
   ```

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| Quota check fails | Request AWS quota increases — see [hub-student-deployment.md](hub-student-deployment.md#aws-quota-requirements) |
| Grafana shows "No data" for students | Run `bash scripts/fix-grafana-rbac.sh` or `bash scripts/provision-grafana-student-access.sh` |
| Pull secret invalid | Re-download from https://console.redhat.com/openshift/install/pull-secret |
| `agd` not found | Re-run `make setup` or manually clone AgnosticD v2 |

---

## Reference

- **Full deployment guide:** [docs/hub-student-deployment.md](hub-student-deployment.md)
- **Release validation:** [docs/release-validation.md](release-validation.md)
- **Onboarding manifest:** `onboard.yml` (schema: project-onboard skill spec v1.0)
- **All Makefile targets:** `make help`
