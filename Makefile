.DEFAULT_GOAL := help
COMPOSE ?= docker compose

.PHONY: help up down logs ps check api-check verifier-check portal-check app-check portal-dev api-dev verifier-dev app-run

help: ## Show targets
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-16s %s\n", $$1, $$2}'

up: ## Build and start db, verifier, api and portal (Docker)
	$(COMPOSE) up --build -d

down: ## Stop the stack
	$(COMPOSE) down

logs: ## Follow the stack logs
	$(COMPOSE) logs -f --tail=100

ps: ## Show running services
	$(COMPOSE) ps

check: api-check verifier-check portal-check app-check ## Lint and test everything

api-check: ## Lint and test backend/api
	$(MAKE) -C backend/api lint test

verifier-check: ## Lint and test backend/verifier
	$(MAKE) -C backend/verifier lint test

portal-check: ## Lint, format check, test and build the portal
	cd portal && npm run check

app-check: ## Analyze and test the Flutter app
	cd app && mise exec -- flutter analyze && mise exec -- flutter test

api-dev: ## Run the API with reload (needs a database, see backend/api/README.md)
	$(MAKE) -C backend/api dev

verifier-dev: ## Run the verifier with reload
	$(MAKE) -C backend/verifier dev

portal-dev: ## Run the portal dev server (http://localhost:5173)
	cd portal && npm run dev

app-run: ## Run the app on the connected device or emulator
	cd app && mise exec -- flutter run --dart-define=API_BASE_URL=$${API_BASE_URL:-http://10.0.2.2:8000/api}
