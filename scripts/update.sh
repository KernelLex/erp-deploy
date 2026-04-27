#!/bin/bash
# Pull latest code and redeploy on the production server (no Docker)
# Run as root: sudo bash update.sh
# Usage: sudo bash update.sh [--skip-frontend]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/../.env"
set -a; source "$ENV_FILE"; set +a

: "${SITE_NAME:?}"
BENCH_USER="frappe"
BENCH_DIR="/home/$BENCH_USER/frappe-bench"
FRONTEND_SRC="$SCRIPT_DIR/../../hr-frontend"
FRONTEND_DIST="/var/www/hr-frontend"
SKIP_FRONTEND=false

[[ "${1:-}" == "--skip-frontend" ]] && SKIP_FRONTEND=true

log() { echo -e "\n\033[1;34m==> $*\033[0m"; }
[[ $EUID -eq 0 ]] || { echo "Run as root: sudo bash update.sh"; exit 1; }

# ── 1. Pull latest hr_client ──────────────────────────────────────────────────
log "Updating hr_client app"
sudo -u "$BENCH_USER" bash -c "
  cd $BENCH_DIR
  bench update --apps hr_client --no-backup --reset
  bench --site $SITE_NAME migrate
  bench clear-cache
"

# ── 2. Restart bench workers ──────────────────────────────────────────────────
log "Restarting bench processes"
supervisorctl restart all

# ── 3. Rebuild + redeploy frontend ────────────────────────────────────────────
if [[ "$SKIP_FRONTEND" == false ]]; then
  log "Rebuilding React frontend"
  cd "$FRONTEND_SRC"
  git pull --rebase
  npm install --prefer-offline
  VITE_USE_MOCK=false npm run build

  rm -rf "${FRONTEND_DIST:?}"/*
  cp -r dist/* "$FRONTEND_DIST/"
  chown -R www-data:www-data "$FRONTEND_DIST"
  log "Frontend deployed"
fi

log "Update complete"
