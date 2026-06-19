# DUOPAY Deployment Guide — Hostinger VPS

## Prerequisites

- Hostinger VPS (or any Linux VPS: Ubuntu 20.04 LTS recommended)
- Domain name (e.g., duopay.com)
- SSH access to your VPS
- Basic terminal knowledge

---

## Step 1: Connect to Your VPS

```bash
ssh root@your-vps-ip
# or
ssh user@your-vps-ip
```

---

## Step 2: Install Dependencies

### Update system
```bash
apt update && apt upgrade -y
```

### Install Node.js (v18+)
```bash
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
apt install -y nodejs npm
node --version
```

### Install Docker & Docker Compose (recommended for easier management)
```bash
apt install -y docker.io docker-compose

# Start Docker service
systemctl start docker
systemctl enable docker

# Verify
docker --version
docker-compose --version
```

### Install Nginx (reverse proxy)
```bash
apt install -y nginx

# Start Nginx
systemctl start nginx
systemctl enable nginx
```

---

## Step 3: Clone & Setup DUOPAY

```bash
cd /opt

# Clone the repository
git clone https://github.com/BoabNick/duo.git duopay
cd duopay

# Install Node dependencies
npm install --production
```

---

## Step 4: Configure Environment

```bash
# Create .env file from template
cp .env.example .env

# Edit with your settings
nano .env
```

**Important settings:**
```
PORT=3000
NODE_ENV=production
DB_PATH=/opt/duopay/data/duopay.db
CORS_ORIGIN=https://yourdomain.com
```

---

## Step 5A: Deploy with Docker (Recommended)

### Build and run
```bash
cd /opt/duopay

# Build Docker image
docker build -t duopay:latest .

# Create data directory
mkdir -p data

# Run container
docker run -d \
  --name duopay \
  -p 3000:3000 \
  -v $(pwd)/data:/app/data \
  -e NODE_ENV=production \
  -e PORT=3000 \
  -e DB_PATH=/app/data/duopay.db \
  --restart unless-stopped \
  duopay:latest
```

### Or use Docker Compose
```bash
docker-compose up -d
```

---

## Step 5B: Deploy with Systemd (No Docker)

### Create systemd service
```bash
sudo nano /etc/systemd/system/duopay.service
```

**Paste:**
```ini
[Unit]
Description=DUOPAY POS Application
After=network.target

[Service]
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
```

### Enable and start
```bash
sudo systemctl daemon-reload
sudo systemctl enable duopay
sudo systemctl start duopay

# Check status
sudo systemctl status duopay

# View logs
sudo journalctl -u duopay -f
```

---

## Step 6: Configure Nginx (Reverse Proxy)

### Create Nginx config
```bash
sudo nano /etc/nginx/sites-available/duopay
```

**Paste (replace `yourdomain.com` with your domain):**
```nginx
server {
    listen 80;
    server_name yourdomain.com www.yourdomain.com;

    # Redirect HTTP to HTTPS
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    server_name yourdomain.com www.yourdomain.com;

    # SSL certificates (Let's Encrypt via Certbot)
    ssl_certificate /etc/letsencrypt/live/yourdomain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/yourdomain.com/privkey.pem;

    # Security headers
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "SAMEORIGIN" always;

    # Reverse proxy to Node.js backend
    location / {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
    }

    # Static files caching
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
}
```

### Enable site
```bash
sudo ln -s /etc/nginx/sites-available/duopay /etc/nginx/sites-enabled/
sudo rm /etc/nginx/sites-enabled/default

# Test config
sudo nginx -t

# Reload
sudo systemctl reload nginx
```

---

## Step 7: Install SSL Certificate (Let's Encrypt)

### Install Certbot
```bash
apt install -y certbot python3-certbot-nginx
```

### Get certificate
```bash
sudo certbot certonly --nginx -d yourdomain.com -d www.yourdomain.com

# Certbot will automatically update Nginx config
```

### Auto-renewal
```bash
sudo systemctl enable certbot.timer
sudo systemctl start certbot.timer
```

---

## Step 8: Set File Permissions

```bash
# Set proper ownership
sudo chown -R www-data:www-data /opt/duopay

# Set permissions
sudo chmod -R 755 /opt/duopay
sudo chmod -R 775 /opt/duopay/data
```

---

## Step 9: Verify Deployment

```bash
# Check if DUOPAY is running
curl http://localhost:3000/api/health

# Check Nginx is proxying correctly
curl https://yourdomain.com/api/health

# View logs
docker logs duopay          # if using Docker
# or
sudo journalctl -u duopay   # if using Systemd
```

---

## Step 10: Access the Web App

Open your browser to:
```
https://yourdomain.com
```

You should see the DUOPAY POS app with sidebar menu.

---

## Database Backup

### Backup database
```bash
# Periodic backup script
sudo nano /usr/local/bin/duopay-backup.sh
```

**Paste:**
```bash
#!/bin/bash
BACKUP_DIR="/backups/duopay"
mkdir -p $BACKUP_DIR
cp /opt/duopay/data/duopay.db $BACKUP_DIR/duopay-$(date +%Y%m%d-%H%M%S).db
# Keep only last 30 days of backups
find $BACKUP_DIR -name "duopay-*.db" -mtime +30 -delete
```

### Make executable and schedule
```bash
chmod +x /usr/local/bin/duopay-backup.sh

# Add to crontab (daily at 2 AM)
sudo crontab -e
# Add: 0 2 * * * /usr/local/bin/duopay-backup.sh
```

---

## Monitoring & Maintenance

### Check service health
```bash
sudo systemctl status duopay
curl https://yourdomain.com/api/health
```

### View logs
```bash
# Docker
docker logs -f duopay

# Systemd
sudo journalctl -u duopay -f

# Nginx errors
sudo tail -f /var/log/nginx/error.log
```

### Update DUOPAY
```bash
cd /opt/duopay
git pull origin main
npm install
sudo systemctl restart duopay
```

---

## Firewall Setup

```bash
# UFW (Uncomplicated Firewall)
ufw allow 22/tcp    # SSH
ufw allow 80/tcp    # HTTP
ufw allow 443/tcp   # HTTPS
ufw enable
```

---

## Troubleshooting

### Port 3000 already in use
```bash
lsof -i :3000
kill -9 <PID>
```

### Database locked
```bash
# Check if multiple processes are accessing the DB
ps aux | grep node

# Restart
sudo systemctl restart duopay
```

### CORS errors
Update `CORS_ORIGIN` in `.env` to match your domain:
```
CORS_ORIGIN=https://yourdomain.com
```

### Let's Encrypt renewal issues
```bash
sudo certbot renew --dry-run
sudo certbot renew
```

---

## Performance Tuning

### Enable Nginx caching
```nginx
proxy_cache_path /var/cache/nginx levels=1:2 keys_zone=duopay:10m max_size=100m;

location / {
    proxy_cache duopay;
    proxy_cache_valid 200 10m;
    ...
}
```

### Increase Node.js memory
```bash
# In .env or systemd service:
NODE_OPTIONS=--max-old-space-size=512
```

---

## Next Steps

1. **Configure SPIn connector** — add your connector URL and Register ID in the web app settings
2. **Configure PAX terminals** — add IP addresses for any local PAX A-series terminals
3. **Set up transaction backups** — automated daily backups to S3 or external storage
4. **Enable authentication** — add operator login/logout system
5. **Add email notifications** — payment confirmations and daily reports

---

## Support

For issues or questions:
- Check logs: `docker logs duopay` or `journalctl -u duopay -f`
- GitHub repo: https://github.com/BoabNick/duo
- Hostinger support: https://www.hostinger.com/support
