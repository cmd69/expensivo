# ============================================================================
# Makefile - Expensivo (repo público de producción)
# ============================================================================
# Comandos compatibles con el repo privado. Usa docker-compose.prod.yml.
# Servicios: postgres, backend, frontend, redis (mismos nombres que el privado).
# ============================================================================

COMPOSE_FILE ?= docker-compose.prod.yml

.PHONY: help backup-db migrate up down restart logs logs-backend logs-db shell-backend shell-db deploy

help: ## Mostrar esta ayuda
	@echo "Comandos disponibles (compose: $(COMPOSE_FILE)):"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

backup-db: ## Crear backup de la base de datos (formato custom con timestamp)
	@echo "🔄 Creando backup (formato custom) de la base de datos..."
	@mkdir -p backups
	@TIMESTAMP=$$(date +%Y%m%d_%H%M%S); \
	DB_NAME=$$(docker compose -f $(COMPOSE_FILE) exec -T postgres printenv POSTGRES_DB 2>/dev/null | tr -d '\r\n' || echo "expensivo_db"); \
	DB_USER=$$(docker compose -f $(COMPOSE_FILE) exec -T postgres printenv POSTGRES_USER 2>/dev/null | tr -d '\r\n' || echo "expensivo_user"); \
	BACKUP_FILE="backups/$${DB_NAME}_$${TIMESTAMP}.dump"; \
	echo "📦 Backup: $$BACKUP_FILE"; \
	echo "📊 Base de datos: $$DB_NAME | Usuario: $$DB_USER"; \
	docker compose -f $(COMPOSE_FILE) exec -T postgres pg_dump -U $$DB_USER -d $$DB_NAME -F c -f "/tmp/backup.dump"; \
	docker compose -f $(COMPOSE_FILE) cp postgres:/tmp/backup.dump $$BACKUP_FILE; \
	docker compose -f $(COMPOSE_FILE) exec -T postgres rm -f /tmp/backup.dump; \
	if [ -f $$BACKUP_FILE ]; then \
		BACKUP_SIZE=$$(du -h $$BACKUP_FILE | cut -f1); \
		echo "✅ Backup creado exitosamente: $$BACKUP_FILE ($$BACKUP_SIZE)"; \
	else \
		echo "❌ Error al crear el backup"; \
		rm -f $$BACKUP_FILE; \
		exit 1; \
	fi

backup-restore: ## Restaurar backup (simple, sin migración de ownership)
	@if [ -z "$(BACKUP_PATH)" ]; then \
		echo "❌ Error: Debes proporcionar BACKUP_PATH"; \
		echo "Uso: make backup-restore BACKUP_PATH=<ruta/al/backup.dump>"; \
		echo "Ejemplo: make backup-restore BACKUP_PATH=backups/expense_db_manual_20251214_175850.dump"; \
		exit 1; \
	fi; \
	./scripts/backup_and_restore.sh $(BACKUP_PATH)

backup-restore-migrate: ## Restaurar backup y migrar ownership de usuario antiguo al nuevo
	@if [ -z "$(BACKUP_PATH)" ]; then \
		echo "❌ Error: Debes proporcionar BACKUP_PATH"; \
		echo "Uso: make backup-restore-migrate BACKUP_PATH=<ruta/al/backup.dump>"; \
		echo "Ejemplo: make backup-restore-migrate BACKUP_PATH=backups/expense_db_manual_20251214_175850.dump"; \
		exit 1; \
	fi; \
	./scripts/backup_and_restore_with_migration.sh $(BACKUP_PATH)

migrate: ## Ejecutar migraciones de Alembic (alembic upgrade head)
	docker compose -f $(COMPOSE_FILE) exec -T backend alembic upgrade head

up: ## Iniciar todos los servicios
	docker compose -f $(COMPOSE_FILE) up -d

down: ## Detener todos los servicios
	docker compose -f $(COMPOSE_FILE) down

restart: ## Reiniciar todos los servicios
	docker compose -f $(COMPOSE_FILE) restart

logs: ## Ver logs de todos los servicios
	docker compose -f $(COMPOSE_FILE) logs -f

logs-backend: ## Ver logs del backend
	docker compose -f $(COMPOSE_FILE) logs -f backend

logs-db: ## Ver logs de PostgreSQL
	docker compose -f $(COMPOSE_FILE) logs -f postgres

shell-backend: ## Abrir shell en el contenedor del backend
	docker compose -f $(COMPOSE_FILE) exec backend bash

shell-db: ## Abrir shell en PostgreSQL
	@DB_USER=$$(docker compose -f $(COMPOSE_FILE) exec -T postgres printenv POSTGRES_USER 2>/dev/null | tr -d '\r\n' || echo "expensivo_user"); \
	DB_NAME=$$(docker compose -f $(COMPOSE_FILE) exec -T postgres printenv POSTGRES_DB 2>/dev/null | tr -d '\r\n' || echo "expensivo_db"); \
	docker compose -f $(COMPOSE_FILE) exec postgres psql -U $$DB_USER -d $$DB_NAME

deploy: ## Pull, up, migrate y estado (flujo completo de deploy)
	docker compose -f $(COMPOSE_FILE) pull
	docker compose -f $(COMPOSE_FILE) up -d
	@echo "🔄 Ejecutando migraciones de Alembic..."
	docker compose -f $(COMPOSE_FILE) exec -T backend alembic upgrade head
	docker compose -f $(COMPOSE_FILE) ps
