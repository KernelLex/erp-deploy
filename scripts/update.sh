#!/bin/bash
# Pull latest code and rebuild. Run this whenever hr_client or hr-frontend changes.
# Usage: bash scripts/update.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="$(dirname "$SCRIPT_DIR")"
cd "$DEPLOY_DIR"

source .env

echo "=== Pulling latest deploy config ==="
git pull

echo "=== Rebuilding custom image ==="
docker build --no-cache -t erp-custom:latest .

echo "=== Restarting services ==="
docker compose up -d --force-recreate backend scheduler worker-short worker-long websocket hr-frontend

echo "=== Running migrations ==="
docker compose exec backend bench --site ${SITE_NAME} migrate
docker compose exec backend bench --site ${SITE_NAME} clear-cache

echo "=== Update complete! ==="
