# Architecture

## 1. Decision summary

- Monorepo with `apps/api`, `apps/mobile`, `packages/contracts/openapi.yaml`, and `docs`.
- Node.js/TypeScript/Express API deployed as one Railway service, backed by Railway PostgreSQL and Prisma migrations.
- Flutter Android client using Riverpod, Drift/SQLite, Dio, Android secure storage, connectivity signals, app lifecycle hooks, and WorkManager-based best-effort background work.
- Local-first reads and writes. The API is a synchronization/authentication boundary, not the source for rendering each screen.
- Client-generated expense UUIDs, unique mutation UUIDs, durable outbox, server receipts for idempotency, optimistic versions, append-only change sequence, opaque cursors, paginated bootstrap/delta feeds, and persistent tombstones.
- Integer poisha throughout. PostgreSQL uses `BIGINT`, TypeScript domain/data code uses `bigint`, OpenAPI uses a bounded JSON integer, and Dart uses `int`.
- A single fixed household with the two member keys `SUMON` and `EBRAHIM`. No registration/member-management endpoint exists.

## 2. System topology

The Android app reads and writes its Drift database even when offline. Dio calls the public Railway HTTPS API only from the sync and authentication layers. The API validates the OpenAPI-defined payloads, authenticates access, applies mutations transactionally through Prisma, and writes PostgreSQL change-log/idempotency records. Railway runs committed migrations before a new API release receives traffic.

```text
Flutter UI/Riverpod
        |
application services and serialized sync coordinator
        |
Drift/SQLite + durable outbox     Android secure storage
        |                                  |
        +------------ Dio/HTTPS -----------+
                           |
                  Express API on Railway
                           |
                Prisma + Railway PostgreSQL
```

Android background scheduling is opportunistic. WorkManager can request a network-constrained sync, but Android can delay, group, or cancel it. Launch, foreground, mutation, manual refresh, and live network-recovery triggers provide the reliable next opportunity.

## 3. Code and responsibility boundaries

### API

- `config`: parse and fail fast on environment configuration.
- `http`: Express setup, routes, authentication middleware, request IDs, error mapping, body limits, and rate limits.
- `domain`: money constraints, expense rules, version decisions, auth/session policy, and sync result types. It must not depend on Express or Prisma types.
- `application`: login/refresh/logout, mutation processing, bootstrap, and change-feed use cases.
- `infrastructure`: Prisma repositories, transactions, cryptography, JWTs, clock, and logging.
- `generated`: contract-generated types, if used. Generated files are not manually edited.

The API does not calculate the dashboard for the mobile client. Dashboard calculation is local so it remains available offline. The API owns authentication, validation, canonical versions/timestamps/tombstones, mutation idempotency, and the ordered change feed.

### Mobile

- `features`: login, dashboard, expenses, and sync-facing presentation code.
- `domain`: expense/member/category models plus pure amount, split, settlement, and range functions.
- `data/local`: Drift tables, DAOs, transactions, and migrations.
- `data/remote`: Dio setup and generated/contract-aligned DTO mapping.
- `sync`: triggers, single-flight coordinator, outbox state machine, bootstrap/pull/push, retry policy, and conflict events.
- `security`: access/refresh tokens and session identity via Android secure storage. No tokens are stored in Drift.

Riverpod providers expose application services and reactive Drift queries. Widgets do not call Dio directly and do not implement split/sync rules.

### Contract

`packages/contracts/openapi.yaml` is the sole HTTP schema and endpoint contract. It defines casing, enums, error codes, bounds, authentication, pagination, and examples. Architecture prose explains intent but does not override that file. CI must lint it and verify generated artifacts are current before API/mobile code merges.

## 4. Canonical data model

Names below are logical; Prisma naming may use conventional singular model names and mapped PostgreSQL table names.

### `Household`

- `id UUID` primary key.
- `name` operational label.
- `createdAt TIMESTAMPTZ`.

Exactly one row is provisioned. Every household-owned query still includes `householdId` to avoid accidental cross-scope access and to make token authorization explicit.

### `Member`

- `id UUID` primary key.
- `householdId UUID` foreign key.
- `key MemberKey` where the enum is `SUMON | EBRAHIM`.
- `displayName` fixed to `Sumon | Ebrahim`.
- `pinHash` Argon2id encoded hash.
- `createdAt`, `updatedAt`, optional `disabledAt` as `TIMESTAMPTZ`.
- Unique `(householdId, key)`.

