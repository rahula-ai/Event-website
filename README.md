# Dharmasthala Sacred Events

A modern, responsive event website for temple and cultural events.  
One codebase. Two deployment targets. Zero manual edits between them.

---

## How the two deployments work

```
GitHub repo (main branch)
        │
        ├─── push to main ──────────────────────────────────────────────┐
        │                                                               │
        ▼                                                               ▼
deploy-pages.yml                                            deploy-vps.yml
        │                                                               │
        │  Takes: root index.html + 404.html                           │  Takes: backend/ frontend/ nginx/ scripts/
        │  Ignores: backend/ nginx/ scripts/ docker-compose            │  Does: test → build images → push GHCR
        │                                                               │        → SSH to server → rolling deploy
        ▼                                                               ▼
GitHub Pages                                                   Your VPS (Docker)
https://you.github.io/repo/                            https://dharmasthala.org.in

  Full visual site                                        Full stack
  Forms → demo banner                                     Forms → MongoDB + email
  Free, no server                                         ~$6–20/month
```

The same `index.html` serves both targets. It detects `github.io` in the
hostname at runtime and switches between demo mode and production mode
automatically. No manual edits required.

---

## Repository structure

Every file is annotated with which deployment uses it and what it does.

```
dharmasthala-events/
│
│  ┌─────────────────────────────────────────────────────────────────┐
│  │ SHARED BY BOTH DEPLOYMENTS                                      │
│  └─────────────────────────────────────────────────────────────────┘
│
├── index.html                  Single source of truth for the frontend.
│                               • GitHub Pages serves this directly from
│                                 the repo root.
│                               • The VPS workflow copies it to frontend/
│                                 before building the Docker image.
│                               DO NOT maintain a separate frontend/index.html
│                               — it will drift. Edit only this file.
│
├── 404.html                    GitHub Pages 404 fallback (redirects to index).
│                               Harmlessly ignored by Docker / the VPS.
│
├── .gitignore                  Prevents secrets, certs, and build artifacts
│                               from ever being committed.
│
├── .env.example                Template for the .env file needed on the VPS.
│                               Safe to commit — contains no real values.
│                               Copy to .env on the server and fill in values.
│
│  ┌─────────────────────────────────────────────────────────────────┐
│  │ GITHUB ACTIONS WORKFLOWS                                        │
│  └─────────────────────────────────────────────────────────────────┘
│
├── .github/
│   └── workflows/
│       ├── deploy-pages.yml    Triggered by: push to main (index.html changes)
│       │                       Does: uploads index.html + 404.html to GitHub Pages
│       │                       Needs: Pages enabled in repo Settings
│       │                       Secrets needed: none
│       │
│       └── deploy-vps.yml      Triggered by: push to main (any non-docs change)
│                               Does: test → build Docker images → push to GHCR
│                                     → SSH to server → rolling deploy → health check
│                               Secrets needed: see "GitHub Secrets" section below
│
│  ┌─────────────────────────────────────────────────────────────────┐
│  │ VPS / DOCKER ONLY (ignored by GitHub Pages)                     │
│  └─────────────────────────────────────────────────────────────────┘
│
├── backend/
│   ├── main.py                 FastAPI application. All API endpoints:
│   │                           /api/contact, /api/newsletter, /api/register
│   │                           Admin exports, optional auth module.
│   ├── requirements.txt        Python dependencies.
│   ├── Dockerfile              Multi-stage build. Non-root runtime user.
│   │                           4 Uvicorn workers for production.
│   └── .dockerignore           Excludes .env, __pycache__, tests from image.
│
├── frontend/
│   ├── index.html              ← NOT committed. Injected by CI from root.
│   │                           (The deploy-vps.yml workflow runs
│   │                            `cp index.html frontend/index.html`
│   │                            before `docker build`.)
│   ├── Dockerfile              Alpine Nginx serves the static HTML.
│   │                           Aggressive caching for assets, no-cache for HTML.
│   └── nginx-local.conf        Nginx config inside the frontend container only.
│                               Serves index.html for all routes (SPA fallback).
│
├── nginx/
│   ├── nginx.conf              Host-level Nginx config. TLS settings,
│   │                           gzip, rate limit zones, worker tuning.
│   │                           Mounted into the nginx container on the VPS.
│   └── conf.d/
│       ├── dharmasthala.conf   The main site vhost. Handles:
│       │                       • HTTP → HTTPS redirect
│       │                       • TLS certificate paths
│       │                       • All security headers (HSTS, CSP, etc.)
│       │                       • Rate limiting per endpoint
│       │                       • Proxy to backend (/api/*) and frontend (/)
│       │                       Edit YOUR_DOMAIN before first deploy.
│       └── dev.conf            HTTP-only config for local development.
│                               Used by docker-compose.dev.yml.
│
├── docker-compose.yml          Production service definitions:
│                               nginx, frontend, backend, mongo, certbot.
│                               Internal Docker network — only nginx is public.
│
├── docker-compose.dev.yml      Development overrides: hot-reload, exposed ports,
│                               no TLS, mongo accessible on localhost:27017.
│
├── Makefile                    Convenience commands. Run `make help` to list all.
│
├── scripts/
│   ├── setup-server.sh         Run ONCE on a fresh Ubuntu VPS as root.
│   │                           Installs Docker, UFW, Fail2ban, cron jobs.
│   │                           Generates DH parameters for TLS.
│   │
│   ├── init-ssl.sh             Run ONCE after setup-server.sh.
│   │                           Obtains Let's Encrypt TLS certificate via Certbot.
│   │
│   ├── deploy.sh               Called by deploy-vps.yml on every push to main.
│   │                           Can also be run manually for hotfixes.
│   │                           Pulls new images → rolling restart → health check.
│   │                           Rolls back to previous image if health check fails.
│   │
│   ├── backup.sh               Daily MongoDB backup via cron. Compresses to
│   │                           .archive.gz. Optional S3/B2 sync. 30-day retention.
│   │
│   ├── renew-ssl.sh            Certbot renewal. Run by cron twice daily.
│   │                           Reloads Nginx if certs were updated.
│   │
│   └── mongo-init.js           Runs automatically when MongoDB container first
│                               starts. Creates app user, collections, indexes,
│                               and JSON schema validation.
│
└── monitoring/                 Optional observability stack (Prometheus + Grafana).
    ├── docker-compose.monitoring.yml   Add-on compose file.
    ├── prometheus.yml          Scrape targets: backend, nginx, node, cadvisor.
    ├── alerts.yml              Alert rules: backend down, high errors, disk, SSL.
    └── alertmanager.yml        Email notifications for alerts.
```

