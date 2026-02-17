#!/bin/bash
# Script para restaurar un backup de PostgreSQL (sin migración de ownership)
# Este script simplemente restaura el backup usando --no-owner
# Uso: ./scripts/backup_and_restore.sh <ruta/al/backup.dump>

set -e  # Salir si hay errores

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🔄 Proceso de Restauración de Backup PostgreSQL (Simple)${NC}"
echo "================================================"

# Verificar que se proporcionó el archivo de backup
if [ -z "$1" ]; then
  echo -e "${RED}❌ Error: Debes proporcionar la ruta al archivo de backup${NC}"
  echo "   Uso: $0 <ruta/al/backup.dump>"
  echo "   Ejemplo: $0 backups/expense_db_manual_20251214_175850.dump"
  exit 1
fi

BACKUP_FILE=$1

# Verificar que el archivo existe
if [ ! -f "$BACKUP_FILE" ]; then
  echo -e "${RED}❌ Error: El archivo de backup no existe: $BACKUP_FILE${NC}"
  exit 1
fi

# ===== PASO 1: VERIFICAR CONTENEDOR Y OBTENER CREDENCIALES =====
echo ""
echo -e "${BLUE}📦 Paso 1: Verificando contenedor y credenciales...${NC}"

# Verificar que el contenedor está corriendo
if ! docker compose ps postgres | grep -q "Up"; then
  echo -e "${RED}❌ Error: El contenedor de PostgreSQL no está corriendo${NC}"
  echo "   Ejecuta: docker compose up -d postgres"
  exit 1
fi

# Obtener credenciales actuales
DB_USER=$(docker compose exec -T postgres printenv POSTGRES_USER | tr -d '\r\n' || echo "expense_user")
DB_NAME=$(docker compose exec -T postgres printenv POSTGRES_DB | tr -d '\r\n' || echo "expense_db")
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

echo "   Usuario actual: $DB_USER"
echo "   Base de datos: $DB_NAME"
echo "   Ruta de backup: $BACKUP_FILE"
echo "   Timestamp: $TIMESTAMP"

# ===== PASO 2: COPIAR BACKUP AL CONTENEDOR =====
echo ""
echo -e "${BLUE}📥 Paso 2: Copiando backup al contenedor...${NC}"
docker compose cp "$BACKUP_FILE" postgres:/tmp/backup.dump
echo "   ✅ Backup copiado"

# ===== PASO 3: RESTAURAR BACKUP =====
echo ""
echo -e "${BLUE}📥 Paso 3: Restaurando backup...${NC}"

# Verificar si el backup es formato custom (.dump) o SQL (.sql)
if [[ "$BACKUP_FILE" == *.dump ]]; then
  # Formato custom: usar pg_restore
  echo "   Formato detectado: Custom (.dump)"
  echo "   Restaurando con --no-owner y --no-privileges..."
  docker compose exec -T postgres pg_restore \
    -U "$DB_USER" \
    -d "$DB_NAME" \
    --clean \
    --if-exists \
    --no-owner \
    --no-privileges \
    --verbose \
    /tmp/backup.dump || {
      echo -e "${YELLOW}⚠️  Algunos warnings pueden aparecer durante la restauración${NC}"
    }
else
  # Formato SQL: usar psql
  echo "   Formato detectado: SQL (.sql)"
  docker compose exec -T postgres psql \
    -U "$DB_USER" \
    -d "$DB_NAME" \
    --single-transaction \
    < /tmp/backup.dump
fi

echo -e "${GREEN}✅ Backup restaurado${NC}"

# Limpiar archivo temporal
docker compose exec -T postgres rm -f /tmp/backup.dump

# ===== PASO 4: VERIFICAR RESTAURACIÓN =====
echo ""
echo -e "${BLUE}🔍 Paso 4: Verificando restauración...${NC}"

TABLE_COUNT=$(docker compose exec -T postgres psql -U "$DB_USER" -d "$DB_NAME" -t -c \
  "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public';" | tr -d ' ')

echo "   Tablas encontradas: $TABLE_COUNT"

if [ "$TABLE_COUNT" -gt "0" ]; then
  echo -e "${GREEN}✅ Restauración verificada: $TABLE_COUNT tablas encontradas${NC}"
else
  echo -e "${YELLOW}⚠️  No se encontraron tablas. Verifica manualmente.${NC}"
fi

# ===== RESUMEN FINAL =====
echo ""
echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}✅ Proceso completado exitosamente${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
echo ""
echo "📝 Resumen:"
echo "   ✅ Backup restaurado: $BACKUP_FILE"
echo "   ✅ Usuario: $DB_USER"
echo "   ✅ Base de datos: $DB_NAME"
echo "   ✅ Tablas: $TABLE_COUNT"
echo ""
echo "🔧 Próximos pasos:"
echo "   1. Verifica las tablas:"
echo "      docker compose exec postgres psql -U $DB_USER -d $DB_NAME -c '\\dt'"
echo "   2. Verifica el ownership:"
echo "      docker compose exec postgres psql -U $DB_USER -d $DB_NAME -c 'SELECT tablename, tableowner FROM pg_tables WHERE schemaname = '\''public'\'';'"
echo "   3. Reinicia el backend para aplicar cambios:"
echo "      docker compose restart backend"
echo "   4. Verifica las migraciones:"
echo "      docker compose exec backend alembic current"
echo ""
