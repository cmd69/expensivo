#!/bin/bash
# ============================================================================
# Deploy de producción en la VM
# ============================================================================
# Uso: desde la carpeta del repo público (ej. ~/docker/expense_mvp)
#   ./scripts/deploy-production.sh
# O mejor: make deploy (incluye backup-db si lo ejecutas antes)
# ============================================================================

set -e

COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.prod.yml}"

if [ ! -f "$COMPOSE_FILE" ]; then
  echo "Error: No se encuentra $COMPOSE_FILE. Ejecuta desde la raíz del proyecto (ej. ~/docker/expense_mvp)."
  exit 1
fi

echo "Pulling imágenes (compose: $COMPOSE_FILE)..."
docker compose -f "$COMPOSE_FILE" pull

echo "Levantando servicios..."
docker compose -f "$COMPOSE_FILE" up -d

echo "Ejecutando migraciones de Alembic..."
docker compose -f "$COMPOSE_FILE" exec -T backend alembic upgrade head

echo "Estado:"
docker compose -f "$COMPOSE_FILE" ps

echo "Listo. Comprobar health con: docker compose -f $COMPOSE_FILE ps"
