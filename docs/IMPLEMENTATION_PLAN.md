# Implementation plan

## 1. Inspected baseline

Inspection on 2026-08-13 found the working directory empty and not initialized as a Git repository. There were no existing files, instructions, dependencies, or user changes to preserve. `git status` and `git rev-parse` therefore returned “not a git repository.” Parent locations checked contained no inherited `AGENTS.md`.

Installed tools:

```text
Flutter 3.47.0 (stable)
Dart 3.13.0
Node.js v24.15.0
npm 11.12.1
```

The repository was subsequently initialized on `main`, and the documentation baseline was pushed before scaffolding. The commands below remain the target workflow as each milestone lands.

### Scaffold verification — 2026-08-13

The monorepo/tooling scaffold now includes the npm API workspace, strict TypeScript Express liveness service, Prisma PostgreSQL CLI foundation without data models, Android-only Flutter shell, OpenAPI location/lint, environment placeholders, root scripts, and contributor README. The Android namespace/application ID is `com.sumonebrahim.houseexpenses`.

These commands were run successfully on the inspected Windows environment:

```powershell
npm.cmd install
npm.cmd run openapi:lint
npm.cmd run format:check
npm.cmd run lint
npm.cmd run typecheck
npm.cmd test
npm.cmd run build
npm.cmd run prisma:generate --workspace @expenses/api
npm.cmd run prisma:validate --workspace @expenses/api

Set-Location apps/mobile
flutter pub get
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
```

The compiled API was also started on a temporary local port and `GET /health/live` returned `{"status":"ok"}`. The API suite contains one passing liveness test, and the Flutter suite contains one passing shell widget test.

`flutter build apk --debug` was not run: `flutter doctor -v` found Android SDK 36/build-tools 36 but no JDK, with `JAVA_HOME` unset and no `java` binary on `PATH`. Install/configure JDK 17, rerun `flutter doctor -v`, then run the documented build command.

No Docker configuration was added because this scaffold does not connect to PostgreSQL or run PostgreSQL integration tests. Reassess local PostgreSQL tooling in the database milestone and document the concrete need before adding it.

## 2. Delivery principles

- Complete milestones in order. Keep each change independently reviewable and leave main checks green.
- Define/lint OpenAPI before implementing each HTTP behavior; generated transport types must not become a second hand-edited contract.
- Build and test integer domain rules before UI or network wiring.
- Build mutation/idempotency/change-feed behavior against real PostgreSQL transactions before mobile synchronization.
- Make every mobile mutation local and durable first. Network code never becomes the write path for UI state.
- Test failure/retry/restart paths as first-class behavior, not only the happy path.
- Do not introduce out-of-scope screens, tables, endpoints, packages, or platform targets.

## 3. Ordered milestones

### Milestone 0 — Repository and repeatable toolchain

Outputs:

- Initialize Git, root `.gitignore`, `.editorconfig`, `README.md`, private npm workspace metadata, lockfile, and CI workflow. Add local PostgreSQL tooling only when integration tests demonstrate the need.
- Pin npm to `11.12.1`, Node to the compatible 24.x line, and document Flutter `3.47.0`/Dart `3.13.0`. Prefer a project Flutter version manager only if the team will actually use it.
- Create empty structural directories from the final tree without feature implementations.
- Establish root scripts for contract linting plus API/mobile formatting, lint/type-check, test, and build checks. Add deterministic OpenAPI generation with the contract implementation milestone.
- Use Android application ID `com.sumonebrahim.houseexpenses`; change it only through the documented Gradle/Kotlin locations before distribution.

Commands/checks:

```powershell
git init
node --version
npm.cmd --version
flutter --version
npm.cmd install
npm.cmd run openapi:lint
git status --short
```

Exit gate: a fresh checkout can install dependencies, contract lint runs, CI invokes the same commands, and no secrets/local databases/build output are tracked.

### Milestone 1 — Contract and pure domain rules

Outputs:

