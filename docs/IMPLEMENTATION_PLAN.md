# Implementation plan

## 1. Delivery rules

- Keep `packages/contracts/openapi.yaml` as the only HTTP contract.
- Commit every Prisma migration and use `prisma migrate deploy` outside local
  schema development. Never use `prisma db push` on shared databases.
- Use only integer poisha for money and pure integer split/settlement functions.
  Every stored amount is a whole number of taka, so `amountMinor` is always a
  multiple of `100`; both ends reject a remainder instead of rounding it.
- Keep Flutter local-first: one Drift transaction updates the visible projection
  for expenses, spending periods, and loans, and the durable outbox.
- Keep sync serialized, cursors transactional, mutation semantics immutable once
  first sent, deletions as tombstones, and server snapshots authoritative on
  conflict.
- Keep every synchronized entity on the one mutation route, the one outbox, and
  the one change feed, discriminated by `entityType`.
- Run PostgreSQL integration tests against a disposable PostgreSQL database;
  never substitute SQLite.

## 2. Milestone status and ordered work

### Milestone 1 — product and architecture guidance (complete)

Delivered repository rules, product acceptance criteria, split examples, sync
invariants, and the monorepo architecture.

Checks:

```powershell
Get-Content -Raw AGENTS.md
Get-Content -Raw docs/PRODUCT_SPEC.md
Get-Content -Raw docs/ARCHITECTURE.md
Get-Content -Raw docs/IMPLEMENTATION_PLAN.md
```

### Milestone 2 — monorepo scaffold (complete)

Delivered npm/Express and Flutter Android shells, strict TypeScript/Flutter
analysis, root scripts, environment templates, ignore rules, and the contract
location. Android ID: `com.sumonebrahim.houseexpenses`.

Checks:

```powershell
npm.cmd install
npm.cmd run check
Set-Location apps/mobile
flutter pub get
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
flutter build apk --debug
```

### Milestone 3 — production v1 backend (complete)

Delivered:

- Prisma/PostgreSQL models and migrations for Household, Member, RefreshToken,
  Expense, ProcessedMutation, and ExpenseChange.
- Database constraints for money/version/cursor/hash bounds and same-household
  payer/member relationships.
- Explicit Argon2id member provisioning from environment PINs.
- Login, refresh rotation/reuse revocation, logout, current member, signed access
  JWTs, and opaque hashed refresh tokens.
- Process/database health, request IDs, Helmet, CORS allowlist, HTTPS enforcement,
  body limits, rate limits, Zod validation, redacted Pino logs, centralized
  errors, and bounded graceful shutdown.
- Serializable, household-scoped mutation handling with idempotency receipts,
  optimistic versions, per-item results, canonical timestamps, tombstones, and
  monotonic change events.
- HMAC-protected change cursors, paginated changes, and watermark-based bootstrap.
- OpenAPI 1.0 and real PostgreSQL integration coverage.

Verification with a dedicated PostgreSQL URL:

```powershell
$env:DATABASE_URL = '<DISPOSABLE_POSTGRESQL_URL>'
$env:TEST_DATABASE_URL = $env:DATABASE_URL
npm.cmd run prisma:generate --workspace @expenses/api
npm.cmd run prisma:validate --workspace @expenses/api
npm.cmd run prisma:migrate:deploy --workspace @expenses/api
npm.cmd run openapi:lint
npm.cmd run format:check
npm.cmd run lint
npm.cmd run typecheck
npm.cmd test
npm.cmd run build
```

Provisioning verification uses test-only PINs and must be separate from normal
test execution:

```powershell
$env:SUMON_INITIAL_PIN = '<TEST_PIN>'
$env:EBRAHIM_INITIAL_PIN = '<DIFFERENT_TEST_PIN>'
npm.cmd run members:provision --workspace @expenses/api
Remove-Item Env:SUMON_INITIAL_PIN
Remove-Item Env:EBRAHIM_INITIAL_PIN
```

Exit criterion: migrations deploy to PostgreSQL; the explicit provision command
creates exactly one household with two Argon2id-hashed members; contract, lint,
type-check, 28 tests, and production compilation pass. The test count may grow;
behavioral coverage, not a fixed count, is authoritative.

### Milestone 4 — Flutter offline-first data layer (complete)

Resolved and pinned Riverpod, Drift/SQLite, Dio, UUID, secure storage,
connectivity, WorkManager, and code-generation packages through Flutter pub.
Delivered:

