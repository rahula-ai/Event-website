# ─────────────────────────────────────────────────────────────────────────────
# Makefile – Dharmasthala Events
# Usage: make <target>
# ─────────────────────────────────────────────────────────────────────────────

.PHONY: help dev prod stop logs ps build push deploy backup ssl-init test lint clean

# ── Auto-help: lists targets with ## comments ─────────────────────────────────
help:
	@echo "Dharmasthala Events – Available commands:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

# ── Development ───────────────────────────────────────────────────────────────
dev: ## Start dev stack with hot-reload
	docker compose -f docker-compose.yml -f docker-compose.dev.yml up --build

dev-down: ## Stop dev stack
	docker compose -f docker-compose.yml -f docker-compose.dev.yml down

# ── Production ────────────────────────────────────────────────────────────────
prod: ## Start production stack
	docker compose up -d

stop: ## Stop all services
	docker compose down

restart: ## Rolling restart of backend + frontend
	docker compose up -d --no-deps --force-recreate backend
	docker compose up -d --no-deps --force-recreate frontend
	docker compose exec nginx nginx -s reload

# ── Info ──────────────────────────────────────────────────────────────────────
logs: ## Follow all logs
	docker compose logs -f

logs-backend: ## Follow backend logs only
	docker compose logs -f backend

logs-nginx: ## Follow Nginx logs only
	docker compose logs -f nginx

ps: ## Show running containers
	docker compose ps

health: ## Check all service health
	@echo "Backend:" && curl -sf http://localhost:8000/health | python3 -m json.tool || echo "❌ Down"
	@echo "Nginx:"   && curl -sf http://localhost/health       | python3 -m json.tool || echo "❌ Down"

# ── Build & Deploy ────────────────────────────────────────────────────────────
build: ## Build Docker images locally
	docker compose build --no-cache

push: ## Push images to registry (set DOCKER_REGISTRY env var)
	docker compose push

deploy: ## Run full production deploy
	bash scripts/deploy.sh

# ── SSL ───────────────────────────────────────────────────────────────────────
ssl-init: ## Obtain Let's Encrypt certificate (first time)
	bash scripts/init-ssl.sh

ssl-renew: ## Force SSL certificate renewal
	bash scripts/renew-ssl.sh

# ── Database ──────────────────────────────────────────────────────────────────
backup: ## Run MongoDB backup now
	bash scripts/backup.sh

mongo-shell: ## Open MongoDB shell
	docker compose exec mongo mongosh \
		-u $${MONGO_ROOT_USER:-mongoroot} \
		-p $${MONGO_ROOT_PASS} \
		--authenticationDatabase admin \
		$${MONGO_DB:-dharmasthala_events}

admin-ui: ## Start Mongo Express admin UI (SSH tunnel: ssh -L 8081:localhost:8081)
	docker compose --profile admin-tools up -d mongo-express
	@echo "Access via SSH tunnel: ssh -L 8081:localhost:8081 user@yourserver"

# ── Monitoring ────────────────────────────────────────────────────────────────
monitoring-up: ## Start Prometheus + Grafana stack
	docker compose -f docker-compose.yml -f monitoring/docker-compose.monitoring.yml up -d

monitoring-down: ## Stop monitoring stack
	docker compose -f monitoring/docker-compose.monitoring.yml down

# ── Testing & Quality ─────────────────────────────────────────────────────────
test: ## Run backend tests
	cd backend && pytest tests/ -v --tb=short

lint: ## Lint backend with Ruff
	cd backend && ruff check . --select E,W,F,I --ignore E501

# ── Cleanup ───────────────────────────────────────────────────────────────────
clean: ## Remove stopped containers, unused images, build cache
	docker compose down --remove-orphans
	docker system prune -f
	docker image prune -f

clean-all: ## Full cleanup including volumes (⚠️  DESTROYS DATA)
	@echo "⚠️  This will DELETE all MongoDB data. Press Ctrl+C to cancel."
	@sleep 5
	docker compose down -v --remove-orphans
	docker system prune -af
