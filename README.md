# Household Expenses

Private, offline-first Android expense sharing for Sumon and Ebrahim. This
monorepo contains a production-oriented v1 Express/PostgreSQL backend and a
Flutter Android client with its complete v1 screens, offline-first persistence,
secure-session HTTP, and synchronization layers.

Money is BDT only and is represented as integer poisha. The API never accepts a
floating-point or decimal money value.

## Repository layout

```text
apps/api                    Express 5, TypeScript, Prisma/PostgreSQL backend
apps/mobile                 Flutter Android local-first app
packages/contracts          authoritative OpenAPI 3.1 contract
docs                        product, architecture, and delivery guidance
```

## Prerequisites

- Node.js `24.x` and npm `11.x`
- PostgreSQL (Railway PostgreSQL in production)
- Flutter `3.47.x` with Dart `3.13.x` for the Android shell
- Git
- Optional: Docker Desktop for an isolated local PostgreSQL test database

The repository was verified with Node `24.15.0`, npm `11.12.1`, Flutter
`3.47.0`, Dart `3.13.0`, and PostgreSQL `18.4`. PostgreSQL—not SQLite—is
required for API integration tests.

## Install

Windows PowerShell:

```powershell
git clone https://github.com/ebrahim2355/personal-expense-app.git
Set-Location personal-expense-app
npm.cmd install

Set-Location apps/mobile
flutter pub get
Set-Location ../..
```

POSIX shell:

```bash
git clone https://github.com/ebrahim2355/personal-expense-app.git
cd personal-expense-app
npm install
(cd apps/mobile && flutter pub get)
```

## Configure and run the API

Copy the placeholder template and replace every required value. Never commit the
resulting `.env` file.

```powershell
Copy-Item apps/api/.env.example apps/api/.env
```

```bash
cp apps/api/.env.example apps/api/.env
```

At minimum, runtime configuration requires `DATABASE_URL`, two independent
random signing secrets of at least 32 characters, and the environment settings
documented in [apps/api/.env.example](apps/api/.env.example). Production also
requires `TRUST_PROXY_HOPS` greater than zero, HTTPS CORS origins if browser
clients are ever allowed, and stable secret values across deployments.

Apply committed migrations; never use `prisma db push`:

```powershell
npm.cmd run prisma:generate --workspace @expenses/api
npm.cmd run prisma:validate --workspace @expenses/api
npm.cmd run prisma:migrate:deploy --workspace @expenses/api
```

For development-only schema authoring, use a disposable development database:

```powershell
npm.cmd run prisma:migrate:dev --workspace @expenses/api -- --name <MIGRATION_NAME>
```

Provision the fixed household and both members explicitly. Set initial PINs in
the process environment, run the command once, then remove those PIN variables.
The command writes only Argon2id hashes and never prints PINs.

```powershell
$env:SUMON_INITIAL_PIN = '<SUMON_6_TO_12_DIGIT_PIN>'
$env:EBRAHIM_INITIAL_PIN = '<EBRAHIM_6_TO_12_DIGIT_PIN>'
npm.cmd run members:provision --workspace @expenses/api
Remove-Item Env:SUMON_INITIAL_PIN
Remove-Item Env:EBRAHIM_INITIAL_PIN
```

```bash
SUMON_INITIAL_PIN='<SUMON_6_TO_12_DIGIT_PIN>' \
EBRAHIM_INITIAL_PIN='<EBRAHIM_6_TO_12_DIGIT_PIN>' \
npm run members:provision --workspace @expenses/api
```

Start the API:

```powershell
npm.cmd run dev --workspace @expenses/api
```

```bash
npm run dev --workspace @expenses/api
```

Check process liveness and database readiness separately:

```powershell
Invoke-RestMethod http://localhost:3000/health/live
Invoke-RestMethod http://localhost:3000/health/ready
Invoke-RestMethod http://localhost:3000/health
```

`/health/live` makes no database claim. `/health/ready` and `/health` return
HTTP `503` when PostgreSQL is unavailable.

## API behavior

The sole HTTP contract is
[packages/contracts/openapi.yaml](packages/contracts/openapi.yaml). Implemented
routes are:

- `POST /v1/auth/login`, `POST /v1/auth/refresh`, `POST /v1/auth/logout`, and
  `GET /v1/auth/me`.
- `POST /v1/sync/mutations` for ordered idempotent create/update/delete batches.
- `GET /v1/sync/bootstrap` for first-device snapshot pagination.
- `GET /v1/sync/changes` for cursor-ordered deltas and tombstones.
- `/health/live`, `/health/ready`, and `/health` for operations.

Expense IDs and mutation IDs are distinct client-generated UUIDs. Update/delete
use `baseVersion`; conflicts return the authoritative server expense/tombstone.
Accepted writes, change events, and processed-mutation receipts are atomic.
Dashboard and 50/50 summary calculations stay in Flutter so they remain
available offline; there is intentionally no server summary endpoint.

## PostgreSQL tests

Integration tests erase all rows in their target database. Use a dedicated test
database only. One optional Docker workflow is shown because the sync suite must
exercise actual PostgreSQL behavior:

The recommended reproducible workflow starts its own Compose project, migrates
and provisions it with generated test-only credentials, runs the real API and
ten two-client Flutter scenarios, performs guarded cleanup, and stops the stack:

```powershell
npm.cmd run test:real-stack
```

Use `npm run test:real-stack` on POSIX. See
[docs/REAL_STACK_TESTING.md](docs/REAL_STACK_TESTING.md) for the exact automated
scenario matrix, `--keep-postgres` API-test workflow, interactive local API
setup, Android networking, cleanup guard, and two-device manual checklist.

