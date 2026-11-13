#!/usr/bin/env bash
set -euo pipefail

RUNTIME="${1:-}"
PROJECT_NAME="${2:-upgrade-path}"

if [[ "$RUNTIME" != "docker" && "$RUNTIME" != "podman" ]]; then
  echo "usage: $0 <docker|podman> [project_name]" >&2
  exit 1
fi

if [[ "$RUNTIME" == "podman" ]]; then
  export PODMAN_COMPOSE_PROVIDER=podman-compose
  VOL_SUFFIX=":Z"
  SCRIPT_MOUNT_SUFFIX=":ro,Z"
else
  VOL_SUFFIX=""
  SCRIPT_MOUNT_SUFFIX=":ro"
fi

compose_cmd() {
  "$RUNTIME" compose -p "$PROJECT_NAME" "$@"
}

cleanup() {
  compose_cmd down -v || true
}
trap cleanup EXIT

VOLUME_NAME="${PROJECT_NAME}_appdata"

echo "=== STEP 1: create compose volumes ==="
compose_cmd up db -d
compose_cmd down

echo "=== STEP 2: seed legacy layout ==="
"$RUNTIME" run --rm -v "${VOLUME_NAME}:/data${VOL_SUFFIX}" docker.io/library/alpine:3.21 sh -eu -c '
  mkdir -p /data/app-bundles/forms
  mkdir -p /data/app-bundle-versions/0001
  printf "legacy-active" > /data/app-bundles/forms/index.txt
  printf "legacy-version" > /data/app-bundle-versions/0001/bundle.zip
'

echo "=== STEP 3: dry-run migration ==="
"$RUNTIME" run --rm \
  -v "${VOLUME_NAME}:/data${VOL_SUFFIX}" \
  -v "$PWD/utilities/migrate-synkronus-data.sh:/migrate.sh${SCRIPT_MOUNT_SUFFIX}" \
  docker.io/library/alpine:3.21 \
  sh /migrate.sh --dry-run /data | tee /tmp/migrate-dry-run.log

grep -q "Migrating app-bundles/ -> app-bundle/active/" /tmp/migrate-dry-run.log
grep -q "Migrating app-bundle-versions/ -> app-bundle/versions/" /tmp/migrate-dry-run.log

echo "=== STEP 4: apply migration ==="
"$RUNTIME" run --rm \
  -v "${VOLUME_NAME}:/data${VOL_SUFFIX}" \
  -v "$PWD/utilities/migrate-synkronus-data.sh:/migrate.sh${SCRIPT_MOUNT_SUFFIX}" \
  docker.io/library/alpine:3.21 \
  sh /migrate.sh /data

echo "=== STEP 5: verify migrated files ==="
"$RUNTIME" run --rm -v "${VOLUME_NAME}:/data${VOL_SUFFIX}" docker.io/library/alpine:3.21 sh -eu -c '
  test -f /data/app-bundle/active/forms/index.txt
  test -f /data/app-bundle/versions/0001/bundle.zip
  test -d /data/attachments
  test -f /data/app-bundles/forms/index.txt
  test -f /data/app-bundle-versions/0001/bundle.zip
'

echo "=== STEP 6: idempotence rerun ==="
"$RUNTIME" run --rm \
  -v "${VOLUME_NAME}:/data${VOL_SUFFIX}" \
  -v "$PWD/utilities/migrate-synkronus-data.sh:/migrate.sh${SCRIPT_MOUNT_SUFFIX}" \
  docker.io/library/alpine:3.21 \
  sh /migrate.sh /data

echo "=== STEP 7: start stack and verify health ==="
compose_cmd up -d

healthy=0
for _ in $(seq 1 40); do
  code=$(curl -sS -o /tmp/upgrade-health-body.txt -w '%{http_code}' --max-time 10 http://localhost:8080/health || true)
  if [[ "$code" == "200" ]]; then
    echo "health_status=$code"
    cat /tmp/upgrade-health-body.txt
    healthy=1
    break
  fi
  sleep 2
done

if [[ "$healthy" -ne 1 ]]; then
  echo "service did not become healthy after migration" >&2
  compose_cmd logs
  exit 1
fi
