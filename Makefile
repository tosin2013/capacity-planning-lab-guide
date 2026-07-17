# Makefile — Capacity Planning Workshop
# Run 'make help' to see available targets.

ACCOUNT     ?= $(shell grep '^account:' deploy/config.yml 2>/dev/null | awk '{print $$2}')
HUB_GUID    ?= $(shell grep '^hub_guid:' deploy/config.yml 2>/dev/null | awk '{print $$2}')
NUM_STUDENTS ?= $(shell grep '^num_students:' deploy/config.yml 2>/dev/null | awk '{print $$2}')
STUDENTS    ?= $(shell printf '%02d ' $$(seq 1 $(or $(NUM_STUDENTS),3)) | sed 's/ $$//')

.PHONY: help setup setup-dev check setup-dry deploy dry-run destroy build serve stop clean student-info validate

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

setup: ## Run full onboarding (prod mode, interactive)
	./bootstrap.sh

setup-dev: ## Run maintainer/contributor setup (dev mode)
	./bootstrap.sh --mode dev

check: ## Run validation checks only (no installs, no deploy)
	@if [ ! -f deploy/config.yml ]; then \
		echo ""; \
		echo "  No configuration found (deploy/config.yml missing)."; \
		echo "  Run 'make setup' first to complete the onboarding wizard."; \
		echo ""; \
		exit 1; \
	fi
	./bootstrap.sh --check-only

setup-dry: ## Dry-run full onboarding (show what would happen)
	./bootstrap.sh --dry-run

deploy: ## Deploy hub + student clusters (reads deploy/config.yml)
	bash scripts/deploy-workshop.sh --account $(ACCOUNT) --hub-guid $(HUB_GUID) --students "$(STUDENTS)"

dry-run: ## Preview deploy commands without executing
	bash scripts/deploy-workshop.sh --account $(ACCOUNT) --hub-guid $(HUB_GUID) --students "$(STUDENTS)" --dry-run

request-quotas: ## Request AWS quota increases for all insufficient limits
	bash scripts/request-quotas.sh

request-quotas-dry: ## Preview quota requests without submitting
	bash scripts/request-quotas.sh --dry-run

destroy: ## Tear down all clusters (students first, then hub)
	bash scripts/teardown-workshop.sh

build: ## Build Antora site locally (requires podman)
	./utilities/lab-build

serve: ## Start local preview server on http://localhost:8080
	./utilities/lab-serve

stop: ## Stop local preview server
	./utilities/lab-stop

clean: ## Remove built HTML from ./www
	./utilities/lab-clean

student-info: ## Generate student-info.txt from provision outputs
	bash scripts/generate-student-info.sh

validate: ## Run Showroom attribute validation (local Antora build)
	bash scripts/validate-showroom-attributes.sh --local-only
