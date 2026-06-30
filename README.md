# DUOPAY — POS System (Web + Android/iOS)

A responsive Point-of-Sale application with **SPIn Dejavoo** and **PAX A-series** terminal
integrations. One frontend codebase ships two ways: as a **web app** served by a Node
backend, and as a native **Android APK / iOS app** packaged with [Capacitor](https://capacitorjs.com/).

- 🌐 **Web app** — HTML5/CSS/JS frontend served by Node/Express
- 📱 **Mobile app** — same frontend wrapped natively → installable `.apk` (and iOS)
- 🖥️ **Backend API** — Node.js/Express with an embedded SQLite database
- 💳 **Payment integrations** — SPIn (cloud) & PAX (local Ethernet)
- 🚀 **Deployment ready** — Docker, Coolify/VPS, Nginx, Let's Encrypt

---

## 📁 Project Structure

```
duo/
├── server.js                 # Express backend API + static file server
├── package.json              # Node deps + Capacitor tooling (devDependencies)
├── capacitor.config.json     # Capacitor config (appId, webDir → public/)
├── Dockerfile                # Backend container image
├── docker-compose.yml        # Local/prod container setup
├── .env.example              # Configuration template
├── public/                   # Frontend — served on web AND bundled into the app
│   ├── index.html            #   markup
│   ├── css/styles.css        #   styles
│   └── js/
│       ├── config.js         #   runtime API-base resolution (web vs native)
│       └── app.js            #   application logic
├── android/                  # Generated native Android project (Gradle)
├── .github/workflows/
│   └── android.yml           # CI: builds the debug APK on push
└── DEPLOYMENT.md             # VPS deployment guide
```

The **same `public/` directory** is the web app's document root *and* Capacitor's `webDir`,
so the web and mobile apps never drift apart.

---

## 🚀 Quick Start (Web)

### Option 1 — Node.js (development)

```bash
npm install          # installs server deps + Capacitor CLI
npm run dev          # nodemon, auto-reload  (or: npm start)
open http://localhost:3000
```

No `.env` is required — every variable has a default. Optionally `cp .env.example .env`.
The SQLite database is created automatically at `DB_PATH` (default `./duopay.db`).

### Option 2 — Docker

```bash
docker compose up -d
open http://localhost:3000
```

(A `package-lock.json` is committed, so the `npm ci` step in the image works.)

---

## 📱 Build the Android APK

The mobile app is the `public/` frontend wrapped by Capacitor. It talks to a **remote
backend** over HTTPS (set in-app via Settings → *Server URL*, default `https://moukas.tech` —
change the default in `public/js/config.js`).

### Build in CI (recommended)

Push to `main` (or run the **Build Android APK** workflow manually). GitHub Actions builds
the debug APK and uploads it as the `duopay-debug-apk` artifact — no local Android SDK needed.

### Build locally

Requires **JDK 17** and the **Android SDK** (`ANDROID_HOME` set; e.g. via Android Studio).

```bash
npm install
npx cap sync android                 # copy web assets into the native project
npm run android:build                # → android/app/build/outputs/apk/debug/app-debug.apk
# release build:
npm run android:build:release
```

Open the project in Android Studio instead with:

```bash
npm run cap:open:android
```

### iOS (optional, macOS only)

```bash
npm run cap:add:ios
npx cap open ios
```

### After editing the frontend

Re-sync so the native projects pick up your changes:

```bash
npx cap sync
```

---

## 💻 Features

- **Checkout** — product grid, cart with live totals, configurable tax rate, payment modal
- **SPIn** — cloud payments via the Foodteria SPIn connector (Dejavoo Z-series); URL,
  Register ID, API key; test-connection
- **PAX** — local Ethernet terminals (ISO 8583); IP/port configuration
- **Settings** — tax rate, terminal name, backend **Server URL** (for the mobile app)
- **Transactions** — recent payment history

---

## 🔌 Backend API

| Method | Endpoint | Description |
| ------ | -------- | ----------- |
| GET  | `/api/health` | Health check |
| GET/POST | `/api/terminals` | List / upsert terminals |
| GET | `/api/terminals/:id` | Get one terminal |
| POST | `/api/terminals/:id/test` | Test terminal connection |
| GET/POST | `/api/transactions` | List / create transactions |
| GET | `/api/transactions/:id` | Get one transaction |
| PATCH | `/api/transactions/:id` | Update transaction status |
| GET | `/api/settings` | Read all settings |
| POST | `/api/settings/:key` | Update one setting |
| POST | `/api/payments/spin` | Process a SPIn card payment |

CORS allows the configured web origins (`CORS_ORIGIN`) plus the Capacitor native origins
(`https://localhost`, `capacitor://localhost`, …) so the mobile app can reach the backend.

### Example

```bash
curl http://localhost:3000/api/health
curl -X POST http://localhost:3000/api/transactions \
  -H "Content-Type: application/json" \
  -d '{"order_id":"test-1","terminal_id":1,"amount":10.00,"method":"Cash","status":"APPROVED"}'
```

---

## 🔧 Configuration

`.env` (all optional — defaults shown):

```
PORT=3000
NODE_ENV=production
DB_PATH=./duopay.db
CORS_ORIGIN=https://moukas.tech,https://www.moukas.tech
```

**Mobile backend URL** is configured at runtime in the app (Settings → Server URL). The
compiled-in default lives in `public/js/config.js` (`DEFAULT_SERVER_URL`).

---

## 🌍 Deployment

The web app runs as a Docker container on a [Coolify](https://coolify.io/) VPS, served at
`moukas.tech`. Deployment is handled by **Coolify's own GitHub integration**: connect this
repo as the application source and enable **auto-deploy on push** (or add Coolify's deploy
webhook to the repo). Coolify then builds from the committed `Dockerfile` on every push to
`main` — no GitHub Actions deploy step is required.

See [DEPLOYMENT.md](./DEPLOYMENT.md) for a full VPS + Nginx + Let's Encrypt walkthrough.
Always serve over HTTPS in production.

---

## 🐛 Troubleshooting

- **Port in use** — `lsof -i :3000` then kill the PID, or set `PORT`.
- **SPIn connection failed** — verify connector URL/Register ID/API key and CORS.
- **PAX** — full PAX comms require the on-site desktop connector; the web/app side only
  configures and records.
- **Android build fails locally** — ensure `ANDROID_HOME` is set and JDK 17 is active, then
  re-run `npx cap sync android` before `./gradlew assembleDebug`.

---

## 📄 License

MIT.
