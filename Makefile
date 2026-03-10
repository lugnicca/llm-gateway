.PHONY: up down logs status test audit terraform-validate terraform-plan

# Local stack
up:
	docker compose -f docker-compose.local.yml up -d --build

down:
	docker compose -f docker-compose.local.yml down

logs:
	docker compose -f docker-compose.local.yml logs -f litellm

status:
	docker compose -f docker-compose.local.yml ps
	@echo ""
	@curl -s http://localhost:4000/health/liveliness 2>/dev/null && echo " Gateway: OK" || echo " Gateway: DOWN"

# Testing
test:
	@echo "Usage: make test KEY=sk-litellm-xxx"
	@test -n "$(KEY)" || (echo "Error: KEY is required" && exit 1)
	bash scripts/test-user-setup.sh --key $(KEY)

audit:
	bash scripts/security-audit.sh

# Terraform
terraform-validate:
	cd terraform && terraform validate

terraform-plan:
	cd terraform && terraform plan -var-file=terraform.tfvars

# User management
create-key:
	@echo "Usage: make create-key USER=alice@company.com TEAM=engineering BUDGET=100"
	@test -n "$(USER)" || (echo "Error: USER is required" && exit 1)
	GATEWAY_URL=http://localhost:4000 MASTER_KEY=$(MASTER_KEY) \
		bash scripts/create-user-key.sh --user $(USER) --team "$(TEAM)" --budget $(BUDGET)

onboard:
	@echo "Usage: make onboard USER=alice@company.com TEAM=engineering BUDGET=100"
	@test -n "$(USER)" || (echo "Error: USER is required" && exit 1)
	GATEWAY_URL=http://localhost:4000 MASTER_KEY=$(MASTER_KEY) \
		bash scripts/onboard-dev.sh --user $(USER) --team "$(TEAM)" --budget $(BUDGET)