- Write `packages/contracts/openapi.yaml` for auth, error envelopes, canonical expense/tombstone, bootstrap, change pages, and mutation batches/results.
- Encode UUID formats, enum values, JSON safe integer amount bounds, RFC 3339 timestamps, PIN/note limits, batch limit 50, and page defaults/maxima.
- Generate or map TypeScript/Dart DTOs in one repeatable direction from the contract. Generated code is isolated and not hand edited.
- Implement API and Dart pure domain tests for string-to-poisha parsing/formatting, categories/members, even/odd splits, settlement, and half-open range semantics. No HTTP/database/UI yet.

Commands/checks:

```powershell
npm.cmd run openapi:lint
npm.cmd run openapi:generate
npm.cmd run typecheck
npm.cmd test
Set-Location apps/mobile
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test test/domain
```

Exit gate: contract examples validate, generation is deterministic, both languages pass the documented money examples, and no money function accepts/returns a floating-point value.

### Milestone 2 — PostgreSQL schema and API skeleton

Outputs:

- Scaffold strict TypeScript/Express with configuration validation, structured redacted logs, request IDs, error mapping, security headers, JSON limits, liveness, readiness, and graceful shutdown.
- Add Prisma schema/migration for household, members, expenses, refresh sessions, mutation receipts, and append-only changes, including keys/checks/indexes described in architecture.
- Seed only the fixed household/member identities; leave PIN hashes to secure provisioning.
- Add a PostgreSQL integration-test harness. Do not substitute SQLite for transaction/concurrency tests.

Commands/checks:

```powershell
npm.cmd run prisma:generate --workspace @expenses/api
npm.cmd run prisma:validate --workspace @expenses/api
npm.cmd run prisma:migrate:dev --workspace @expenses/api -- --name init
npm.cmd run lint --workspace @expenses/api
npm.cmd run typecheck --workspace @expenses/api
npm.cmd test --workspace @expenses/api
npm.cmd run dev --workspace @expenses/api
```

Check `/health/live` and `/health/ready`, inspect the generated SQL, and run migrations up on an empty test database. Exit gate: startup fails on invalid config, readiness reflects database state, rollback leaves no partial sync data, and the schema enforces the fixed enum/amount/version constraints.

### Milestone 3 — Authentication and member provisioning

Outputs:

- Add an interactive/non-echoing operational provision command that sets Sumon/Ebrahim PIN hashes using Argon2id without command-line PIN arguments.
- Implement login, refresh rotation, reuse/family revocation, logout, access JWT verification, household scoping, and generic error responses.
- Configure per-IP and per-member login limits plus broader authenticated API limits.
- Document local and Railway provisioning without retaining temporary plaintext environment values.

Commands/checks:

```powershell
npm.cmd run members:provision --workspace @expenses/api
npm.cmd test --workspace @expenses/api -- auth
npm.cmd run lint --workspace @expenses/api
npm.cmd run typecheck --workspace @expenses/api
```

Exit gate: correct logins work for exactly two members; bad credentials do not disclose which field failed; access expiry, one-time refresh rotation, duplicate concurrent refresh, old-token reuse, logout, rate limiting, and log redaction have integration coverage.

### Milestone 4 — Transactional sync API

Outputs:

- Implement `/v1/sync/mutations` with canonical request hashing, durable receipts, base-version checks, full canonical results, atomic change append, and soft-delete tombstones.
- Implement paginated bootstrap with a stable watermark/page token and `/v1/sync/changes` with opaque household-scoped cursors.
- Bound batch/page/body sizes. Ensure every database query scopes the authenticated household.
- Keep dashboard and generic CRUD endpoints absent.

Commands/checks:

```powershell
npm.cmd run openapi:lint
npm.cmd run openapi:generate
npm.cmd run prisma:generate --workspace @expenses/api
npm.cmd test --workspace @expenses/api -- sync
npm.cmd run lint --workspace @expenses/api
npm.cmd run typecheck --workspace @expenses/api
```