- immutable expense/session models with integer-only `amountMinor`;
- Drift expense, durable outbox, and sync metadata tables with generated code;
- transactional local create/edit/soft-delete and immediate repository streams;
- secure token storage, Dio transport, single-flight refresh, and retry-once;
- serialized push/bootstrap/pull, frozen mutation semantics, idempotent lost
  response recovery, dependency rebasing, transactional cursors, tombstones,
  server-wins conflict notices, and bounded retry metadata;
- Riverpod dependency injection with repository/application boundaries;
- launch, resume, mutation, manual, live network-recovery, and best-effort
  network-constrained WorkManager triggers.

Checks:

```powershell
Set-Location apps/mobile
flutter pub get
dart run build_runner build
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
$env:PUB_CACHE = (Join-Path (Get-Location) '.pub-cache') # if drives differ
flutter pub get
flutter build apk --debug
```

Exit criterion met for the data layer: fake-API tests prove immediate local
reads, durable intent, idempotent retry, single-flight sync, cursor pagination,
tombstones, conflicts, refresh-once, and local-data retention. The debug APK
builds.

### Milestone 5 — Flutter authentication and first bootstrap (complete)

Delivered the fixed member selector/PIN screen, generic and offline error states,
persisted member identity restoration, secure-token session gate, best-effort
server refresh-token revocation on logout, and local credential clearing without
deleting expenses/outbox data. First-device bootstrap continues through the
existing coordinator immediately after an online login.

Verification includes login widget states plus existing refresh-once, auth-expiry,
paginated bootstrap, and local-data-retention tests.

### Milestone 6 — Flutter expense UI and dashboard (complete)

Delivered, as of this milestone. Milestone 9 later replaced the dashboard's month
range with the open spending period and added search:

- Material 3 dashboard with current Dhaka month, date ranges, local totals,
  per-member paid/allocated amounts, exact settlement, recent/empty states, and
  pull/manual refresh;
- deterministic BDT string parsing/formatting and pure integer split/summary;
- quick add/edit with logged-in payer default, fixed category selection, Dhaka
  date/time, note validation, keyboard-safe scrolling, and duplicate-submit guard;
- newest-first history with date/payer/category filters, edit, and confirmed
  local soft delete;
- settings/account with member, API environment, app version, manual sync,
  local-data/background-sync explanation, and logout;
- pending/offline/error state plus server-wins conflict notices.

Checks:

```powershell
Set-Location apps/mobile
flutter pub get
dart run build_runner build
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
flutter build apk --debug
```

Pure and widget coverage includes amount boundaries, exact BDT display,
even/odd settlement examples, deleted rows, Dhaka midnight/month boundaries,
login errors, dashboard/empty states, 320-pixel enlarged-text layout, offline
add, duplicate submission, edit, deletion confirmation, sync state, and conflict
feedback.

### Milestone 7 — local real-stack multi-client convergence (complete)

Delivered:

- disposable PostgreSQL 18 Compose topology with committed Prisma migrations;
- a guarded, test-database-only reset command and random, non-logged bootstrap
  credentials;
- a cross-platform runner that starts the real API, waits on database-backed
  readiness, runs the mobile test, cleans rows, and shuts down deterministically;
- two independent file-backed Drift clients using production Dio, authentication,
  repository, outbox, and sync-coordinator implementations;
- real HTTP/PostgreSQL coverage for offline cross-client creates, concurrent
  creates, lost-response idempotency, edit propagation, server-wins conflicts
  and notices, tombstones/totals, interrupted cursor pagination, refresh-once and
  revoked credentials, process-restart durability, and Dhaka/UTC boundaries;
- safe request/mutation/cursor diagnostics plus a debug-only Settings view of
  cursor preview, pending count, last result, and last successful sync;
- emulator, USB `adb reverse`, LAN, and two-device manual verification guidance.

Checks:

```powershell
npm.cmd run test:real-stack -- --keep-postgres
$env:NODE_ENV = 'test'
$env:DATABASE_URL = 'postgresql://expenses_test:expenses_test@127.0.0.1:55432/expenses_e2e_test?schema=public'
$env:TEST_DATABASE_URL = $env:DATABASE_URL
npm.cmd test
npm.cmd run stack:test:down
```

Exit criterion met locally: ten mobile real-stack scenarios and all 28 API tests
pass against PostgreSQL. Milestone 9 raised the suite to thirteen scenarios and
milestone 10 to fourteen. A
two-installation hardware smoke pass remains part of release validation, using
the deterministic checklist in
`docs/REAL_STACK_TESTING.md`. Android background timing remains explicitly
best-effort and is not used as a deterministic test completion signal.

### Milestone 9 — spending periods, lending ledger, whole taka, and search (complete)

Delivered:

