#!/bin/sh
# Migrate pre-release synkronus volume layout to app-bundle/active, app-bundle/versions, attachments.
# Only operates on the data volume root (paths that map to /app/data in the container).
# It does NOT copy attachment blobs that lived only on the container filesystem (e.g. /app/attachments
# on older installs); salvage those separately before recreating the container — see upgrade-path.md
# Usage: ./utilities/migrate-synkronus-data.sh [--dry-run] <data-root-path>
#        SYNKRONUS_DATA_ROOT=/path ./utilities/migrate-synkronus-data.sh [--dry-run]
# Run with the stack stopped. See upgrade-path.md

set -eu

DRY_RUN=false
ROOT=""

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    *)
      if [ -z "$ROOT" ]; then
        ROOT=$arg
      fi
      ;;
  esac
done

if [ -z "$ROOT" ]; then
  ROOT=${SYNKRONUS_DATA_ROOT:-}
fi

if [ -z "$ROOT" ]; then
  echo "Usage: $0 [--dry-run] <data-root-path>" >&2
  echo "  data-root: root of the Synkronus data volume (contents of /app/data in the container)" >&2
  echo "  Or set SYNKRONUS_DATA_ROOT." >&2
  exit 1
fi

if [ ! -d "$ROOT" ]; then
  echo "ERROR: not a directory: $ROOT" >&2
  exit 1
fi

ROOT=$(CDPATH= cd -- "$ROOT" && pwd)

do_mkdir() {
  if $DRY_RUN; then
    echo "[dry-run] mkdir -p $*"
  else
    mkdir -p "$@"
  fi
}

do_cp_a() {
  if $DRY_RUN; then
    echo "[dry-run] cp -a" "$@"
  else
    cp -a "$@"
  fi
}

echo "=== Synkronus data migration ==="
echo "Data root: $ROOT"
$DRY_RUN && echo "(dry run — no changes written)"
echo ""

do_mkdir "$ROOT/app-bundle/active" "$ROOT/app-bundle/versions" "$ROOT/attachments"

# Legacy: app-bundles/ -> app-bundle/active/
if [ -d "$ROOT/app-bundles" ] && [ -n "$(ls -A "$ROOT/app-bundles" 2>/dev/null || true)" ]; then
  if [ -z "$(ls -A "$ROOT/app-bundle/active" 2>/dev/null || true)" ]; then
    echo "Migrating app-bundles/ -> app-bundle/active/ ..."
    do_cp_a "$ROOT/app-bundles/." "$ROOT/app-bundle/active/"
  else
    echo "app-bundle/active/ is not empty; skipping app-bundles migration (empty active first if you need to re-run)."
  fi
else
  echo "No legacy app-bundles/ to migrate (or empty)."
fi

# Legacy: app-bundle-versions/ -> app-bundle/versions/
if [ -d "$ROOT/app-bundle-versions" ] && [ -n "$(ls -A "$ROOT/app-bundle-versions" 2>/dev/null || true)" ]; then
  if [ -z "$(ls -A "$ROOT/app-bundle/versions" 2>/dev/null || true)" ]; then
    echo "Migrating app-bundle-versions/ -> app-bundle/versions/ ..."
    do_cp_a "$ROOT/app-bundle-versions/." "$ROOT/app-bundle/versions/"
  else
    echo "app-bundle/versions/ is not empty; skipping app-bundle-versions migration."
  fi
else
  echo "No legacy app-bundle-versions/ to migrate (or empty)."
fi

echo ""
echo "Done. If the service starts correctly, you may rename old folders, e.g.:"
echo "  mv \"$ROOT/app-bundles\" \"$ROOT/app-bundles.bak.\$(date +%Y%m%d)\""
echo "  mv \"$ROOT/app-bundle-versions\" \"$ROOT/app-bundle-versions.bak.\$(date +%Y%m%d)\""
echo "Then: podman compose up -d   # or docker compose up -d"
