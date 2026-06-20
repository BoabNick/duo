# AGENTS.md

## Cursor Cloud specific instructions

### What this repo is
DUOPAY is a Node.js/Express + SQLite point-of-sale app. The runnable product is the web app
served by Express on port `3000` (`server.js` serves `public/index.html` plus a JSON API under
`/api/*`). The `*.swift` files are an iOS (SwiftUI) client and cannot be built/run on this Linux
VM — treat them as out of scope for local dev.

### Running / building / testing
- Run (dev, hot reload): `npm run dev` (nodemon). Production-style run: `npm start`. App is at
  `http://localhost:3000`.
- There is no build step and no lint config. The `npm test` script is a placeholder that always
  exits 1 (`echo "Error: no test specified" && exit 1`) — there are no automated tests.
- SQLite DB is created automatically on first request at `DB_PATH` (default `./duopay.db`). Env is
  optional; defaults work without a `.env`. `docker-compose.yml` sets `DB_PATH=/app/data/duopay.db`.

### Non-obvious gotchas
- No `package-lock.json` is committed, so `npm ci` (used by the `Dockerfile`) fails. Use
  `npm install` for local setup. Docker is not needed to run the app.
- Cash and PAX payments in the web UI are NOT persisted to the backend: `processPayment()` in
  `public/index.html` only marks them approved client-side and clears the cart. Only SPIn payments
  POST to the server (`/api/payments/spin`). To create/verify persisted transactions, use the API
  directly, e.g. `POST /api/transactions`. This is existing app behavior, not a bug to "fix".
- The Transactions list is ordered newest-first; pre-existing rows can look like a mismatch with a
  just-completed cart total because cash sales aren't recorded server-side (see above).