---

## GitHub Secrets reference

Go to: **Your repo → Settings → Secrets and variables → Actions → New repository secret**

### Required for GitHub Pages

| Secret | Value |
|--------|-------|
| *(none)* | GitHub Pages needs no secrets — enable it in Settings only |

### Required for VPS deployment

| Secret | How to get it |
|--------|--------------|
| `DEPLOY_HOST` | Your server IP address or hostname |
| `DEPLOY_USER` | SSH username — use `dharmasthala` (created by setup-server.sh) |
| `DEPLOY_SSH_KEY` | Private key — see key generation below |
| `DEPLOY_PORT` | SSH port — omit this secret entirely if using standard port 22 |
| `DOMAIN` | Your domain without `https://` — e.g. `dharmasthala.org.in` |
| `GHCR_READ_TOKEN` | GitHub PAT with `read:packages` — see token creation below |

### Generate a deploy SSH key

```bash
# On your local machine — generates a dedicated key for CI/CD
ssh-keygen -t ed25519 -C "github-actions-deploy" -f ~/.ssh/dharmasthala_deploy -N ""

# Private key → paste into GitHub Secret named DEPLOY_SSH_KEY
cat ~/.ssh/dharmasthala_deploy

# Public key → add to the server's authorized_keys
ssh dharmasthala@YOUR_SERVER_IP \
  "echo '$(cat ~/.ssh/dharmasthala_deploy.pub)' >> ~/.ssh/authorized_keys"
```