Migrations create the household/member identities, while a one-time operational command reads PINs from secure input, hashes them, and sets `pinHash`. Plain PINs never enter seed files, migrations, source control, command output, or logs. There is no route to insert a third member.

### `Expense`

- `id UUID` primary key, supplied by the client.
- `householdId UUID` foreign key.
- `amountMinor BIGINT`, checked to `1..99_999_999_999`.
- `category Category` enum: `GROCERIES | UTILITIES | TRANSPORT | HOUSEHOLD | MEDICINE | OTHER`.
- `payerId UUID` foreign key to a member in the same household; the API maps it to the public `payer` member key.
- `occurredAt TIMESTAMPTZ`.
- `note VARCHAR(500 code points maximum at validation)` nullable. Database character length is a defense-in-depth check where practical.
- `version INTEGER`, starts at 1 and increments once per accepted update/delete.
- `updatedAt TIMESTAMPTZ`, server-assigned.
- `deletedAt TIMESTAMPTZ` nullable, server-assigned on delete.
- `lastChangeSequence BIGINT`, the sequence of its newest committed change.
- Indexes on `(householdId, occurredAt)`, `(householdId, lastChangeSequence)`, and payer as query evidence requires.

`occurredAt` is authored by the client as an explicit-offset RFC 3339 instant. `updatedAt`, `deletedAt`, version, and change sequence are authored only by the server. Baseline behavior never hard-deletes an expense.

### `MutationReceipt`

- `mutationId UUID` primary key.
- `householdId UUID`, `memberId UUID`, and `entityId UUID`.
- `requestHash` of a canonical representation of operation, base version, entity ID, and payload.
- `result JSONB`, containing the original applied/conflict/rejected result.
- `createdAt TIMESTAMPTZ`.

The receipt is written in the same database transaction as an accepted expense write and change-log row. Duplicate mutation ID plus the same request hash returns the stored result. Duplicate ID plus different semantics returns `409 IDEMPOTENCY_KEY_REUSED`. Receipts are retained for at least as long as any client may retry; for this small fixed household, the baseline is indefinite retention.

### `Change`

- `sequence BIGINT` monotonically increasing primary key.
- `householdId UUID`.
- `entityType`, initially only `EXPENSE`.
- `entityId UUID` and `entityVersion INTEGER`.
- `operation CREATED | UPDATED | DELETED`.
- `originMutationId UUID`.
- `snapshot JSONB`, the complete canonical expense/tombstone at this change.
- `changedAt TIMESTAMPTZ`.

The change row and expense update are atomic. An append-only log makes pagination deterministic and ensures deletions can be replayed. Change snapshots are retained indefinitely for the initial product. Any future compaction would require a new cursor generation plus forced bootstrap protocol and is not part of this milestone.

### `RefreshSession`

- `id UUID`, `memberId UUID`, and `familyId UUID`.
- `tokenHash` unique SHA-256 hash of a high-entropy opaque refresh token.
- `expiresAt`, `createdAt`, `lastUsedAt`, optional `revokedAt`.
- Optional `replacedBySessionId UUID` to track rotation.
- Minimal device metadata as needed for security investigation; never the raw token.

Refreshing rotates the token. Reuse of a revoked/replaced token revokes the whole family and requires login.

## 5. Mobile local data model

Drift holds these logical tables:

- `local_expenses`: the current UI projection, including every public expense field, last acknowledged server version, optimistic version, local sync state, and local modification time. Tombstones remain present but normal queries filter them out.
- `outbox_mutations`: mutation UUID, entity UUID, operation, base version, immutable payload, local sequence, dependency/predecessor, attempt metadata, and state (`queued`, `inFlight`, `needsAttention`).
- `sync_state`: household, bootstrap watermark/page token, last fully applied change cursor, last attempt/success timestamps, and non-secret status.

Tokens stay in Android secure storage. The selected authenticated member identity may be cached alongside the secure session metadata; it is not trusted for API authorization.

A local create uses optimistic version 1 with `baseVersion = 0`. A local edit/delete uses the projection's optimistic version as its base and advances the projection by one. Mutations for one entity are ordered. Before its first attempt a queued mutation may be replaced/coalesced only if no request could have left the device; once an attempt begins its semantic payload is immutable. A later edit becomes a dependent mutation and is not sent until its predecessor is acknowledged.

