#!/bin/bash
# Script para restaurar un backup de PostgreSQL y migrar usuario antiguo al nuevo
# Este script detecta el usuario del backup y migra el ownership al usuario actual
# Uso: ./scripts/backup_and_restore_with_migration.sh <ruta/al/backup.dump>

set -e  # Salir si hay errores

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🔄 Proceso de Restauración de Backup PostgreSQL${NC}"
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

# ===== PASO 1: RUTA BACKUP Y USUARIO Y BASE DE DATOS =====
echo ""
echo -e "${BLUE}📦 Paso 1: Estableciendo ruta de backup...${NC}"

# Verificar que el contenedor está corriendo
if ! docker compose ps postgres | grep -q "Up"; then
  echo -e "${RED}❌ Error: El contenedor de PostgreSQL no está corriendo${NC}"
  echo "   Ejecuta: docker compose up -d postgres"
  exit 1
fi

# Obtener credenciales actuales
DB_USER=$(docker compose exec -T postgres printenv POSTGRES_USER | tr -d '\r\n' || echo "expense_user")
DB_NAME=$(docker compose exec -T postgres printenv POSTGRES_DB | tr -d '\r\n' || echo "expense_db")
DB_PASSWORD=$(docker compose exec -T postgres printenv POSTGRES_PASSWORD | tr -d '\r\n' || echo "")
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

echo "   Usuario actual: $DB_USER"
echo "   Base de datos: $DB_NAME"
echo "   Ruta de backup: $BACKUP_FILE"
echo "   Timestamp: $TIMESTAMP"

# ===== PASO 2: DETECTAR USUARIO ANTIGUO DEL BACKUP =====
echo ""
echo -e "${BLUE}🔍 Paso 2: Detectando usuario antiguo del backup...${NC}"

# Copiar backup al contenedor temporalmente para analizarlo
docker compose cp "$BACKUP_FILE" postgres:/tmp/backup.dump

# Extraer el usuario antiguo del backup usando pg_restore --list
# Buscamos líneas que contengan "OWNER TO" y extraemos el nombre del usuario
OLD_USER=""
if [[ "$BACKUP_FILE" == *.dump ]]; then
  # Para formato custom, usar pg_restore --list
  OLD_USER=$(docker compose exec -T postgres pg_restore --list /tmp/backup.dump 2>/dev/null | \
    grep -i "OWNER TO" | \
    head -1 | \
    sed -E "s/.*OWNER TO ([^;]+).*/\1/i" | \
    tr -d ' "' | \
    head -1 || echo "")
  
  # Si no encontramos en el listado, intentar restaurar y capturar el error
  if [ -z "$OLD_USER" ]; then
    echo "   Analizando contenido del backup..."
    # Intentar restaurar con --no-owner para ver qué usuario se menciona en los errores
    ERROR_OUTPUT=$(docker compose exec -T postgres pg_restore \
      -U "$DB_USER" \
      -d "$DB_NAME" \
      --no-owner \
      --no-privileges \
      --list-only \
      /tmp/backup.dump 2>&1 || true)
    
    # Buscar patrones como "OWNER TO expense_user" o "role \"expense_user\""
    OLD_USER=$(echo "$ERROR_OUTPUT" | \
      grep -oE "OWNER TO [a-zA-Z_][a-zA-Z0-9_]*" | \
      head -1 | \
      sed -E "s/OWNER TO //i" || echo "")
    
    # Si aún no encontramos, buscar en el contenido del dump directamente
    if [ -z "$OLD_USER" ]; then
      OLD_USER=$(docker compose exec -T postgres strings /tmp/backup.dump 2>/dev/null | \
        grep -i "owner to" | \
        head -1 | \
        sed -E "s/.*[Oo][Ww][Nn][Ee][Rr] [Tt][Oo] ([a-zA-Z_][a-zA-Z0-9_]*).*/\1/i" | \
        head -1 || echo "")
    fi
  fi
fi

# Si no detectamos el usuario, usar expense_user como valor por defecto
if [ -z "$OLD_USER" ]; then
  echo -e "${YELLOW}⚠️  No se pudo detectar automáticamente el usuario antiguo del backup${NC}"
  echo -e "${YELLOW}   Usando 'expense_user' como usuario por defecto del backup${NC}"
  OLD_USER="expense_user"
