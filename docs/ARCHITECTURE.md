# Architecture

## 1. Implemented v1 topology

```text
Flutter Android (Riverpod, Drift, Dio, secure storage)
        | local-first UI and durable outbox
        | HTTPS + bearer JWT
        v
Express 5 / TypeScript API on Railway
        | Prisma 7 + PostgreSQL driver adapter
        v
Railway PostgreSQL
```

The API is the authentication and canonical synchronization boundary. Flutter
renders from Drift and will compute dashboard totals locally, so expense data
remains available offline. There is no server summary endpoint and no server
search endpoint; history search runs against local rows.

The repository's only HTTP contract is
`packages/contracts/openapi.yaml`. Route code validates with Zod but must stay
behaviorally identical to that contract.

## 2. Backend boundaries

- `src/config`: environment validation and production proxy/origin rules.
- `src/domain`: fixed enums, integer money bounds/split rules, transport-neutral
  models, validation, and stable application errors.
- `src/application`: authentication/session and synchronization use cases.
- `src/infrastructure`: Prisma/PostgreSQL, token/cursor cryptography, and safe
  structured logging.
- `src/http`: Express middleware, health/auth/sync routes, request IDs, rate
  limits, and centralized errors.
- `prisma`: PostgreSQL schema and committed migrations.
- `scripts/bootstrap.ts`: explicit, idempotent fixed-household/member
  provisioning from environment PINs.
- `test/integration`: tests against actual PostgreSQL behavior.

Express and Prisma types do not leak into the public domain model. API request
bodies are reconstructed from Zod-validated fields; there is no mass assignment.

## 2.1 Implemented mobile data boundaries

- `lib/src/domain`: immutable expense/period/loan/session models and exact
  wire-enum mappings. `amountMinor` is a Dart `int` holding a whole number of
  taka in poisha; no money path uses `double`.
- `lib/src/data/local`: Drift tables, generated database code, row/domain
  mapping, and explicit schema migration strategy.
- `lib/src/data/remote`: contract DTOs, Dio transport, error classification,
  and an authenticated request client.
- `lib/src/data/security`: token-store abstraction and Android secure-storage
  implementation. Tokens never enter Drift or ordinary preferences.
- `lib/src/data/repositories`: UI-facing expense/period/loan/authentication
  operations, plus the shared local-mutation event type all three ledgers
  announce writes on.
- `lib/src/application`: session state, serialized sync, conflict notices, and
  launch/resume/mutation/manual/connectivity triggers.
- `lib/src/notifications`: the activity notifier interface the coordinator
  depends on, pure title/body wording, the `flutter_local_notifications`
  presenter, the permission wrapper, and the `firebase_messaging` wrapper that
  supplies the token and the arrival stream. Only the presenters and the wrappers
  touch a plugin, so wording and the sync path stay testable without Android.
- `lib/src/presentation`: Material 3 login, dashboard, add/edit, lending,
  history, settings, reusable expense/loan/sync widgets, and Riverpod view
  state. Widgets use repository/domain abstractions and primitive status
  streams rather than Drift rows or Dio.
- `lib/src/background`: network-constrained, best-effort Android WorkManager
  scheduling and headless synchronization, on a fifteen-minute period. One
  `runBackgroundSync` body serves both headless entry points — the WorkManager
  dispatcher and the FCM background handler — so a pushed wake and a scheduled
  poll do identical work. Each entry point builds its own database, sync, and
  notification objects, because a background isolate shares nothing with the UI
  isolate. It also holds the app's only platform channel,
  `BackgroundWorkPolicy`, which reads and asks for Android's
  battery-optimization exemption. That channel is hosted by `MainActivity`, so it
  is usable **only from the UI isolate** — neither headless entry point has a
  handler on the other end and neither must ever call it.
- `lib/src/providers.dart`: Riverpod dependency graph. Widgets consume domain
  streams and application services, never raw Drift or Dio objects.

The local schema has five tables:

1. `local_expenses` stores server-compatible fields including the owning
   `period_id`, the authoritative server version/timestamps when known, a local
   modification instant, soft deletion, and `SYNCED`, `PENDING`, or
   `NEEDS_ATTENTION` projection state. `period_id` is nullable, because a device
   can record an expense before its first bootstrap knows a period.
2. `local_periods` stores the period UUID, sequence number, opened instant,
   nullable closed instant, optional note, server version/timestamps, and
   projection state. It has no soft-delete column.