- `SpendingPeriod` and `LoanEntry` Prisma models, their migration, a partial
  unique index that allows exactly one open period per household, and an
  `Expense.periodId` composite foreign key;
- whole-taka money at every layer: OpenAPI `multipleOf: 100`, Zod and Dart
  validation, a `amountMinor % 100 = 0` database check, and a one-time backfill
  that gives each household a first open period, assigns existing expenses to it,
  rounds any sub-taka amount to the nearest whole taka with a one-taka floor, and
  rewrites stored change snapshots and mutation receipts to the new shape;
- period create/close mutations sharing the existing mutation route, outbox, and
  change feed through `entityType` (`EXPENSE`, `PERIOD`, `LOAN`), with
  `PERIOD_ALREADY_OPEN`, `PERIOD_NOT_FOUND`, no reopen, and no period delete;
- loan create/update/delete with a manual debtor, its own net total, and no
  effect on the expense settlement figure;
- Flutter period and loan repositories, a close-and-open-next transaction that
  queues the close ahead of the next period's create, a period-scoped dashboard
  without a range control, a lending screen, and local-only history search over
  notes, categories, payers, and amounts;
- bootstrap ordering PERIOD → EXPENSE → LOAN so an expense never lands before its
  period.

Checks:

```powershell
npm.cmd run openapi:lint
npm.cmd run check
npm.cmd run mobile:check
npm.cmd run test:real-stack
```

Exit criterion met: the API unit and PostgreSQL integration suites, the Flutter
suite, and thirteen real-stack scenarios pass, including period-close
convergence across devices, loan CRUD across devices, and a server-side
whole-taka rejection. The manual two-installation checklist in
`docs/REAL_STACK_TESTING.md` remains part of release validation.

### Milestone 10 — Android notifications for the other member's activity (complete)

An explicit product revision: notifications moved from out of scope to in scope,
for local notifications posted by background sync only. Push was still out of
scope at this point, so notifications inherited background sync's timing —
milestone 11 is the revision that fixed that.

Delivered:

- `ExpenseChange.actorMemberKey` plus its migration, which backfills authorship
  by joining each change to the `ProcessedMutation` that produced it, and an
  `actorMember` field on `EntityChange` in the contract. Authorship has to come
  from the server: pushing a mutation deletes its outbox row before the same
  change arrives in the feed, so locally an own write is indistinguishable from
  the other member's;
- `ChangeDto.operation` and `ChangeDto.actorMember` parsed on the client, the
  second one nullable so an APK running against an older API syncs normally and
  simply stays quiet;
- notifiable activity collected inside the page transaction and announced only
  after it commits, filtered to changes that altered local state and that the
  server attributed to the other member. Bootstrap never announces;
- one high-importance `household-activity` channel, per-change wording with the
  amount, category, payer, and note, an `InboxStyle` summary when a sync brings
  more than one change, and notification ids derived from entity and version so
  a retried page cannot double-post;
- `POST_NOTIFICATIONS` requested once on the first open after install, recorded
  in `SyncMetadata`, and a Settings notifications card showing Android's own
  answer, a household-activity switch, and re-enable instructions after a denial;
- background sync raised from every six hours to WorkManager's fifteen-minute
  floor, with its own notifier built inside the background isolate.

Checks:

```powershell
npm.cmd run check
npm.cmd run mobile:check
npm.cmd run test:real-stack
```

Exit criterion met: fourteen real-stack scenarios pass, the new one proving that
the author's device stays silent about its own write echoing back while the other
device is told about it. The two-device notification checklist in
`docs/REAL_STACK_TESTING.md` remains part of release validation, because
WorkManager timing cannot be asserted in a test.

### Milestone 11 — closed-app delivery (complete, pending one device measurement)

Milestone 10 delivered notifications that were correct but late: on the target
phone, with the app closed and the device idle, the fifteen-minute job was
deferred for hours. Two revisions followed, in order.

First, the polling path was hardened. `adb shell am get-standby-bucket` reported
**40 (RARE)** with the JobScheduler `WITHIN_QUOTA` constraint unsatisfied, and the
power-save whitelist turned out to be the only lever an app can pull — an app
ignoring battery optimisations sits in bucket **5 (EXEMPTED)**, outside both Doze
and the quota. Delivered:

- a `BackgroundWorkPolicy` platform channel over `PowerManager`, hosted by
  `MainActivity`, that reads the exemption and opens both the exemption dialog and
  the app-details page, and answers `false` rather than throwing when an OEM build
  has removed the activity;
- the exemption asked for at startup immediately after the notification ask — allow
  notifications first, then keep them timely — gated on the live platform answer
  rather than a stored flag, and never recording an ask whose dialog failed to
  launch;
