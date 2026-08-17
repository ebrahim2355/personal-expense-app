# Product specification

## 1. Product summary

This product is a private Android expense ledger for one household with exactly two members, Sumon and Ebrahim. Either member can sign in, and both see the same expenses. The app is local-first: reads and writes use the on-device database, the UI changes immediately, and synchronization reconciles the device with the API when HTTP access is available.

Shared spending is settled in spending periods rather than calendar months: a period runs until the members agree they are square, and closing it opens the next one. Money lent between the members is recorded by hand in a separate lending ledger that never moves the shared-expense settlement figure.

All values are in Bangladeshi taka (BDT). The stored unit is integer poisha (`100 poisha = ৳1`), and only whole taka are accepted, so every stored amount is a multiple of 100. No amount is ever entered or displayed with a decimal point. Floating-point money calculations are forbidden.

## 2. Product boundaries

### In scope

- PIN login for the two pre-provisioned members, with no public registration.
- Dashboard totals and settlement for the household's open spending period.
- Closing the open spending period, which archives it and opens the next one.
- Add, view, edit, and soft-delete an expense.
- Select either member as payer; default to the signed-in member.
- History over every spending period, closed ones included, with a local search over amount, note, category, and payer and optional period, payer, category, and date-range filters.
- A separate lending ledger of hand-recorded loans between the two members, with its own net total, its own search, and add/edit/delete.
- Offline use after the first successful login/bootstrap, immediate local updates, manual refresh, and automatic/best-effort sync triggers.
- A visible but unobtrusive offline/pending state and a brief message when a conflict is resolved with server data.

### Out of scope

- Budgets, configurable split percentages, receipts, notifications, recurring expenses, bank integrations, iOS, web administration, public registration, additional members, and additional households.
- Sub-taka amounts, decimal amount entry, and any currency other than BDT.
- Reopening a closed spending period, deleting a spending period, and more than one open spending period at a time.
- Interest, repayment schedules, or partial-repayment tracking on lending entries; a settled loan is edited or deleted by hand.
- Any server-side search, filter, or summary endpoint. Search and totals are computed on the device from local rows.

## 3. Definitions

- **Member:** one of `SUMON` or `EBRAHIM`, displayed as “Sumon” or “Ebrahim”.
- **Spending period:** a numbered stretch of shared spending the household settles as one unit. It runs from the instant it is opened until it is stamped closed, and it is not tied to a calendar month. Exactly one period is open per household at any time.
- **Open period:** the spending period whose `closedAt` is `null`. Every new expense is filed into it.
- **Settled period:** a spending period with a `closedAt` instant. It stays readable in History and keeps its expenses; it is never reopened and never deleted.
- **Paid:** the sum of expenses for which the member is the payer.
- **Allocated:** the member's sum of per-expense 50/50 shares, including the payer remainder rule.
- **Balance:** `paid - allocated`. A positive balance is money owed to that member.
- **Active expense:** an expense whose `deletedAt` is `null`.
- **Loan entry:** a hand-recorded loan between the two members, with a debtor, a whole-taka amount, an automatic timestamp, and an optional note. Loan entries are counted only in the lending net total.
- **Lending net total:** the sum of loans Ebrahim owes minus the sum of loans Sumon owes. It is independent of expense settlement.
- **Selected range:** an optional half-open interval `[startInclusive, endExclusive)` based on calendar boundaries in `Asia/Dhaka`. Only History offers one, and it is unset by default.
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
- As a member, I enter the amount as whole taka, and the field will not accept a decimal point at all.
- As a member, I see myself as the default payer, but I can choose the other member.
- As a member, I can see an expense immediately after saving even without network access.
- As a member, I can open and edit an active expense and see the edited values immediately.
- As a member, I can confirm deletion; it disappears from active totals/list immediately but remains a tombstone for synchronization.
- As a member, I am briefly informed if another device's newer version replaces my conflicting local edit.

An expense is filed into the open spending period when it is saved. An edit never moves it to another period, so an expense recorded offline before a close still belongs to the period it was recorded in.

### Spending periods

