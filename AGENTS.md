# Household Expenses repository guide

## Repository layout

- `apps/api`: Node.js, TypeScript, and Express API. Prisma is the only database access layer; PostgreSQL migrations live in `apps/api/prisma/migrations`.
- `apps/mobile`: Flutter Android app. Use Riverpod for state, Drift over SQLite for durable local data, Dio for HTTP, and Android WorkManager integration only for best-effort background sync.
- `packages/contracts/openapi.yaml`: the single API contract. Generate or validate client/server types from it; do not create undocumented duplicate request or response shapes.
- `docs`: product, architecture, and delivery guidance.

Do not add iOS, a web admin, or extra product areas without an explicit scope change.

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
- Parse entered BDT from strings into poisha and format poisha with integer division/remainders. API amounts are JSON safe integers and PostgreSQL `BIGINT`; convert to/from JavaScript `bigint` at the API boundary.
- Expense IDs and mutation IDs are client-generated UUIDs. They identify different things and must never be reused.
- Store timestamps as UTC instants. Calendar range boundaries are calculated in the `Asia/Dhaka` time zone and use `[startInclusive, endExclusive)` semantics.
- Keep expense deletion soft. A deleted expense remains a versioned tombstone and stays in bootstrap/change responses.
- Server-generated `version`, `updatedAt`, `deletedAt`, and change cursors are authoritative.
- Keep domain code independent from Express, Prisma, Flutter widgets, Drift, and Dio where practical. Dashboard and split calculations should be pure, unit-tested integer functions.
- Log request/correlation IDs, mutation IDs, status, and timing, but never PINs, bearer tokens, refresh tokens, authorization headers, or full sensitive request bodies.

## Money and settlement rules

For an expense of `A` poisha:

```text
lowerHalf = A ~/ 2
payerShare = lowerHalf + (A % 2)
otherShare = lowerHalf
```

The payer receives the one-poisha remainder when `A` is odd. For a selected range, calculate each member's allocated share by summing the per-expense allocation; do not divide the range total by two. A member's balance is `paid - allocated`. A positive balance means the other member owes them; the two balances must sum to zero.

## Sync invariants

- A local mutation updates Drift and the visible UI in one transaction, and also appends a durable outbox item.
- Freeze a mutation payload before its first send. Retrying the same mutation UUID must send byte-for-byte equivalent semantics.
- The server stores an idempotency receipt atomically with each accepted mutation and returns the stored result for a retry. Reusing an ID for different content is an error.
- Serialize sync runs. Pull/bootstrap pages fully, push only dependency-ready mutations in local sequence, apply replies transactionally, and persist a cursor only after its page is applied.
- Mutations are processed with optimistic `baseVersion`. On conflict, replace the local entity with the returned server snapshot/tombstone, discard that mutation and dependent local mutations for the entity, and show a brief conflict message.
- Apply remote changes idempotently using entity version. A change carrying the client's `originMutationId` can acknowledge the matching outbox row after a lost HTTP response.
- A new installation has no cursor: authenticate online, consume the paginated bootstrap snapshot, persist its watermark, then pull changes after that watermark before declaring sync complete.
- Retry timeouts, connectivity failures, HTTP 429, and retryable 5xx responses with bounded exponential backoff and jitter. Honor `Retry-After`. Do not retry validation or authorization failures blindly.
- Connectivity state is only a reason to try. Only an HTTP response establishes API reachability.
- Trigger sync on launch, foreground resume, local mutation, manual refresh, network recovery while alive, and best-effort Android background work. Android does not guarantee immediate or exact background execution.

## Validation and security expectations

- Validate every external value on both mobile and API. The contract is authoritative for enum values, UUIDs, timestamps, page sizes, note length, and amount bounds.
- Accept an amount only when its decimal string has at most two fractional digits and maps to `1..99_999_999_999` poisha. Reject exponent notation, signs, NaN/infinity, and excess precision.
- Notes are optional, trimmed, normalized to `null` when empty, and limited to 500 Unicode code points. Categories and payers must be exact contract enum values.
- Hash PINs with Argon2id and a unique salt. Do not store or log plaintext PINs.
- Use short-lived access JWTs plus opaque, rotating, revocable refresh tokens. Store only refresh-token hashes server-side and tokens only in Android secure storage.
- Require HTTPS, validate configuration at startup, use generic login failures, rate-limit authentication and API traffic, and cap JSON body/batch/page sizes.
- Add tests for money boundaries, odd-poisha splits, date-range boundaries, duplicate mutation delivery, lost responses, pagination, version conflicts, tombstones, refresh rotation/reuse, and server-wins reconciliation.

## Scope boundaries

In scope: login for the two fixed members, dashboard/date ranges/settlement, add/view/edit/soft-delete expenses, offline local operation, and synchronization.

Out of scope: budgets, custom split percentages, receipts, notifications, recurring expenses, bank integration, iOS, web administration, public registration, new members, or multiple households.
