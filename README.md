# ClientERP — Deploy (Ubuntu, no Docker)

Deploys the full ERP stack directly on Ubuntu 22.04 / 24.04:

| What | Where |
|---|---|
| **ERPNext 15 + HRMS + hr_client** | `http://SITE_NAME` (nginx → gunicorn) |
| **React HR Frontend** | `http://FRONTEND_DOMAIN` (nginx static) |

No Docker. Bench manages processes via Supervisor.

---

## Prerequisites on the server

- Fresh Ubuntu 22.04 or 24.04 (root or sudo access)
- A domain or IP for each of `SITE_NAME` and `FRONTEND_DOMAIN`  
  (can be the same machine, different subdomains)
- Outbound internet (to pull apps from GitHub)

---

## Step 1 — Clone the deploy repo

```bash
sudo apt update && sudo apt install -y git
git clone https://github.com/KernelLex/erp-deploy.git ~/erp-deploy
cd ~/erp-deploy
```

---

## Step 2 — Configure .env

```bash
cp .env.example .env
nano .env
```

Fill in all values:

```env
SITE_NAME=erp.yourdomain.com       # ERPNext desk domain
FRONTEND_DOMAIN=app.yourdomain.com  # React app domain
DB_ROOT_PASSWORD=StrongPass1!
ADMIN_PASSWORD=StrongPass2!
HR_CLIENT_REPO=https://github.com/KernelLex/hr-client-erp.git
```

---

## Step 3 — Run the installer

```bash
sudo bash scripts/install.sh
```

This single script (~15-25 min on first run):

1. Installs system packages (mariadb, redis, nginx, supervisor, node 18, python3.10, wkhtmltopdf)
2. Creates a `frappe` system user
3. Initialises bench with frappe v15
4. Pulls erpnext, hrms, hr_client
5. Creates the ERPNext site and runs migrations
6. Runs `bench setup production` → configures Supervisor + nginx for ERPNext
7. Builds the React frontend and deploys it to `/var/www/hr-frontend`
8. Adds a separate nginx vhost for the frontend

---

## Step 4 — Access the system

| URL | What |
|---|---|
| `http://SITE_NAME` | ERPNext Desk — login: `Administrator` / your `ADMIN_PASSWORD` |
| `http://FRONTEND_DOMAIN` | React HR Frontend |

---

## Updating after code changes

Push your changes to GitHub, then on the server:

```bash
sudo bash ~/erp-deploy/scripts/update.sh
# Skip frontend rebuild:
sudo bash ~/erp-deploy/scripts/update.sh --skip-frontend
```

---

## Common bench commands

All bench commands run as the `frappe` user:

```bash
sudo -u frappe bash -c "cd ~/frappe-bench && bench --site erp.yourdomain.com migrate"
sudo -u frappe bash -c "cd ~/frappe-bench && bench --site erp.yourdomain.com clear-cache"
sudo -u frappe bash -c "cd ~/frappe-bench && bench --site erp.yourdomain.com console"

# View logs
sudo tail -f /home/frappe/frappe-bench/logs/worker.log
sudo tail -f /home/frappe/frappe-bench/logs/web.error.log

# Restart workers
sudo supervisorctl restart all
```

---

## Optional: HTTPS with Let's Encrypt

```bash
sudo apt install -y certbot python3-certbot-nginx
sudo certbot --nginx -d erp.yourdomain.com -d app.yourdomain.com
```

Certbot auto-renews via a systemd timer.

---

## Architecture

```
Internet
   │
   ├─ :80/443 ─▶ nginx [erp.yourdomain.com]
   │                  └─▶ gunicorn :8000  (frappe/ERPNext)
   │                  └─▶ node    :9000  (socketio)
   │
   └─ :80/443 ─▶ nginx [app.yourdomain.com]  (static React SPA)
                       └─▶ /api/* proxied to gunicorn :8000
```

Supervisor manages: gunicorn, socketio, redis-cache, redis-queue, bench workers, scheduler.

---

## Troubleshooting

**`bench new-site` fails with DB auth error**
→ Check `DB_ROOT_PASSWORD` in `.env`. Verify with: `mysql -u root -p`

**nginx config test fails**
→ `sudo nginx -t` — check for conflicting server_name blocks.

**Workers not starting**
→ `sudo supervisorctl status` — look for `FATAL`. Check `/home/frappe/frappe-bench/logs/`.

**Frontend API calls fail (CORS / 502)**
→ The `/api/` proxy in the frontend vhost points to `127.0.0.1:8000`. Verify gunicorn is running: `sudo supervisorctl status frappe-bench-frappe-web:`.
