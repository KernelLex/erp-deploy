#!/bin/bash
# Full ERPNext + hr_client production install on Ubuntu 22.04/24.04
# Run as root (or with sudo): sudo bash install.sh
# Usage: sudo bash install.sh

set -euo pipefail

# ── Load config ──────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/../.env"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: .env not found at $ENV_FILE"
  echo "Copy .env.example to .env and fill in values first."
  exit 1
fi

set -a; source "$ENV_FILE"; set +a

: "${SITE_NAME:?SITE_NAME not set in .env}"
: "${DB_ROOT_PASSWORD:?DB_ROOT_PASSWORD not set in .env}"
: "${ADMIN_PASSWORD:?ADMIN_PASSWORD not set in .env}"
: "${FRONTEND_DOMAIN:?FRONTEND_DOMAIN not set in .env}"
: "${HR_CLIENT_REPO:=https://github.com/KernelLex/hr-client-erp.git}"

BENCH_USER="frappe"
BENCH_DIR="/home/$BENCH_USER/frappe-bench"
FRAPPE_BRANCH="version-15"

log() { echo -e "\n\033[1;34m==> $*\033[0m"; }
die() { echo -e "\033[1;31mERROR: $*\033[0m" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "Run as root: sudo bash install.sh"

# ── 1. System packages ────────────────────────────────────────────────────────
log "Installing system packages"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y \
  git curl wget \
  python3.10 python3.10-dev python3.10-venv python3-pip \
  redis-server \
  mariadb-server mariadb-client \
  nginx \
  supervisor \
  nodejs npm \
  xvfb libfontconfig wkhtmltopdf \
  libmysqlclient-dev \
  software-properties-common \
  cron

# Node 18 (bench requires 18+)
if ! node --version 2>/dev/null | grep -q "^v18\|^v20"; then
  log "Installing Node 18 via NodeSource"
  curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
  apt-get install -y nodejs
fi

npm install -g yarn

# ── 2. MariaDB hardening ──────────────────────────────────────────────────────
log "Configuring MariaDB"
systemctl enable --now mariadb

mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '$DB_ROOT_PASSWORD';" 2>/dev/null || true
mysql -u root -p"$DB_ROOT_PASSWORD" -e "DELETE FROM mysql.user WHERE User='';" 2>/dev/null || true
mysql -u root -p"$DB_ROOT_PASSWORD" -e "DROP DATABASE IF EXISTS test;" 2>/dev/null || true
mysql -u root -p"$DB_ROOT_PASSWORD" -e "FLUSH PRIVILEGES;" 2>/dev/null || true

# Frappe-required MariaDB settings
cat > /etc/mysql/mariadb.conf.d/99-frappe.cnf <<'MYCNF'
[mysqld]
character-set-client-handshake = FALSE
character-set-server            = utf8mb4
collation-server                = utf8mb4_unicode_ci

[mysql]
default-character-set = utf8mb4
MYCNF

systemctl restart mariadb

# ── 3. Redis ──────────────────────────────────────────────────────────────────
log "Enabling Redis"
systemctl enable --now redis-server

# ── 4. Frappe user ────────────────────────────────────────────────────────────
log "Creating system user: $BENCH_USER"
id "$BENCH_USER" &>/dev/null || useradd -m -s /bin/bash "$BENCH_USER"

# Allow frappe user to manage nginx + supervisor via sudo (bench setup production needs this)
cat > /etc/sudoers.d/frappe <<SUDOERS
$BENCH_USER ALL=(ALL) NOPASSWD: /usr/bin/supervisorctl, /usr/sbin/nginx, /bin/systemctl restart nginx, /bin/systemctl reload nginx, /bin/systemctl restart supervisor, /bin/systemctl reload supervisor
SUDOERS

# ── 5. Install bench CLI ──────────────────────────────────────────────────────
log "Installing frappe-bench CLI"
pip3 install frappe-bench

# ── 6. Init bench & install apps ─────────────────────────────────────────────
log "Initialising bench at $BENCH_DIR"
sudo -u "$BENCH_USER" bash -c "
  set -euo pipefail
  cd /home/$BENCH_USER

  if [[ -d frappe-bench ]]; then
    echo 'Bench already exists, skipping init'
  else
    bench init frappe-bench \
      --frappe-branch $FRAPPE_BRANCH \
      --verbose
  fi

  cd frappe-bench

  # Get apps if not already present
  bench_app_exists() { [[ -d apps/\$1 ]]; }

  bench_app_exists erpnext  || bench get-app --branch $FRAPPE_BRANCH erpnext
  bench_app_exists hrms      || bench get-app --branch $FRAPPE_BRANCH hrms
  bench_app_exists hr_client || bench get-app $HR_CLIENT_REPO
"

# ── 7. Create site ────────────────────────────────────────────────────────────
log "Creating site: $SITE_NAME"
sudo -u "$BENCH_USER" bash -c "
  set -euo pipefail
  cd $BENCH_DIR

  if bench --site $SITE_NAME list-apps &>/dev/null; then
    echo 'Site already exists, skipping creation'
  else
    bench new-site $SITE_NAME \
      --db-root-password '$DB_ROOT_PASSWORD' \
      --admin-password '$ADMIN_PASSWORD' \
      --install-app erpnext \
      --install-app hrms \
      --install-app hr_client
  fi

  bench --site $SITE_NAME set-config developer_mode 0
  bench --site $SITE_NAME migrate
  bench build --app frappe
"

# Set as default site
echo "$SITE_NAME" > "$BENCH_DIR/sites/currentsite.txt"

# ── 8. Production setup (supervisor + nginx for ERPNext) ─────────────────────
log "Running bench setup production"
cd "$BENCH_DIR"
sudo -u "$BENCH_USER" bench setup production "$BENCH_USER" --yes

# bench setup production may restart nginx; give it a moment
sleep 2

# ── 9. React frontend ─────────────────────────────────────────────────────────
log "Building React frontend"
FRONTEND_SRC="$SCRIPT_DIR/../../hr-frontend"
FRONTEND_DIST="/var/www/hr-frontend"

if [[ ! -d "$FRONTEND_SRC" ]]; then
  die "hr-frontend directory not found at $FRONTEND_SRC. Run this script from the repo root."
fi

# Build
cd "$FRONTEND_SRC"
npm install --prefer-offline
VITE_USE_MOCK=false npm run build

# Deploy static files
mkdir -p "$FRONTEND_DIST"
rm -rf "${FRONTEND_DIST:?}"/*
cp -r dist/* "$FRONTEND_DIST/"
chown -R www-data:www-data "$FRONTEND_DIST"

# ── 10. Nginx vhost for React frontend ───────────────────────────────────────
log "Configuring nginx for frontend: $FRONTEND_DOMAIN"
cat > /etc/nginx/sites-available/hr-frontend <<NGINX
server {
    listen 80;
    server_name $FRONTEND_DOMAIN;

    root $FRONTEND_DIST;
    index index.html;

    # React SPA fallback
    location / {
        try_files \$uri \$uri/ /index.html;
    }

    # Proxy API calls to ERPNext (same server, different nginx vhost)
    location /api/ {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host $SITE_NAME;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 120;
    }

    # Static assets — long cache
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot|map)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }

    gzip on;
    gzip_types text/plain text/css application/json application/javascript application/x-javascript text/xml application/xml image/svg+xml;
    gzip_min_length 256;
}
NGINX

ln -sf /etc/nginx/sites-available/hr-frontend /etc/nginx/sites-enabled/hr-frontend

nginx -t
systemctl reload nginx

# ── Done ──────────────────────────────────────────────────────────────────────
log "Install complete!"
echo ""
echo "  ERPNext desk  → http://$SITE_NAME"
echo "  HR Frontend   → http://$FRONTEND_DOMAIN"
echo ""
echo "Credentials: admin / $ADMIN_PASSWORD"
echo ""
echo "Next steps if you have a domain + SSL:"
echo "  sudo apt install certbot python3-certbot-nginx"
echo "  sudo certbot --nginx -d $SITE_NAME -d $FRONTEND_DOMAIN"
