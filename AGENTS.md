# Household Expenses repository guide

## Repository layout

- `apps/api`: Node.js, TypeScript, and Express API. Prisma is the only database access layer; PostgreSQL migrations live in `apps/api/prisma/migrations`.
- `apps/mobile`: Flutter Android app. Use Riverpod for state, Drift over SQLite for durable local data, Dio for HTTP, Android WorkManager integration for best-effort background sync, and `firebase_messaging` for the data-only push that wakes that same sync sooner.
- `packages/contracts/openapi.yaml`: the single API contract. Generate or validate client/server types from it; do not create undocumented duplicate request or response shapes.
- `docs`: product, architecture, and delivery guidance.

Do not add iOS, a web admin, or extra product areas without an explicit scope change. Spending periods, the manual lending ledger, whole-taka amounts, and local history search are already in scope and implemented; do not remove them or move search or dashboard summaries to the server.

## Standard commands

The initial scaffold must expose these stable commands. Until its package files exist, treat this list as the required command interface.

```powershell
# Repository/API
npm.cmd install
npm.cmd run openapi:lint
npm.cmd run lint
npm.cmd run typecheck
npm.cmd test
npm.cmd run dev --workspace @expenses/api
npm.cmd run prisma:generate --workspace @expenses/api
npm.cmd run prisma:migrate:dev --workspace @expenses/api
npm.cmd run prisma:migrate:deploy --workspace @expenses/api

# Mobile
Set-Location apps/mobile
flutter pub get
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
flutter build apk --debug
```

Run the narrowest relevant checks while developing and the complete lint, type-check, contract, migration, and test suite before merging. Commit Prisma migration files; never use `prisma db push` for shared or production databases.

## Engineering constraints

- The product has one household and exactly two fixed members: `SUMON` and `EBRAHIM`. There is no registration or member-management API.
- Use BDT only. Persist and calculate `amountMinor` as integer poisha. Never use binary floating point, `double`, or JavaScript decimal arithmetic for money.
- Amounts are whole taka. Every stored `amountMinor` is a multiple of `100`; reject a sub-taka remainder on both ends instead of rounding it.
- Parse entered BDT from digit-only strings into poisha and format poisha with integer division/remainders. API amounts are JSON safe integers and PostgreSQL `BIGINT`; convert to/from JavaScript `bigint` at the API boundary.
- Entity IDs and mutation IDs are client-generated UUIDs. They identify different things and must never be reused.
- Store timestamps as UTC instants. Calendar range boundaries are calculated in the `Asia/Dhaka` time zone and use `[startInclusive, endExclusive)` semantics.
- Keep expense and loan deletion soft. A deleted row remains a versioned tombstone and stays in bootstrap/change responses. Spending periods are never deleted and never reopened, so they have no tombstone.
- Exactly one spending period is open per household, enforced by a partial unique index and by rejecting a second open period. An expense belongs to a period; an omitted `periodId` resolves to the open one, and a closed period still accepts an expense recorded offline before the close.
- Loans are entirely manual and separate. They have their own net total and must never move the expense settlement figure.
- Server-generated `version`, `updatedAt`, `deletedAt`, and change cursors are authoritative.
- Keep domain code independent from Express, Prisma, Flutter widgets, Drift, and Dio where practical. Dashboard and split calculations should be pure, unit-tested integer functions.
- Log request/correlation IDs, mutation IDs, status, and timing, but never PINs, bearer tokens, refresh tokens, authorization headers, or full sensitive request bodies.

## Money and settlement rules

For an expense of `A` poisha, where `T = A ~/ 100` is its whole taka:

```text
lowerHalf = (T ~/ 2) * 100
payerShare = (T ~/ 2 + T % 2) * 100
otherShare = lowerHalf
```

The payer receives the one-taka remainder when `T` is odd, so no share is ever a sub-taka figure. Calculate each member's allocated share by summing the per-expense allocation over the rows in scope — the open spending period on the dashboard, or the selected range in History; do not divide a total by two. A member's balance is `paid - allocated`. A positive balance means the other member owes them; the two balances must sum to zero.

The lending ledger is summed separately as `ebrahimOwesMinor - sumonOwesMinor` over active loan rows. Never fold it into the expense settlement figure.

## Sync invariants