The local expense projection and outbox append/update occur in one Drift transaction. This guarantees that visible local state always has durable sync intent.

## 6. API boundary

All routes are under `/v1` except health endpoints. Exact schemas and status codes belong in OpenAPI.

### Authentication routes

- `POST /v1/auth/login`: member key and PIN; returns member/session data, a short-lived access JWT, and opaque refresh token.
- `POST /v1/auth/refresh`: rotates a valid refresh token and returns a new access/refresh pair.
- `POST /v1/auth/logout`: revokes the presented refresh session; idempotent from the user's perspective.
- `GET /v1/auth/me`: returns the authenticated fixed member/household identity.

### Synchronization routes

- `GET /v1/sync/bootstrap?limit=&pageToken=`: paginated current snapshot for a device with no cursor.
- `GET /v1/sync/changes?cursor=&limit=`: ordered changes strictly after a cursor.
- `POST /v1/sync/mutations`: bounded batch of expense create/update/delete mutations.

The app does not need separate online-only expense CRUD or dashboard endpoints. All expense writes use the mutation endpoint and all server-to-client state uses bootstrap/changes, preventing parallel undocumented shapes.

### Operations routes

- `GET /health/live`: process is running; no database claim.
- `GET /health/ready`: configuration is valid and the database is reachable.

Health responses reveal no secrets or detailed database errors.

## 7. Authentication and authorization flow

1. The user selects `SUMON` or `EBRAHIM` and submits a 6–12 digit PIN over HTTPS.
2. The API applies both per-IP and per-member-key login rate limits and returns the same failure shape for unknown/incorrect credentials.
3. The API verifies the Argon2id hash and issues an access JWT of about 10 minutes plus a random 256-bit refresh token with a bounded lifetime.
4. The access JWT contains issuer, audience, subject/member ID, household ID, member key, issued/expiry times, and a unique token ID. It contains no PIN or refresh token.
5. The mobile client stores tokens in Android secure storage and keeps access tokens out of logs and SQLite.
6. A Dio interceptor attaches the access token. On one `401 TOKEN_EXPIRED`, a single-flight refresh occurs; concurrent requests wait. The original request is retried once only after successful rotation.
7. The server stores the new refresh hash and revokes/replaces the old session atomically. Detected old-token reuse revokes the token family.
8. Logout revokes the refresh session, clears secure credentials, and locks local UI. A definitive refresh rejection does the same. Transient HTTP absence does not log the user out.

Every sync query is scoped from authenticated JWT claims, never from a client-supplied household/member identity. Payer remains selectable as either fixed member because it is expense data, not authorization impersonation.

Use Argon2id with parameters benchmarked for the Railway service, unique salts, and an optional server pepper held in Railway secrets. JWT keys/secrets, database URLs, and token hashes are never committed. Express should use a strict proxy configuration for Railway, security headers, JSON size limits, schema validation, parameterized database access through Prisma, and structured redacted logs. A native mobile client does not justify permissive browser CORS.

## 8. Synchronization contract

The following is the intended OpenAPI shape; names and constraints must be copied into the contract before implementation.

### Mutation request

```json
{
  "mutations": [
    {
      "mutationId": "UUID",
      "entityId": "UUID",
      "operation": "CREATE | UPDATE | DELETE",
      "baseVersion": 0,
      "expense": {
        "amountMinor": 101,
        "category": "GROCERIES",
        "payer": "SUMON",
        "occurredAt": "2026-08-13T08:30:00+06:00",
        "note": "Milk"
      }
    }
  ]
}
```

`CREATE` requires `baseVersion = 0` and a complete client-editable expense payload. `UPDATE` requires a positive base version and a complete replacement payload. `DELETE` requires a positive base version and no expense payload. Batches are capped (initially 50) and processed in listed order. The client sends only dependency-ready mutations and keeps per-entity order.

### Mutation response

```json
{
  "results": [
    {
      "mutationId": "UUID",
      "status": "APPLIED | CONFLICT | REJECTED",
      "code": "VERSION_CONFLICT",
      "expense": {
        "id": "UUID",
        "amountMinor": 101,
        "category": "GROCERIES",
        "payer": "SUMON",
        "occurredAt": "2026-08-13T02:30:00Z",
        "note": "Milk",
        "version": 2,
        "updatedAt": "2026-08-13T02:31:00Z",
        "deletedAt": null
      }
    }
  ]
}
```

