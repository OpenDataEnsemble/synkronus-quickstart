#!/bin/sh
# Copy attachment blobs out of a running Synkronus container to the host.
# Tries both current and legacy paths inside the container:
#   - /app/data/attachments  (current: next to the binary under /app/data)
#   - /app/attachments        (older installs that stored blobs only on the container FS)
#
# Requires: podman or docker on the host.
#
# Usage:
#   ./backup-attachments.sh [-c name] [-o dir]
#   SYNKRONUS_CONTAINER=my_synkronus ./backup-attachments.sh [output-dir]
#
#   -c   container name or id (default: synkronus, or SYNKRONUS_CONTAINER)
#   -o   output directory (default: ./attachments-backup-YYYYMMDD-HHMMSS in cwd)

set -eu

usage() {
  echo "Usage: $0 [-c container] [-o output-dir]" >&2
  echo "       SYNKRONUS_CONTAINER=name $0 [output-dir]" >&2
  echo "Backs up /app/data/attachments and, if non-empty, /app/attachments from a running Synkronus container." >&2
}

CONTAINER="${SYNKRONUS_CONTAINER:-synkronus}"
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
  echo "  Tip: run \`$RUNTIME ps\` and pass -c <name-or-id>, or set SYNKRONUS_CONTAINER." >&2
  exit 1
fi

if [ -z "$OUT" ]; then
  OUT="$(pwd)/attachments-backup-$(date +%Y%m%d-%H%M%S)"
fi

mkdir -p "$OUT"

backup_if_nonempty() {
  _path=$1
  _dest=$2

  if ! $RUNTIME exec "$CONTAINER" test -d "$_path" 2>/dev/null; then
    echo "Skip (no directory): $_path"
    return 0
  fi

  if ! $RUNTIME exec "$CONTAINER" sh -c "test -n \"\$(ls -A \"$_path\" 2>/dev/null)\"" 2>/dev/null; then
    echo "Skip (empty): $_path"
    return 0
  fi

  echo "Backing up $_path -> $_dest/ ..."
  mkdir -p "$_dest"
  $RUNTIME cp "$CONTAINER:$_path/." "$_dest/"
}

echo "=== Synkronus attachment backup ==="
echo "Runtime: $RUNTIME"
echo "Container: $CONTAINER"
echo "Output: $OUT"
echo ""

backup_if_nonempty "/app/data/attachments" "$OUT/app-data-attachments"
backup_if_nonempty "/app/attachments" "$OUT/legacy-app-attachments"

echo ""
echo "Done. Files are under: $OUT"
echo "If app-data-attachments has files and legacy-app-attachments is empty, attachments live on the volume (current layout)."