- As a member, I see which period the dashboard is showing and when it opened.
- As a member, I can close the open period once we have settled up, after a confirmation that repeats the final total and settlement line.
- As a member, closing the period empties the dashboard and immediately opens the next numbered period, so I can keep recording straight away.
- As a member, I can still browse a settled period and its expenses in History.
- As a member, I cannot reopen or delete a settled period, and the household never has two open periods.

### Lending ledger

- As a member, I can write down money lent between us, choosing who owes it and a whole-taka amount, with an optional note.
- As a member, I see a single net line for outstanding loans, computed only from these entries.
- As a member, I can edit or delete a lending entry when we repay or correct it.
- As a member, I understand that lending entries never change the shared-expense settlement figure on the dashboard.

The lending ledger is entirely manual. Nothing repays, ages, or clears an entry automatically.

### History and search

- As a member, I can search history by amount, note fragment, category, or payer name.
- As a member, search reaches every period, closed ones included, so a settled expense is still findable.
- As a member, I can narrow history to one spending period, one payer, one category, or a date range, and clear the range back to all dates.
- As a member, search and filtering work offline, because they read only local rows.

### Dashboard and synchronization

- As a member, I see the household's open spending period rather than a calendar month.
- As a member, I can see total spend, each member's paid amount, each member's allocated share, and a single settlement statement for that period.
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

- The dashboard shows the household's open spending period. There is no date-range control on it.
- Name the period and the date it opened. Before the first successful bootstrap no period is known; say so and show zero-valued totals.
- Show, from active local expenses filed into the open period:
  - total spent;
  - Sumon paid;
  - Ebrahim paid;
  - Sumon allocated;
  - Ebrahim allocated;
  - settlement text.
- Show the count of expenses in the period and the most recent few in reverse occurrence order with formatted amount, category, payer, occurrence date, and note preview when present.
- Provide add, tap-to-view/edit, pull/manual refresh, pending-sync indicator, offline/sync-error feedback, and the close-period action.
- An empty period shows zero-valued totals, “All settled”, and an empty-state message.

### 5.3 Closing a spending period

- Offer a close action on the dashboard, disabled while no period is known and while a close is in progress.
- Require a confirmation that names the period and repeats its final total spent and settlement line, so nothing is settled by an accidental tap.
- On confirmation, stamp the open period closed and create the next period, numbered one higher, in the same local transaction that queues both mutations.
- Queue the close before the create so the server never sees two open periods, and briefly confirm which period closed and which is now open.
- Cancelling changes nothing. A failed close leaves the period open and says so.
- Closing does not move, delete, or reprice any expense. The settled period keeps its rows and stays browsable in History.
- A settled period is never reopened and never deleted.

### 5.4 Add/edit expense

- Required fields: amount, category, payer, and occurrence date/time.
- Optional field: note.
- Defaults on add: signed-in member as payer, current date/time in `Asia/Dhaka`, Groceries as the initial quick-entry category, and empty note. The member may change category or payer before saving.
- The amount field accepts digits only and is labelled whole taka only. A decimal point cannot be typed into it.
- Display an existing active expense's fields on edit.
- Parse and validate before committing. A successful save is one local database transaction containing the optimistic expense projection and its outbox mutation.
- An added expense is filed into the open spending period. An edit keeps the period the expense already has.
- Disable duplicate save taps while the local transaction is in progress. Returning to the dashboard shows the local result immediately.

### 5.5 Expense view and deletion

- A view may share the edit screen but must show amount, category, payer, occurrence date/time, note, and pending/synced state.
- Deletion requires confirmation naming the expense amount/category or occurrence date.
- Confirmed deletion writes a local tombstone and outbox mutation in one transaction. Deleted items are excluded from normal lists and calculations.

### 5.6 Expense history, search, and settings

