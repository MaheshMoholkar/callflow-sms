# AdFlow (CallFlow) Monorepo

AdFlow is a call automation platform with four apps in one repository:

- `api/`: Go backend (`/api/v1`)
- `callflow_app/`: Flutter Android app for call detection and SMS follow-ups
- `admin/`: React + Vite admin console
- `web/`: Next.js public landing pages (`/:id`)

## Repository Structure

```text
adflow/
├── api/            # Go API, DB migrations, sqlc queries/generated code
├── admin/          # React admin UI (Vite + Tailwind v4)
├── web/            # Next.js public landing pages
├── callflow_app/   # Flutter Android app + native Android services
└── Dockerfile      # Multi-stage image: API + built admin assets
```

## Current Feature Set

- JWT auth by phone/password
- User profile update
- Template CRUD (with optional image upload via UploadThing)
- Rules configuration + compiled config fetch
- Unified app sync payload (`/sync/config`)
- Contact batch upsert for device sync
- User landing page CRUD + public landing endpoint
- Admin user listing and plan/status updates
- Android foreground service for call detection and automated SMS sending

## Prerequisites

- Go `1.24+`
- PostgreSQL `16+` (or compatible)
- Node.js `20+` (for `admin` and `web`)
- Flutter `3.16+` / Dart `3.2+` (Android toolchain required)
- [golang-migrate](https://github.com/golang-migrate/migrate)
- [sqlc](https://sqlc.dev/) (only needed when SQL definitions change)

## Backend Setup (`api/`)

### 1) Configure environment

The API loads `api/.env` automatically when present.

Minimum local example:

```env
JWT_SECRET=replace-with-a-long-random-secret
PORT=8080

DB_HOST=localhost
DB_PORT=5432
DB_USER=postgres
DB_PASSWORD=postgres
DB_NAME=callflow_db
DB_SSL_MODE=disable
```

### 2) Run migrations

```bash
cd api
migrate -path internal/sql/migrations \
  -database "postgres://postgres:postgres@localhost:5432/callflow_db?sslmode=disable" \
  up
```

### 3) Run API

```bash
cd api
go run cmd/api/main.go
```

Health check: `http://localhost:8080/api/v1/health`

### 4) Regenerate SQL code (when queries/migrations change)

```bash
cd api
sqlc generate
```

## Admin App (`admin/`)

```bash
cd admin
npm install
npm run dev
```

Default dev server: `http://localhost:5173`

Notes:

- Vite base path is `/admin/` (`admin/vite.config.js`).
- API base URL is currently hardcoded in `admin/src/api.js`.
- Login check is client-side and hardcoded in `admin/src/auth.jsx`.

Build:

```bash
cd admin
npm run build
```

To serve built admin through the Go API locally:

```bash
cd admin && npm run build
cd ../api
ADMIN_DIST_DIR=../admin/dist go run cmd/api/main.go
```

Then open `http://localhost:8080/admin`.

## Public Landing Web (`web/`)

```bash
cd web
npm install
npm run dev
```

Default dev server: `http://localhost:3000`

Environment:

- `NEXT_PUBLIC_API_BASE` (optional)
  - Default: `http://localhost:8080/api/v1`
  - Used by `web/app/[id]/page.jsx` to fetch landing data.

Routes:

- `/`: placeholder page
- `/:id`: public user landing page

## Mobile App (`callflow_app/`)

```bash
cd callflow_app
flutter pub get
flutter run
```

Optional code generation refresh:

```bash
cd callflow_app
dart run build_runner build --delete-conflicting-outputs
```

Important current behavior:

- API and landing base URLs are hardcoded in `callflow_app/lib/core/constants.dart`.
- Native Android integration is implemented (call-state service, SMS sending, SIM selection, boot receiver).
- App flow includes splash/version check, auth, permissions, dashboard, rules, templates, landing editor, settings.

## API Routes (Current)

Base prefix: `/api/v1`

Public:

- `GET /health`
- `GET /app/version`
- `POST /auth/register`
- `POST /auth/login`
- `GET /public/landing/:id`

Authenticated:

- `GET /user/profile`
- `PUT /user/profile`
- `GET /template`
- `POST /template/upload-image`
- `POST /template`
- `PUT /template/:id`
- `DELETE /template/:id`
- `GET /rules`
- `PUT /rules`
- `GET /rules/config`
- `GET /contacts`
- `POST /contacts/batch`
- `GET /sync/config`
- `GET /landing`
- `PUT /landing`
- `POST /landing/upload-image`

Admin (currently no API auth middleware):

- `GET /admin/users`
- `PUT /admin/users/:id/plan`
- `PUT /admin/users/:id/status`

## API Environment Variables (Current)

Required:

- `JWT_SECRET`

Database:

- `DB_HOST` (default `localhost`)
- `DB_PORT` (default `5432`)
- `DB_USER` (default `postgres`)
- `DB_PASSWORD` (default `postgres`)
- `DB_NAME` (default `callflow_db`)
- `DB_SSL_MODE` (default `disable`)
- `DB_CHANNEL_BINDING` (default empty)
- `DB_MAX_CONNS` (default `20`)
- `DB_MIN_CONNS` (default `5`)
- `DB_MAX_CONN_LIFETIME_SECS` (default `1800`)
- `DB_MAX_CONN_IDLE_TIME_SECS` (default `600`)
- `DB_STATEMENT_TIMEOUT_MS` (default `30000`)

Server/app metadata:

- `PORT` (default `8080`)
- `APP_VERSION`
- `APP_VERSION_CODE`
- `APP_DOWNLOAD_URL`
- `APP_RELEASE_NOTES`
- `APP_FORCE_UPDATE` (`true`/`false`)

Optional integrations:

- `UPLOADTHING_TOKEN` (required only for image upload endpoints)
- `ADMIN_DIST_DIR` (path to built admin assets; default `/app/admin/dist`)

Note: CORS is currently configured as allow-all in code.

## Docker

The root `Dockerfile` builds:

1. Admin static assets
2. Go API binary
3. A final image that serves API + `/admin` UI

Build/run:

```bash
# If missing, generate once:
# cd admin && npm install

docker build -t adflow .
docker run --env-file api/.env -p 8080:8080 adflow
```

There is no `docker-compose.yml` in the current repository.
