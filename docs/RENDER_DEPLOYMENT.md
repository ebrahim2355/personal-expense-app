# Render deployment

This runbook prepares a Render PostgreSQL database and API service from the
committed `render.yaml` Blueprint. It contains no credentials and does not
authorize creating or changing live resources. Keep the repository root as the
service root so npm workspaces, the root lockfile, and `render.yaml` are all
visible to the build.

Android signing, the release APK/AAB commands, data-preserving installation, and
the SQLite migration rules are platform-independent and are documented once in
[`PRODUCTION_DEPLOYMENT.md`](PRODUCTION_DEPLOYMENT.md). Only the hosting steps
differ here.

## Read this before your first sync

Two facts change what you do, so decide both before creating anything.

- **`preDeployCommand` requires a paid instance type.** On a free instance type
  Render will not run it, so migrations will not be applied and the API will
  start against an empty or outdated schema. See
  [Free instance types](#free-instance-types) for the two supported
  alternatives.
- **`region` is immutable after a resource is created.** The Blueprint asks for
  `singapore`, the closest region to Dhaka. If you already created a service in
  another region, it keeps that region; either accept it or recreate the
  resources.

## Create the database and API service

1. Push this branch to GitHub. The Blueprint is read from the repository, not
   uploaded.
2. In the Render dashboard choose **New** > **Blueprint**, connect this
   repository, and select the branch. Render reads `render.yaml` from the root.
3. Render lists the two resources it will create: the `household-expenses-api`
   web service and the `household-expenses-postgres` database. Confirm the plans
   match what you intend to pay for before applying.
4. Render prompts for the three values marked `sync: false` in the Blueprint.
   Secret prompts happen **only during Blueprint creation** and are ignored on
   later syncs, so a value skipped here must be added manually in the service's
   **Environment** tab afterwards:

```text
JWT_ACCESS_SECRET      <independent random value, at least 32 characters>
CURSOR_SIGNING_SECRET  <independent random value, at least 32 characters>
PIN_PEPPER             <optional stable random value>
```

5. Apply. Render provisions the database, builds the service, runs the
   pre-deploy migration, then starts the API and waits on `/health/ready`.

`DATABASE_URL` is wired by the Blueprint through
`fromDatabase: {property: connectionString}`, which resolves to the database's
internal connection string. Do not paste a database URL into the environment by
hand and do not expose the database publicly; the internal string keeps traffic
off the public internet.

Every other environment variable is declared in `render.yaml` with a literal
value, so the service configuration is reviewable in Git rather than only in a
dashboard. Three of them will stop the service from starting if you change them
carelessly:

- `TRUST_PROXY_HOPS` must be greater than 0. The configuration loader throws
  `TRUST_PROXY_HOPS must be configured in production.` when it is 0, and the
  process exits before listening.
- `JWT_ACCESS_SECRET` and `CURSOR_SIGNING_SECRET` must be different values.
  Startup throws when they are equal.
- Every entry in `CORS_ALLOWED_ORIGINS` must be an exact HTTPS origin in
  production. The default is empty, which rejects browser origins while still
  allowing the native Android client, because it sends no `Origin` header.

`PORT` is injected by Render and is deliberately not declared. The API calls
`server.listen(port)` with no host, so every interface is bound and Render can
reach it.

`FIREBASE_SERVICE_ACCOUNT_BASE64` is the one exception to the reviewable-in-Git
rule. It is declared with `sync: false`, so the Blueprint reserves the key and the
value is pasted in the **Environment** tab. It holds the base64 of the Firebase
service-account JSON — base64 because the private key inside contains newlines and
a dashboard field mangles them.

It is optional, and that is deliberate. Unset, the API starts normally, logs

```text
push disabled: FIREBASE_SERVICE_ACCOUNT_BASE64 is not configured, clients rely on background polling
```

once, and every mutation still succeeds; clients fall back to their fifteen-minute
poll. Set, the same startup logs `push enabled` and each landed change wakes the
other member's phone in seconds. So it can be added, rotated, or removed without a
code or database change, and losing it degrades timing rather than function.

A malformed value does stop the service, on purpose: startup decodes and validates
the JSON, so a truncated paste fails as one clear log line instead of as
notifications that silently never arrive. The two messages are

```text
FIREBASE_SERVICE_ACCOUNT_BASE64 must be base64-encoded service account JSON.
FIREBASE_SERVICE_ACCOUNT_BASE64 must contain project_id, client_email, and private_key.
```

The private key is redacted from every other log line.

## Verify the deployment

Render assigns an `onrender.com` HTTPS URL, or use a custom domain. Verify all
three health endpoints:

```powershell
$api = 'https://<API_HOST>'
Invoke-RestMethod "$api/health/live"
Invoke-RestMethod "$api/health/ready"
Invoke-RestMethod "$api/health"
```

`/health/live` proves only that the process is running. `/health/ready` is the
configured health check and returns `503` until PostgreSQL answers `SELECT 1`.

Inspect **Logs** for the service, and filter by the `requestId` returned in a
response header. Logs intentionally omit tokens, PINs, database URLs, exception
messages, and stack traces, so a failure is diagnosed from status codes,
mutation IDs, and timings rather than payloads.

A failed pre-deploy migration fails the whole deploy. The previous release keeps
serving with no downtime, and the deploy is marked failed in **Events**. Read the
pre-deploy logs, not the build logs, for the Prisma error.

Push is verified from the same log stream. Startup logs `push enabled` or `push
disabled: …` exactly once, so that line answers whether the credential was read at
all. Once both phones have signed in on the new APK, each landed change logs

```text
household activity push sent
```

with `deviceCount`, `delivered`, and `retired` — never the token itself. A
`deviceCount` of `0` means the other member's phone has not registered yet;
`delivered` short of `deviceCount` with a non-zero `retired` means Google reported a
token as gone and the row was disabled, which the next launch of that phone
re-registers. `household activity push failed` is a warning rather than an error on
purpose: the mutations are already committed and the poll still covers it.

## Provision or rotate the two PINs

Provisioning is an explicit one-off command, never part of a deployment, because
it re-hashes PINs and revokes existing sessions every time it runs.

On a paid instance type, add four temporary environment variables in the
service's **Environment** tab — `HOUSEHOLD_SLUG`, `HOUSEHOLD_NAME`,
`SUMON_INITIAL_PIN`, and `EBRAHIM_INITIAL_PIN` — then open the service **Shell**
tab and run:

```bash
npm run members:provision --workspace @expenses/api
```

Free instance types have no shell. Run the command locally against the
database's **external** connection string instead:

```powershell
$env:DATABASE_URL = '<EXTERNAL_DATABASE_URL>'
$env:HOUSEHOLD_SLUG = '<LOWERCASE_HOUSEHOLD_SLUG>'
$env:HOUSEHOLD_NAME = '<HOUSEHOLD_DISPLAY_NAME>'
$env:SUMON_INITIAL_PIN = '<SUMON_6_TO_12_DIGIT_PIN>'
$env:EBRAHIM_INITIAL_PIN = '<EBRAHIM_6_TO_12_DIGIT_PIN>'
npm.cmd run members:provision --workspace @expenses/api
Remove-Item Env:SUMON_INITIAL_PIN
Remove-Item Env:EBRAHIM_INITIAL_PIN
Remove-Item Env:DATABASE_URL
```

Use 6-12 digit PINs. The command is transactional and idempotent for the fixed
household: it creates or updates only Sumon and Ebrahim, stores Argon2id hashes,
revokes their existing refresh sessions, and does not delete expenses, periods,
loans, changes, or mutation receipts. It refuses to create a second household.
Remove the PIN variables immediately after success, from the Render dashboard as
well if you added them there. Rotate a PIN by rerunning the same command with
both desired PIN values; both members must sign in again.

Rotate `JWT_ACCESS_SECRET` during a planned maintenance window: existing access
tokens fail immediately, while valid refresh sessions obtain a new one. Rotate
`PIN_PEPPER` only together with reprovisioning, because existing hashes require
the old pepper. Do not rotate `CURSOR_SIGNING_SECRET` — it invalidates every
device's sync cursor, and a mobile cursor-reset/bootstrap recovery feature would
have to ship first.

## Free instance types

The Blueprint is written for a paid instance type because that is the correct
production shape. On a free instance type, two things do not work.

**No pre-deploy command.** Choose one:

- *Recommended for a free tier.* Delete the `preDeployCommand` line from
  `render.yaml` and apply migrations from your machine against the database's
  external connection string before each deploy that contains a new migration:

  ```powershell
  $env:DATABASE_URL = '<EXTERNAL_DATABASE_URL>'
  npm.cmd run prisma:migrate:deploy --workspace @expenses/api
  Remove-Item Env:DATABASE_URL
  ```

  This keeps a failing migration away from the running service, and you see the
  Prisma output directly.

- *Automatic but weaker.* Delete `preDeployCommand` and chain the migration into
  the start command:

  ```yaml
  startCommand: npm run prisma:migrate:deploy --workspace @expenses/api && npm run start --workspace @expenses/api
  ```

  `prisma migrate deploy` is idempotent and takes an advisory lock, so repeated
  restarts are safe. The cost is that a failing migration now crash-loops the
  service instead of failing one deploy, and there is no previous release still
  serving.

Never work around this with `prisma db push`. It does not record migration
history and can drop data to reach the target schema.

**No shell.** Provision members from your machine as shown above.

Also expect a free web service to spin down when idle and to take several
seconds to answer the first request afterwards. The mobile client retries with
backoff and honors `Retry-After`, so a cold start delays a sync rather than
breaking it, but manual refresh will feel slow after a quiet period.

## Backup, restore, upgrade, and rollback

Render's paid PostgreSQL instance types keep automatic daily backups and support
point-in-time recovery; free instance types do not. Take a manual logical backup
before any schema or security change, using the external connection string
temporarily and a locally installed matching PostgreSQL client:

```powershell
pg_dump --format=custom --no-owner --no-acl --file expenses.backup '<EXTERNAL_DATABASE_URL>'
pg_restore --clean --if-exists --no-owner --no-acl --dbname '<RESTORE_DATABASE_URL>' expenses.backup
```

Never place either URL or `expenses.backup` in the repository. Validate restored
row counts and `/health/ready` against a temporary service before switching
production traffic.

Application rollback means redeploying a known-good deploy from the service's
**Events** tab. Database migrations must stay backward compatible with the prior
API release; when they are not, restore the pre-change backup before redeploying
the older API. Prisma has no automatic down migration in this workflow.

The `20260816053800_periods_loans_whole_taka` migration rewrites data. It creates
one open spending period per household, assigns every existing expense to it,
rounds any sub-taka `Expense.amountMinor` to the nearest whole taka with a
one-taka floor, and rewrites the stored `ExpenseChange.snapshot` and
`ProcessedMutation.result` documents to match the new strict shape. There is no
down migration, the original sub-taka values are not recoverable from the
database afterwards, and redeploying an older API cannot restore the old
amounts. Take a backup immediately before deploying it.

The `20260817090000_change_author` migration adds `ExpenseChange.actorMemberKey`,
backfills it from the `ProcessedMutation` behind each change, and then makes the
column `NOT NULL`. It is additive for readers, but the column has no default, so
an older API — which never sets it — cannot insert a change row afterwards and
would fail every mutation on the write. Redeploying the previous release is
therefore not a rollback on its own; restore the pre-migration backup first. On a
free instance type without a pre-deploy command, apply the migration from your
machine immediately before the deploy that carries the new code, so the window in
which writes fail stays short.

## Point the Android app at Render

Deploy the API, including the migration above, before installing the new APK. The
app treats a change with no recorded author as one not to announce, so the new APK
against an older API syncs normally and only misses notifications; the reverse
ordering is the one that fails silently.

The `20260818120000_device_tokens` migration is the easy one: it adds a new
`DeviceToken` table and the `DevicePlatform` enum and touches nothing existing. An
older API ignores both, so it is safe to apply ahead of the deploy and safe to
leave in place after a rollback. The table stays empty until a phone running the
new APK registers, and an empty table simply means no push is sent.

The API origin is supplied at build time and is not a secret:

```powershell
Set-Location apps/mobile
flutter pub get
flutter build apk --release `
  --dart-define=API_BASE_URL=https://<API_HOST>
```

Release builds reject a missing or non-HTTPS origin, and the production manifest
sets `android:usesCleartextTraffic="false"`. Never pass PINs, tokens, database
credentials, or signing passwords as Dart defines.

Changing the API host means rebuilding and reinstalling the app. Both phones must
point at the same host, or they will sync against different databases and appear
to lose each other's expenses.

## Migrating from Railway

`railway.toml` and `render.yaml` describe the same build, migration, start, and
readiness contract, so both can coexist; each platform ignores the other's file.
To move live data:

1. Back up the Railway database with `pg_dump` as shown above.
2. Create the Render resources and let the pre-deploy migration bring the schema
   up to date, or apply migrations manually on a free instance type.
3. Restore into the Render database with `pg_restore`, then compare row counts
   for households, members, expenses, spending periods, loan entries, changes,
   and processed mutations.
4. Carry `CURSOR_SIGNING_SECRET` and `PIN_PEPPER` across unchanged. A new cursor
   secret invalidates both phones' sync cursors, and a new pepper makes every
   existing PIN unverifiable.
5. Rebuild and reinstall the app with the new `API_BASE_URL`, then run the
   production smoke test in
   [`PRODUCTION_DEPLOYMENT.md`](PRODUCTION_DEPLOYMENT.md) end to end before
   retiring the Railway service.
