# Webhook Deployment Quick Start

## For Your VPS (5 minutes)

### 1. Generate Webhook Secret
```bash
WEBHOOK_SECRET=$(openssl rand -hex 32)
echo $WEBHOOK_SECRET
# Save this value!
```

### 2. Copy Webhook Server
```bash
# Option A: From this repo
cp /home/user/duo/webhook-server.js /opt/
# Or from GitHub
cd /opt && curl -O https://raw.githubusercontent.com/BoabNick/duo/main/webhook-server.js
```

### 3. Create Systemd Service
```bash
sudo tee /etc/systemd/system/webhook-server.service > /dev/null <<EOF
[Unit]
Description=GitHub Webhook Deployment Server
After=network.target

[Service]
Type=simple
User=www-data
WorkingDirectory=/opt
ExecStart=/usr/bin/node /opt/webhook-server.js
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
Environment="GITHUB_WEBHOOK_SECRET=$WEBHOOK_SECRET"
Environment="NODE_ENV=production"

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable webhook-server
sudo systemctl start webhook-server
```

### 4. Copy Deploy Script to DUO
```bash
sudo cp /path/to/duo/deploy.sh /opt/duopay/
sudo chmod +x /opt/duopay/deploy.sh
```

### 5. Create Systemd Service for DUO (if not already done)
```bash
sudo tee /etc/systemd/system/duopay.service > /dev/null <<EOF
[Unit]
Description=DUOPAY POS Application
After=network.target

[Service]
Type=simple
User=www-data
WorkingDirectory=/opt/duopay
ExecStart=/usr/bin/node /opt/duopay/server.js
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
Environment="NODE_ENV=production"
Environment="PORT=3000"
Environment="DB_PATH=/opt/duopay/data/duopay.db"

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable duopay
sudo systemctl start duopay
```

### 6. Test Webhook Server
```bash
sudo systemctl status webhook-server
sudo journalctl -u webhook-server -f
```

## For Your GitHub Repo

### 1. Add Secrets
**Settings** → **Secrets and variables** → **Actions**

Add two secrets:
- `WEBHOOK_URL`: Your VPS webhook URL (e.g., `http://localhost:9000` or `https://moukas.tech/webhook`)
- `WEBHOOK_SECRET`: The secret from Step 1 above

### 2. Configure GitHub Webhook
**Settings** → **Webhooks** → **Add webhook**

- **Payload URL**: `https://moukas.tech/webhook:9000/deploy/duo`
  - Or if behind reverse proxy: `https://moukas.tech/api/webhook/deploy/duo`
- **Content type**: `application/json`
- **Secret**: Paste the webhook secret
- **Events**: `Push events`
- **Active**: ✅

**Note:** The webhook server listens on `localhost:9000` (not accessible from GitHub). You need to:
- Option A: Use a reverse proxy at the public domain
- Option B: Forward a public HTTPS endpoint to `localhost:9000`
- Option C: Use GitHub Actions workflow to trigger (already in `deploy.yml`)

### 3. Test Deployment
Push to main branch:
```bash
git push origin main
```

Check logs:
```bash
sudo journalctl -u webhook-server -f  # See webhook requests
sudo journalctl -u duopay -f           # See deployment progress
```

## That's It!

Now every push to `main` will:
1. GitHub Actions workflow triggers
2. Workflow sends webhook to your VPS
3. Webhook server validates signature and runs `/opt/duopay/deploy.sh`
4. Script pulls latest code, installs deps, restarts service
5. Service is live with new code

## Adding More Projects

See `WEBHOOK-DEPLOYMENT.md` for complete guide on adding more projects.

Quick template:
```bash
# For project2 on port 3001:
mkdir -p /opt/project2
# Deploy code, create deploy.sh, create systemd service
# Then webhook server automatically handles /deploy/project2
```

## Troubleshooting

**Webhook server not running:**
```bash
sudo systemctl restart webhook-server
sudo journalctl -u webhook-server -n 50
```

**Deploy script failing:**
```bash
bash /opt/duopay/deploy.sh  # Run manually to see errors
```

**GitHub can't reach webhook:**
- Check firewall: `sudo ufw status`
- Check if webhook server is listening: `sudo ss -tuln | grep 9000`
- GitHub webhook delivery logs: Repo → Settings → Webhooks → Recent Deliveries
