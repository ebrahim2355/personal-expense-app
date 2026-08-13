# Product specification

## 1. Product summary

This product is a private Android expense ledger for one household with exactly two members, Sumon and Ebrahim. Either member can sign in, and both see the same expenses. The app is local-first: reads and writes use the on-device database, the UI changes immediately, and synchronization reconciles the device with the API when HTTP access is available.

All values are in Bangladeshi taka (BDT). The stored unit is integer poisha (`100 poisha = ৳1.00`). Floating-point money calculations are forbidden.

## 2. Product boundaries

### In scope

- PIN login for the two pre-provisioned members, with no public registration.
- Dashboard totals and settlement for a selected date range.
- Add, view, edit, and soft-delete an expense.
- Select either member as payer; default to the signed-in member.
- Offline use after the first successful login/bootstrap, immediate local updates, manual refresh, and automatic/best-effort sync triggers.
- A visible but unobtrusive offline/pending state and a brief message when a conflict is resolved with server data.

### Out of scope

- Budgets, configurable split percentages, receipts, notifications, recurring expenses, bank integrations, iOS, web administration, public registration, additional members, and additional households.

## 3. Definitions

- **Member:** one of `SUMON` or `EBRAHIM`, displayed as “Sumon” or “Ebrahim”.
- **Paid:** the sum of expenses for which the member is the payer.
- **Allocated:** the member's sum of per-expense 50/50 shares, including the payer remainder rule.
- **Balance:** `paid - allocated`. A positive balance is money owed to that member.
- **Active expense:** an expense whose `deletedAt` is `null`.
- **Selected range:** a half-open interval `[startInclusive, endExclusive)` based on calendar boundaries in `Asia/Dhaka`.
- **Pending:** committed to the local database but not yet acknowledged by the server.

## 4. User stories

### Authentication

- As Sumon or Ebrahim, I can select my name and enter my PIN so that I access the shared household data.
- As a signed-in member, I can reopen the app without losing offline access to already cached data when the API is temporarily unreachable.
- As a signed-in member, I can log out, which removes credentials from Android secure storage and locks the app until another successful login.
- As the household owner, I cannot create public accounts from the app; member credentials are provisioned operationally.

The first login on a new installation requires an HTTP connection because the server must verify the PIN and provide the first data snapshot. After a prior authenticated session, an expired access token does not prevent local reads/writes while offline; synchronization pauses until refresh succeeds. A definitive server authentication rejection locks the app, but durable unsynchronized household data is not silently deleted.

### Expenses

- As a member, I can add an expense with amount, category, payer, occurrence date/time, and an optional note.
- As a member, I see myself as the default payer, but I can choose the other member.
- As a member, I can see an expense immediately after saving even without network access.
- As a member, I can open and edit an active expense and see the edited values immediately.
- As a member, I can confirm deletion; it disappears from active totals/list immediately but remains a tombstone for synchronization.
- As a member, I am briefly informed if another device's newer version replaces my conflicting local edit.

### Dashboard and synchronization

- As a member, I initially see the current calendar month in `Asia/Dhaka`.
- As a member, I can select another start/end date and see locally recalculated totals.
- As a member, I can see total spend, each member's paid amount, each member's allocated share, and a single settlement statement.
- As a member, I can manually refresh and see whether changes are pending or the app is offline.
- As a member, I benefit from sync attempts on launch, foreground resume, after a mutation, manual refresh, network recovery while the app is alive, and best-effort Android background work.

Android may defer or suppress background work because of battery, network, vendor, and OS policies. The product must not promise instant background synchronization; foreground and manual sync remain authoritative user paths.

## 5. Screens and behavior

### 5.1 Session gate and login

- If no usable local session exists, show a fixed member selector (Sumon/Ebrahim), numeric PIN input, and sign-in action.
- Do not show registration, password reset, or member creation.
- Use a generic error for an incorrect member/PIN combination.
- Prevent repeated submission while a request is in flight. Rate limiting is also enforced by the API.
- If a cached session exists, open cached household data immediately and refresh credentials/synchronize opportunistically.

### 5.2 Dashboard and expense list