fi

if [ -z "$OLD_USER" ]; then
  echo -e "${YELLOW}⚠️  No se especificó usuario antiguo. Se restaurará sin migración de usuario.${NC}"
  MIGRATE_USER=false
elif [ "$OLD_USER" == "$DB_USER" ]; then
  echo "   ✅ El usuario del backup es el mismo que el actual. No se requiere migración."
  MIGRATE_USER=false
else
  echo "   Usuario antiguo detectado: $OLD_USER"
  echo "   Usuario nuevo: $DB_USER"
  MIGRATE_USER=true
fi

# ===== PASO 3: CREAR USUARIO ANTIGUO SI NO EXISTE =====
if [ "$MIGRATE_USER" = true ]; then
  echo ""
  echo -e "${BLUE}👤 Paso 3: Preparando usuario antiguo...${NC}"
  
  # Verificar si el usuario antiguo existe
  USER_EXISTS=$(docker compose exec -T postgres psql -U "$DB_USER" -d postgres -t -c \
    "SELECT 1 FROM pg_roles WHERE rolname = '$OLD_USER';" | tr -d ' ' || echo "0")
  
  if [ "$USER_EXISTS" != "1" ]; then
    echo "   Creando usuario temporal: $OLD_USER"
    # Crear el usuario con permisos mínimos (solo para poder restaurar)
    docker compose exec -T postgres psql -U "$DB_USER" -d postgres -c \
      "CREATE ROLE \"$OLD_USER\" WITH LOGIN;" || {
      echo -e "${YELLOW}⚠️  No se pudo crear el usuario. Intentando continuar...${NC}"
    }
    echo "   ✅ Usuario $OLD_USER creado temporalmente"
  else
    echo "   ✅ Usuario $OLD_USER ya existe"
  fi
fi

# ===== PASO 4: RESTAURAR BACKUP =====
echo ""
echo -e "${BLUE}📥 Paso 4: Restaurando backup...${NC}"

# Verificar si el backup es formato custom (.dump) o SQL (.sql)
if [[ "$BACKUP_FILE" == *.dump ]]; then
  # Formato custom: usar pg_restore
  echo "   Formato detectado: Custom (.dump)"
  
  if [ "$MIGRATE_USER" = true ]; then
    echo "   Restaurando con --no-owner (se migrará ownership después)..."
    # Restaurar con --no-owner para evitar problemas de permisos, luego migraremos el ownership
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
    echo "   Restaurando sin migración de usuario..."
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
  fi
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

# ===== PASO 5: MIGRAR OWNERSHIP AL USUARIO NUEVO =====
if [ "$MIGRATE_USER" = true ]; then
  echo ""
  echo -e "${BLUE}🔄 Paso 5: Migrando ownership de $OLD_USER a $DB_USER...${NC}"
  
  # Cambiar ownership de la base de datos
  echo "   Cambiando ownership de la base de datos..."
  docker compose exec -T postgres psql -U "$DB_USER" -d postgres -c \
    "ALTER DATABASE \"$DB_NAME\" OWNER TO \"$DB_USER\";" 2>/dev/null || true
  
  # Cambiar ownership del esquema public
  echo "   Cambiando ownership del esquema public..."
  docker compose exec -T postgres psql -U "$DB_USER" -d "$DB_NAME" -c \
    "ALTER SCHEMA public OWNER TO \"$DB_USER\";" 2>/dev/null || true
  
  # Migración masiva de ownership usando un bloque DO
  echo "   Aplicando migración masiva de ownership..."
  # Usar un heredoc con comillas simples para evitar expansión de variables problemática
  # y usar current_user que será el usuario que ejecuta (DB_USER)
  docker compose exec -T postgres psql -U "$DB_USER" -d "$DB_NAME" <<'SQL_EOF'
-- Cambiar ownership de todos los objetos
DO $$
DECLARE
    r RECORD;
    new_user TEXT;
