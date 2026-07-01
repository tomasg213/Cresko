.PHONY: setup dev-backend dev-frontend dev db-status clean

BACKEND_DIR = backend
FRONTEND_DIR = frontend
VENV_DIR = $(BACKEND_DIR)/.venv

setup: setup-backend setup-frontend

setup-backend:
	python3 -m venv $(VENV_DIR) && \
	. $(VENV_DIR)/bin/activate && \
	pip install --upgrade pip && \
	pip install -r $(BACKEND_DIR)/requirements.txt

setup-frontend:
	cd $(FRONTEND_DIR) && pnpm install

dev-backend:
	. $(VENV_DIR)/bin/activate && \
	uvicorn app.main:app --reload --host 0.0.0.0 --port 8000 --app-dir $(BACKEND_DIR)

dev-frontend:
	cd $(FRONTEND_DIR) && pnpm dev

dev:
	@trap 'kill 0' EXIT; \
	$(MAKE) dev-backend & \
	$(MAKE) dev-frontend & \
	wait

db-status:
	@echo "Checking PostgreSQL connection..."
	@PGPASSWORD=$${DB_PASSWORD:-cresko} psql \
		-h $${DB_HOST:-localhost} \
		-p $${DB_PORT:-5432} \
		-U $${DB_USER:-cresko} \
		-d $${DB_NAME:-cresko} \
		-c "SELECT 'Connection OK' AS status;" 2>&1 || \
		echo "ERROR: Could not connect to PostgreSQL. Is it running?"

db-migrate:
	. $(VENV_DIR)/bin/activate && \
	cd $(BACKEND_DIR) && \
	alembic upgrade head

db-revision:
	. $(VENV_DIR)/bin/activate && \
	cd $(BACKEND_DIR) && \
	alembic revision --autogenerate -m "$(message)"

clean:
	rm -rf $(VENV_DIR)
	rm -rf $(FRONTEND_DIR)/node_modules
	rm -rf $(FRONTEND_DIR)/.next
	rm -rf $(BACKEND_DIR)/__pycache__
	rm -rf $(BACKEND_DIR)/app/__pycache__
	rm -rf $(BACKEND_DIR)/app/core/__pycache__
	find . -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true