- Default range: start of the current month through start of the next month in `Asia/Dhaka`.
- Provide a date-range control. A user-selected end date is presented inclusively, then converted internally to the next local-day boundary for the exclusive endpoint.
- Show, from active local expenses in the range:
  - total spent;
  - Sumon paid;
  - Ebrahim paid;
  - Sumon allocated;
  - Ebrahim allocated;
  - settlement text.
- Show active expenses in reverse occurrence order with formatted amount, category, payer, occurrence date, and note preview when present.
- Provide add, tap-to-view/edit, pull/manual refresh, pending-sync indicator, and offline/sync-error feedback.
- An empty range shows zero-valued totals, “Settled up”, and an empty-state message.

### 5.3 Add/edit expense

- Required fields: amount, category, payer, and occurrence date/time.
- Optional field: note.
- Defaults on add: signed-in member as payer, current date/time in `Asia/Dhaka`, no category preselected unless the UI clearly requires a user choice, and empty note.
- Display an existing active expense's fields on edit.
- Parse and validate before committing. A successful save is one local database transaction containing the optimistic expense projection and its outbox mutation.
- Disable duplicate save taps while the local transaction is in progress. Returning to the dashboard shows the local result immediately.

### 5.4 Expense view and deletion

- A view may share the edit screen but must show amount, category, payer, occurrence date/time, note, and pending/synced state.
- Deletion requires confirmation naming the expense amount/category or occurrence date.
- Confirmed deletion writes a local tombstone and outbox mutation in one transaction. Deleted items are excluded from normal lists and calculations.

### 5.5 Conflict and sync feedback

- A version conflict replaces the optimistic local expense with the server snapshot (including a server tombstone), removes the conflicting and dependent queued mutations for that expense, and shows a short message such as “Expense changed on another device. Latest version kept.”
- A transient sync failure leaves local changes pending and does not block local work.
- A server validation rejection marks the affected item as needing attention and shows an actionable error; it must not be retried indefinitely.
- Connectivity status can trigger an attempt, but the UI calls the service reachable only after an HTTP success.

## 6. Expense fields and validation

The public expense shape is:

| Field | Ownership | Validation and behavior |
| --- | --- | --- |
| `id` | Client on create | UUID; stable for the lifetime of the expense and tombstone. |
| `amountMinor` | Client value | Integer poisha in `1..99_999_999_999`; JSON safe integer; PostgreSQL `BIGINT`. |
| `category` | Client value | Exactly one of `GROCERIES`, `UTILITIES`, `TRANSPORT`, `HOUSEHOLD`, `MEDICINE`, `OTHER`. |
| `payer` | Client value | Exactly `SUMON` or `EBRAHIM`; defaults to the logged-in member only when adding. |
| `occurredAt` | Client value | A valid RFC 3339 instant with an explicit offset; normalized to UTC for storage. UI entry/display uses `Asia/Dhaka`. |
| `note` | Client value | Optional; trim surrounding whitespace; empty becomes `null`; at most 500 Unicode code points. |
| `version` | Server | Positive integer, starts at 1, increments by exactly one for each accepted edit or deletion. |
| `updatedAt` | Server | RFC 3339 UTC instant assigned for each accepted create/edit/delete. |
| `deletedAt` | Server | `null` for active data; server-assigned RFC 3339 UTC instant for a soft deletion. |

Mobile and API validation must agree with `packages/contracts/openapi.yaml`. The API still validates all values even when the mobile form has already done so.

### Amount entry and display

- Accept ordinary unsigned decimal input with at most two fractional digits, for example `1`, `1.2`, or `1.20`.
- Reject empty input, zero, negatives, explicit plus signs, exponent notation, more than two decimal places, non-digits, NaN/infinity, and values above the maximum.
- Convert with string operations: whole taka times 100 plus the right-padded two-digit poisha portion.
- Format with integer division/remainder and exactly two digits after the decimal point, for example `40000` poisha as `৳400.00`. Grouping separators are display-only.

### Range validation

- Both calendar dates are required and the displayed end date must not precede the start date.
- Convert local day/month boundaries using an IANA time-zone implementation for `Asia/Dhaka`; do not hard-code a UTC offset into domain logic.
- Filter by `occurredAt >= startInclusive && occurredAt < endExclusive` and `deletedAt == null`.

## 7. Split and settlement formulas

For every expense, let `A` be its positive integer amount in poisha:

```text
lowerHalf = A ~/ 2
remainder = A % 2
payerAllocated = lowerHalf + remainder
otherAllocated = lowerHalf
```