Exit gate: integration tests prove create/update/delete version progression, duplicate delivery, mutation-ID misuse, response-loss retry, update/update and update/delete conflicts, transaction rollback, tombstone replay, multi-page bootstrap, writes during bootstrap, cursor restart, and cross-household denial.

### Milestone 5 — Android/Flutter foundation and Drift

Outputs:

- Scaffold Android only (`flutter create --platforms=android ...`); no iOS directory.
- Add Riverpod, Drift/SQLite, Dio, secure storage, UUID, IANA time-zone, connectivity-trigger, and WorkManager dependencies with compatible locked versions.
- Establish feature/domain/data/sync boundaries, app theme/navigation, typed configuration, Drift migrations, and provider overrides for tests.
- Implement `local_expenses`, `outbox_mutations`, and `sync_state` with transactional DAOs and reactive dashboard queries.

Commands/checks:

```powershell
Set-Location apps/mobile
flutter pub get
dart run build_runner build --delete-conflicting-outputs
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test test/data/local
flutter build apk --debug
```

Exit gate: Android debug build succeeds, schema migration tests pass, reactive queries exclude tombstones correctly, and a local expense projection cannot commit without its durable outbox intent.

### Milestone 6 — Mobile authentication/session shell

Outputs:

- Implement fixed member selector/PIN login, secure token storage, cached session gate, logout, and first-device connection messaging.
- Add Dio base configuration, redacted logging, access-token attachment, single-flight refresh, one retry after refresh, and definitive-auth-rejection lock behavior.
- Keep transient network failure distinct from invalid credentials/revocation so offline users retain local access.

Commands/checks:

```powershell
Set-Location apps/mobile
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test test/features/auth test/data/remote
flutter test integration_test/auth_flow_test.dart
```

Exit gate: secrets never enter Drift/logs, concurrent `401`s cause one refresh, rotation updates secure storage safely, a first login needs HTTP, and an established session can enter cached UI during an outage.

### Milestone 7 — Local expense and dashboard experience

Outputs:

- Implement dashboard/list, Dhaka range picker/default month, add/view/edit form, payer default/selection, note/category/amount validation, delete confirmation, and reactive settlement text.
- Every save/delete performs only the Drift projection+outbox transaction before navigation/UI success.
- Add pending/offline states and an explicit manual refresh trigger; do not yet claim server convergence until the sync engine milestone.

Commands/checks:

```powershell
Set-Location apps/mobile
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test test/features/expenses test/features/dashboard
flutter test integration_test/offline_expense_flow_test.dart
```

Exit gate: add/edit/delete work with the API unavailable, logged-in payer defaults correctly but remains selectable, validation matches OpenAPI, deleted expenses leave tombstones, and all documented dashboard examples pass widget/domain tests.

### Milestone 8 — Mobile sync and server-wins reconciliation

Outputs:

- Implement the serialized/coalescing coordinator, resumable bootstrap, pull/apply/cursor transaction, dependency-ready push, receipt/origin acknowledgement, persistent retry state, and final pull.
- Make attempted mutation payloads immutable. Order dependent same-entity mutations and discard the chain on conflict.
- Map applied/conflict/rejected results to canonical projection, conflict Snackbar/banner, or actionable sync error.
- Implement bounded exponential backoff/jitter and authoritative HTTP reachability behavior.

Commands/checks:

```powershell
Set-Location apps/mobile
dart run build_runner build --delete-conflicting-outputs
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test test/sync
flutter test integration_test/two_device_sync_test.dart
```

Exit gate: restart/response-loss/duplicate-page tests converge without duplicate writes; paginated bootstrap resumes; cursors never advance before data commit; concurrent device edits follow server-wins UX; tombstones propagate; unrelated pending mutations survive another entity's conflict.

### Milestone 9 — Sync triggers and Android background work

Outputs:

- Wire coordinator triggers for launch, lifecycle foreground resume, successful local mutation, manual refresh, connectivity recovery while process is alive, and WorkManager.
- Coalesce simultaneous triggers, dispose subscriptions, add network constraints, and bound background execution/retry work.
- Present copy that says background sync is best effort rather than instant/guaranteed.

