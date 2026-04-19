#!/bin/bash
set -e

if [ -z "$1" ]; then
    echo "Usage: $0 <username> [--recreate]"
    exit 1
fi

USERNAME="$1"
RECREATE=false

if [ "$2" == "--recreate" ]; then
    RECREATE=true
fi

DB_USER="synk_$USERNAME"
DB_NAME="synk_$USERNAME"
PASSWORD=$(openssl rand -base64 30 | tr -d /=+ | cut -c1-40)
SUGGESTED_ADMIN_PASSWORD=$(openssl rand -base64 30 | tr -d /=+ | cut -c1-40)

find_db_container() {
    local runtime="$1"
    local container_name

    if $runtime ps -a --format '{{.Names}}' | grep -Fxq "postgres"; then
        echo "postgres"
        return 0
    fi

    container_name=$($runtime ps -a --filter "label=com.docker.compose.service=db" --format '{{.Names}}' | head -n1)
    if [ -n "$container_name" ]; then
        echo "$container_name"
        return 0
    fi

    container_name=$($runtime ps -a --filter "label=io.podman.compose.service=db" --format '{{.Names}}' | head -n1)
    if [ -n "$container_name" ]; then
        echo "$container_name"
        return 0
    fi

    return 1
}

detect_runtime() {
    if [ -n "${SYNK_RUNTIME:-}" ]; then
        if ! command -v "$SYNK_RUNTIME" >/dev/null 2>&1; then
            echo "$0: SYNK_RUNTIME is set to '$SYNK_RUNTIME' but command was not found" >&2
            exit 1
        fi
        echo "$SYNK_RUNTIME"
        return 0
    fi

    if command -v docker >/dev/null 2>&1 && find_db_container docker >/dev/null 2>&1; then
        echo "docker"
        return 0
    fi

    if command -v podman >/dev/null 2>&1 && find_db_container podman >/dev/null 2>&1; then
        echo "podman"
        return 0
    fi

    if command -v podman >/dev/null 2>&1; then
        echo "podman"
        return 0
    fi

    if command -v docker >/dev/null 2>&1; then
        echo "docker"
        return 0
    fi

    echo "$0: need podman or docker in PATH" >&2
    exit 1
}

RUNTIME=$(detect_runtime)
DB_CONTAINER=$(find_db_container "$RUNTIME" || true)

if [ -z "$DB_CONTAINER" ]; then
    echo "$0: could not locate the running postgres container for runtime '$RUNTIME'" >&2
    echo "Start the database first with '$RUNTIME compose up db -d' and retry." >&2
    exit 1
fi

echo "Using runtime: $RUNTIME"
echo "Using database container: $DB_CONTAINER"

# Check if database exists
DB_EXISTS=$($RUNTIME exec "$DB_CONTAINER" psql -U synkronus_user -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname='$DB_NAME';")

if [ "$DB_EXISTS" == "1" ]; then
    if [ "$RECREATE" = false ]; then
        echo "User and DB already exists - use '--recreate' flag to recreate them"
        exit 0
    else
        # Drop user and database
        $RUNTIME exec "$DB_CONTAINER" psql -U synkronus_user -d postgres -c "DROP DATABASE IF EXISTS $DB_NAME;"
        $RUNTIME exec "$DB_CONTAINER" psql -U synkronus_user -d postgres -c "DROP ROLE IF EXISTS $DB_USER;"
        echo "User and DB recreated"
    fi
fi

# Create role and database
$RUNTIME exec "$DB_CONTAINER" psql -U synkronus_user -d postgres -c "CREATE ROLE $DB_USER LOGIN PASSWORD '$PASSWORD';"
$RUNTIME exec "$DB_CONTAINER" psql -U synkronus_user -d postgres -c "CREATE DATABASE $DB_NAME OWNER $DB_USER;"

echo "Database created!"
echo "Connection string:"
echo "postgres://$DB_USER:$PASSWORD@db:5432/$DB_NAME?sslmode=disable"
echo "Suggested synk_admin password: $SUGGESTED_ADMIN_PASSWORD"
