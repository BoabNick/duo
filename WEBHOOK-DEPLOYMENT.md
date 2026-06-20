# Webhook Auto-Deployment Setup

This guide explains how to set up GitHub webhook-based auto-deployment for the DUOPAY project and add more projects to your VPS.

## Overview

- **Webhook Server**: Node.js server running on VPS port 9000 (internal only)
- **Deployment Script**: Per-project bash script that pulls code, installs deps, restarts service
- **GitHub Webhook**: Triggers deployment on push to `main` branch
- **Systemd Services**: Manage individual project services per port (3000, 3001, 3002, etc.)

## Prerequisites

- VPS with Nginx reverse proxy configured
- GitHub webhook secret (HMAC key)
- SSH deploy key for GitHub (or use personal token)
- systemd available on VPS

## Setup Steps

### Step 1: Generate GitHub Webhook Secret

```bash
WEBHOOK_SECRET=$(openssl rand -hex 32)
echo "Webhook Secret: $WEBHOOK_SECRET"
# Save this in GitHub repository secrets as WEBHOOK_SECRET
```

### Step 2: Copy Webhook Server to VPS

```bash
# On your local machine
scp /path/to/webhook-server.js user@your-vps:/opt/

# Or on VPS:
cd /opt
curl -O https://raw.githubusercontent.com/BoabNick/duo/main/webhook-server.js
# (adjust URL if needed)
```

### Step 3: Create Systemd Service for Webhook Server

Copy the template from `systemd/webhook-server.service` to your VPS:

```bash
sudo cp systemd/webhook-server.service /etc/systemd/system/webhook-server.service
```

Edit the file and replace `YOUR_WEBHOOK_SECRET_HERE` with your actual secret:

```bash
sudo nano /etc/systemd/system/webhook-server.service
# Edit: Environment="GITHUB_WEBHOOK_SECRET=your-secret-here"
```

Enable and start:

```bash
sudo systemctl daemon-reload
sudo systemctl enable webhook-server
sudo systemctl start webhook-server
sudo systemctl status webhook-server

# View logs
sudo journalctl -u webhook-server -f
```

### Step 4: Setup DUO Project Deployment

Copy the deploy script to your VPS:

```bash
# On VPS
mkdir -p /opt/duopay
cp /home/user/duo/deploy.sh /opt/duopay/
chmod +x /opt/duopay/deploy.sh
```

Or if already deployed:
```bash
# Update existing installation
cp deploy.sh /opt/duopay/
chmod +x /opt/duopay/deploy.sh
```

Copy the systemd service:

```bash
sudo cp systemd/duo.service /etc/systemd/system/duopay.service
sudo systemctl daemon-reload
sudo systemctl enable duopay
sudo systemctl start duopay
```

### Step 5: Configure GitHub Webhooks

In your GitHub repository:

1. Go to **Settings** → **Webhooks**
2. Click **Add webhook**
3. Set **Payload URL**: `https://your-vps-domain/webhook:9000/deploy/duo`
   - Note: This URL should be accessible from GitHub. Options:
     - Use a reverse proxy endpoint (e.g., `https://moukas.tech/webhook/deploy/duo`)
     - Or expose webhook server publicly (NOT recommended - use firewall rules instead)
4. Set **Content type**: `application/json`
5. Set **Secret**: Paste your webhook secret
6. Select events: `Push events` (or just `main` branch)
7. Check **Active**
8. Click **Add webhook**

### Step 6: Add GitHub Secrets (for CI/CD workflow)

In GitHub repo settings → Secrets and variables → Actions:

- `WEBHOOK_URL`: `https://your-vps-domain/webhook` (or internal address)
- `WEBHOOK_SECRET`: Your webhook secret

These are used by `.github/workflows/deploy.yml` to trigger deployments.

### Step 7: Test Deployment

**Manual test:**
```bash
# On your VPS, test webhook server
PAYLOAD='{"action":"test"}'
SECRET="your-webhook-secret"
SIGNATURE="sha256=$(echo -n "$PAYLOAD" | openssl dgst -sha256 -hmac "$SECRET" -hex | cut -d' ' -f2)"

curl -X POST http://localhost:9000/deploy/duo \
  -H "Content-Type: application/json" \
  -H "X-Hub-Signature-256: $SIGNATURE" \
  -d "$PAYLOAD"
```

**Real test:**
```bash
# Push to main branch
git push origin main

# Monitor deployment
sudo journalctl -u webhook-server -f
sudo journalctl -u duopay -f
```

## Adding More Projects

To add a new project to your VPS backend:

### 1. Create Project Directory

```bash
mkdir -p /opt/project2
cd /opt/project2
git clone <your-github-repo> .
npm install --production  # or equivalent for your tech stack
```

### 2. Create Deployment Script

Create `/opt/project2/deploy.sh` using this template:

```bash
#!/bin/bash
set -e

PROJECT_DIR="/opt/project2"
PROJECT_NAME="project2"
PORT=3001

echo "[$(date)] Starting deployment for $PROJECT_NAME..."
cd "$PROJECT_DIR" || exit 1

echo "[$(date)] Pulling latest code..."
git pull origin main || exit 1

# Install deps (adjust for your tech stack)
echo "[$(date)] Installing dependencies..."
npm install --production || exit 1  # or: pip install -r requirements.txt, go build, etc.

echo "[$(date)] Restarting service..."
systemctl restart project2 || echo "Warning: systemctl restart failed"

sleep 2

echo "[$(date)] Health check..."
HEALTH_CHECK=$(curl -s -f "http://localhost:$PORT/api/health" || echo "")
if [ $? -eq 0 ]; then
  echo "[$(date)] ✅ Deployment successful"
  exit 0
else
  echo "[$(date)] ⚠️  Deployment completed but health check failed"
  exit 0
fi
```

Make it executable:
```bash
chmod +x /opt/project2/deploy.sh
```

### 3. Create Systemd Service

Create `/etc/systemd/system/project2.service`:

```ini
[Unit]
Description=Project 2 Service
After=network.target
Wants=webhook-server.service

[Service]
Type=simple
User=www-data
WorkingDirectory=/opt/project2
ExecStart=/usr/bin/node /opt/project2/server.js  # Adjust command for your tech stack
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

Environment="NODE_ENV=production"
Environment="PORT=3001"

[Install]
WantedBy=multi-user.target
```

Enable and start:
```bash
sudo systemctl daemon-reload
sudo systemctl enable project2
sudo systemctl start project2
sudo systemctl status project2
```

### 4. Create Nginx Virtualhost

Create `/etc/nginx/sites-available/project2domain.com`:

```nginx
server {
    listen 80;
    server_name project2domain.com www.project2domain.com;
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    server_name project2domain.com www.project2domain.com;

    ssl_certificate /etc/letsencrypt/live/project2domain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/project2domain.com/privkey.pem;

    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "SAMEORIGIN" always;

    location / {
        proxy_pass http://localhost:3001;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
    }
}
```

Enable and test:
```bash
sudo ln -s /etc/nginx/sites-available/project2domain.com /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx
```

### 5. Get SSL Certificate

```bash
sudo certbot certonly --nginx -d project2domain.com -d www.project2domain.com
sudo systemctl reload nginx
```

### 6. Configure GitHub Webhook

In your project2 GitHub repo:
- Settings → Webhooks → Add webhook
- Payload URL: `https://moukas.tech/webhook/deploy/project2`
- Secret: Same webhook secret (if using shared server)
- Events: Push events
- Active: ✅

### 7. Update GitHub Secrets

In project2 repo settings → Secrets:
- `WEBHOOK_URL`: Same as DUO
- `WEBHOOK_SECRET`: Same as DUO

## Port Assignment Reference

Use unique ports for each project:

```
3000 → duopay.com (DUO)
3001 → project2domain.com
3002 → project3domain.com
3003 → project4domain.com
3004 → project5domain.com
9000 → webhook-server (internal)
```

## Security Considerations

1. **Webhook Secret**: Keep it safe, never commit to git
2. **Firewall**: Only expose ports 80, 443 publicly
   ```bash
   sudo ufw allow 22/tcp
   sudo ufw allow 80/tcp
   sudo ufw allow 443/tcp
   sudo ufw enable
   ```
3. **Webhook Port**: Port 9000 should only accept localhost or be behind firewall
4. **SSH Keys**: Use GitHub deploy keys (read-only) instead of personal tokens
5. **Database Backups**: Regular backups before deployments

## Troubleshooting

### Webhook not triggering

```bash
# Check webhook server logs
sudo journalctl -u webhook-server -f

# Check if listening
sudo ss -tuln | grep 9000
```

### Deployment fails

```bash
# Check service logs
sudo journalctl -u duopay -f

# Check deployment script manually
bash /opt/duopay/deploy.sh
```

### Port conflicts

```bash
# Find what's using a port
sudo lsof -i :3000

# Kill if needed
sudo kill -9 <PID>
```

### Nginx not routing

```bash
# Test Nginx config
sudo nginx -t

# Reload
sudo systemctl reload nginx

# Check error log
sudo tail -f /var/log/nginx/error.log
```

## Monitoring

### View all service statuses

```bash
sudo systemctl status duopay
sudo systemctl status webhook-server
sudo systemctl status project2
# etc.
```

### Unified logs

```bash
# All services
sudo journalctl -u "*.service" -f

# Just webhook
sudo journalctl -u webhook-server -f

# Just one project
sudo journalctl -u duopay -f
```

### Restart all services

```bash
sudo systemctl restart webhook-server duopay project2 project3 project4
```

## Auto-Renewal for SSL Certs

Certbot handles this automatically with systemd timer:

```bash
sudo systemctl status certbot.timer
sudo systemctl enable certbot.timer

# Manual renewal test
sudo certbot renew --dry-run
```

## Summary

With this setup, to add a new project you only need:
1. Copy deploy.sh template and customize for tech stack
2. Create systemd service file
3. Add Nginx virtualhost + SSL cert
4. Configure GitHub webhook with same secret
5. Test deployment

All deployments trigger automatically on `git push origin main` 🚀