- History is newest first and covers every spending period, closed ones included.
- One search box matches, case-insensitively, the bare amount, the formatted amount, the category name, the payer name, and the note. Both `1,200` and `1200` find the same expense.
- Optional filters narrow the list by spending period, payer, fixed category, and an inclusive displayed date range. All of them start unset, and the range can be cleared back to all dates.
- Distinguish an empty ledger from a search that matched nothing.
- A subtle row state distinguishes acknowledged, waiting-to-sync, and needs-attention changes without preventing edit/delete.
- Settings shows the signed-in member, API environment/host label, app version, manual sync, logout, and a short local-data explanation.
- Logout attempts refresh-token revocation, always clears Android secure tokens locally, and does not delete Drift expenses, periods, loans, or queued mutations if the API is unavailable.

### 5.7 Lending ledger

- The lending ledger is its own tab with its own add action, separate from expenses.
- Show one net line computed only from active loan entries: “Ebrahim owes Sumon {amount}”, “Sumon owes Ebrahim {amount}”, or “No outstanding loans”.
- State on the screen that these entries are tracked on their own and that shared expenses settle separately on the dashboard.
- List entries newest first with the debtor, the amount, the recorded date, and a note preview when present.
- Offer a search box over amount, note, and member name, and a “who owes” filter. Distinguish an empty ledger from a search that matched nothing.
- Required fields on add/edit: who owes and a whole-taka amount. The note is optional.
- The timestamp is stamped automatically when the entry is saved and is not editable; an edit keeps the original stamp.
- Deletion requires confirmation and writes a local tombstone plus outbox mutation in one transaction, exactly like an expense.
- Nothing in this ledger affects total spent, paid, allocated, or the dashboard settlement text.

### 5.8 Conflict and sync feedback

- A version conflict replaces the optimistic local entity with the server snapshot (including a server tombstone), removes the conflicting and dependent queued mutations for that entity, and briefly says which ledger changed elsewhere and that server data was kept.
- A transient sync failure leaves local changes pending and does not block local work.
- A server validation rejection marks the affected item as needing attention and shows an actionable error naming the returned code; it must not be retried indefinitely.
- Connectivity status can trigger an attempt, but the UI calls the service reachable only after an HTTP success.

## 6. Entity fields and validation

The public expense shape is:

| Field | Ownership | Validation and behavior |
| --- | --- | --- |
| `id` | Client on create | UUID; stable for the lifetime of the expense and tombstone. |
| `amountMinor` | Client value | Integer poisha in `100..99_999_999_999` and an exact multiple of `100`; JSON safe integer; PostgreSQL `BIGINT`. |
| `category` | Client value | Exactly one of `GROCERIES`, `UTILITIES`, `TRANSPORT`, `HOUSEHOLD`, `MEDICINE`, `OTHER`. |
| `payer` | Client value | Exactly `SUMON` or `EBRAHIM`; defaults to the logged-in member only when adding. |
| `occurredAt` | Client value | A valid RFC 3339 instant with an explicit offset; normalized to UTC for storage. UI entry/display uses `Asia/Dhaka`. |
| `note` | Client value | Optional; trim surrounding whitespace; empty becomes `null`; at most 500 Unicode code points. |
| `periodId` | Client value, server default | UUID of the spending period the expense belongs to. Omitted on the wire means the household's open period. A period that does not exist is rejected; a settled period is accepted, because an expense recorded offline before a close belongs to the period it was recorded in. An edit never moves an expense to another period. |
| `version` | Server | Positive integer, starts at 1, increments by exactly one for each accepted edit or deletion. |
| `updatedAt` | Server | RFC 3339 UTC instant assigned for each accepted create/edit/delete. |
| `deletedAt` | Server | `null` for active data; server-assigned RFC 3339 UTC instant for a soft deletion. |

The public spending-period shape is:

| Field | Ownership | Validation and behavior |
| --- | --- | --- |
| `id` | Client on create | UUID; stable for the lifetime of the period. |
| `sequenceNumber` | Client value | Integer in `1..2_147_483_647`, unique per household, and one higher than the highest period the device knows. |
| `startedAt` | Client value | RFC 3339 instant the period opened. |
| `closedAt` | Client value | `null` while open; an RFC 3339 instant not preceding `startedAt` once settled. A settled period cannot be reopened. |
| `note` | Client value | Optional; same trimming and 500 code-point limit as an expense note. |
| `version` | Server | Positive integer, starts at 1, increments by exactly one for each accepted update. |
| `updatedAt` | Server | RFC 3339 UTC instant assigned for each accepted create/update. |

