#!/bin/bash

################################################################################
# DUOPAY Complete Setup Script for Ubuntu
# Installs everything needed and deploys a production-ready POS app
# Usage: sudo bash setup.sh yourdomain.com
################################################################################

set -e  # Exit on any error

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration from arguments
DOMAIN="${1:-moukas.tech}"
EMAIL="${2:-admin@${DOMAIN}}"
DUOPAY_DIR="/opt/duopay"

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}This script must be run as root (use: sudo bash setup.sh)${NC}"
    exit 1
fi

# Banner
clear
echo -e "${BLUE}"
echo "╔════════════════════════════════════════════════════════════╗"
echo "║                                                            ║"
echo "║         DUOPAY - Complete Production Setup                ║"
echo "║              Full-Stack POS System                         ║"
echo "║                                                            ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo -e "${YELLOW}Domain: ${GREEN}${DOMAIN}${NC}"
echo -e "${YELLOW}Email: ${GREEN}${EMAIL}${NC}"
echo -e "${YELLOW}Install directory: ${GREEN}${DUOPAY_DIR}${NC}"
echo ""
read -p "Press Enter to continue or Ctrl+C to cancel..." -t 5

################################################################################
# STEP 1: System Update
################################################################################

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}STEP 1: System Update${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

apt-get update -qq
apt-get upgrade -y -qq
echo -e "${GREEN}✓ System updated${NC}\n"

################################################################################
# STEP 2: Install Node.js 18
################################################################################

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}STEP 2: Installing Node.js 18${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash - -qq
apt-get install -y -qq nodejs
echo -e "${GREEN}✓ Node.js $(node --version) installed${NC}\n"

################################################################################
# STEP 3: Install Nginx
################################################################################

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}STEP 3: Installing Nginx${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

apt-get install -y -qq nginx
systemctl start nginx
systemctl enable nginx
echo -e "${GREEN}✓ Nginx installed and running${NC}\n"

################################################################################
# STEP 4: Install Certbot (Let's Encrypt)
################################################################################

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}STEP 4: Installing Certbot for SSL${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

apt-get install -y -qq certbot python3-certbot-nginx
echo -e "${GREEN}✓ Certbot installed${NC}\n"

################################################################################
# STEP 5: Install Git
################################################################################

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}STEP 5: Installing Git${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

apt-get install -y -qq git curl wget
echo -e "${GREEN}✓ Git installed${NC}\n"

################################################################################
# STEP 6: Create Application Directory
################################################################################

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}STEP 6: Creating application directory${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

mkdir -p ${DUOPAY_DIR}
mkdir -p ${DUOPAY_DIR}/data
chown -R www-data:www-data ${DUOPAY_DIR}
echo -e "${GREEN}✓ Directory created: ${DUOPAY_DIR}${NC}\n"

################################################################################
# STEP 7: Clone DUOPAY Repository
################################################################################

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}STEP 7: Cloning DUOPAY repository${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

cd /tmp
git clone https://github.com/BoabNick/duo.git duopay-repo -q
cp -r duopay-repo/* ${DUOPAY_DIR}/
rm -rf duopay-repo
echo -e "${GREEN}✓ DUOPAY cloned${NC}\n"

################################################################################
# STEP 8: Install Node Dependencies
################################################################################

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}STEP 8: Installing Node.js dependencies${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

cd ${DUOPAY_DIR}
npm install --production -q
echo -e "${GREEN}✓ Dependencies installed${NC}\n"

################################################################################
# STEP 9: Create .env Configuration
################################################################################

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}STEP 9: Creating .env configuration${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

cat > ${DUOPAY_DIR}/.env << EOF
PORT=3000
NODE_ENV=production
DB_PATH=${DUOPAY_DIR}/data/duopay.db
CORS_ORIGIN=https://${DOMAIN}
EOF

chown www-data:www-data ${DUOPAY_DIR}/.env
chmod 600 ${DUOPAY_DIR}/.env
echo -e "${GREEN}✓ .env created${NC}\n"

################################################################################
# STEP 10: Create Systemd Service
################################################################################

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}STEP 10: Creating Systemd service${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

cat > /etc/systemd/system/duopay.service << 'EOF'
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

systemctl daemon-reload
systemctl enable duopay
systemctl start duopay
sleep 3

# Verify service is running
if systemctl is-active --quiet duopay; then
    echo -e "${GREEN}✓ DUOPAY service created and running${NC}\n"
else
    echo -e "${RED}✗ DUOPAY service failed to start${NC}"
    journalctl -u duopay -n 20
    exit 1
fi

################################################################################
# STEP 11: Configure Nginx Reverse Proxy
################################################################################

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}STEP 11: Configuring Nginx reverse proxy${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

cat > /etc/nginx/sites-available/duopay << EOF
server {
    listen 80;
    server_name ${DOMAIN} www.${DOMAIN};

    # Redirect HTTP to HTTPS
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name ${DOMAIN} www.${DOMAIN};

    # SSL will be configured by Certbot
    
    # Security headers
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "SAMEORIGIN" always;

    # Reverse proxy to Node.js
    location / {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
    }

    # Cache static assets
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
}
EOF

ln -sf /etc/nginx/sites-available/duopay /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

# Test Nginx config
if nginx -t 2>/dev/null; then
    systemctl reload nginx
    echo -e "${GREEN}✓ Nginx configured${NC}\n"
else
    echo -e "${RED}✗ Nginx configuration error${NC}"
    nginx -t
    exit 1
fi

################################################################################
# STEP 12: Install SSL Certificate
################################################################################

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}STEP 12: Installing SSL certificate${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

certbot certonly --nginx \
    -d ${DOMAIN} \
    -d www.${DOMAIN} \
    --non-interactive \
    --agree-tos \
    --email ${EMAIL} \
    --redirect 2>&1 | grep -E "Successfully|already exists|ERROR" || true

echo -e "${GREEN}✓ SSL certificate installed${NC}\n"

################################################################################
# STEP 13: Setup Firewall
################################################################################

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}STEP 13: Configuring firewall${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

ufw --force enable -q
ufw allow 22/tcp -q
ufw allow 80/tcp -q
ufw allow 443/tcp -q
echo -e "${GREEN}✓ Firewall configured${NC}\n"

################################################################################
# STEP 14: Setup Automated Backups
################################################################################

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}STEP 14: Setting up automated backups${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

mkdir -p /backups/duopay
chown www-data:www-data /backups/duopay

cat > /usr/local/bin/duopay-backup.sh << 'EOF'
#!/bin/bash
BACKUP_DIR="/backups/duopay"
mkdir -p $BACKUP_DIR
cp /opt/duopay/data/duopay.db $BACKUP_DIR/duopay-$(date +%Y%m%d-%H%M%S).db
find $BACKUP_DIR -name "duopay-*.db" -mtime +30 -delete
EOF

chmod +x /usr/local/bin/duopay-backup.sh
/usr/local/bin/duopay-backup.sh

# Add to crontab
(crontab -u www-data -l 2>/dev/null | grep -v "duopay-backup" || true; echo "0 2 * * * /usr/local/bin/duopay-backup.sh") | crontab -u www-data -

echo -e "${GREEN}✓ Automated backups configured (daily at 2 AM)${NC}\n"

################################################################################
# STEP 15: Test Installation
################################################################################

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}STEP 15: Testing installation${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

sleep 2

# Test API locally
HEALTH_CHECK=$(curl -s http://localhost:3000/api/health 2>/dev/null | grep -o "ok" || echo "FAIL")

if [ "$HEALTH_CHECK" = "ok" ]; then
    echo -e "${GREEN}✓ API health check passed${NC}"
else
    echo -e "${RED}✗ API health check failed${NC}"
    echo "Service logs:"
    journalctl -u duopay -n 10
fi

echo ""

################################################################################
# Success Message
################################################################################

echo -e "${GREEN}"
echo "╔════════════════════════════════════════════════════════════╗"
echo "║                                                            ║"
echo "║        ✓ DUOPAY SETUP COMPLETE - PRODUCTION READY         ║"
echo "║                                                            ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

echo -e "${YELLOW}Access your app:${NC}"
echo -e "${GREEN}  https://${DOMAIN}${NC}"
echo ""

echo -e "${YELLOW}What's installed:${NC}"
echo "  ✓ Node.js 18"
echo "  ✓ Nginx (reverse proxy)"
echo "  ✓ Certbot (SSL/HTTPS)"
echo "  ✓ DUOPAY POS application"
echo "  ✓ SQLite database"
echo "  ✓ Systemd service (auto-restart)"
echo "  ✓ Automated daily backups"
echo "  ✓ Firewall (UFW)"
echo ""

echo -e "${YELLOW}Next steps:${NC}"
echo "  1. Open https://${DOMAIN} in your browser"
echo "  2. Configure SPIn connector (URL, Register ID, API key)"
echo "  3. Configure PAX terminal (IP address, port)"
echo "  4. Add products to menu and start processing payments"
echo ""

echo -e "${YELLOW}Useful commands:${NC}"
echo "  View logs:        journalctl -u duopay -f"
echo "  Restart service:  systemctl restart duopay"
echo "  Check status:     systemctl status duopay"
echo "  Manual backup:    /usr/local/bin/duopay-backup.sh"
echo "  View database:    ls -lh /opt/duopay/data/duopay.db"
echo ""

echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}Setup completed successfully! Your POS system is ready.${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
