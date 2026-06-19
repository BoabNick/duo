# DUOPAY — Full-Stack POS System

A responsive, production-ready Point-of-Sale application with **SPIn Dejavoo** and **PAX A-series** terminal integrations.

- 📱 **Web App** — HTML5/CSS/JS frontend (desktop, tablet, iPad)
- 🖥️ **Backend API** — Node.js/Express with SQLite database
- 💳 **Payment Integrations** — SPIn (cloud) & PAX (local Ethernet)
- 🚀 **Deployment Ready** — Docker, Systemd, Nginx, Let's Encrypt
- 🛠️ **Swift iOS App** — Full SwiftUI implementation (separate folder)

---

## 📁 Project Structure

```
duo/
├── server.js                  # Express backend API
├── package.json               # Node dependencies
├── Dockerfile                 # Container image
├── docker-compose.yml         # Local dev setup
├── .env.example               # Configuration template
├── DEPLOYMENT.md              # Hostinger VPS guide
├── README.md                  # This file
├── public/
│   └── index.html             # Frontend (served by Express)
├── data/                      # SQLite database (created on first run)
├── duopay_web.html            # Standalone HTML version (legacy)
├── ContentView.swift          # iOS app (SwiftUI)
├── SpinConnectorClient.swift  # iOS SPIn client
├── PaxConnectorClient.swift   # iOS PAX client
└── ...                        # Other iOS/Swift files
```

---

## 🚀 Quick Start

### Option 1: Run with Docker (Recommended)

```bash
# Clone repo
git clone https://github.com/BoabNick/duo.git
cd duo

# Create data directory
mkdir -p data

# Build and run
docker-compose up -d

# Access the app
open http://localhost:3000
```

### Option 2: Run with Node.js

```bash
# Install dependencies
npm install

# Create .env from template
cp .env.example .env

# Start server
npm start

# Access the app
open http://localhost:3000
```

### Option 3: Deploy to Hostinger VPS

See [DEPLOYMENT.md](./DEPLOYMENT.md) for complete step-by-step instructions.

---

## 💻 Features

### Checkout Screen
- Product grid (café menu)
- Shopping cart with real-time totals
- Configurable tax rate
- Payment method selection (SPIn, PAX, Cash)

### SPIn Integration
- Direct API calls to Foodteria SPIn Connector
- Supports Dejavoo Z-series terminals
- Cloud-based payment processing
- Auth codes, reference numbers, transaction history
- Settings: Connector URL, Register ID, API key

### PAX Integration
- Direct Ethernet connection (local network)
- ISO 8583 protocol support
- Configuration: Terminal IP, port, timeout
- Ideal for on-site terminals without cloud connectivity
- Batch close, status check, void/refund

### Settings
- Tax rate configuration
- Terminal name customization
- Language selection
- Transaction history with filters

### Backend API
- `GET /api/health` — Health check
- `GET/POST /api/terminals` — Terminal management
- `GET/POST /api/transactions` — Transaction history
- `GET/POST /api/settings` — Configuration
- `POST /api/payments/spin` — SPIn payment processing

---

## 🔧 Configuration

### Create .env file

```bash
cp .env.example .env
```

**Key settings:**
```
PORT=3000
NODE_ENV=production
DB_PATH=./duopay.db
CORS_ORIGIN=https://yourdomain.com
```

### Configure Terminals in Web UI

1. Open http://localhost:3000 (or your domain)
2. Navigate to **SPIn** or **PAX** section
3. Enter connector details:
   - **SPIn**: URL, Register ID, API key
   - **PAX**: IP address, port (default 10001)
4. Click "Test Connection"
5. Toggle to enable payment method

---

## 📊 Database

SQLite database (`duopay.db`) with tables:

- **terminals** — Configured payment terminals (SPIn, PAX, etc.)
- **transactions** — Payment history with status, amounts, auth codes
- **settings** — Merchant settings (tax rate, language, etc.)

### Backup Database

```bash
cp duopay.db duopay-backup-$(date +%Y%m%d).db
```

---

## 🐳 Docker Commands

```bash
# Build image
docker build -t duopay:latest .

# Run container
docker run -d -p 3000:3000 --name duopay duopay:latest

# View logs
docker logs -f duopay

# Stop container
docker stop duopay

# Remove container
docker rm duopay

# Using Docker Compose
docker-compose up -d      # Start
docker-compose down       # Stop
docker-compose logs -f    # View logs
```

---

## 🔐 Security Considerations