Commands/checks:

```powershell
Set-Location apps/mobile
flutter analyze
flutter test test/sync/triggers
flutter test integration_test/sync_triggers_test.dart
flutter build apk --release
```

Also verify on at least one physical Android device: process restart, airplane mode recovery, foreground resume, battery saver, and delayed WorkManager execution. Exit gate: every required trigger reaches the same single-flight coordinator and connectivity alone never marks a sync successful.

### Milestone 10 — Production hardening and Railway release

Outputs:

- Add full CI gates, dependency/security audit policy, production API build, Railway configuration, migration release command, HTTPS base URL, backup/restore runbook, and secret/provisioning runbook.
- Run two-device end-to-end scenarios against a Railway staging database before production.
- Validate log redaction, health checks, graceful shutdown, database connection limits, rate limiting behind Railway proxy, request/body caps, and release cleartext blocking.
- Create the release APK/app bundle only after confirming the permanent Android application ID/signing setup.

Commands/checks:

```powershell
npm.cmd ci
npm.cmd run openapi:lint
npm.cmd run lint
npm.cmd run typecheck
npm.cmd test
npm.cmd audit --omit=dev
npm.cmd run build --workspace @expenses/api
npm.cmd run prisma:migrate:deploy --workspace @expenses/api
Set-Location apps/mobile
flutter pub get
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
flutter build appbundle --release
```

Railway checks: deploy migrations once, hit liveness/readiness over HTTPS, authenticate both members, run paginated/bootstrap and idempotent mutation smoke tests, inspect redacted logs, then exercise restore in a non-production database. Exit gate: CI and staging end-to-end suite pass, secrets are externalized, rollback/migration strategy is documented, and known Android background limitations appear in release documentation.

## 4. Cross-cutting test matrix

At minimum, preserve these scenarios as named automated tests:

| Area | Required cases |
| --- | --- |
| Money | `1`, `2`, `101`, maximum amount, invalid decimal precision, formatted BDT, no floating types. |
| Split | Odd remainder to Sumon payer; odd remainder to Ebrahim payer; range allocation by expense; both balances sum to zero. |
| Time | Dhaka current-month boundaries, inclusive displayed end date/exclusive instant, UTC normalization, occurrence exactly at each boundary. |
| Auth | Both fixed members, wrong PIN, rate limit, expired access, rotation, concurrent refresh, reuse revocation, logout, offline cached session. |
| Mutation | UUID idempotency, changed-payload reuse, lost response, create collision, version conflict, delete tombstone, dependent local chain. |
| Pull | Empty page, multiple pages, duplicate page, crash before/after cursor commit, changes during bootstrap, invalid page token. |
| Devices | Offline edit vs remote edit, offline delete vs remote edit, conflict message, server wins, unrelated outbox preserved, eventual convergence. |
| Android | Launch/resume/mutation/manual/recovery triggers, trigger coalescing, delayed/cancelled background work, cleartext rejection. |

## 5. Risks and mitigations