3. `local_loans` stores the entry UUID, debtor member key, whole-taka amount,
   client-stamped instant, optional note, server version/timestamps, soft
   deletion, and projection state.
4. `outbox_mutations` stores an auto-incrementing local order, unique mutation
   UUID, entity UUID, entity type, action, base version, frozen JSON payload,
   creation time, attempt count/times, retry deadline, last error code, and
   status. `entity_type` defaults to `EXPENSE`, so a row queued before periods
   and loans existed still names the right entity after an upgrade.
5. `sync_metadata` is a singleton holding household/member identity, the last
   committed opaque cursor, resumable bootstrap token/watermark, the last
   successful full-sync instant used by the UI, the instant the notification
   permission was requested, whether household-activity announcements are
   enabled, the instant the battery-optimization exemption was asked for, the
   instant the background isolate last completed a run, a fingerprint of the FCM
   token last registered with the API, when that registration succeeded, and when
   a push last woke this device. It does not hold access or refresh tokens, and it
   never holds the FCM token itself — only a SHA-256 digest of it, which is enough
   to tell an unchanged token from a rotated one without storing an address.

   The last five all start null, and null is the honest answer in each case: the
   exemption has not been asked for on this install, no background run has been
   observed, nothing has been registered, and no push has ever arrived.
   `last_background_sync_at` is distinct from the full-sync instant
   because any foreground sync moves that one; only this column can answer
   whether Android is letting closed-app delivery happen at all, so the
   background dispatcher writes it for every outcome, an offline one included.
   `last_push_received_at` is the one value that separates a working push from a
   well-timed poll, which is why it is stored and shown rather than inferred.

Create/edit/delete writes the projection and outbox in one SQLite transaction,
then emits a trigger after commit. Closing a spending period is one transaction
holding the close update, the next period's insert, and both outbox rows, with
the close queued first so the server never sees two open periods. Sync claims at
most the earliest unresolved mutation per entity, keyed by entity type and
entity UUID, allowing independent entities in one server batch while preserving
per-entity dependencies. An accepted result deletes its receipt and rebases the
next local mutation. A conflict deletes that entity's dependent outbox chain,
stores the returned server snapshot/tombstone, and emits a UI notice naming the
entity type. Validation/protocol failures stop blind retries; transient
HTTP/network failures persist capped exponential backoff with jitter and honor
`Retry-After`.

A 401 causes one single-flight refresh-token rotation and exactly one retry of
the original request. A failed refresh clears secure tokens and moves session
state to signed out without deleting expenses, periods, loans, sync metadata, or
outbox rows.

## 3. Canonical PostgreSQL model

### `Household`

- UUID primary key generated by PostgreSQL.
- Unique operational `slug`, display `name`, and `createdAt TIMESTAMPTZ(3)`.
- One row is provisioned for v1. No household CRUD route exists.

### `Member`

- UUID primary key and `householdId` foreign key.
- `key` is exactly `SUMON` or `EBRAHIM`; `(householdId, key)` is unique.
- Fixed display name, Argon2id `pinHash`, timestamps, optional `disabledAt`.
- Composite `(householdId, id)` uniqueness supports same-household foreign keys.
- No PIN hash is selected into public member responses.

### `RefreshToken`

- UUID token ID and family ID, member foreign key, SHA-256 `tokenHash`.
- Expiry, last-used, revoke, and replacement timestamps/references.
- The raw 256-bit token secret exists only in the response/client secure
  storage. It is never persisted.
- Reusing a rotated/revoked token revokes remaining tokens in its family.

### `SpendingPeriod`

- Client-generated UUID primary key and authenticated `householdId`.
- `sequenceNumber INT` is unique per household and numbers the period the
  members see; `(householdId, sequenceNumber)` is unique.
- `startedAt TIMESTAMPTZ(3)`, nullable `closedAt TIMESTAMPTZ(3)`, nullable
  `note VARCHAR(500)`, positive version, server timestamps, and nonnegative
  `lastChangeSequence`.
- A partial unique index over `householdId` where `closedAt IS NULL` allows at
  most one open period per household, so two devices racing to open one cannot
  both win.
- There is no `deletedAt`. Active expenses reference the period, so a period is
  archived by closing it and never removed.
- An accepted create starts at version 1. The close is an update and increments
  exactly once.

### `LoanEntry`