### Create the GHCR_READ_TOKEN

1. Go to: **GitHub → Settings → Developer settings → Personal access tokens → Fine-grained tokens**
2. Click **Generate new token**
3. Set expiry to 1 year (calendar-reminder to rotate it)
4. Repository access: **All repositories** (or select your repo)
5. Permissions: **Packages → Read**
6. Generate and copy the token
7. Add as GitHub Secret named `GHCR_READ_TOKEN`

**Why not use `GITHUB_TOKEN`?**
`GITHUB_TOKEN` is a short-lived token that only works on the GitHub Actions
runner. When the workflow SSHs into your server and runs `docker login`, it
is no longer on the runner — `GITHUB_TOKEN` is not available there and the
login fails silently. `GHCR_READ_TOKEN` is a persistent PAT that travels
with the SSH session.

---

## First deployment checklist

### GitHub Pages (one time)

- [ ] Repo is on GitHub
- [ ] Go to **Settings → Pages → Source** → set to **GitHub Actions**
- [ ] Push to `main` — the `deploy-pages.yml` workflow runs automatically
- [ ] Live at `https://YOUR_USERNAME.github.io/YOUR_REPO/`

### VPS (one time, in order)

- [ ] Point DNS A record to your server IP
- [ ] Run `setup-server.sh` on a fresh Ubuntu 22.04/24.04 VPS
- [ ] Clone repo to `/opt/dharmasthala`
- [ ] `cp .env.example .env` and fill in all `← REQUIRED` fields
- [ ] `sed -i 's/YOUR_DOMAIN/dharmasthala.org.in/g' nginx/conf.d/dharmasthala.conf`
- [ ] `bash scripts/init-ssl.sh` — obtain TLS certificate
- [ ] `docker compose up -d` — start the full stack
- [ ] Add all GitHub Secrets listed above
- [ ] Push to `main` — the `deploy-vps.yml` workflow deploys automatically

### After any push to main (automatic)

- `deploy-pages.yml` updates the GitHub Pages demo site
- `deploy-vps.yml` tests, builds new Docker images, and deploys to the VPS

---

## Local development

```bash
# Copy and configure environment
cp .env.example .env
# Edit .env — use dev credentials (e.g. MONGO_ROOT_PASS=devpassword)

# Start dev stack (hot-reload, no TLS, ports exposed)
make dev
# or: docker compose -f docker-compose.yml -f docker-compose.dev.yml up

# Access points
# Frontend:  http://localhost:3000
# Backend:   http://localhost:8000
# API docs:  http://localhost:8000/docs
# MongoDB:   localhost:27017 (connect with Compass)
# Via Nginx: http://localhost:8080
```

---

## Enabling backup modules

### Newsletter integration

```ini
# .env — set ONE service, leave others blank
MAILCHIMP_API_KEY=your-key
MAILCHIMP_LIST_ID=your-list-id
```

```bash
docker compose up -d --no-deps backend   # restart backend to pick up new env
```

### User authentication

```ini
# .env
AUTH_ENABLED=true
```

```bash
docker compose up -d --no-deps backend
```

Adds: `POST /api/auth/register`, `POST /api/auth/login`,
`POST /api/auth/logout`, `GET /api/auth/me`

### Event registration

Already live on both frontend and backend. On GitHub Pages the modal shows
demo messaging. On VPS it posts to `/api/register`, saves to MongoDB, and
emails the attendee a confirmation.

---

## Common commands

```bash
make help           # full command list
make prod           # start production stack
make dev            # start dev stack with hot-reload
make logs           # stream all logs
make health         # curl /health endpoint
make backup         # manual database backup
make deploy         # pull latest images + rolling restart
make ssl-renew      # force certificate renewal
make mongo-shell    # open MongoDB shell
make admin-ui       # start Mongo Express (access via SSH tunnel)
make monitoring-up  # start Prometheus + Grafana
make clean          # prune stopped containers
```