- `APPLIED` includes the new canonical expense/tombstone.
- `CONFLICT` includes the current canonical expense/tombstone and a stable error code.
- `REJECTED` includes a stable, safe validation/business code and field details where useful. A rejected create may have no canonical expense.
- Envelope/auth failures use normal HTTP errors. A valid batch can return item-level results.

The server authenticates and validates the envelope, canonicalizes/hash-checks each mutation, then for each new mutation transactionally:

1. Locks or conditionally updates the target state.
2. Requires absent entity plus base 0 for create, or exact current `version == baseVersion` for edit/delete.
3. On success assigns version/timestamps, preserves a tombstone on delete, appends a change with `originMutationId`, and stores the `APPLIED` receipt.
4. On mismatch stores and returns a `CONFLICT` receipt with the current server snapshot.
5. On a semantic rejection stores a stable `REJECTED` receipt so blind retries cannot change the result.

If the database commits but the HTTP response is lost, resending the same mutation returns its receipt without a second write. The corresponding change's `originMutationId` also lets a pulling client acknowledge its outbox record safely.

### Bootstrap response

```json
{
  "items": ["complete canonical expense or tombstone"],
  "watermarkCursor": "opaque",
  "nextPageToken": "opaque-or-null"
}
```

On the first page, the server captures the household's current maximum change sequence as the watermark. Pages return expenses whose `lastChangeSequence` is at or before that watermark, ordered by stable expense UUID. The opaque page token carries the watermark and last key and is authenticated/validated by the server. An expense changed after the watermark is omitted from remaining snapshot pages and arrives through the subsequent delta feed.

The client applies each page transactionally and stores bootstrap progress, but it does not install the watermark as its normal cursor or declare bootstrap complete until every page succeeds. It then sets the cursor to the watermark and immediately drains `/changes` to capture writes that occurred during bootstrap. Duplicate/newer snapshots are safe because application is version-aware. If bootstrap is interrupted, the saved page token resumes the same watermark; an invalid/expired token restarts bootstrap safely.

### Change response

```json
{
  "changes": [
    {
      "cursor": "opaque",
      "entityType": "EXPENSE",
      "originMutationId": "UUID",
      "expense": "complete canonical expense or tombstone"
    }
  ],
  "nextCursor": "opaque",
  "hasMore": false
}
```

`cursor` is an opaque household-scoped encoding of the monotonic sequence. Default page size is 100 and maximum is 500. Changes are ordered by sequence. In one Drift transaction the client applies versions/tombstones, acknowledges matching origin mutation IDs, and advances to `nextCursor`. A crash before commit repeats the page; a crash after commit resumes after it. When `hasMore` is true, pull the next page immediately. Empty responses retain a valid cursor.

## 9. Sync coordinator and reconciliation

Only one sync run may execute at a time. Additional triggers coalesce into one follow-up run.

For a normal established device:

1. Ensure an access token or attempt one refresh. Treat no HTTP response as transient, not as logout.
2. Pull all change pages from the durable cursor. Apply a newer remote version directly when no local chain conflicts.
3. If an incoming remote version advances beyond a queued mutation's base, server data wins: apply it, remove that mutation and its dependent chain, and emit one brief conflict event.
4. Push bounded batches containing only the head/dependency-ready mutation for each entity, ordered by local sequence.
5. Apply each result in one local transaction. `APPLIED` replaces the projection with canonical data and releases its next dependent mutation. `CONFLICT` replaces it with server data and discards its chain. `REJECTED` stops retries and marks it for user attention.
6. Pull to exhaustion again so the cursor includes the client's own writes and any concurrent writes.

For a new device, bootstrap replaces step 2 before any ordinary change cursor exists. A new installation normally has no outbox; if local state restoration ever creates that condition, bootstrap completes before pushing so unknown server entities are not overwritten.

Incoming snapshots are applied only when their version is newer than the acknowledged canonical version, except a matching origin mutation may also confirm an in-flight optimistic version. Tombstones use the same version logic as active rows.

### Retry policy

