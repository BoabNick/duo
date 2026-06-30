# AGENTS.md

## Project overview

DUOPAY is a POS app shipped two ways from one frontend:

- **Web app**: a Node.js/Express server (`server.js`) serves the static frontend in
  `public/` and a REST API on the same port, backed by an embedded SQLite database
  (auto-created on first run).
- **Mobile app**: the same `public/` directory is wrapped by **Capacitor** (`capacitor.config.json`,
  `webDir: public`) into a native **Android** project (`android/`) that builds an `.apk`. An
  iOS project can be added on macOS with `npx cap add ios`.

## Run the web app (dev)

- Start: `npm run dev` (nodemon) or `npm start`. Listens on port `3000` (override `PORT`).
- No `.env` is required — all env vars have defaults. Optionally `cp .env.example .env`.
- SQLite DB is created automatically at `DB_PATH` (default `./duopay.db`). The DB file and
  `node_modules/` are git-ignored.
- Health check: `curl http://localhost:3000/api/health`.

## Build the Android APK

- Requires JDK 17 + Android SDK (`ANDROID_HOME`). Locally:
  `npm install && npx cap sync android && npm run android:build`
  → `android/app/build/outputs/apk/debug/app-debug.apk`.
- CI builds it without a local SDK: `.github/workflows/android.yml` (push to `main` or run
  manually) uploads the `duopay-debug-apk` artifact.
- After editing anything in `public/`, run `npx cap sync` so the native project is updated.
  Web assets are copied into `android/app/src/main/assets/public` (git-ignored, regenerated
  by sync) — never edit them there.

## Build / lint / test

- **No build step** for the web app — the server runs JS directly; the frontend is static.
- **No linter / no tests** are configured. `npm test` is a placeholder that exits 1 — do not
  treat its failure as a regression.

## Frontend layout

- `public/index.html` — markup only.
- `public/css/styles.css` — all styles.
- `public/js/config.js` — resolves the API base at runtime: same-origin `/api` on web,
  an absolute URL on native/local-bundle (configurable in-app via Settings → Server URL).
- `public/js/app.js` — application logic. Functions are global (referenced by inline
  `onclick` handlers in the HTML); keep them on the global scope.

## Non-obvious caveats

- SPIn (Dejavoo) and PAX integrations need real external endpoints/hardware. The app is fully
  exercisable without them via the **Cash** payment method or the REST API directly.
- `sqlite3` is a native module; `npm install` compiles/downloads a prebuilt binary.
- Capacitor tooling lives in `devDependencies`, so the Docker image (`npm ci --omit=dev`)
  stays lean and the `android/` project is excluded from the image via `.dockerignore`.
