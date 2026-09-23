#!/usr/bin/env bash
set -euo pipefail

HOST="localhost"
PORT="5432"
DATABASE="cbsrmt"
USER_NAME="postgres"
VALIDATE_ONLY=0

usage() {
  cat <<'EOF'
Usage: bash install/apply_cast_corrections.sh [options]

Options:
  --host HOST         PostgreSQL host (default: localhost)
  --port PORT         PostgreSQL port (default: 5432)
  --database NAME     Database name (default: cbsrmt)
  --user USER         PostgreSQL user (default: postgres)
  --validate-only     Validate JSON files without changing PostgreSQL
  -h, --help          Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host) HOST="$2"; shift 2 ;;
    --port) PORT="$2"; shift 2 ;;
    --database) DATABASE="$2"; shift 2 ;;
    --user) USER_NAME="$2"; shift 2 ;;
    --validate-only) VALIDATE_ONLY=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

PYTHON="$ROOT/.venv/bin/python"
if [[ ! -x "$PYTHON" ]]; then
  command -v python3 >/dev/null 2>&1 || { echo "python3 is required." >&2; exit 1; }
  PYTHON="$(command -v python3)"
fi

DSN="host=$HOST port=$PORT dbname=$DATABASE user=$USER_NAME"
ARGS=("$ROOT/tools/apply_cast_corrections.py" --dsn "$DSN" --data-dir "$ROOT/data")
if [[ "$VALIDATE_ONLY" -eq 1 ]]; then
  ARGS+=(--validate-only)
fi

"$PYTHON" "${ARGS[@]}"
echo "PASS: cast corrections validated and promoted."