A period has no `deletedAt`: deletion is not an operation on it. At most one period per household may have a `null` `closedAt`, and the API enforces that even when two devices race.

The public loan-entry shape is:

| Field | Ownership | Validation and behavior |
| --- | --- | --- |
| `id` | Client on create | UUID; stable for the lifetime of the entry and tombstone. |
| `debtor` | Client value | Exactly `SUMON` or `EBRAHIM`. The other member is the creditor; it is not a stored field. |
| `amountMinor` | Client value | The same whole-taka rule and bounds as an expense amount. |
| `occurredAt` | Client stamp | Assigned by the client when the entry is created and never edited afterwards. |
| `note` | Client value | Optional; same trimming and 500 code-point limit as an expense note. |
| `version` | Server | Positive integer, starts at 1, increments by exactly one for each accepted edit or deletion. |
| `updatedAt` | Server | RFC 3339 UTC instant assigned for each accepted create/edit/delete. |
| `deletedAt` | Server | `null` for active data; server-assigned RFC 3339 UTC instant for a soft deletion. |

Mobile and API validation must agree with `packages/contracts/openapi.yaml`. The API still validates all values even when the mobile form has already done so.

### Amount entry and display

- Accept whole-taka digits only, for example `1`, `40`, or `1200`. There is no fractional part to enter.
- The input field itself refuses anything but digits, so a decimal point, separator, or sign never reaches parsing.
- Reject empty input, zero, more than nine digits, non-digits, and values outside `100..99_999_999_999` poisha once multiplied.
- Convert with integer arithmetic: whole taka times 100.
- Format with integer division and no fractional part, for example `40000` poisha as `৳400`. Grouping separators are display-only.
- No amount anywhere in the product renders a decimal point.

### Range validation

- A range is optional and only History offers one. When unset, every date matches.
- When set, both calendar dates are required and the displayed end date must not precede the start date.
- Convert local day/month boundaries using an IANA time-zone implementation for `Asia/Dhaka`; do not hard-code a UTC offset into domain logic.
- Filter by `occurredAt >= startInclusive && occurredAt < endExclusive` and `deletedAt == null`.

### Search

- Search is local. It reads rows already on the device and never calls the API.
- The needle is trimmed and compared case-insensitively as a substring.
- An expense matches when the needle occurs in the bare amount, the formatted amount, the category display name, the payer display name, or the note.
- A loan entry matches when the needle occurs in the bare amount, the formatted amount, either member's display name, or the note.
- An empty needle matches everything, so search composes with the other filters rather than replacing them.

## 7. Split and settlement formulas

Amounts are whole taka, so the split happens at taka granularity. For every expense, let `T` be its amount in whole taka (`amountMinor / 100`):

```text
lowerHalf = T ~/ 2
remainder = T % 2
payerAllocatedTaka = lowerHalf + remainder
otherAllocatedTaka = lowerHalf
```

Both allocations are converted back to poisha by multiplying by 100, so every allocated figure is itself a whole number of taka. Equivalently, the payer receives `ceil(T / 2)` taka and the other member receives `floor(T / 2)`, implemented only with integers.

For a set of expenses:

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
- `sumonBalance == 0`: “All settled”.

All interpolated amounts use BDT formatting.

The lending ledger has its own, separate total. For active loan entries:

```text
ebrahimOwes = sum(amountMinor where debtor == EBRAHIM)
sumonOwes = sum(amountMinor where debtor == SUMON)
net = ebrahimOwes - sumonOwes
```

Net text mirrors the settlement wording: positive is “Ebrahim owes Sumon {net}”, negative is “Sumon owes Ebrahim {abs(net)}”, and zero is “No outstanding loans”. This figure is never added to, subtracted from, or displayed alongside the expense settlement total.

### Worked example: even amounts and settlement

