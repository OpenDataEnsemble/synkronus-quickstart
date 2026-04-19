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

# Detect container runtime
if command -v podman >/dev/null 2>&1; then
    RUNTIME=podman
elif command -v docker >/dev/null 2>&1; then
    RUNTIME=docker
else
    echo "$0: need podman or docker in PATH" >&2
    exit 1
fi

# Check if database exists
DB_EXISTS=$($RUNTIME exec postgres psql -U synkronus_user -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname='$DB_NAME';")

if [ "$DB_EXISTS" == "1" ]; then
    if [ "$RECREATE" = false ]; then
        echo "User and DB already exists - use '--recreate' flag to recreate them"
        exit 0
    else
        # Drop user and database
        $RUNTIME exec postgres psql -U synkronus_user -d postgres -c "DROP DATABASE IF EXISTS $DB_NAME;"
        $RUNTIME exec postgres psql -U synkronus_user -d postgres -c "DROP ROLE IF EXISTS $DB_USER;"
        echo "User and DB recreated"
    fi
fi

# Create role and database
$RUNTIME exec postgres psql -U synkronus_user -d postgres -c "CREATE ROLE $DB_USER LOGIN PASSWORD '$PASSWORD';"
$RUNTIME exec postgres psql -U synkronus_user -d postgres -c "CREATE DATABASE $DB_NAME OWNER $DB_USER;"

echo "Database created!"
echo "Connection string:"
echo "postgres://$DB_USER:$PASSWORD@db:5432/$DB_NAME?sslmode=disable"
echo "Suggested synk_admin password: $SUGGESTED_ADMIN_PASSWORD"