```powershell
docker run --name expenses-api-postgres-test `
  -e POSTGRES_USER=expenses_test `
  -e POSTGRES_PASSWORD=expenses_test `
  -e POSTGRES_DB=expenses_test `
  -p 127.0.0.1:55432:5432 `
  -d postgres:18.4-alpine

$env:DATABASE_URL = 'postgresql://expenses_test:expenses_test@127.0.0.1:55432/expenses_test?schema=public'
$env:TEST_DATABASE_URL = $env:DATABASE_URL
npm.cmd run prisma:migrate:deploy --workspace @expenses/api
npm.cmd test --workspace @expenses/api
```

POSIX shell:

```bash
docker run --name expenses-api-postgres-test \
  -e POSTGRES_USER=expenses_test \
  -e POSTGRES_PASSWORD=expenses_test \
  -e POSTGRES_DB=expenses_test \
  -p 127.0.0.1:55432:5432 \
  -d postgres:18.4-alpine

export DATABASE_URL='postgresql://expenses_test:expenses_test@127.0.0.1:55432/expenses_test?schema=public'
export TEST_DATABASE_URL="$DATABASE_URL"
npm run prisma:migrate:deploy --workspace @expenses/api
npm test --workspace @expenses/api
```

If `TEST_DATABASE_URL` is absent, PostgreSQL integration tests are reported as
skipped; unit and HTTP-shell tests still run.

## Validation commands

From the repository root:

```powershell
npm.cmd run openapi:lint
npm.cmd run format:check
npm.cmd run lint
npm.cmd run typecheck
npm.cmd test
npm.cmd run build
```

`npm.cmd run check` runs those contract/API checks in order. Replace `npm.cmd`
with `npm` on POSIX systems. To include integration coverage, set
`TEST_DATABASE_URL` first as shown above.

Flutter checks run from `apps/mobile`:

```powershell
flutter pub get
dart run build_runner build
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
flutter build apk --debug
```

Launch an Android device/emulator with `flutter devices`, then
`flutter run -d <ANDROID_DEVICE_ID>`. Debug builds default to
`http://10.0.2.2:3000`, the Android Emulator mapping for the development PC.
For another host or production, pass the URL explicitly:

```powershell
flutter run -d <ANDROID_DEVICE_ID> `
  --dart-define=API_BASE_URL=http://192.168.1.20:3000
flutter build apk --release `
  --dart-define=API_BASE_URL=https://your-api.example

# USB-connected physical device: forward this device's loopback to the PC API
adb -s <ANDROID_DEVICE_ID> reverse tcp:3000 tcp:3000
flutter run -d <ANDROID_DEVICE_ID> `
  --dart-define=API_BASE_URL=http://127.0.0.1:3000
```

Release configuration requires HTTPS. The URL is not a secret; tokens and PINs
must never be passed as Dart defines. If a Windows repository and pub cache are
on different drives, set `$env:PUB_CACHE = (Join-Path (Get-Location)
'.pub-cache')` from `apps/mobile`, rerun `flutter pub get`, and build. See
[apps/mobile/README.md](apps/mobile/README.md) for the reason and data-layer
behavior.

The Android application ID is `com.sumonebrahim.houseexpenses`; change
`namespace` and `applicationId` in
`apps/mobile/android/app/build.gradle.kts`, the `MainActivity.kt` package/path,
and signing configuration together before distribution.

The mobile app now includes the fixed-member PIN login, local SQLite dashboard,
date-range totals and settlement, quick add/edit, filtered expense history,
confirmed soft deletion, pending/offline/conflict feedback, and account/settings
screen. Dashboard calculations use only active Drift rows and integer poisha.
The default range is the current `Asia/Dhaka` month. The Settings screen labels
the API environment and explains that Android background sync is best effort,
not immediate. See [apps/mobile/README.md](apps/mobile/README.md) for the screen
and verification details.

## Production deployment and Android installation

The committed `railway.toml` defines the API build, production migration,
start, readiness, and restart behavior. The complete operator runbook is
[docs/PRODUCTION_DEPLOYMENT.md](docs/PRODUCTION_DEPLOYMENT.md), including:

- Railway PostgreSQL attachment, environment variables, logs, one-off member
  provisioning, key/PIN rotation, backup/restore, rollback, and smoke tests.
- Android production URL, package/version/icon ownership, upload-keystore setup,
  signed APK and app-bundle commands, direct installation, data-preserving
  upgrades, SQLite migration rules, and rollback constraints.

No external Railway resource is created by repository commands. Creating or
modifying a live Railway project remains an explicit operator action.

## Security and scope

- Do not commit database URLs, signing keys, PINs, token values, Android signing
  material, `.env` files, logs, or local databases.
- Access JWTs are short-lived. Refresh tokens are opaque, hashed at rest,
  rotated, revocable, and family-revoked on detected reuse.
- API inputs are strictly validated; ORM queries are household scoped; logs
  redact authorization, token, PIN, hash, and database URL fields.
- This release has no registration, member management, hard delete, server
  dashboard summary, public API key, iOS app, or web administration.

Further guidance:

- [Product specification](docs/PRODUCT_SPEC.md)
- [Architecture](docs/ARCHITECTURE.md)
- [Implementation plan](docs/IMPLEMENTATION_PLAN.md)
- [Local real-stack and two-client testing](docs/REAL_STACK_TESTING.md)
- [Repository rules](AGENTS.md)
