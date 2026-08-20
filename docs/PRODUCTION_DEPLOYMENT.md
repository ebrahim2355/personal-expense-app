# Production deployment

This runbook prepares Railway PostgreSQL/API and signed Android artifacts. It
does not contain credentials and does not authorize creating or changing live
resources. Keep the repository root as Railway's service root so npm workspaces,
the root lockfile, and `railway.toml` are all available.

Deploying to Render instead? The hosting steps are in
[`RENDER_DEPLOYMENT.md`](RENDER_DEPLOYMENT.md), which also covers moving live
data across. Everything below from **Android identity, icon, and production URL**
onwards is platform-independent and applies to either host; so do the migration
warning and the production smoke test.

## Railway PostgreSQL and API

1. Create a Railway project, then add a PostgreSQL database from **New** >
   **Database** > **PostgreSQL**.
2. Add a GitHub service for this repository. Do not expose PostgreSQL publicly;
   connect the API to it with a private reference variable.
3. In the API service variables, set `DATABASE_URL` to the PostgreSQL service's
   reference value `${{Postgres.DATABASE_URL}}` (replace `Postgres` if the
   database service has another name). Add the remaining runtime variables from
   `apps/api/.env.example` with these production values:

```text
NODE_ENV=production
JWT_ACCESS_SECRET=<independent random value, at least 32 characters>
CURSOR_SIGNING_SECRET=<independent random value, at least 32 characters>
JWT_ISSUER=household-expenses-api
JWT_AUDIENCE=household-expenses-mobile
ACCESS_TOKEN_TTL_SECONDS=600
REFRESH_TOKEN_TTL_DAYS=30
PIN_PEPPER=<optional stable random value>
CORS_ALLOWED_ORIGINS=
TRUST_PROXY_HOPS=1
JSON_BODY_LIMIT=64kb
RATE_LIMIT_MAX=300
AUTH_RATE_LIMIT_MAX=20
RATE_LIMIT_WINDOW_MS=60000
DATABASE_POOL_MAX=10
DATABASE_CONNECTION_TIMEOUT_MS=5000
LOG_LEVEL=info
```

`PORT` is injected by Railway. Empty `CORS_ALLOWED_ORIGINS` rejects browser
origins while allowing the native Android client, which sends no `Origin`.
Only add exact HTTPS browser origins if a browser client is explicitly added.

Railway reads these committed settings from `railway.toml`:

```text
Build:       npm ci --include=dev && npm run build --workspace @expenses/api
Pre-deploy:  npm run prisma:migrate:deploy --workspace @expenses/api
Start:       npm run start --workspace @expenses/api
Readiness:   /health/ready (10-second timeout)
Restart:     on process failure, at most 10 retries
```

The pre-deploy command applies only committed Prisma migrations. Never replace
it with `prisma migrate dev` or `prisma db push`. A failed migration stops that
deployment before the new application process starts. Inspect **Deployments** >
the deployment > **Build Logs**, **Deploy Logs**, and **Runtime Logs**. Filter
runtime logs by the response `requestId`; logs intentionally omit tokens, PINs,
database URLs, exception messages, and stack traces.

Generate a Railway HTTPS domain for the API service, then verify:

```powershell
$api = 'https://<API_DOMAIN>'
Invoke-RestMethod "$api/health/live"
Invoke-RestMethod "$api/health/ready"
Invoke-RestMethod "$api/health"
```

`/health/live` proves only that the process is running. Railway must use
`/health/ready`, which returns `503` until PostgreSQL answers `SELECT 1`.

## Provision or rotate the two PINs

Provisioning is an explicit one-off command, not part of every deployment. Add
temporary service variables `HOUSEHOLD_SLUG`, `HOUSEHOLD_NAME`,
`SUMON_INITIAL_PIN`, and `EBRAHIM_INITIAL_PIN`. With the Railway CLI installed,
log in, link the target project/environment, and open the deployed API shell:

```powershell
railway login
railway link
railway environment <PRODUCTION_ENVIRONMENT>
railway ssh --service <API_SERVICE>
npm run members:provision --workspace @expenses/api
exit
```

Use 6-12 digit PINs. The command is transactional and idempotent for the fixed
household: it creates or updates only Sumon and Ebrahim, stores Argon2id hashes,
revokes their existing refresh sessions, and does not delete expenses, changes,
or mutation receipts. It refuses to create a second household. Remove the two
PIN variables immediately after success. Rotate a PIN by rerunning the same
command with both desired PIN values; both members must sign in again.

Rotate `JWT_ACCESS_SECRET` during a planned maintenance window; existing access
tokens fail immediately, while valid refresh sessions can obtain a new one.
Rotate `PIN_PEPPER` only together with reprovisioning, because existing hashes
require the old pepper. Changing
`CURSOR_SIGNING_SECRET` invalidates device sync cursors; preserve it through
normal deployments and restoration. A planned rotation requires a mobile
cursor-reset/bootstrap recovery feature before changing it.

## Backup, restore, upgrade, and rollback

Enable Railway PostgreSQL backups and take an on-demand backup before schema or
security changes. Periodically test a restore into a separate non-production
PostgreSQL service. For a manual logical backup, use Railway's external database
connection details temporarily and a locally installed matching PostgreSQL
client:

```powershell
pg_dump --format=custom --no-owner --no-acl --file expenses.backup '<DATABASE_URL>'
pg_restore --clean --if-exists --no-owner --no-acl --dbname '<RESTORE_DATABASE_URL>' expenses.backup
```

