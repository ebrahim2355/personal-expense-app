# Implementation plan

## 1. Delivery rules

- Keep `packages/contracts/openapi.yaml` as the only HTTP contract.
- Commit every Prisma migration and use `prisma migrate deploy` outside local
  schema development. Never use `prisma db push` on shared databases.
- Use only integer poisha for money and pure integer split/settlement functions.
- Keep Flutter local-first: one Drift transaction updates the visible expense
  projection and durable outbox.
- Keep sync serialized, cursors transactional, mutation semantics immutable once
  first sent, deletions as tombstones, and server snapshots authoritative on
  conflict.
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

### Milestone 3 — production v1 backend (complete in this change)

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

### Milestone 4 — Flutter domain and Drift foundation (next)

Add packages through Flutter's package manager: Riverpod, Drift/SQLite, Dio,
UUID, time-zone data, secure storage, connectivity trigger support, and Android
WorkManager integration. Define immutable domain models and pure functions for:

- decimal-string BDT input to integer poisha;
- integer BDT formatting;
- per-expense payer-remainder allocation;
- local Dhaka date-range boundaries;
- paid/allocated/balance/settlement totals.

Then create Drift migrations for local expenses, immutable durable outbox items,
and sync state. Do not call the API from widgets.

Checks:

```powershell
Set-Location apps/mobile
flutter pub get
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
```

Exit criterion: boundary examples from the product spec pass as pure tests and a
Drift transaction proves every optimistic local write has durable sync intent.

### Milestone 5 — Flutter authentication and first bootstrap

Implement the fixed member selector/PIN screen, secure token storage, Dio bearer
interceptor, single-flight refresh, logout/lock behavior, and first-device
bootstrap. A first installation must authenticate online. Cached local data stays
available during transient HTTP absence after a prior session.

Checks add mocked HTTP contract tests for login/refresh/logout and a PostgreSQL
API + Android/Flutter integration scenario for paginated bootstrap followed by a
post-watermark pull.

Exit criterion: tokens never enter Drift/logs; every bootstrap page is applied
before its watermark is committed; auth rejection locks the app without silently
deleting pending local household data.

### Milestone 6 — Flutter expense UI and dashboard

Build the dashboard/list, date-range control, add/view/edit/delete flows, payer
default/selector, validation, pending/offline state, and conflict message. Reads
remain Drift queries. Saves/deletes remain local projection + outbox transactions.

Checks include widget tests and pure totals for even/odd poisha, multiple
expenses, deleted rows, empty ranges, and exact Dhaka month boundaries.

Exit criterion: all product-spec screen and validation acceptance criteria pass
offline without waiting for HTTP.

### Milestone 7 — full sync coordinator and Android triggers

Implement single-flight pull/push/reconcile cycles, dependency-ready outbox
ordering, immutable retry semantics, `originMutationId` lost-response
acknowledgement, server-wins conflict transactions, permanent rejection state,
bounded backoff/jitter, `Retry-After`, and triggers on launch/resume/mutation/manual
refresh/live network recovery/best-effort WorkManager.

Exit criterion: two devices converge across offline create/update/delete,
duplicate delivery, lost responses, pagination, conflicts, and tombstones.
Documentation and UI explicitly state that Android background timing is not
guaranteed.

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

## 5. Scope guard

Do not add budgets, custom split percentages, receipts, notifications, recurring
expenses, bank integrations, iOS, web administration, public registration,
member management, additional households, or server dashboard summaries without
an explicit product/architecture revision.
