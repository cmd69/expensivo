# expensivo

Instancia de **producción** del gestor de gastos. Usa imágenes pre-construidas desde DockerHub.

## Stack

- **Backend:** Python / FastAPI (imagen `cmd69/expensivo-backend:latest`)
- **Frontend:** Next.js (imagen `cmd69/expensivo-frontend:latest`)
- **Base de datos:** PostgreSQL 15 + Redis 7
- **Deploy:** Docker Compose con imágenes de registry
- **Tipo:** prod — no compilar aquí, solo desplegar

## Relación prod/dev

- **Repo prod (este):** `~/homelab/docker/expensivo/`
- **Repo dev:** `~/homelab/docker/expensivo-dev/` — código fuente aquí

**Para desarrollo, usar siempre `expensivo-dev`.** Este repo solo despliega.

## Arrancar

```bash
make up          # levantar servicios
make down        # parar
make logs        # ver logs
make deploy      # pull + up + migrate
make backup-db   # backup de la BD
```

## Ejecución de comandos

**Todos los comandos se ejecutan dentro del contenedor:**

```bash
make shell-backend                    # shell en el backend
make shell-db                         # psql en PostgreSQL
make migrate                          # alembic upgrade head
docker compose exec backend <cmd>     # cualquier comando
```

**Nunca ejecutar `python3`, `pip install`, `npm` u otros comandos directamente en el host.**

## Puertos

| Servicio | Puerto host |
|---|---|
| Frontend | 3030 |
| Backend | 8008 |
| PostgreSQL | 5432 |
| Redis | 6379 |

## Convención de commits

```
[NN] TYPE(scope): descripción breve
```

- `[NN]` secuencial por repo (último: `[06]`, siguiente: `[07]`)
- Tipos: `FEAT` `FIX` `DOCS` `REFACTOR` `CHORE` `TEST` `CI` `INFRA` `STYLE`
- Guía completa: `~/.agent/CODING.md`