- A local mutation updates Drift and the visible UI in one transaction, and also appends a durable outbox item.
- One mutation route, one outbox, and one change feed carry every synchronized entity. Each candidate, result, change row, and bootstrap item names its `entityType` (`EXPENSE`, `PERIOD`, `LOAN`), which defaults to `EXPENSE`. Bootstrap applies periods before expenses before loans.
- Freeze a mutation payload before its first send. Retrying the same mutation UUID must send byte-for-byte equivalent semantics.
- The server stores an idempotency receipt atomically with each accepted mutation and returns the stored result for a retry. Reusing an ID for different content is an error.
- Serialize sync runs. Pull/bootstrap pages fully, push only dependency-ready mutations in local sequence, apply replies transactionally, and persist a cursor only after its page is applied.
- Mutations are processed with optimistic `baseVersion`. On conflict, replace the local entity with the returned server snapshot/tombstone, discard that mutation and dependent local mutations for the entity, and show a brief conflict message.
- Apply remote changes idempotently using entity version. A change carrying the client's `originMutationId` can acknowledge the matching outbox row after a lost HTTP response.
- A new installation has no cursor: authenticate online, consume the paginated bootstrap snapshot, persist its watermark, then pull changes after that watermark before declaring sync complete.
- Retry timeouts, connectivity failures, HTTP 429, and retryable 5xx responses with bounded exponential backoff and jitter. Honor `Retry-After`. Do not retry validation or authorization failures blindly.
- Connectivity state is only a reason to try. Only an HTTP response establishes API reachability.
- Trigger sync on launch, foreground resume, local mutation, manual refresh, network recovery while alive, and best-effort Android background work. Android does not guarantee immediate or exact background execution.
- Every change row names its author in `actorMember`, which the server assigns from the authenticated identity. Decide notifications from that field alone. A missing outbox row does not identify the other member: acknowledging your own write deletes the row before the same change arrives in the feed.
- Announce only the other member's changes, only from the change feed, and only after the page transaction has committed. Bootstrap never notifies, and an unattributed change — an older API — never notifies.
- Ask Android for the battery-optimization exemption at startup, right after the notification ask. Gate it on `PowerManager.isIgnoringBatteryOptimizations`, not on the stored flag, and never record an ask whose dialog failed to launch. Without the exemption an idle phone drops the app to App Standby bucket 40 (RARE) and defers the fifteen-minute job for hours. Keep the exemption out of the "will notify" decision: it governs when a notification arrives, not whether it can be posted.
- `background_work_policy.dart` and its `MainActivity` handler are the only platform channel in the app, and they are **UI-isolate only** — the handler lives on the Activity, so the WorkManager isolate has no receiver. Every channel call answers `false` rather than throwing.
- Record `lastBackgroundSyncAt` from the background dispatcher for every outcome, offline included: the column answers whether Android ran the worker, which no other stored value can. Write it outside `SyncCoordinator` so the coordinator stays ignorant of its isolate, and leave `updatedAt` alone.
- A push is a nudge, never a message. The server sends data only; the client syncs and composes every notification from its own database, which is the only reason author suppression and the household-activity switch still apply — the tray draws a server-composed `notification` block before any Dart runs, and the switch exists only in device-local `SyncMetadata`. Never add a `notification` block unless the force-stop measurement in `apps/mobile/README.md` forces the documented content-free fallback.
- Send the push after every mutation transaction has committed, fire-and-forget with a `.catch()` attached, and only for a change that actually landed: a replayed mutation returns the stored receipt's `APPLIED` verbatim, so status alone cannot tell a new change from a re-upload. A failed send must never fail a mutation.
- `firebase_messaging` must never ask for a permission. `NotificationSettingsController.ensureNotificationPermission` is the single owner of that ask, and its rule — never record an ask that failed to reach Android — is the fix for a shipped bug that a second asker would silently undo.
- Device registration tokens are addresses, not credentials, but they are never logged and never printed: the logger redacts `token` and `privateKey` at every depth. Push works without a credential configured — the API logs "push disabled" once and clients fall back to polling, which is why FCM is an accelerator and the fifteen-minute poll stays.

## Validation and security expectations

- Validate every external value on both mobile and API. The contract is authoritative for enum values, UUIDs, timestamps, page sizes, note length, and amount bounds.
- Accept an amount only when it is a whole number of taka mapping to `100..99_999_999_999` poisha and divisible by `100`. Reject decimal points, exponent notation, signs, NaN/infinity, and any sub-taka remainder.
- Notes are optional, trimmed, normalized to `null` when empty, and limited to 500 Unicode code points. Categories and payers must be exact contract enum values.
- Hash PINs with Argon2id and a unique salt. Do not store or log plaintext PINs.
- Use short-lived access JWTs plus opaque, rotating, revocable refresh tokens. Store only refresh-token hashes server-side and tokens only in Android secure storage.
- Require HTTPS, validate configuration at startup, use generic login failures, rate-limit authentication and API traffic, and cap JSON body/batch/page sizes.
- Add tests for money boundaries, whole-taka rejection, odd-taka splits, date-range boundaries, period open/close rules, loan create/edit/delete and its net total, local search, duplicate mutation delivery, lost responses, pagination, version conflicts, tombstones, refresh rotation/reuse, and server-wins reconciliation.

## Scope boundaries

In scope: login for the two fixed members, a dashboard scoped to the open spending period with settlement, closing a period to open the next one, add/view/edit/soft-delete expenses, a manual lending ledger, history filters and local search, offline local operation, synchronization, Android notifications for the other member's synced activity, and near-instant delivery of those notifications through data-only FCM push with background polling as the backstop.

Out of scope: budgets, custom split percentages, receipts, server-composed notification content (a push carries no detail, so the tray never draws one), recurring expenses, bank integration, iOS, web administration, public registration, new members, multiple households, sub-taka amounts, loans derived automatically from expenses, and server-side search or dashboard summaries.
