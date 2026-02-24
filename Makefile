.PHONY: up down reset run test docs nb dashboard psql validate help

# ─────────────────────────────────────────
# Docker
# ─────────────────────────────────────────

up:        ## Start Postgres + pgAdmin
	docker compose up -d
	@echo ""
	@echo "  DB ready at   postgresql://churn_user:churn_pass@localhost:5432/churn_analytics"
	@echo "  pgAdmin at    http://localhost:5050  (admin@churn.local / admin)"

down:      ## Stop containers (keeps data)
	docker compose down

reset:     ## Wipe data and reseed from scratch
	docker compose down -v
	docker compose up -d
	@echo "Database reset and reseeded."

# ─────────────────────────────────────────
# dbt
# ─────────────────────────────────────────

run:       ## Run all dbt models
	cd dbt && dbt run

test:      ## Run all dbt tests
	cd dbt && dbt test

docs:      ## Generate and serve dbt docs (opens browser)
	cd dbt && dbt docs generate && dbt docs serve

# ─────────────────────────────────────────
# Dashboard & Notebook
# ─────────────────────────────────────────

dashboard: ## Launch Streamlit dashboard at http://localhost:8501
	streamlit run dashboard/app.py

nb:        ## Launch Jupyter notebook
	jupyter notebook notebooks/churn_analysis.ipynb

# ─────────────────────────────────────────
# SQL shortcuts
# ─────────────────────────────────────────

psql:      ## Open psql shell
	psql postgresql://churn_user:churn_pass@localhost:5432/churn_analytics

validate:  ## Run validation checks
	psql postgresql://churn_user:churn_pass@localhost:5432/churn_analytics \
	  -f sql/99_validation_checks.sql

# ─────────────────────────────────────────

help:      ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
	  | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

.DEFAULT_GOAL := help
