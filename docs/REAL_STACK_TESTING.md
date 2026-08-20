# Local real-stack and two-client testing

This guide exercises the production API protocol with PostgreSQL and two
independent file-backed Drift databases. It does not replace either database
with SQLite on the server, and it does not share local state between clients.

## Automated proof

Prerequisites are Docker Desktop, Node/npm, and Flutter from the versions in the
root README. From the repository root, run:

```powershell
npm.cmd install
Set-Location apps/mobile
flutter pub get
Set-Location ../..
npm.cmd run test:real-stack
```

```bash
npm install
(cd apps/mobile && flutter pub get)
npm run test:real-stack
```

The command starts PostgreSQL 18 from `compose.test.yaml` on
`127.0.0.1:55432`, deploys committed Prisma migrations, generates random
test-only signing values and member PINs without printing them, provisions the
fixed household, builds and starts the API on `127.0.0.1:3100`, and runs
`apps/mobile/test/real_stack_sync_test.dart`. Readiness polling is bounded and
HTTP-based; the scenarios do not use arbitrary sleeps. The runner resets only
the dedicated test database and stops its Compose project in `finally`.

Pass `-- --keep-postgres` to keep PostgreSQL running for the API integration
suite:

```powershell
npm.cmd run test:real-stack -- --keep-postgres
$env:NODE_ENV = 'test'
$env:DATABASE_URL = 'postgresql://expenses_test:expenses_test@127.0.0.1:55432/expenses_e2e_test?schema=public'
$env:TEST_DATABASE_URL = $env:DATABASE_URL
npm.cmd test
npm.cmd run stack:test:down
```

The cleanup command refuses to run unless `NODE_ENV=test`, `DATABASE_URL` and
`TEST_DATABASE_URL` are identical, and the decoded database name ends in
`-test` or `_test`. It truncates only the eight application tables in that
database. Never point either test variable at development, staging, or
production.

## Covered scenarios

The real-stack test deterministically proves:

1. Sumon's offline create is immediately local and later reaches Ebrahim.
2. Different offline creates from both clients converge exactly once.
3. A response lost after the server commits is retried with the same mutation
   UUID and produces one expense.
4. An edit reaches a client that was offline.
5. Concurrent edits of one base version produce one winner; the stale client
   installs server data and receives a conflict notice.
6. A delete propagates as a tombstone and disappears from active totals.
7. A deliberately interrupted `pageSize=1` pull resumes from its committed
   cursor without a gap or duplicate.
8. An invalid access token refreshes once; a revoked refresh token signs out
   without deleting the expense database or pending outbox.
9. Closing and reopening the same SQLite file preserves a pending mutation,
   which later synchronizes.
10. `2026-07-31T18:00:00Z` is in August in Asia/Dhaka while the instant one
    second earlier remains in July.
11. Closing a period settles it on both devices, opens exactly one successor with
    the next sequence number, leaves the already-recorded expense on the settled
    period, and files the next expense against the new open period.
12. A hand-recorded loan created on one device reaches the other with its debtor,
    amount, and net total, survives an edit that flips the debtor, and disappears
    as a tombstone after a delete — while the expense settlement figure never
    moves.
13. A sub-taka amount forced into the outbox is refused by the server as
    `INVALID_MUTATION`, the round trip still completes, that one row is marked
    `NEEDS_ATTENTION`, and it is never retried.
14. Each device is told about the other member's create, edit, and delete, in both
    directions, and stays silent about its own — including the case that makes
    this hard, where one run pushes a mutation and then pulls the change the
    server wrote for it, after the outbox row has already been deleted. A client
    that installs later receives everything through bootstrap and announces
    nothing.

Push is deliberately absent from this list. Every device-facing part of it is
covered by the API and Flutter suites — the exact message shape, token retirement,
the member handoff, a mutation applying when the send fails, a replayed batch
waking nobody, and the registration/rotation/sign-out paths — and the one thing
left is whether Google actually delivers to a given phone, which no test can
assert. That is the manual **Push wake checks** below. The real-stack suite runs
with no Firebase credential, so it exercises exactly the disabled-notifier path
that a production API without the variable would take.

## Interactive local API

For manual Android testing, start the disposable PostgreSQL service:

```powershell
npm.cmd run stack:test:up
Copy-Item apps/api/.env.example apps/api/.env
```

