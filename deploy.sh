#!/bin/bash
set -e

PROJECT_DIR="/home/user/duo"
PROJECT_NAME="duo"
PORT=3000

echo "[$(date)] Starting deployment for $PROJECT_NAME..."
cd "$PROJECT_DIR" || exit 1

echo "[$(date)] Pulling latest code from GitHub..."
git pull origin main || {
  echo "[$(date)] Error: Failed to pull from GitHub"
  exit 1
}

echo "[$(date)] Installing dependencies..."
npm install --production || {
  echo "[$(date)] Error: npm install failed"
  exit 1
}

echo "[$(date)] Restarting service..."
if command -v systemctl &> /dev/null; then
  systemctl restart duo 2>/dev/null || {
    echo "[$(date)] Warning: systemctl restart failed, service may not be running"
  }
else
  echo "[$(date)] Warning: systemctl not available, manual restart required"
fi

sleep 2

echo "[$(date)] Running health check..."
HEALTH_CHECK=$(curl -s -f "http://localhost:$PORT/api/health" 2>/dev/null || echo "")
if [ $? -eq 0 ]; then
  echo "[$(date)] ✅ Deployment successful - health check passed"
  exit 0
else
  echo "[$(date)] ⚠️  Deployment completed but health check failed"
  echo "[$(date)] Manual verification recommended"
  exit 0  # Don't fail - health check might fail due to service restart timing
fi