- **HTTPS only** — Always use SSL/TLS in production (Let's Encrypt)
- **API authentication** — Add operator login before production
- **CORS configuration** — Update to match your domain
- **Database backups** — Automate daily backups
- **Firewall rules** — Restrict access to admin endpoints
- **Environment variables** — Never commit `.env` to git

---

## 🌍 Deployment

### Hostinger VPS (Recommended)

Full guide in [DEPLOYMENT.md](./DEPLOYMENT.md):

1. SSH into VPS
2. Install Node.js, Docker, Nginx
3. Clone repository
4. Configure `.env`
5. Deploy with Docker Compose or Systemd
6. Set up Nginx reverse proxy
7. Install SSL certificate (Let's Encrypt)
8. Configure firewall rules

**Example:**
```bash
ssh root@your-vps-ip
cd /opt
git clone https://github.com/BoabNick/duo.git duopay
cd duopay
docker-compose up -d
```

### Other Hosting Platforms
- **Heroku** — `Procfile` + `package.json` (add Procfile if needed)
- **Railway.app** — Git push to deploy
- **Render.com** — Auto-deploy from GitHub
- **DigitalOcean App Platform** — Docker image deployment

---

## 📱 iOS App

The project includes a full **SwiftUI implementation** for iPad:

- **SpinConnectorClient.swift** — Foundation-only networking client
- **SpinPOSConnector.swift** — Observable connector class
- **PaxConnectorClient.swift** — PAX terminal client
- **PaxPOSConnector.swift** — PAX connector wrapper
- **ContentView.swift** — Main POS interface
- **Settings Views** — Terminal configuration UIs

To use in your Xcode project:
1. Copy Swift files to your project
2. Add to target build phases
3. Adjust POSConnector protocol if needed
4. Wire into your SwiftUI view hierarchy

---

## 🛠️ Development

### Run in Dev Mode

```bash
npm install --save-dev nodemon
npm run dev
```

Watches for file changes and auto-restarts server.

### API Testing

```bash
# Health check
curl http://localhost:3000/api/health

# Get terminals
curl http://localhost:3000/api/terminals

# Create transaction
curl -X POST http://localhost:3000/api/transactions \
  -H "Content-Type: application/json" \
  -d '{"order_id":"test-1","terminal_id":1,"amount":10.00,"method":"Cash","status":"APPROVED"}'

# Get transactions
curl http://localhost:3000/api/transactions
```

---

## 🐛 Troubleshooting

### Port 3000 already in use
```bash
lsof -i :3000
kill -9 <PID>
```

### Database locked
```bash
ps aux | grep node
# Kill and restart the process
npm start
```

### SPIn connection failed
- Verify connector URL is accessible
- Check Register ID is correct
- Confirm API key (if required)
- Check firewall/CORS settings

### PAX connection failed
- Verify terminal IP is correct
- Ensure terminal is on same network
- Check port (default 10001)
- Confirm ISO 8583 protocol enabled on terminal

---

## 📝 API Documentation

### Terminals

**GET /api/terminals**
```json
[{
  "id": 1,
  "name": "Dejavoo Z8",
  "type": "spin",
  "enabled": true,
  "config": {
    "url": "https://connector.example.com",
    "register": "DEMO-REG-01",
    "apiKey": "secret-key"
  }
}]
```

**POST /api/terminals**
```json
{
  "name": "Dejavoo Z8",
  "type": "spin",
  "enabled": true,
  "config": { "url": "...", "register": "...", "apiKey": "..." }
}
```

### Transactions

**GET /api/transactions?limit=100&offset=0**
```json
[{
  "id": 1,
  "order_id": "web-1234567890",
  "terminal_id": 1,
  "amount": 10.00,
  "tip": 2.00,
  "total": 12.00,
  "method": "Card (SPIn)",
  "status": "APPROVED",
  "auth_code": "00A1B2",
  "reference_number": "REF123",
  "created_at": "2024-01-15T10:30:00Z"
}]
```

**POST /api/transactions**
```json
{
  "order_id": "web-1234567890",
  "terminal_id": 1,
  "amount": 10.00,
  "tip": 2.00,
  "method": "Card (SPIn)",
  "status": "APPROVED"
}
```

### Settings

**GET /api/settings**
```json
{
  "tax_rate": "5",
  "currency": "CAD",
  "terminal_name": "DUOPAY-001",
  "language": "en"
}
```

**POST /api/settings/:key**
```json
{ "value": "10" }
```

---

## 📄 License

MIT — Feel free to use in your projects.

---

## 🤝 Contributing

Pull requests welcome! Please test thoroughly before submitting.

---

## 📞 Support

For issues:
1. Check [DEPLOYMENT.md](./DEPLOYMENT.md) troubleshooting section
2. Review API logs: `docker logs duopay` or `journalctl -u duopay -f`
3. Open GitHub issue with error details

---

## 🎯 Roadmap

- [ ] Authentication & user roles
- [ ] Email/SMS receipts
- [ ] Inventory management
- [ ] Advanced reporting
- [ ] Multi-location support
- [ ] Stripe/Square integration
- [ ] Mobile POS app (native iOS/Android)
- [ ] Offline mode with sync

---

**Built with ❤️ for QC merchants**
