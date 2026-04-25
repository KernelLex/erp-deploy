# ClientERP — Deploy

Runs the full ERP stack on any Ubuntu server:
- **ERPNext v15 + HRMS + hr_client** (custom app) → `http://YOUR_IP:8080`
- **React HR Frontend** → `http://YOUR_IP:3000`

Everything runs in Docker. No manual ERPNext install needed.

---

## What's inside

| Service | What it does | Port |
|---|---|---|
| `frontend` | ERPNext desk (nginx proxy) | 8080 |
| `backend` | Frappe/ERPNext app server | internal |
| `websocket` | Real-time updates | internal |
| `scheduler` | Cron jobs | internal |
| `worker-short/long` | Background jobs | internal |
| `db` | MariaDB 10.6 | internal |
| `redis-cache/queue` | Redis | internal |
| `hr-frontend` | React app (nginx) | 3000 |

---

## Step 1 — Prepare your Ubuntu server

SSH into your server, then run:

```bash
curl -fsSL https://raw.githubusercontent.com/KernelLex/erp-deploy/main/scripts/install-docker.sh | bash

# IMPORTANT: log out and back in so docker group takes effect
exit
# SSH back in, then verify:
docker --version
docker compose version
```

---

## Step 2 — Clone this repo on the server

```bash
git clone https://github.com/KernelLex/erp-deploy.git
cd erp-deploy
```

---

## Step 3 — Configure your .env

```bash
cp .env.example .env
nano .env
```

Fill in:

```env
SERVER_IP=192.168.1.100        # your server's actual IP
SITE_NAME=erp.localhost
DB_ROOT_PASSWORD=StrongPass1!
ADMIN_PASSWORD=StrongPass2!
```

---

## Step 4 — Build and start

```bash
bash scripts/build-and-start.sh
```

This will:
1. Build the custom Docker image (ERPNext + HRMS + hr_client) — **takes 5–15 min first time**
2. Start all services
3. Create the ERPNext site automatically
4. Install all apps

Watch progress:
```bash
docker compose logs -f create-site
```

---

## Step 5 — Access the system

| URL | What |
|---|---|
| `http://YOUR_IP:8080` | ERPNext Desk — login: Administrator / your ADMIN_PASSWORD |
| `http://YOUR_IP:3000` | React HR Frontend |

---

## Updating after code changes

```bash
cd erp-deploy
bash scripts/update.sh
```

---

## Common commands

```bash
# View running services
docker compose ps

# View logs
docker compose logs -f backend
docker compose logs -f hr-frontend

# Run bench commands inside the container
docker compose exec backend bench --site erp.localhost migrate
docker compose exec backend bench --site erp.localhost clear-cache
docker compose exec backend bench --site erp.localhost console

# Stop everything
docker compose down

# Stop and wipe all data (DESTRUCTIVE)
docker compose down -v
```

---

## Troubleshooting

**`create-site` keeps waiting**
→ `docker compose logs configurator` — usually a DB connection issue. Check DB_ROOT_PASSWORD in .env.

**Port 8080 or 3000 already in use**
→ Change the port in compose.yml: `"8081:8080"`.

**Frontend shows "Network Error"**
→ SERVER_IP in .env must match your actual server IP. Rebuild: `docker compose build hr-frontend && docker compose up -d hr-frontend`.

**Site already exists on restart**
→ `create-site` is one-time. On repeat `docker compose up` it will error harmlessly. If it blocks, drop and recreate: `docker compose exec backend bench drop-site erp.localhost --force`.

---

## Architecture

```
Internet
   │
   ├─ :8080 ─▶ frontend (nginx) ─▶ backend (gunicorn :8000)
   │                              ├─▶ websocket (node :9000)
   │                              └─▶ db (mariadb) + redis
   │
   └─ :3000 ─▶ hr-frontend (nginx, React SPA)
                      │
                      └─▶ API calls to :8080/api/...
```