Equivalently, the payer receives `ceil(A / 2)` and the other member receives `floor(A / 2)`, implemented only with integers.

For a range:

```text
total = sum(expense.amountMinor)
sumonPaid = sum(amount where payer == SUMON)
ebrahimPaid = sum(amount where payer == EBRAHIM)
sumonAllocated = sum(the per-expense Sumon allocation)
ebrahimAllocated = sum(the per-expense Ebrahim allocation)

sumonBalance = sumonPaid - sumonAllocated
ebrahimBalance = ebrahimPaid - ebrahimAllocated
```

The invariants are:

```text
sumonPaid + ebrahimPaid == total
sumonAllocated + ebrahimAllocated == total
sumonBalance + ebrahimBalance == 0
```

Settlement text:

- `sumonBalance > 0`: “Ebrahim owes Sumon {abs(sumonBalance)}”.
- `sumonBalance < 0`: “Sumon owes Ebrahim {abs(sumonBalance)}”.
- `sumonBalance == 0`: “Settled up”.

All interpolated amounts use BDT formatting.

### Worked example: even amounts and settlement

Within the range, Sumon paid `100000` poisha (`৳1,000.00`) and Ebrahim paid `20000` poisha (`৳200.00`). Both expenses are even.

```text
total = 120000
sumonAllocated = 60000
ebrahimAllocated = 60000
sumonBalance = 100000 - 60000 = 40000
ebrahimBalance = 20000 - 60000 = -40000
```

The dashboard says: **“Ebrahim owes Sumon ৳400.00”.**

### Worked example: odd poisha paid by Sumon

For one expense of `101` poisha (`৳1.01`) paid by Sumon:

```text
lowerHalf = 101 ~/ 2 = 50
remainder = 101 % 2 = 1
sumonAllocated = 51
ebrahimAllocated = 50
sumonBalance = 101 - 51 = 50
```

The dashboard says: **“Ebrahim owes Sumon ৳0.50”.** The extra poisha belongs to Sumon's own allocated share, not Ebrahim's.

### Worked example: odd poisha paid by Ebrahim

For the same `101` poisha expense paid by Ebrahim, Ebrahim is allocated `51`, Sumon is allocated `50`, and the dashboard says **“Sumon owes Ebrahim ৳0.50”.** This demonstrates why range allocation must sum each expense rather than simply halve the range total.

## 8. Acceptance criteria

### Authentication and security

- Only Sumon and Ebrahim can be selected; there is no registration route or screen.
- Correct PIN login returns a short-lived access token and rotating refresh token; incorrect credentials return a generic response and are rate-limited.
- PIN hashes use Argon2id; plaintext PINs and tokens do not appear in the database, application logs, or Drift.
- Android tokens are held in secure storage and all production API traffic uses HTTPS.
- A previously authenticated user can read and mutate cached data offline; a first installation explains that initial sign-in requires connectivity.

### Expense behavior

- A valid add/edit/delete is visible from local data before any HTTP request completes.
- Payer defaults to the logged-in member on add and can be changed to either member.
- Invalid amounts, enums, timestamps, UUIDs, notes, or ranges are rejected locally and by the API.
- A deletion immediately removes the item from active views/totals while retaining a versioned local/server tombstone.
- Repeated delivery of one mutation UUID cannot apply the mutation twice.

### Dashboard correctness

- At launch the range is the current `Asia/Dhaka` calendar month, independent of device UTC offset.
- Totals include only active expenses whose occurrence instant is inside the half-open selected range.
- The even and odd worked examples above pass as pure unit tests, including all balance invariants.
- No production money path uses floating-point arithmetic.

### Synchronization

- Sync is attempted on launch, foreground resume, after mutation, manual refresh, network recovery while alive, and eligible best-effort Android background work.
- Failed/transient requests preserve the outbox and retry with bounded exponential backoff and jitter.
- A lost response followed by the same mutation UUID returns the original result without another write.
- Bootstrap and change feeds can span pages without gaps; the cursor is saved only with the same transaction that applies its page.
- Remote soft deletes reach offline devices as tombstones.
- On an optimistic-version conflict, server data wins locally and the user sees a brief conflict message.
- The app never treats a connectivity signal alone as proof that the API is reachable.