- Client-generated UUID primary key and authenticated `householdId`.
- `amountMinor BIGINT` under database checks for `100..99_999_999_999` poisha
  and `amountMinor % 100 = 0`, the same whole-taka rule as an expense amount.
- A composite debtor foreign key enforcing that the debtor is in the same
  household. The creditor is the other member and is not stored.
- `occurredAt TIMESTAMPTZ(3)` assigned by the client at creation, nullable
  `note VARCHAR(500)`, positive version, server timestamps, nullable
  `deletedAt`, and nonnegative `lastChangeSequence`.
- Loans are a separate ledger. No query joins them to expenses, and no server
  code combines the two totals.
- An accepted create starts at version 1. Update/delete increment exactly once.
  Delete sets `deletedAt`; it never removes the row.

### `Expense`

- Client-generated UUID primary key and authenticated `householdId`.
- `amountMinor BIGINT` with database checks for `1..99_999_999_999` poisha and
  `amountMinor % 100 = 0`, which together make `100` the smallest storable
  amount and permit only whole taka. JSON input/output is a bounded safe
  integer; TypeScript converts to/from `bigint` only at the Prisma boundary.
- Enum category and a composite payer foreign key enforcing that the payer is
  in the same household.
- A composite `periodId` foreign key enforcing that the spending period belongs
  to the same household. The column is `NOT NULL`: an omitted wire `periodId`
  resolves to the household's open period, and a named period only has to
  exist, because an expense recorded offline before a close still belongs to the
  period it was recorded in.
- `occurredAt TIMESTAMPTZ(3)`, nullable `note VARCHAR(500)`, positive version,
  server timestamps, nullable `deletedAt`, and nonnegative
  `lastChangeSequence`.
- An accepted create starts at version 1. Update/delete increment exactly once.
  Delete sets `deletedAt`; it never removes the row.

### `ProcessedMutation`

- Client mutation UUID primary key, household/member/entity IDs, entity type,
  operation, canonical SHA-256 request hash, JSONB result, and timestamp.
- `entityType` defaults to `EXPENSE` so receipts written before periods and
  loans existed keep a correct meaning.
- Written in the same transaction as any accepted expense, period, or loan and
  its change event.
- Same UUID plus same semantics returns the stored result. Same UUID plus
  different semantics returns per-item `REJECTED/IDEMPOTENCY_KEY_REUSED`.
- Invalid operation-specific data can also receive a durable rejected
  receipt when its outer mutation identity is valid.

### `ExpenseChange`

- PostgreSQL `BIGSERIAL` sequence is the global monotonic event cursor.
- The table keeps its original name but carries the change feed for every
  synchronized entity. `entityType`, defaulting to `EXPENSE`, selects which
  snapshot shape the JSONB document holds.
- Household/entity/version, operation (`CREATED`, `UPDATED`, `DELETED`), unique
  origin mutation UUID, complete canonical JSONB snapshot, and server time.