Never place either URL or `expenses.backup` in the repository. Validate restored
row counts and `/health/ready` against a temporary API service before switching
production. Application rollback means redeploying a known-good Railway
deployment. Database migrations must remain backward compatible with the prior
API release; when they are not, restore the pre-change backup before redeploying
the old API. Prisma has no automatic down migration in this workflow.

The `20260816053800_periods_loans_whole_taka` migration rewrites data. It creates
one open spending period per household, assigns every existing expense to it,
rounds any sub-taka `Expense.amountMinor` to the nearest whole taka with a
one-taka floor, and rewrites the stored `ExpenseChange.snapshot` and
`ProcessedMutation.result` documents to match the new strict shape. There is no
down migration, and the original sub-taka values are not recoverable from the
database afterwards. Take an on-demand backup immediately before deploying it,
and note that redeploying an older API cannot restore the old amounts.

## Android identity, icon, and production URL

- App name: **Household Expenses**.
- Package/application ID: `com.sumonebrahim.houseexpenses`.
- Release version: `1.0.0+1`; increment the build number after `+` for every
  installed update and the semantic version when appropriate.
- The launcher icon is the Flutter mark, shipped as `mipmap-*/ic_launcher.png` at
  the five densities and nothing else — there is no adaptive icon, so every API
  level composes the same bitmap. `drawable/ic_stat_notification.xml` is the same
  mark traced as a flat white-on-transparent silhouette for the status bar, which
  Android tints from alpha alone. If the mark ever changes, both have to change:
  replace all five densities together, keep the resource names, and re-trace the
  silhouette rather than pointing the plugin at `@mipmap/ic_launcher`, which posts
  a solid white blob.
- Supply the public Railway HTTPS origin at build time. The URL is not a secret:

```powershell
--dart-define=API_BASE_URL=https://<API_DOMAIN>
```

Release builds reject missing/non-HTTPS origins. The production manifest also
sets `android:usesCleartextTraffic="false"`. Never put PINs, tokens, database
credentials, or signing passwords in Dart defines.

## Android upload/signing key

Create the key outside the repository and back it up in two secure locations.
Losing it prevents installing updates over the existing app:

```powershell
New-Item -ItemType Directory -Force "$HOME\.android-keystores"
keytool -genkeypair -v `
  -keystore "$HOME\.android-keystores\household-expenses-upload.jks" `
  -alias household-expenses-upload -keyalg RSA -keysize 4096 `
  -validity 10000
```

Configure either ignored `apps/mobile/android/key.properties`:

```properties
storeFile=C:/Users/<USER>/.android-keystores/household-expenses-upload.jks
storePassword=<KEYSTORE_PASSWORD>
keyAlias=household-expenses-upload
keyPassword=<KEY_PASSWORD>
```

or environment variables `ANDROID_KEYSTORE_PATH`,
`ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, and `ANDROID_KEY_PASSWORD`.
All four values are required. `key.properties`, `*.jks`, `*.keystore`, APKs, and
AABs are gitignored. Without these values the release build creates an unsigned
verification artifact instead of silently using the debug key.

Build the direct-install artifact:

```powershell
Set-Location apps/mobile
flutter pub get
flutter build apk --release `
  --dart-define=API_BASE_URL=https://<API_DOMAIN>
```

The signed APK is `build/app/outputs/flutter-apk/app-release.apk`. Verify it with
`apksigner verify --verbose --print-certs <APK_PATH>`. For Play/internal sharing:

```powershell
flutter build appbundle --release `
  --dart-define=API_BASE_URL=https://<API_DOMAIN>
```

The bundle is `build/app/outputs/bundle/release/app-release.aab`.

## Install, update, rollback, and local SQLite

Install on each phone with USB debugging or by opening the APK:

```powershell
adb install build/app/outputs/flutter-apk/app-release.apk
```

For every update, keep the same application ID and signing key, increment the
build number, and install over the existing app:

```powershell
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

Do not uninstall and do not clear app storage; either action removes the local
SQLite database and secure tokens. A Drift migration is required whenever table,
column, index, constraint, or persisted-data semantics change: increment
`schemaVersion`, implement and test the upgrade in `migration`, then ship the new
APK. Pure UI/API changes need no SQLite migration. Before risky upgrades, let
both phones finish sync. APK rollback is allowed only when the older app can read
the current SQLite schema and remains API-compatible; otherwise ship a forward
fix. Android also blocks version-code downgrade unless the app is uninstalled,
which would erase local data.

## Production smoke test

1. Confirm all three health endpoints, then inspect logs for the request IDs.
2. Sign in as Sumon on one phone and Ebrahim on the other; verify a wrong PIN has
   the same generic failure and returns no diagnostic details.
3. Add an odd-taka expense on phone A, manually sync, sync phone B, and verify
   the payer receives the one-taka remainder in settlement.
4. Edit on phone B, sync both ways, then soft-delete and verify the tombstone is
   reflected on phone A.
5. Disable networking, add an expense, restart the app, restore networking, and
   verify the durable outbox synchronizes without duplication.
6. Close the spending period on phone A, sync both, and verify both phones show
   one open period and keep the settled period's expenses in History.
7. Record a loan on phone A, sync both, and verify phone B shows the same lending
   net total while the expense settlement figure is unchanged.
8. Install the next higher-build-number APK with `adb install -r`; verify the
   existing expense history remains before and after synchronization.
