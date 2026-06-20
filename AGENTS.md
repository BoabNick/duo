# AGENTS.md

## Cursor Cloud specific instructions

DUOPAY is a single runnable service: a Node.js/Express server (`server.js`) that
serves the static frontend in `public/` and a REST API on the same port, backed by
an embedded SQLite database (auto-created on first run). The repo also contains
loose Swift/SwiftUI source files (`*.swift`) for an iOS app, but there is **no
`Package.swift`/Xcode project**, so the iOS code is not buildable in this repo.

### Run the app (dev)
- Start: `npm run dev` (nodemon, auto-reload) or `npm start`. Listens on port `3000`
  (override with `PORT`). See `package.json` scripts.
- No `.env` is required — all env vars have defaults. Optionally `cp .env.example .env`.
- SQLite DB is created automatically at `DB_PATH` (default `./duopay.db`); no separate
  DB process is needed. The DB file and `node_modules/` are git-ignored.
- Health check: `curl http://localhost:3000/api/health`.

### Build / lint / test
- **No build step** — the server runs JS directly and the frontend is static HTML.
- **No linter** is configured.
- **No tests exist.** `npm test` is a placeholder that intentionally exits 1 — do not
  treat its failure as a regression.

### Non-obvious caveats
- The SPIn (Dejavoo) and PAX integrations require real external endpoints/hardware.
  The app is fully exercisable end-to-end without them: use the **Cash** payment
  method in the checkout UI, or the REST API directly (`/api/terminals`,
  `/api/transactions`, `/api/settings`).
- `Dockerfile` runs `npm ci --only=production` and copies a `package-lock.json`, but
  **no lockfile is committed**, so `docker build` / `docker-compose up` will fail as-is.
  For local development use Node directly (`npm install` + `npm run dev`), not Docker.
- `sqlite3` is a native module; `npm install` compiles/downloads a prebuilt binary.