- `actorMemberKey` names the member whose authenticated identity produced the
  change, written in the same transaction as the change itself. It is the only
  authoritative answer to "who did this", and the client's notification decision
  rests entirely on it — see [section 7](#7-pull-cursors-tombstones-and-first-device-bootstrap).
- Household queries use `sequence > decodedCursor`, ascending order, and
  `limit + 1` to calculate `hasMore`.
- A deleted snapshot is a full expense or loan tombstone with non-null
  `deletedAt`. A period change is never `DELETED`.

Sequence values may contain gaps after rolled-back PostgreSQL transactions; the
ordering is monotonic, not required to be contiguous.

## 4. Authentication and authorization

1. Login accepts only a fixed member key and a 6–12 digit PIN over HTTPS.
2. The API verifies the Argon2id hash of `PIN + PIN_PEPPER` and returns the same
   `INVALID_CREDENTIALS` response for credential failures.
3. A ten-minute access JWT is the default (`ACCESS_TOKEN_TTL_SECONDS` is bounded
   to 60–3600). Claims include issuer, audience, member subject, household ID,
   member key, expiry, and unique JWT ID.
4. The refresh credential is `tokenId.randomSecret`, opaque to the client and
   valid for a configured 1–90 days. Only its SHA-256 hash is stored.
5. Refresh rotation creates the replacement and revokes/links the old token in
   a serializable transaction. Detected old-token reuse revokes the family.
6. Logout requires an access JWT, scopes the refresh token to that member and
   household, and is idempotent from the caller's perspective.
7. Every authenticated endpoint verifies both the JWT and the enabled member
   row. Every database read/write derives household scope from that identity;
   no request accepts a household ID for authorization.

Flutter must store both tokens in Android secure storage. There is no shared API
key in the APK and no public registration/member-management route.

## 5. HTTP boundary

Operations:

- `GET /health/live`: process only, no database query.
- `GET /health/ready`: `SELECT 1`; returns 503 when PostgreSQL is unavailable.
- `GET /health`: combined process/readiness response.

Authentication:

- `POST /v1/auth/login`
- `POST /v1/auth/refresh`
- `POST /v1/auth/logout`
- `GET /v1/auth/me`

Synchronization:

- `POST /v1/sync/mutations`: 1–50 ordered mutation candidates.
- `GET /v1/sync/changes`: signed cursor and page size 1–250 (default 100).
- `GET /v1/sync/bootstrap`: signed page token and the same page bounds.

There are no parallel online CRUD shapes. Client writes to all three
synchronized entities always use the mutation route; server-to-client state
always uses bootstrap/changes. Every mutation candidate, mutation result, change
row, and bootstrap item names its `entityType`, which defaults to `EXPENSE` and
selects the single payload key that is present.

Request middleware assigns/validates `X-Request-ID`, applies Helmet, enforces
HTTPS in production behind an explicitly trusted proxy count, accepts native
Android requests without an Origin, checks configured browser origins exactly,
limits JSON bodies, and applies general and tighter auth rate limits. Central
errors return `{ error: { code, message, requestId, details? } }` and never echo
credentials or request bodies.

## 6. Mutation transaction and conflict behavior

The server processes batch items in listed order. Each item gets its own
serializable transaction so an invalid/conflicting item cannot roll back or
duplicate a valid sibling.

For one candidate:

1. Parse operation-specific rules and calculate a canonical request hash. The
   parse is selected by `entityType`, so a period payload is never read as an
   expense.
2. Look up `(mutationId, authenticated household)`. Return the stored result for
   an identical retry, or reject semantic reuse.
3. For create, require `baseVersion = 0`, a complete payload for that entity
   type, and an unused entity UUID. An expense also requires a same-household
   enabled payer, otherwise `REJECTED/PAYER_NOT_FOUND`, and a resolvable
   spending period, otherwise `REJECTED/PERIOD_NOT_FOUND`. A loan requires a
   same-household enabled debtor, otherwise `REJECTED/PAYER_NOT_FOUND`.
4. For update/delete, condition the SQL write on entity UUID, household,
   `version = baseVersion`, and `deletedAt IS NULL`. A period has no
   `deletedAt`, so its update is conditioned on version alone.
5. If the conditional write misses but the scoped entity exists, store and
   return `CONFLICT/VERSION_CONFLICT` plus the current canonical
   snapshot/tombstone. If it does not exist in that household, return
   `REJECTED/ENTITY_NOT_FOUND` without exposing another household's row.
6. On acceptance, assign server UTC timestamps/version, insert a change snapshot,
   link its sequence to the entity, and insert the processed result atomically.
7. Retry PostgreSQL serializable write conflicts (`P2034`) at most three times.

Entity-specific rules:

- An omitted expense `periodId` resolves to the household's open period. A named
  period only has to exist in the household: a closed period still accepts an
  offline-recorded expense, so a create made before a close is not lost.
- Creating a period whose `closedAt` is `null` while another open period exists
  returns `REJECTED/PERIOD_ALREADY_OPEN`. The partial unique index enforces the
  same rule when two devices race.
- Updating a period that no longer exists in the household returns
  `REJECTED/PERIOD_NOT_FOUND`, and clearing `closedAt` on a settled period
  returns `REJECTED/INVALID_MUTATION`: a period is never reopened.
- A `PERIOD` `DELETE` is always rejected. The mutation schema has no delete
  variant for periods, so it fails parsing as `REJECTED/INVALID_MUTATION` before
  any row is read.
- An amount that is not a whole number of taka is `REJECTED/INVALID_MUTATION`
  for both expenses and loans, whatever the client believed.

The mobile conflict rule is server-wins: transactionally replace Drift with the
returned snapshot/tombstone, delete the conflicting and dependent entity outbox
items, and show a brief conflict message naming the entity type. A rejected
result instead marks that one outbox row `NEEDS_ATTENTION` with its returned
code, leaves the rest of the batch alone, and is never retried.

## 7. Pull cursors, tombstones, and first-device bootstrap

Change and page tokens are opaque base64url payloads protected by HMAC-SHA256 and
scoped to the authenticated household. A token copied between households is
invalid. Clients never manufacture or compare cursor internals.

Normal pull:

1. Begin at no cursor (sequence zero) or the last transactionally persisted
   cursor.
2. Request changes and apply the full page idempotently by entity version.
3. An `originMutationId` may acknowledge an outbox row after an earlier HTTP
   response was lost.
4. Persist `nextCursor` only in the same Drift transaction as the page.
5. Continue while `hasMore`; a deleted change remains a tombstone.

First-device bootstrap:

1. Authenticate online; a new installation cannot bootstrap anonymously.
2. Call bootstrap without a page token. The API captures the household's latest
   change sequence as a watermark.
3. Consume every page. The signed page token preserves the watermark and UUID
   position. Current rows, including historical tombstones, are returned only
   when their latest sequence is at/before the watermark.
4. Persist the bootstrap dataset and watermark only after all pages are applied.
5. Pull changes strictly after the watermark. This catches any entity created or
   changed during pagination before sync is declared complete.

Connectivity state is only a trigger. HTTP success/failure is authoritative.
The mobile coordinator serializes runs, keeps frozen outbox semantics, uses
bounded exponential backoff/jitter, honors `Retry-After`, and avoids blind
retries for auth/validation failures. Android WorkManager remains best-effort;
Android cannot
guarantee immediate or exact background execution.

Notifying the other member's activity rides on this same pull, with no second
network path:

1. A change is notifiable only when it actually altered local state, only when
   the feed attributed it to a member, and only when that member differs from the
   one recorded in `sync_metadata`. Everything else resolves to silence,
   including a device with no recorded member — it has no way to recognize its
   own writes, so it announces nothing rather than announcing wrongly.
2. The comparison has to use the server's `actorMemberKey`. Acknowledging a
   pushed mutation deletes its outbox row, and the same run then pulls the change
   the server wrote for it — so by the time the change arrives, the absence of an
   outbox row says nothing about who wrote it.
3. Notifiable items accumulate inside the transaction that applies the page and
   persists the cursor, and are posted only after that transaction commits.
   Posting inside it would announce a page that may still roll back; a crash in
   the gap loses a notification instead, which is the safer failure.
4. Bootstrap applies snapshots directly and never runs this path, so a fresh
   installation is silent no matter how much history it consumes.
5. The coordinator depends on a notifier interface, not on the notification
   plugin, and awaits it. The background isolate exits the moment a run returns,
   so a stream listener could never be relied on to fire; it also builds its own
   notifier, because plugin registrations do not cross isolates.

Timeliness is a separate problem from delivery, and it is Android's to grant.
Measured on the target phone: with the app closed and the phone idle it sat in App
Standby bucket 40 (RARE) with the JobScheduler `WITHIN_QUOTA` constraint
unsatisfied, so the fifteen-minute job was deferred for hours; in active use the
same install sat in bucket 10 and ran on schedule. The power-save whitelist is the
only lever an app can pull — an app ignoring battery optimisations moves to bucket
5 (EXEMPTED), outside both Doze and the quota — so startup asks for it once,
immediately after the notification permission.

That ask follows the same rules as the permission ask, for the same reasons: gate
on the live platform answer rather than a stored flag, so an install granted the
exemption elsewhere self-heals; never record an ask whose dialog failed to launch,
because recording it would spend the prompt on something nobody saw; and never
throw, because startup must survive a platform that cannot answer. It differs in
one respect — this dialog can be re-shown, so the stored timestamp exists to avoid
nagging rather than to ration a single chance, and Settings can offer a real
button. Nothing re-reads the answer after that button: Android reports only that
the dialog opened, so a re-check is the only truthful path.

The exemption is deliberately excluded from the "will notify" decision. It governs
*when* a notification arrives, not whether it can be posted, and conflating them
would report notifications as off when they are merely late.

Two limits survive a granted exemption, and both are stated in Settings rather
than implied away. HyperOS/MIUI force-stops an app cleared from Recents, which
cancels its jobs until the app is next opened; only the OEM Autostart toggle
mitigates that and no app can read or set it. And polling alone is fifteen
minutes at best, which is what the push path below exists to shorten.

## 8. Money and time ownership

The API validates and stores canonical expense values but does not calculate a
dashboard response. Flutter sums synchronized active rows itself: the dashboard
sums the household's open spending period, and History sums the selected
`Asia/Dhaka` half-open interval when one is chosen.

Every stored amount is a whole number of taka, so `amountMinor` is always a
multiple of `100`. Poisha remains the storage unit for both entities, and both
ends reject a remainder rather than rounding it.

For expense `A` poisha, with `T = A ~/ 100` taka:

```text
lowerHalf = (T ~/ 2) * 100
payerAllocated = (T ~/ 2 + T % 2) * 100
otherAllocated = lowerHalf
```

For `10100` poisha (৳101) paid by Sumon, Sumon is allocated `5100` and Ebrahim
`5000`. Sumon's balance is `10100 - 5100 = 5000`, so the settlement is “Ebrahim
owes Sumon ৳50”. The odd taka always lands on the payer, and no split ever
produces a sub-taka figure. No JavaScript/Dart floating-point path is allowed for
money.

Loans are summed independently: the lending net total is `ebrahimOwesMinor -
sumonOwesMinor` over active loan rows, and it never moves the expense settlement
figure.

Clients send `occurredAt` with an explicit RFC 3339 offset. PostgreSQL stores the
instant as `TIMESTAMPTZ`; responses use UTC ISO timestamps. Flutter alone turns
`Asia/Dhaka` calendar boundaries into `[startInclusive, endExclusive)` instants.

## 9. Railway deployment and operations

The Railway API service builds from the monorepo root. Deploy steps are:

1. `npm ci && npm run build --workspace @expenses/api`
2. Pre-deploy `npm run prisma:migrate:deploy --workspace @expenses/api`
3. Start `npm run start --workspace @expenses/api`
4. Healthcheck `/health/ready`

The API references Railway PostgreSQL through `DATABASE_URL` on the private
network. Railway terminates public HTTPS; Express trusts the configured proxy
hop and rejects insecure production requests. `SIGTERM`/`SIGINT` stop accepting
new HTTP connections, wait for the server to close, disconnect Prisma, and have
a ten-second forced shutdown bound.

Provisioning is an explicit post-migration operational action. Initial PIN
variables must be removed from the runtime environment after successful hashing.
Migrations and provisioning never print credentials.

## 10. Required verification

The Flutter suite uses in-memory Drift and fake HTTP/sync boundaries to cover
immediate offline reads, mutation retry/idempotency, concurrent trigger
single-flight behavior, change pagination, bootstrap handoff, tombstones,
conflicts, refresh-once behavior, and local-data retention after auth/network
failure. Repository tests additionally cover period open/close bookkeeping, the
single-open-period rule, loan create/edit/delete with its own outbox entity type,
and local search over notes, categories, payers, and amounts. Pure tests cover
BDT parsing/formatting, whole-taka rejection at both bounds, odd-taka allocation,
settlement, the lending net total, and IANA `Asia/Dhaka` month/day boundaries.
Widget tests cover login errors, exact dashboard totals for the open period, the
close-period flow, the lending screen, history search, empty/small-screen states,
local add/edit/delete, duplicate submission, offline status, and server-wins
conflict feedback.
The backend suite covers login/failure/unauthorized requests, refresh rotation
and logout, validation/money boundaries including whole-taka rejection, period
create/close rules (`PERIOD_ALREADY_OPEN`, `PERIOD_NOT_FOUND`, a rejected period
delete, and no reopen), loan create/update/delete, expense-to-period assignment,
Dhaka-to-UTC boundaries, duplicate and concurrent offline creates, update/delete
propagation, stale-version conflict, cursor/bootstrap pagination for all three
entity types, tombstones, and household isolation. Integration tests require
`TEST_DATABASE_URL` for an actual disposable PostgreSQL database; SQLite is never
substituted.

The real-stack suite adds two independent file-backed Drift databases over the
production Dio/auth/sync path, the compiled Express API, and PostgreSQL 18. Its
thirteen scenarios include period-close convergence across devices, loan CRUD
across devices, and a server-side whole-taka rejection. It injects failures at
transport boundaries to prove lost-response idempotency and interrupted
cursor-page recovery without timing sleeps. Test cleanup is accepted only for an
explicitly matched `_test`/`-test` database URL. Request IDs connect mobile and
API logs; logs contain mutation IDs, statuses, cursor/page counts, and timings,
but omit credentials, Authorization headers, database URLs, and expense payloads.
Debug Settings exposes only cursor preview, pending count, last sync result, and
last success time.
