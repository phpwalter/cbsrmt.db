#!/usr/bin/env bash
set -euo pipefail

HOST="localhost"
PORT="5432"
DATABASE="cbsrmt"
USER_NAME="postgres"
REBUILD=0

usage() {
  cat <<'EOF'
Usage: bash install/fresh_install.sh [options]

Options:
  --host HOST         PostgreSQL host (default: localhost)
  --port PORT         PostgreSQL port (default: 5432)
  --database NAME     Database name (default: cbsrmt)
  --user USER         PostgreSQL user (default: postgres)
  --rebuild           Drop and recreate only CBS RMT schemas
  -h, --help          Show this help

Authentication uses normal libpq behavior. For unattended installs use PGPASSWORD or .pgpass.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host) HOST="$2"; shift 2 ;;
    --port) PORT="$2"; shift 2 ;;
    --database) DATABASE="$2"; shift 2 ;;
    --user) USER_NAME="$2"; shift 2 ;;
    --rebuild) REBUILD=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

command -v psql >/dev/null 2>&1 || { echo "psql is required." >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "python3 is required." >&2; exit 1; }

if [[ -z "${PGPASSWORD:-}" ]]; then
  read -r -s -p "PostgreSQL password for $USER_NAME: " PGPASSWORD
  echo
  export PGPASSWORD
fi

if [[ ! "$DATABASE" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
  echo "Database name may contain only letters, numbers, and underscores and may not begin with a number." >&2
  exit 2
fi

MAINT=(psql -X -v ON_ERROR_STOP=1 -h "$HOST" -p "$PORT" -U "$USER_NAME" -d postgres)
database_exists="$("${MAINT[@]}" -tA -c "SELECT EXISTS (SELECT 1 FROM pg_database WHERE datname = '$DATABASE');" | tr -d '[:space:]')"
if [[ "$database_exists" != "t" ]]; then
  echo "Database '$DATABASE' does not exist; creating it..."
  "${MAINT[@]}" -c "CREATE DATABASE \"$DATABASE\";"
fi

PSQL=(psql -X -v ON_ERROR_STOP=1 -h "$HOST" -p "$PORT" -U "$USER_NAME" -d "$DATABASE")
DSN="host=$HOST port=$PORT dbname=$DATABASE user=$USER_NAME"

echo "CBS RMT PostgreSQL fresh installer"
echo "Target: $USER_NAME@$HOST:$PORT/$DATABASE"

existing="$("${PSQL[@]}" -tA -c "SELECT EXISTS (SELECT 1 FROM pg_namespace WHERE nspname IN ('catalog','api','admin','stage','import','account'));" | tr -d '[:space:]')"

if [[ "$REBUILD" -eq 1 ]]; then
  echo "Rebuild requested: dropping CBS RMT schemas only."
  "${PSQL[@]}" -c "DROP SCHEMA IF EXISTS admin, api, import, stage, account, catalog CASCADE;"
elif [[ "$existing" == "t" ]]; then
  echo "CBS RMT schemas already exist. Re-run with --rebuild to replace only CBS RMT schemas." >&2
  exit 1
fi

echo "Installing schema and functions..."
"${PSQL[@]}" -f "$ROOT/install/schema.sql"

if [[ ! -x "$ROOT/.venv/bin/python" ]]; then
  echo "Creating Python virtual environment..."
  python3 -m venv "$ROOT/.venv"
fi

PYTHON="$ROOT/.venv/bin/python"
echo "Installing loader dependency..."
"$PYTHON" -m pip install --disable-pip-version-check -r "$ROOT/requirements.txt"

echo "Reconciling, staging, and importing JSON data..."
"$PYTHON" "$ROOT/tools/load_json.py" --dsn "$DSN" --data-dir "$ROOT/data"

echo "Running integrity tests..."
"${PSQL[@]}" -f "$ROOT/tests/001_integrity.sql"

echo "Running API contract tests..."
"${PSQL[@]}" -f "$ROOT/tests/002_api_contract.sql"

echo ""
echo "Final database counts:"
"${PSQL[@]}" -c "SELECT (SELECT count(*) FROM catalog.episode) AS episodes, (SELECT count(*) FROM catalog.broadcast) AS broadcast_rows, (SELECT count(*) FROM catalog.broadcast WHERE broadcast_sequence IS NOT NULL) AS actual_broadcasts, (SELECT count(*) FROM catalog.person) AS people, (SELECT count(*) FROM catalog.genre) AS genres, (SELECT count(*) FROM catalog.adaptation) AS adaptations;"

echo ""
echo "PASS: CBS RMT PostgreSQL schema and data are installed and validated."
