#!/bin/sh
# Create a PostgreSQL logical dump of the Synkronus database from a running Postgres container.
# Uses pg_dump inside the container (reads POSTGRES_USER / POSTGRES_DB from the container env).
#
# Matches the default quickstart compose: service `db`, container_name `postgres`, database `synkronus`.
#
# Requires: podman or docker on the host.
#
# Usage:
#   ./backup-db.sh [-c name] [-o file.sql]
#   SYNKRONUS_DB_CONTAINER=postgres ./backup-db.sh [output-file.sql]
#
#   -c   container name or id (default: postgres, or SYNKRONUS_DB_CONTAINER)
#   -o   output file (default: ./synkronus-db-backup-YYYYMMDD-HHMMSS.sql in cwd)
#
# Plain SQL (default). Suitable for pg_restore only if you use custom format; this script uses
# pg_dump plain SQL for simple inspection and `psql -f` restores.

set -eu

usage() {
  echo "Usage: $0 [-c container] [-o backup.sql]" >&2
  echo "       SYNKRONUS_DB_CONTAINER=name $0 [backup.sql]" >&2
  echo "Dumps the Synkronus database from a running Postgres container (pg_dump)." >&2
}

CONTAINER="${SYNKRONUS_DB_CONTAINER:-postgres}"
OUT=""

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    -c)
      if [ -z "${2:-}" ]; then echo "$0: -c needs a value" >&2; exit 1; fi
      CONTAINER="$2"
      shift 2
      ;;
    -o)
      if [ -z "${2:-}" ]; then echo "$0: -o needs a value" >&2; exit 1; fi
      OUT="$2"
      shift 2
      ;;
    *)
      if [ -n "$OUT" ]; then
        echo "$0: unexpected argument: $1" >&2
        exit 1
      fi
      OUT=$1
      shift
      ;;
  esac
done

if command -v podman >/dev/null 2>&1; then
  RUNTIME=podman
elif command -v docker >/dev/null 2>&1; then
  RUNTIME=docker
else
  echo "$0: need podman or docker in PATH" >&2
  exit 1
fi

if ! $RUNTIME inspect "$CONTAINER" >/dev/null 2>&1; then
  echo "$0: container not found: $CONTAINER" >&2
  echo "  Tip: run \`$RUNTIME ps\` — quickstart uses container_name \`postgres\` for \`db\`." >&2
  echo "  Or set SYNKRONUS_DB_CONTAINER." >&2
  exit 1
fi

if [ -z "$OUT" ]; then
  OUT="$(pwd)/synkronus-db-backup-$(date +%Y%m%d-%H%M%S).sql"
fi

# If -o pointed at a directory, write a file inside it
if [ -d "$OUT" ]; then
  OUT="$(CDPATH= cd -- "$OUT" && pwd)/synkronus-db-backup-$(date +%Y%m%d-%H%M%S).sql"
fi

OUT_DIR=$(dirname "$OUT")
mkdir -p "$OUT_DIR"

echo "=== Synkronus database backup (pg_dump) ==="
echo "Runtime: $RUNTIME"
echo "Container: $CONTAINER"
echo "Output file: $OUT"
echo ""

# Shell inside container expands POSTGRES_* from the container environment.
# --no-owner --no-acl ease restore under different role names.
if ! $RUNTIME exec "$CONTAINER" sh -c 'pg_dump --no-owner --no-acl -U "$POSTGRES_USER" "$POSTGRES_DB"' >"$OUT"; then
  echo "$0: pg_dump failed" >&2
  rm -f "$OUT"
  exit 1
fi

bytes=$(wc -c <"$OUT" | tr -d ' ')
echo "Wrote $bytes bytes to $OUT"
printf "Example restore: %s exec -i %s psql -U synkronus_user synkronus < %s\n" "$RUNTIME" "$CONTAINER" "$OUT"