- `SyncMetadata.lastBackgroundSyncAt`, written by the background dispatcher for
  every outcome including an offline one, because it is the only value that can
  answer whether Android let the worker run at all;
- Settings advisories naming the option HyperOS actually shows — **No
  restrictions**, not the recommended-looking default — plus a real
  **Allow background activity** button and an honest **Re-check**.

That lifted the ceiling but did not remove it: polling alone is fifteen minutes at
best. So push was moved from out of scope to in scope, for data-only messages
only. Delivered:

- a `DeviceToken` table addressed by household and member, keyed on the token's
  SHA-256 so re-registering an unchanged token is a no-op, with a token Google
  reports as gone marked `disabledAt` rather than deleted;
- `POST /v1/devices` and `POST /v1/devices/unregister` on their own rate-limit
  bucket, logging the member and platform but never the token, and neither route
  reading a device back out;
- a `HouseholdActivityNotifier` interface with a disabled implementation, so an API
  with no `FIREBASE_SERVICE_ACCOUNT_BASE64` skips the device query as well as the
  send and behaves exactly as it did before push existed;
- the send fired after every mutation transaction has committed, fire-and-forget
  with a `.catch()` attached, and only for a change that actually landed — a
  replayed mutation returns the stored receipt's `APPLIED` verbatim, so the batch
  tracks which ids were answered from a receipt and excludes them;
- `high` priority, a thirty-minute TTL, one collapse key, and no `notification`
  block. The client composes every notification from its own database, which is
  the only reason author suppression and the household-activity switch still
  apply: the tray draws a server-composed block before any Dart runs, and the
  switch exists only in device-local `SyncMetadata`;
- schema v6 on the device — an FCM token fingerprint, its registration instant, and
  the last push received — plus `PushRegistrationController`, which posts after
  sign-in and on every `onTokenRefresh`, skips an unchanged token, retries next
  launch when the POST failed, and deregisters at sign-out while the access token
  is still valid;
- one `runBackgroundSync()` body shared by the WorkManager dispatcher and the FCM
  background handler, so a pushed wake stamps `lastBackgroundSyncAt` and composes
  notifications exactly as a poll does;
- a **Push wake** line in Settings, which is the only way to tell a working push
  from a well-timed poll.

Checks:

```powershell
npm.cmd run check
npm.cmd run mobile:check
```

Exit criterion met in software: the API and Flutter suites pass, including the
message-shape assertion, token retirement, the member handoff, a mutation applying
when the send fails outright, and a replayed batch waking nobody.

One measurement is deliberately outstanding rather than assumed. Whether a
data-only message reaches a package HyperOS/MIUI has force-stopped by a Recents
swipe is not reliably documented, so it is measured on the device. If nothing
arrives, the pre-designed fallback is one flag: a content-free tray notification
("Household Expenses" / "New household activity") with no amount, note, or member
name — the smallest change that would let the tray wake the app, and the only
circumstance under which a `notification` block may be sent.

A third revision followed once push was in place: the exemption is no longer asked
for at startup. Two system screens ahead of the app's own first screen was too much
to spend, the more so as the second is not a dialog on this phone but a **Battery
details** screen whose correct answer is not the recommended one. Android's
documented limits are what make dropping it safe — a high-priority FCM message has
no execution limits with the screen off and Doze active, and from Android 13 the
standby bucket no longer governs a high-priority allowance at all — so the
exemption buys timeliness for the fifteen-minute backstop rather than for push. It
is now offered only by the Settings advisory, which appears exactly while Android
reports the exemption missing, so the ask carries its own justification. Nothing
about it is recorded any more: it can be re-shown at will, so the live platform
answer is the whole state, and `batteryExemptionRequestedAt` stays in schema v6
unwritten rather than costing a migration to remove. The accepted cost is that a
member who never opens Settings stays throttled, and their backstop keeps running
late.

### Milestone 8 — Railway staging, CI, and release hardening

Create separate staging/production databases and secrets. Configure root npm
workspace build, migration pre-deploy, API start, `/health/ready`, HTTPS domain,
proxy trust, backups, log retention/redaction review, rate-limit observation, and
rollback/migration recovery. Add CI for OpenAPI, API checks with PostgreSQL, mobile
checks, secret scanning, and migration validation.

Exit criterion: a staging deployment migrates, provisions through an explicit
one-off action, passes smoke/sync tests, shuts down gracefully, and completes a
documented backup/restore and rollback exercise before production data is used.

## 3. Current deployment commands

From the monorepo root, Railway should use:

```text
Build:      npm ci && npm run build --workspace @expenses/api
Pre-deploy: npm run prisma:migrate:deploy --workspace @expenses/api
Start:      npm run start --workspace @expenses/api
Health:     /health/ready
```

The member provisioning command is intentionally not part of pre-deploy because
it would re-hash/reset PINs on every release.

`FIREBASE_SERVICE_ACCOUNT_BASE64` is the only optional runtime secret and is set
in the dashboard rather than declared with a value. It can be added or removed
without a code change: absent, the API logs "push disabled" once and clients fall
back to the fifteen-minute poll.

## 4. Risk register

| Risk | Impact | Mitigation/evidence |
| --- | --- | --- |
| Drift/OpenAPI/server shape divergence | Sync corruption | One contract, contract lint, DTO contract tests before mobile networking. |
| Decimal/floating money path | Incorrect balances | Integer JSON bound, PostgreSQL BIGINT/check, pure boundary tests. |
| Duplicate/lost mutation responses | Duplicate expenses | UUID receipts and event/expense write in one transaction; retry integration test. |
| Concurrent offline edits | Silent overwrite | Conditional `baseVersion`; authoritative conflict snapshot; server-wins mobile rule. |
| Cursor saved before data | Permanent missed changes | Apply page and cursor in one future Drift transaction; pagination tests. |
| Tombstone omitted/compacted | Deleted row resurrection | Full delete snapshots retained in expense/event tables and bootstrap/change feeds. |
| Bootstrap concurrent writes | Missing initial data | Stable watermark pages followed by mandatory changes pull. |
| Refresh theft/reuse | Session compromise | High-entropy opaque token, hash at rest, atomic rotation, family revocation. |
| Credential leakage | Account/database compromise | Placeholder examples, Pino redaction, no body logging, secret diff review. |
| Cross-household query regression | Data disclosure | Composite foreign keys, identity-derived filters, explicit isolation integration test. |
| Railway connection exhaustion | API outages | Configured bounded pool/timeout; observe staging and tune to Railway plan. |
| Android background delay | Stale remote view, late notifications | Foreground/manual triggers; a data-only push the moment a change lands; the battery-optimization exemption that moves the app out of the JobScheduler quota; fifteen-minute periodic work as the backstop; honest best-effort WorkManager messaging in Settings and the READMEs. |
| Whole-taka backfill rewrites history | Silently altered past amounts | One committed migration that rounds to the nearest taka with a one-taka floor; back up before deploying it, and treat it as irreversible. |
| Two devices opening a period at once | Two open periods, split dashboard | Partial unique index on the open period, `PERIOD_ALREADY_OPEN` rejection, close queued before the next create; real-stack close-convergence scenario. |
| Loans mistaken for expense settlement | Wrong amount actually paid | Separate tables, separate net total, no shared query; tests assert the settlement figure does not move when a loan is recorded. |
| Own write announced as the other member's | Every entry self-notifies | Server-assigned `actorMember` on every change row, compared against the member recorded on the device; acknowledging a push deletes the outbox row, so nothing local can make that call. Real-stack scenario 14 asserts the author's device stays silent. |
| Expense detail leaving the household through Google | Amounts and notes disclosed to a third party | The push payload is `{ "type": "household-activity" }` and nothing else; a `notification` block is never sent. A unit test asserts the exact message shape. |
| A failed or misconfigured push breaking a mutation | Lost writes, failed requests | The send happens after every transaction commits, is never awaited, and has a `.catch()`; a missing credential selects a disabled notifier. Integration tests assert a mutation applies when the send fails outright. |
| Replayed mutation waking the household | Notification for a change that never landed | Receipt-answered mutation ids are tracked and excluded, because a replay returns the stored `APPLIED` verbatim. Asserted against real PostgreSQL. |
| Device token leaking through a log | An outsider can wake the phone | The logger redacts `token` and `privateKey` at every depth; the device routes log the member and platform only. Tokens grant no authority over the account either way. |

## 5. Scope guard

Spending periods, the lending ledger, whole-taka amounts, local history search,
Android notifications for the other member's synced activity, and data-only FCM
push with background polling as the backstop are in scope and implemented; do not
remove them or reintroduce a month-based dashboard range without an explicit
product revision.

Do not add budgets, custom split percentages, receipts, server-composed
notification content, recurring expenses, bank integrations, iOS, web
administration, public registration, member management, additional households,
sub-taka amounts, automatic loans derived from expenses, or server-side search or
dashboard summaries without an explicit product/architecture revision.

The one exception to "no server-composed notification content" is the content-free
fallback described in milestone 11, and only if the force-stop measurement shows a
data-only message does not arrive.