Fill `apps/api/.env` with local-only values. Use port `3000`, database URL
`postgresql://expenses_test:expenses_test@127.0.0.1:55432/expenses_e2e_test?schema=public`,
independent random signing secrets of at least 32 characters, `TRUST_PROXY_HOPS=0`,
and explicit 6–12 digit initial PINs. The file is ignored; never commit it.

Leave `FIREBASE_SERVICE_ACCOUNT_BASE64` unset unless you are specifically running
the push checks below. Unset is the normal local shape: the API logs `push
disabled: …` once and clients poll, which is what most of the manual checklist
exercises. Set it only against a Firebase project you are willing to send test
messages through, and remember that a real phone registered here will keep being
woken by whichever API last saw its token.

Then run:

```powershell
npm.cmd run prisma:migrate:deploy --workspace @expenses/api
npm.cmd run members:provision --workspace @expenses/api
npm.cmd run dev --workspace @expenses/api
```

Provisioning is idempotent for the configured household/member keys, but it
updates the PIN hashes. Remove the initial PIN values from `.env` after the
command and restart the API. Check readiness with:

```powershell
Invoke-RestMethod http://127.0.0.1:3000/health/ready
```

## Android networking

An Android target's `localhost` is not normally the development PC.

- Android Emulator: use `http://10.0.2.2:3000`, which is the debug default.
- USB device: run `adb -s <DEVICE_ID> reverse tcp:3000 tcp:3000`, then use
  `http://127.0.0.1:3000` on that device. Repeat the reverse command per device.
- Wi-Fi device: use `http://<PC_LAN_IP>:3000`; the phone and PC must share a
  reachable network and the host firewall must allow the API port.

Examples from `apps/mobile`:

```powershell
flutter devices
flutter run -d <EMULATOR_ID> `
  --dart-define=API_BASE_URL=http://10.0.2.2:3000

adb -s <USB_DEVICE_ID> reverse tcp:3000 tcp:3000
flutter run -d <USB_DEVICE_ID> `
  --dart-define=API_BASE_URL=http://127.0.0.1:3000
```

Only the debug Android manifest permits cleartext HTTP for local development.
Release builds require HTTPS. The base URL is not a secret; never pass PINs or
tokens as Dart defines.

## Two-device manual checklist

Use two emulators, two physical devices, or one of each. Each installation must
have its own app data. Keep the API readiness endpoint open in a third terminal.

1. Sign in as Sumon on A and Ebrahim on B, then manually sync both.
2. Disable A's network, create a uniquely noted expense, and confirm it appears
   immediately with a pending indicator. Re-enable network, sync A then B, and
   confirm one matching row on both.
3. Disable both networks, create a different uniquely noted expense on each,
   reconnect, sync both in alternating order, and confirm both rows occur once
   on both devices.
4. With both devices current, disconnect B, edit a row on A, sync A, reconnect
   B, and confirm B pulls the edit.
5. Give both devices the same version, disconnect both, edit that row differently,
   reconnect and sync A first, then B. Confirm B shows a brief conflict notice
   and exactly A's server-authoritative values.
6. Delete a row on one device, sync both, and confirm it is absent from history
   and totals on the other.
7. Create an expense offline, force-stop and relaunch that app before reconnecting,
   and confirm its pending row survives and later synchronizes.
8. On A, close the current spending period. Sync both. Confirm both devices show
   one open period with an empty dashboard, that the settled period keeps its
   expenses in History, and that a new expense on B lands in the new period.
9. Record a loan on A for a whole-taka amount, sync both, and confirm B shows the
   same debtor, amount, and lending net total, and that the expense settlement
   figure on the dashboard is unchanged. Edit the loan on B, delete it on A, and
   confirm both devices agree after a sync.
10. Try to enter an amount with a decimal point, a thousands separator, or `0` on
    either device and confirm the form refuses it before any row is written.
11. In a debug build, open Settings and confirm cursor preview, pending count,
    last result, and last-success time change after sync. Correlate request IDs in
    mobile/API logs; no PIN, JWT, refresh token, Authorization header, database
    URL, or expense payload should appear.

Android WorkManager is best effort and cannot guarantee an immediate background
run. Foreground resume and manual sync are the authoritative manual checks.

### Notification checks

These are the only proof that notifications actually reach a phone: WorkManager
timing, the Android permission dialog, and the notification tray are all outside
what any test in this repository can assert.

