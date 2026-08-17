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
pass against PostgreSQL. Milestone 9 raised the suite to thirteen scenarios. A
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
| Android background delay | Stale remote view | Foreground/manual triggers; honest best-effort WorkManager messaging. |
| Whole-taka backfill rewrites history | Silently altered past amounts | One committed migration that rounds to the nearest taka with a one-taka floor; back up before deploying it, and treat it as irreversible. |
| Two devices opening a period at once | Two open periods, split dashboard | Partial unique index on the open period, `PERIOD_ALREADY_OPEN` rejection, close queued before the next create; real-stack close-convergence scenario. |
| Loans mistaken for expense settlement | Wrong amount actually paid | Separate tables, separate net total, no shared query; tests assert the settlement figure does not move when a loan is recorded. |

## 5. Scope guard

Spending periods, the lending ledger, whole-taka amounts, and local history
search are in scope and implemented; do not remove them or reintroduce a
month-based dashboard range without an explicit product revision.

Do not add budgets, custom split percentages, receipts, notifications, recurring
expenses, bank integrations, iOS, web administration, public registration,
member management, additional households, sub-taka amounts, automatic loans
derived from expenses, or server-side search or dashboard summaries without
an explicit product/architecture revision.