BEGIN
    -- Usar el usuario actual (que es el que ejecuta el comando, DB_USER)
    new_user := current_user;
    
    -- Cambiar ownership de todas las tablas
    FOR r IN (SELECT tablename FROM pg_tables WHERE schemaname = 'public')
    LOOP
        BEGIN
            EXECUTE format('ALTER TABLE public.%I OWNER TO %I', r.tablename, new_user);
        EXCEPTION WHEN OTHERS THEN
            -- Ignorar errores y continuar
            NULL;
        END;
    END LOOP;
    
    -- Cambiar ownership de todas las secuencias
    FOR r IN (SELECT sequence_name FROM information_schema.sequences WHERE sequence_schema = 'public')
    LOOP
        BEGIN
            EXECUTE format('ALTER SEQUENCE public.%I OWNER TO %I', r.sequence_name, new_user);
        EXCEPTION WHEN OTHERS THEN
            -- Ignorar errores y continuar
            NULL;
        END;
    END LOOP;
    
    -- Cambiar ownership de todos los tipos
    FOR r IN (SELECT typname FROM pg_type WHERE typnamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public') AND typtype = 'c')
    LOOP
        BEGIN
            EXECUTE format('ALTER TYPE public.%I OWNER TO %I', r.typname, new_user);
        EXCEPTION WHEN OTHERS THEN
            -- Ignorar errores y continuar
            NULL;
        END;
    END LOOP;
    
    -- Cambiar ownership de todas las funciones
    FOR r IN (
        SELECT p.proname, pg_get_function_identity_arguments(p.oid) as args
        FROM pg_proc p
        JOIN pg_namespace n ON p.pronamespace = n.oid
        WHERE n.nspname = 'public'
    )
    LOOP
        BEGIN
            EXECUTE format('ALTER FUNCTION public.%I(%s) OWNER TO %I', r.proname, r.args, new_user);
        EXCEPTION WHEN OTHERS THEN
            -- Ignorar errores y continuar
            NULL;
        END;
    END LOOP;
END
$$;
SQL_EOF
  
  echo -e "${GREEN}✅ Migración de ownership completada${NC}"
  
  # Opcional: eliminar el usuario antiguo
  echo ""
  read -p "¿Deseas eliminar el usuario antiguo '$OLD_USER'? (s/N): " -n 1 -r
  echo
  if [[ $REPLY =~ ^[SsYy]$ ]]; then
    echo "   Eliminando usuario $OLD_USER..."
    docker compose exec -T postgres psql -U "$DB_USER" -d postgres -c \
      "DROP ROLE IF EXISTS \"$OLD_USER\";" 2>/dev/null || true
    echo -e "${GREEN}✅ Usuario $OLD_USER eliminado${NC}"
  else
    echo "   Usuario $OLD_USER se mantiene (puedes eliminarlo manualmente después)"
  fi
fi

# Limpiar archivo temporal
docker compose exec -T postgres rm -f /tmp/backup.dump

# ===== PASO 6: VERIFICAR RESTAURACIÓN =====
echo ""
echo -e "${BLUE}🔍 Paso 6: Verificando restauración...${NC}"

TABLE_COUNT=$(docker compose exec -T postgres psql -U "$DB_USER" -d "$DB_NAME" -t -c \
  "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public';" | tr -d ' ')

echo "   Tablas encontradas: $TABLE_COUNT"

# Verificar ownership de las tablas
if [ "$MIGRATE_USER" = true ]; then
  TABLES_WITH_OLD_USER=$(docker compose exec -T postgres psql -U "$DB_USER" -d "$DB_NAME" -t -c \
    "SELECT COUNT(*) FROM pg_tables WHERE schemaname = 'public' AND tableowner = '$OLD_USER';" | tr -d ' ' || echo "0")
  
  if [ "$TABLES_WITH_OLD_USER" = "0" ]; then
    echo -e "${GREEN}✅ Todas las tablas pertenecen a $DB_USER${NC}"
  else
    echo -e "${YELLOW}⚠️  Aún hay $TABLES_WITH_OLD_USER tablas con el usuario antiguo${NC}"
  fi
fi

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
if [ "$MIGRATE_USER" = true ]; then
  echo "   ✅ Usuario migrado: $OLD_USER → $DB_USER"
fi
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
