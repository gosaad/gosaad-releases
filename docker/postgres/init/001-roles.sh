#!/bin/sh
set -eu

require_env() {
  name="$1"
  eval "value=\${$name:-}"
  if [ -z "$value" ]; then
    echo "missing required environment variable: $name" >&2
    exit 1
  fi
}

require_env POSTGRES_USER
require_env POSTGRES_DB
require_env APP_DB_USER
require_env APP_DB_PASSWORD

if [ "$APP_DB_USER" = "$POSTGRES_USER" ]; then
  echo "APP_DB_USER must not be the bootstrap PostgreSQL superuser" >&2
  exit 1
fi

restore_configured=false
if [ -n "${SYSTEM_RESTORE_DB_ADMIN_USER:-}" ] || [ -n "${SYSTEM_RESTORE_DB_ADMIN_PASSWORD:-}" ]; then
  restore_configured=true
  require_env SYSTEM_RESTORE_DB_ADMIN_USER
  require_env SYSTEM_RESTORE_DB_ADMIN_PASSWORD

  if [ "$SYSTEM_RESTORE_DB_ADMIN_USER" = "$POSTGRES_USER" ]; then
    echo "SYSTEM_RESTORE_DB_ADMIN_USER must not be the bootstrap PostgreSQL superuser" >&2
    exit 1
  fi
  if [ "$SYSTEM_RESTORE_DB_ADMIN_USER" = "$APP_DB_USER" ]; then
    echo "SYSTEM_RESTORE_DB_ADMIN_USER must be separate from APP_DB_USER" >&2
    exit 1
  fi
  if [ "$POSTGRES_DB" = "${SYSTEM_RESTORE_MAINTENANCE_DB:-postgres}" ]; then
    echo "POSTGRES_DB must not equal SYSTEM_RESTORE_MAINTENANCE_DB" >&2
    exit 1
  fi
fi

psql --username "$POSTGRES_USER" --dbname postgres --set ON_ERROR_STOP=1 --set app_user="$APP_DB_USER" --set app_password="$APP_DB_PASSWORD" <<'SQL'
SELECT format('CREATE ROLE %I LOGIN PASSWORD %L NOCREATEDB NOSUPERUSER', :'app_user', :'app_password')
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'app_user')
\gexec
ALTER ROLE :"app_user" LOGIN PASSWORD :'app_password' NOCREATEDB NOSUPERUSER;
SQL

if [ "$restore_configured" = true ]; then
  psql --username "$POSTGRES_USER" --dbname postgres --set ON_ERROR_STOP=1 --set app_db="$POSTGRES_DB" --set app_user="$APP_DB_USER" --set maintenance_db="${SYSTEM_RESTORE_MAINTENANCE_DB:-postgres}" --set restore_user="$SYSTEM_RESTORE_DB_ADMIN_USER" --set restore_password="$SYSTEM_RESTORE_DB_ADMIN_PASSWORD" <<'SQL'
SELECT format('CREATE ROLE %I LOGIN PASSWORD %L CREATEDB NOSUPERUSER', :'restore_user', :'restore_password')
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'restore_user')
\gexec
ALTER ROLE :"restore_user" LOGIN PASSWORD :'restore_password' CREATEDB NOSUPERUSER;
ALTER DATABASE :"app_db" OWNER TO :"restore_user";
GRANT CONNECT ON DATABASE :"maintenance_db" TO :"restore_user";
SQL
fi

psql --username "$POSTGRES_USER" --dbname postgres --set ON_ERROR_STOP=1 --set app_db="$POSTGRES_DB" --set app_user="$APP_DB_USER" <<'SQL'
GRANT CONNECT, CREATE, TEMPORARY ON DATABASE :"app_db" TO :"app_user";
\connect :app_db
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
GRANT USAGE, CREATE ON SCHEMA public TO :"app_user";
SQL