Within the open period, Sumon paid `100000` poisha (`৳1,000`) and Ebrahim paid `20000` poisha (`৳200`). Both amounts are an even number of taka.

```text
total = 120000
sumonAllocated = 60000
ebrahimAllocated = 60000
sumonBalance = 100000 - 60000 = 40000
ebrahimBalance = 20000 - 60000 = -40000
```

The dashboard says: **“Ebrahim owes Sumon ৳400”.**

### Worked example: odd taka paid by Sumon

For one expense of `10100` poisha (`৳101`) paid by Sumon, the split works on the 101 taka:

```text
lowerHalf = 101 ~/ 2 = 50
remainder = 101 % 2 = 1
sumonAllocated = 51 taka = 5100 poisha
ebrahimAllocated = 50 taka = 5000 poisha
sumonBalance = 10100 - 5100 = 5000
```

The dashboard says: **“Ebrahim owes Sumon ৳50”.** The extra taka belongs to Sumon's own allocated share, not Ebrahim's.

### Worked example: odd taka paid by Ebrahim

For the same `10100` poisha expense paid by Ebrahim, Ebrahim is allocated `5100`, Sumon is allocated `5000`, and the dashboard says **“Sumon owes Ebrahim ৳50”.** This demonstrates why period allocation must sum each expense rather than simply halve the period total.

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
- A sub-taka amount is refused by the form, by the local domain model, and by the API, and cannot be stored anywhere.
- A new expense is filed into the open period; an edit leaves its period alone.
- A deletion immediately removes the item from active views/totals while retaining a versioned local/server tombstone.
- Repeated delivery of one mutation UUID cannot apply the mutation twice.

### Spending periods

- Provisioning a household leaves exactly one open period, so a first sync always yields a period to spend against.
- Closing writes the close and the next period's creation as one local transaction and queues the close first.
- The API refuses a second open period, refuses reopening a settled one, and refuses deleting any period.
- A settled period keeps its expenses and remains selectable in History on every device after a sync.
- An expense that names a settled period is still accepted, so an offline record made before a close is not lost.

### Lending ledger

- A loan entry is visible from local data before any HTTP request completes, and its timestamp is assigned by the client rather than typed.
- Editing an entry changes debtor, amount, and note but never its timestamp.
- Deleting an entry hides it locally at once and propagates as a versioned tombstone.
- The lending net total counts only active loan entries, and no lending change alters total spent, paid, allocated, or the dashboard settlement text.

### Search and history correctness

- History covers every period, including settled ones, when no filter is set.
- Searching an amount, a note fragment, a category name, or a payer name finds the matching expenses regardless of period.
- Filters compose: an empty search plus a period selection narrows by period alone.
- Search issues no HTTP request and works with the device offline.

### Dashboard correctness

- The dashboard shows the household's open period, independent of the calendar month and of the device UTC offset.
- Totals include only active expenses filed into that period.
- Before the first bootstrap the dashboard states that no period exists and shows zero-valued totals.
- The even and odd-taka worked examples above pass as pure unit tests, including all balance invariants.
- No amount rendered anywhere contains a decimal point.
- No production money path uses floating-point arithmetic.

### Synchronization

- Sync is attempted on launch, foreground resume, after mutation, manual refresh, network recovery while alive, and eligible best-effort Android background work.
- Expenses, spending periods, and loan entries share one outbox and one change feed, and each mutation names its entity type.
- Bootstrap applies periods before expenses, so an expense never arrives without the period it references.
- Failed/transient requests preserve the outbox and retry with bounded exponential backoff and jitter.
- A lost response followed by the same mutation UUID returns the original result without another write.
- Bootstrap and change feeds can span pages without gaps; the cursor is saved only with the same transaction that applies its page.
- Remote soft deletes reach offline devices as tombstones.
- On an optimistic-version conflict, server data wins locally and the user sees a brief conflict message naming the ledger it came from.
- A validation rejection marks that one queued change as needing attention, leaves the rest of the batch alone, and is not retried.
- The app never treats a connectivity signal alone as proof that the API is reachable.