- Retry no-response/network failures, timeouts, `408`, `429`, and selected `5xx` responses.
- Use bounded exponential backoff with jitter, persist attempt timing, cap background attempts, and honor `Retry-After`.
- A manual/foreground trigger may request an immediate new attempt but still respects an active server rate-limit window.
- Refresh once for an expired access token. Do not loop on `401/403`.
- Do not blindly retry `400/404/409 idempotency misuse/422`; map them to contract/configuration or item attention states.
- Reset backoff after a successful authoritative HTTP exchange.

Connectivity events merely wake the coordinator. DNS, captive portals, TLS, proxy, and server failures are decided by Dio/HTTP results.

## 10. Conflict behavior

The API never merges fields. An update or delete applies only against the exact base version. Any mismatch returns the current complete server representation.

On either a push conflict or a newer pulled change that invalidates a pending chain:

- replace the local projection with the server active row or tombstone;
- delete/mark resolved the conflicting mutation and all dependent mutations for that expense;
- keep unrelated entity mutations;
- recalculate reactive dashboard data;
- display one short, non-blocking conflict message.

Examples:

- Both devices edit version 3. The first accepted mutation creates version 4. The second receives version 4 as conflict data and discards its edit.
- One device deletes version 5 while another edits version 5. Whichever reaches the server first creates version 6; the other receives either the tombstone or active edit as the winning version.
- An applied response is lost. Retry with the same mutation UUID returns the stored applied version; it is not a conflict and does not increment twice.

## 11. Time, money, and dashboard architecture

- Parse entered BDT with a strict decimal-string parser and construct poisha through integer operations.
- Serialize `amountMinor` as a JSON integer restricted below JavaScript's safe-integer ceiling; immediately convert to `bigint` in API domain/data code. Reject unsafe or non-integer JSON values before conversion.
- Convert Prisma `BIGINT` explicitly at HTTP boundaries; never allow `JSON.stringify` to handle a raw JavaScript `bigint`.
- In Dart use `int` and integer division/modulo. No `double` enters amount parsing, storage, split, aggregation, or display.
- Store instants in UTC in PostgreSQL/Drift. Use an IANA time-zone library to construct Dhaka month/day boundaries, then compare instants with `[start, end)` semantics.
- Dashboard Drift queries exclude tombstones and return integer sums. A pure domain function calculates per-expense allocations and settlement; do not infer both allocations from one rounded aggregate half.

## 12. Deployment and operations

### Railway

- One API service built from `apps/api` and one managed PostgreSQL database.
- Build runs dependency install, OpenAPI validation/type generation, TypeScript build, and Prisma client generation.
- A release/pre-deploy command runs `prisma migrate deploy`; application startup does not create schema ad hoc.
- Readiness verifies a bounded database query. Railway HTTPS is mandatory; configure Express's trusted proxy to Railway's documented hop topology before deriving client IP or secure cookies/headers.
- Use a production start command against compiled JavaScript, graceful shutdown, connection limits appropriate to the Railway plan, and automated database backups/restore drills.

Required secrets/configuration include `DATABASE_URL`, JWT issuer/audience/signing material, refresh-token lifetime, optional PIN pepper, allowed public API origin/base URL metadata, log level, and rate-limit settings. Validate all at startup. One-time PIN provisioning values are removed after provisioning.

### Android configuration

- Build-time API base URL points to the Railway HTTPS host; release builds reject cleartext traffic.
- Secure storage holds credentials. Drift holds shared expense/cache/outbox data.
- WorkManager requests network connectivity and invokes the same serialized sync coordinator used in foreground; it has no separate sync rules.
- Lifecycle resume and connectivity subscriptions exist only while the app process is alive and are disposed correctly.

## 13. Verification strategy

- Shared contract examples and generated-type drift checks.
- Pure unit tests for amount parsing/formatting, maximum values, even/odd splits, settlement direction, and Dhaka range edges.
- API unit/integration tests against PostgreSQL for validation, authorization scoping, Argon2 verification, refresh rotation/reuse, mutation idempotency, conditional versions, transaction rollback, tombstones, bootstrap, and cursor paging.
- Drift tests for atomic projection/outbox writes, page/cursor transactions, duplicate application, dependent mutations, and conflict replacement.
- End-to-end sync tests with two logical devices for concurrent update/update, update/delete, offline mutation chains, response loss, restart mid-page, token expiry, rate limiting, and eventual convergence.
- Android integration checks for secure storage, resume trigger, manual refresh, network recovery trigger, and WorkManager registration. Tests must not claim deterministic WorkManager timing.