| Risk | Impact | Mitigation/proof |
| --- | --- | --- |
| Empty, non-Git starting directory | No history or existing automation to lean on. | Initialize explicitly in milestone 0, make a small documentation/bootstrap commit, and establish CI before features. |
| JavaScript/JSON/PostgreSQL money type mismatch | Precision loss or runtime BigInt serialization failures. | Bound the contract below `Number.MAX_SAFE_INTEGER`, reject unsafe JSON numbers, convert immediately to `bigint`, serialize explicitly, and run max-value round-trip tests. |
| Mutation result lost after database commit | Duplicate expense/version increment on retry. | Atomic durable receipt keyed by mutation UUID and canonical request hash; loss/retry integration test. |
| Multiple offline edits of one expense | Wrong base version or changed idempotency payload. | Immutable-after-attempt outbox rows, explicit predecessor ordering, and only dependency-ready heads sent. |
| Cursor/page crash or concurrent bootstrap writes | Missed/duplicated remote state. | Transactional page+cursor commit, stable bootstrap watermark/keyset token, immediate post-bootstrap delta, idempotent version application. |
| Tombstone/change-log growth | Increasing storage/bootstrap time. | Index cursor paths, bounded keyset pages, monitor size. Retain indefinitely initially; design/test a generation reset before any future compaction. |
| Low-entropy PIN attacks | Account compromise. | Argon2id, unique salts, optional pepper, generic failures, layered rate limits, HTTPS, short JWTs, refresh rotation/revocation. |
| Android background restrictions | Delayed convergence while app is closed. | Clearly state best effort, use WorkManager constraints, and reliably retry on next launch/resume/manual/recovery opportunity. |
| Device clock or time-zone mistakes | Wrong month/range or misleading optimistic times. | IANA `Asia/Dhaka` calculations, UTC persistence, server canonical update/delete times, boundary tests. |
| Railway proxy/connections/migration error | Bad client IP limits, outage, or schema skew. | Strict trusted-proxy setting, pool limits, pre-deploy committed migrations, readiness, staging deploy and backup/restore drill. |
| Contract/generated model drift | Mobile/API incompatibility. | Single OpenAPI source, deterministic generation, CI lint and clean-diff check, contract examples used in tests. |

No current blocker changes the architecture. The Android application ID is now `com.sumonebrahim.houseexpenses`; release signing identity and protected signing configuration must still be established before public distribution.

## 6. Proposed final directory tree

```text
expenses/
├── .editorconfig
├── .gitignore
├── AGENTS.md
├── README.md
├── compose.yaml                         # optional later, only if DB tests justify it
├── package.json                         # private workspace/scripts
├── package-lock.json
├── .github/
│   └── workflows/
│       └── ci.yml
├── apps/
│   ├── api/
│   │   ├── package.json
│   │   ├── tsconfig.json
│   │   ├── prisma/
│   │   │   ├── schema.prisma
│   │   │   ├── migrations/
│   │   │   └── seed.ts                 # identities only; no PINs
│   │   ├── scripts/
│   │   │   └── provision-members.ts    # secure interactive/secret input
│   │   ├── src/
│   │   │   ├── config/
│   │   │   ├── domain/
│   │   │   ├── application/
│   │   │   │   ├── auth/
│   │   │   │   └── sync/
│   │   │   ├── infrastructure/
│   │   │   │   ├── auth/
│   │   │   │   ├── logging/
│   │   │   │   └── prisma/
│   │   │   ├── http/
│   │   │   │   ├── middleware/
│   │   │   │   └── routes/
│   │   │   ├── generated/
│   │   │   └── index.ts
│   │   └── test/
│   │       ├── unit/
│   │       └── integration/
│   └── mobile/
│       ├── android/
│       ├── pubspec.yaml
│       ├── analysis_options.yaml
│       ├── lib/
│       │   ├── main.dart
│       │   ├── app/
│       │   ├── domain/
│       │   │   ├── expenses/
│       │   │   ├── money/
│       │   │   └── settlement/
│       │   ├── data/
│       │   │   ├── local/
│       │   │   └── remote/
│       │   ├── features/
│       │   │   ├── auth/
│       │   │   ├── dashboard/
│       │   │   └── expenses/
│       │   ├── security/
│       │   ├── sync/
│       │   └── generated/
│       ├── test/
│       │   ├── domain/
│       │   ├── data/
│       │   ├── features/
│       │   └── sync/
│       └── integration_test/
├── packages/
│   └── contracts/
│       └── openapi.yaml
└── docs/
    ├── PRODUCT_SPEC.md
    ├── ARCHITECTURE.md
    ├── IMPLEMENTATION_PLAN.md
    ├── DEPLOYMENT.md                     # added with Railway milestone
    └── RUNBOOK.md                        # added with hardening milestone
```

Only Android is scaffolded under `apps/mobile`. Deployment/runbook files appear when their milestones can document verified commands rather than guesses.