Automated test 14 already proves the attribution rules, so treat a failure here as
a delivery, permission, or channel problem rather than a sync problem.

Waiting for background sync is the honest check, but it is slow — up to fifteen
minutes, and longer on an idle phone. To force a run, find the scheduled job and
trigger it:

```powershell
adb -s <ANDROID_DEVICE_ID> shell dumpsys jobscheduler |
  Select-String com.sumonebrahim.houseexpenses
adb -s <ANDROID_DEVICE_ID> shell cmd jobscheduler run -f `
  com.sumonebrahim.houseexpenses <JOB_ID>
```

1. Install fresh on B and open it: Android asks for notification permission once.
   Deny it, and confirm login, sync, offline entry, and every screen still behave
   normally. Reinstall, open, and allow it this time.
2. Add an expense on A and sync A. Force B's background sync, or background B and
   wait. B shows one notification naming A's member with the amount, category,
   payer, and note; A shows nothing at all for its own expense.
3. Swipe B fully away from the recents list and repeat step 2. The notification
   still arrives with the app closed.
4. Leave B offline, add three expenses on A, sync A, then bring B online and sync.
   B shows three notifications plus a group summary.
5. Edit, then soft-delete one of them on A, syncing after each. B receives an edit
   notification and then a delete notification.
6. Close the spending period on A and sync both. B receives one notification about
   the period.
7. Open Settings on B, turn **Household activity** off, and repeat step 2: B
   receives nothing, and its expense list, totals, and last-success time still
   update. Turn it back on and confirm notifications resume.
8. On B, revoke notifications in Android's own app settings. The Settings card
   reports that Android is blocking them and explains where to re-enable them.
   Re-enable them there, tap **Re-check**, and confirm the card clears without
   restarting the app.

### Push wake checks

These need the API to have `FIREBASE_SERVICE_ACCOUNT_BASE64` set and the APK to
have been built with a `google-services.json` from the same Firebase project. The
local Compose stack has neither by default, so run these against the deployed API
or export the variable before starting the API by hand. Without it the API logs
`push disabled: …` at startup and these steps prove nothing — check that line
first, because a silent phone and a disabled sender look identical from the
outside.

The API log is the other half of every step below. A landed change logs
`household activity push sent` with `deviceCount`, `delivered`, and `retired`, so
`deviceCount: 0` tells you B never registered and separates a registration problem
from a delivery one.

1. Sign in on B, then check Settings → **Push wake**. It reads "Never received on
   this device" until the first push lands; registration happens at sign-in, so a
   `deviceCount` of 0 on the next change means the POST failed rather than that
   push is broken.
2. Background B without closing it, add an expense on A, and sync A. B notifies
   within seconds, and **Push wake** on B now shows a timestamp to the minute in
   Dhaka time. **That timestamp is the actual assertion** — a notification on its
   own could have come from a background poll that happened to fire.
3. Repeat step 2 with B's screen off and the phone left idle for a few minutes
   first. This is the case polling cannot cover: Play Services' socket is
   Doze-exempt, so a `high` priority message still arrives.
4. Swipe B fully out of Recents and repeat step 2. On HyperOS/MIUI that
   force-stops the package, and whether a data-only message still reaches a
   force-stopped app is **measured here rather than assumed**. If nothing arrives,
   note it and stop: the fallback is a single documented flag, described in
   `docs/IMPLEMENTATION_PLAN.md`, and it is not to be taken on a hunch.
5. Turn **Household activity** off on B and repeat step 2. B stays silent but
   **Push wake** still advances, which is the proof that the push arrived and the
   client suppressed the notification — the switch lives only in B's local
   database, so a server-composed notification would have ignored it.
6. Sign out on B, add an expense on A, and sync A. The API log shows
   `deviceCount: 0`: sign-out deregisters while the access token is still valid, so
   a signed-out phone stops being addressable rather than being woken and dropping
   the message.
7. Put B into airplane mode, add an expense on A, sync A, then bring B back
   online. The push is lost — Google holds it for the thirty-minute TTL but this is
   worth seeing fail — and the notification arrives on B's next poll or next open.
   That is the reason polling stays.
8. Add three expenses on A in quick succession, syncing after each. B is woken
   once, not three times: one collapse key means a burst costs one wake, and the
   sync that follows finds all three changes and posts them with a summary.

When finished, stop and remove only the disposable Compose project:

```powershell
npm.cmd run stack:test:down
```
