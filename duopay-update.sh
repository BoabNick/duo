#!/bin/bash
# DUOPAY Auto-Update Script
# Called by the /api/deploy webhook when GitHub pushes to main

set -e
LOG="/var/log/duopay-deploy.log"
echo "=== DUOPAY Deploy $(date) ===" | tee -a $LOG

cd /opt/duopay

# Pull latest code
git fetch origin main 2>&1 | tee -a $LOG
git reset --hard origin/main 2>&1 | tee -a $LOG

# Install/update dependencies
npm install --production 2>&1 | tee -a $LOG

# Fix permissions
chown -R www-data:www-data /opt/duopay

# Restart service
systemctl restart duopay
sleep 3

# Verify
if systemctl is-active --quiet duopay; then
    echo "✓ DUOPAY deployed successfully" | tee -a $LOG
    curl -s http://localhost:3000/api/health | tee -a $LOG
    echo "" | tee -a $LOG
else
    echo "✗ Deployment failed" | tee -a $LOG
    journalctl -u duopay -n 20 | tee -a $LOG
    exit 1
fi
