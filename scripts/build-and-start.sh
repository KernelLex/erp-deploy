#!/bin/bash
# Run this on the Linux server after cloning the repo.
# It builds the custom ERPNext image and starts everything.
# Usage: bash scripts/build-and-start.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="$(dirname "$SCRIPT_DIR")"
cd "$DEPLOY_DIR"

# Check .env exists
if [ ! -f .env ]; then
    echo "ERROR: .env file not found."
    echo "Run: cp .env.example .env  then edit it with your values."
    exit 1
fi

source .env

# Validate required vars
for var in SERVER_IP SITE_NAME DB_ROOT_PASSWORD ADMIN_PASSWORD; do
    if [ -z "${!var}" ]; then
        echo "ERROR: $var is not set in .env"
        exit 1
    fi
done

echo "=== Step 1: Building custom ERPNext image (this takes 5-10 min first time) ==="
docker build -t erp-custom:latest .

echo ""
echo "=== Step 2: Starting all services ==="
echo "ERPNext Desk will be at: http://${SERVER_IP}:8080"
echo "HR Frontend will be at:  http://${SERVER_IP}:3000"
echo ""

docker compose up -d

echo ""
echo "=== Waiting for site creation (takes ~3 min first time) ==="
echo "Watch progress with: docker compose logs -f create-site"
docker compose logs -f create-site

echo ""
echo "=== Done! ==="
echo ""
echo "ERPNext Desk : http://${SERVER_IP}:8080"
echo "HR Frontend  : http://${SERVER_IP}:3000"
echo "Login with   : Administrator / ${ADMIN_PASSWORD}"
