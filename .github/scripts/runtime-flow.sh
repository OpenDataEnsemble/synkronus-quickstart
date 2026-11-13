#!/usr/bin/env bash
set -euo pipefail

RUNTIME="${1:-}"
SCENARIO="${2:-}"

if [[ "$RUNTIME" != "docker" && "$RUNTIME" != "podman" ]]; then
  echo "usage: $0 <docker|podman> <manual|installer>" >&2
  exit 1
fi

if [[ "$SCENARIO" != "manual" && "$SCENARIO" != "installer" ]]; then
  echo "usage: $0 <docker|podman> <manual|installer>" >&2
  exit 1
fi

if [[ "$RUNTIME" == "podman" ]]; then
  export PODMAN_COMPOSE_PROVIDER=podman-compose
fi

compose_cmd() {
  "$RUNTIME" compose "$@"
}

resolve_db_container() {
  local name

  if "$RUNTIME" ps -a --format '{{.Names}}' | grep -Fxq "postgres"; then
    echo "postgres"
    return 0
  fi

  name=$("$RUNTIME" ps -a --filter "label=com.docker.compose.service=db" --format '{{.Names}}' | head -n1)
  if [[ -n "$name" ]]; then
    echo "$name"
    return 0
  fi

  name=$("$RUNTIME" ps -a --filter "label=io.podman.compose.service=db" --format '{{.Names}}' | head -n1)
  if [[ -n "$name" ]]; then
    echo "$name"
    return 0
  fi

  return 1
}

wait_for_postgres() {
  local db_container
  db_container=$(resolve_db_container || true)
  if [[ -z "$db_container" ]]; then
    echo "could not find db container after compose up" >&2
    exit 1
  fi

  for i in $(seq 1 30); do
    if "$RUNTIME" exec "$db_container" pg_isready -U synkronus_user -d postgres -q 2>/dev/null; then
      echo "postgres ready after ${i}s"
      return 0
    fi
    if [[ "$i" -eq 30 ]]; then
      echo "postgres did not become ready" >&2
      exit 1
    fi
    sleep 1
  done
}

wait_for_health() {
  local url="$1"
  local fail_msg="$2"

  local healthy=0
  for i in $(seq 1 40); do
    code=$(curl -sS -o /tmp/synk-health-body.txt -w '%{http_code}' --max-time 10 "$url" || true)
    if [[ "$code" == "200" ]]; then
      echo "health_status=$code"
      cat /tmp/synk-health-body.txt
      healthy=1
      break
    fi
    sleep 2
  done

  if [[ "$healthy" -ne 1 ]]; then
    echo "$fail_msg" >&2
    compose_cmd logs
    exit 1
  fi
}

seed_attachment_probe() {
  local seeded=0
  for i in $(seq 1 20); do
    if "$RUNTIME" exec synkronus sh -c 'mkdir -p /app/data/attachments/ci && echo ci-probe > /app/data/attachments/ci/probe.txt'; then
      seeded=1
      break
    fi
    sleep 2
  done

  if [[ "$seeded" -ne 1 ]]; then
    echo "failed to seed attachments after service became healthy" >&2
    compose_cmd logs
    exit 1
  fi
}

run_backup_assertions() {
  chmod +x ./utilities/backup-db.sh ./utilities/backup-attachments.sh

  SYNK_RUNTIME="$RUNTIME" ./utilities/backup-db.sh -o /tmp/synk-db-backup.sql
  test -s /tmp/synk-db-backup.sql

  SYNK_RUNTIME="$RUNTIME" ./utilities/backup-attachments.sh -o /tmp/synk-attachments-backup
  test -f /tmp/synk-attachments-backup/app-data-attachments/ci/probe.txt
}

cleanup() {
  compose_cmd down -v || true
}
trap cleanup EXIT

if [[ "$SCENARIO" == "manual" ]]; then
  echo "=== STEP 1: start db ==="
  compose_cmd up db -d
  "$RUNTIME" ps -a

  echo "=== STEP 2: wait for postgres ==="
  wait_for_postgres

  echo "=== STEP 3: create org database ==="
  chmod +x ./create_sync_db.sh
  SYNK_RUNTIME="$RUNTIME" ./create_sync_db.sh myorg

  echo "=== STEP 4: start full stack ==="
  compose_cmd up -d

  echo "=== STEP 5: wait for health ==="
  wait_for_health "http://localhost:8080/health" "service did not become healthy"

  echo "=== STEP 5b: seed attachment data ==="
  seed_attachment_probe

  echo "=== STEP 6: test backup scripts ==="
  run_backup_assertions
  exit 0
fi

echo "=== STEP 1: run installer (no domain, localhost) ==="
chmod +x ./install.sh
printf 'n\nlocalhost\n' | ./install.sh

test -f Caddyfile
test -f docker-compose.override.yml

echo "=== STEP 2: start stack ==="
compose_cmd up -d
compose_cmd ps

echo "=== STEP 3: wait for caddy health endpoint ==="
wait_for_health "http://localhost:8081/health" "installer flow did not become healthy via caddy"

echo "=== STEP 3b: seed attachment data ==="
seed_attachment_probe

echo "=== STEP 4: test backup scripts ==="
run_backup_assertions
