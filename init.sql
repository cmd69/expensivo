-- ============================================================================
-- Script de inicialización de PostgreSQL para Expensivo
-- ============================================================================
-- Este script se ejecuta automáticamente al crear el contenedor por primera vez
-- Solo se ejecuta si la base de datos está vacía (primera vez)
-- ============================================================================

-- Crear extensiones útiles de PostgreSQL
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";  -- Para generar UUIDs
CREATE EXTENSION IF NOT EXISTS "pg_trgm";    -- Para búsquedas de texto (trigramas)

-- ============================================================================
-- NOTA: Los esquemas y tablas se crearán automáticamente mediante Alembic
-- ============================================================================
-- El backend ejecuta las migraciones de Alembic automáticamente al iniciar.
-- No es necesario crear tablas manualmente aquí.
-- ============================================================================

