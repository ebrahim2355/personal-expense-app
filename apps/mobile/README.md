# Household Expenses mobile

Android Flutter client for the Sumon/Ebrahim household. Screens consume domain
models, repositories, and Riverpod presentation providers; they do not depend
on raw Dio or Drift implementation types.

## Implemented screens

- Login: fixed Sumon/Ebrahim selector, obscured numeric PIN, generic credential
  errors, and explicit first-login connectivity guidance.
- Dashboard: the household's open spending period, exact BDT totals, paid and
  allocated amounts, settlement, recent expenses, a confirmed action that settles
  the period and opens the next one, and non-blocking sync/offline state. There is
  no date-range control.
- Lending: the manual loan ledger with its own net total, newest-first entries, a
  local text search, and add/edit/confirmed-delete. It never changes the expense
  settlement figure.
- Add/edit expense: whole-taka digits-only amount validation, category and payer
  selectors, Dhaka date/time, 500-code-point note, and a duplicate-submit guard.
- Add/edit loan: debtor selector, whole-taka amount, optional note, and the same
  duplicate-submit guard. The timestamp is recorded, never asked for.
- History: newest-first local rows with a local text search plus date, payer, and
  category filters, edit, and confirmed soft deletion.
- Settings: signed-in member, API environment, app version, manual sync, logout,
  a notifications card with the background-delivery advisories and the push-wake
  line, and a concise local-data/background-sync explanation.

Bottom navigation is Dashboard, Lending, History, and Settings.

Material 3 controls retain at least 48 logical-pixel tap targets. Layout tests
cover a 320-pixel-wide surface with enlarged text. All visible totals are pure
integer calculations over active local rows, so they continue to work offline.

## API configuration

`API_BASE_URL` is a compile-time value supplied with `--dart-define`. Debug
builds default to `http://10.0.2.2:3000`, because Android Emulator maps
`10.0.2.2` to the development PC; `localhost` would refer to the emulator.
Release builds require an explicit HTTPS URL.

```powershell
# Android Emulator against a local API (the debug default)
flutter run

# Physical device or another development host
flutter run --dart-define=API_BASE_URL=http://192.168.1.20:3000

# Production/release
flutter build apk --release `
  --dart-define=API_BASE_URL=https://your-api.example
```

The base URL is configuration, not a secret. Never put tokens, PINs, or signing
values in a Dart define. Access and refresh tokens are stored only with Android
secure storage; Drift stores expenses, spending periods, loans, outbox, and sync
metadata, but no credentials.
Cleartext traffic is enabled only by the debug manifest for local development;
the main/release manifest explicitly disables it.

Production signing, package/version/icon ownership, signed APK/AAB commands,
and data-preserving install/upgrade steps are documented in
[`docs/PRODUCTION_DEPLOYMENT.md`](../../docs/PRODUCTION_DEPLOYMENT.md).

## Local setup: `google-services.json`

The Android build needs `android/app/google-services.json`, the Firebase client
configuration for package `com.sumonebrahim.houseexpenses`. It is **not in the
repository**. Download it from the Firebase console (Project settings → Your apps
→ Android app) and drop it at exactly that path.

It is deliberately gitignored. The file is a client identifier rather than a
credential — it holds no private key and grants no authority — but it names the
Firebase project and its API key to anyone who clones a public repository, so it
is provisioned locally instead. The cost is that a fresh clone cannot build
Android until it is in place, and the failure names the plugin rather than the
file:

```text
Execution failed for task ':app:processDebugGoogleServices'.
> File google-services.json is missing.
  The Google Services Plugin cannot function without it.
  Searched locations: ...\app\src\debug\google-services.json, ...,
  ...\app\google-services.json
```

That is the missing file and nothing else. Reaching that task is itself the proof:
the plugin resolved, configured against this AGP and Kotlin version, and wired
itself into the variant — a wrong plugin version fails earlier, during
configuration, and names the plugin rather than the file. The last searched
location is the one to fill. Tests, `flutter analyze`, and the API need nothing
from it; only the Android build and an actual push do.

## Generate and verify

`timezone` supplies the IANA `Asia/Dhaka` calendar boundaries; `package_info_plus`
supplies the Settings version label; `firebase_core` and `firebase_messaging`
supply the push registration. All are resolved through Flutter pub and pinned in
`pubspec.lock`.

The generated Drift database is committed so a clone analyzes immediately.
Regenerate it whenever `app_database.dart` changes:

```powershell
flutter pub get
dart run build_runner build
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
flutter build apk --debug
```

Equivalent POSIX commands are identical. On Windows, if the repository and the
default pub cache are on different drives, Kotlin plugin compilation can emit
cross-root incremental-cache errors. Use a same-drive cache for Android builds:

```powershell
$env:PUB_CACHE = (Join-Path (Get-Location) '.pub-cache')
flutter pub get
flutter build apk --debug
```

`.pub-cache` is ignored. This workaround is only for the local Windows tool
layout and does not change application behavior.

If a failed build already started Kotlin with the cross-drive cache, stop that
generated daemon state once before retrying:

```powershell
android\gradlew.bat --stop
flutter clean
```

## Implemented data boundaries

- Drift is the UI source of truth for expenses, spending periods, and loans.
  Local create/edit/delete changes the row and appends a frozen UUID mutation in
  one transaction; closing a period writes the close, the next period, and both
  mutations in a single transaction with the close queued first.
- The sync coordinator serializes jobs, pushes dependency-ready outbox items,
  handles per-item results, bootstraps a new device in period → expense → loan
  order, and pulls every cursor page. One outbox and one change feed carry all
  three entity types, discriminated by `entityType`.
- Conflicts use the server snapshot and emit a short notice naming the entity
  type; permanent rejects remain visible as needing attention and are never
  retried.
- Dio refreshes a 401 once with refresh-token rotation and retries the original
  request once. Refresh failure clears secure tokens without deleting Drift data.
- Launch, resume, mutation, manual refresh, live connectivity recovery,
  network-constrained WorkManager jobs, and an arriving FCM push trigger
  attempts. Connectivity is never treated as proof that the API is reachable.
- A sync that brings in the other member's expense, loan, or spending-period
  change posts one Android notification per change, plus a summary when a single
  sync brings several. The author is taken from the change feed, so a device is
  never notified about its own entry, and bootstrap never notifies at all.

## Notifications

`POST_NOTIFICATIONS` is requested on the first open after installation, and on any
later open while Android still reports notifications as off. The ask is gated on
the platform's own answer rather than on a stored "already asked" flag: a flag
cannot tell a real denial from an ask that never reached Android, so a single
failed ask would leave a member unasked for the life of the install, with no way
back short of reinstalling. Android shows its dialog only once per install and
answers instantly afterwards, so re-asking costs one platform call and never a
second dialog. The `SyncMetadata` timestamp records when the member first
answered, and is written only once an answer has come back. A denial is never
fatal: sync, offline use, and every screen behave exactly as before.

The icon is the app's own mark: a house whose lower half is a receipt with a torn
bottom edge — the roof says household, the tear says expense.
`drawable/ic_stat_notification.xml` and `drawable/ic_launcher_foreground.xml` draw
the same path at two scales, so a notification and the launcher icon it arrives
under are recognisably one object. Vector drawables cannot share a path between
files, so those two are kept in sync by hand: change one and change the other.
Android draws a small icon from its alpha channel alone and tints the result,
which is why the status-bar copy is a flat white-on-transparent silhouette, and
why pointing the plugin at `@mipmap/ic_launcher` would post a solid white blob.

The status-bar icon is listed in `android/app/src/main/res/raw/keep.xml`. The
plugin resolves it from a name string at runtime, so nothing references it
statically and the release resource shrinker deletes it as unreachable — after
which the name fails to resolve, `initialize()` throws, and the app silently
loses both the permission dialog and every notification. Debug builds do not
shrink resources, so this only ever appears in a release APK. Verify a release
build with `aapt2 dump resources build/app/outputs/flutter-apk/app-release.apk`
and confirm `drawable/ic_stat_notification` is listed.

Announcements ride on sync, and sync has two triggers when the app is not in
front of you. A data-only FCM push, sent by the API the moment a change lands,
wakes the app in seconds: Play Services holds one socket that Doze does not
touch, so it arrives on an idle phone. Background polling every fifteen minutes
is the backstop for a push that was never sent, never delivered, or arrived while
the phone was offline. Fifteen minutes is WorkManager's floor rather than a
guarantee — see the caveat below — so on the polling path alone a notification can
be late by much more than that. Opening the app or pulling to refresh syncs and
announces immediately.

The Settings notifications card carries a household-activity switch, a
background-sync line, a push-wake line, and up to two advisories. Whenever
Android reports that
notifications are blocked, a warning explains how to re-enable them and offers
**Open settings** and **Re-check** buttons. There is no in-app "ask again":
Android does not re-show its dialog after a denial, so a button claiming to would
be a lie. Turning the switch off silences announcements only; sync keeps running.

Android schedules background work on a best-effort basis. It cannot guarantee
an immediate run or an exact interval, so foreground and manual triggers remain
authoritative for freshness, and notification timing inherits the same limit —
Doze and App Standby can stretch a fifteen-minute period to hours on an idle
phone.

## Push wake

The push carries no content. The whole payload is
`data: { "type": "household-activity" }`, sent `high` priority with a thirty-minute
TTL and one collapse key, and the app composes every notification from its own
database after syncing.

That is a decision, not a shortcut. A server-composed `notification` block is
drawn by the system tray **before any Dart runs**, which would bypass both rules
that decide what gets said: the author-suppression check on the change feed, and
the household-activity switch — which lives only in this device's Drift
`SyncMetadata`, where the server cannot read it. Keeping the payload empty also
keeps amounts, notes, and member names off Google's wire, and keeps the local
database the only thing a notification is ever composed from, so a notification
can never describe a change this device does not have.

A push and a WorkManager job do the same work through the same code:
`runBackgroundSync()` is shared by both entry points, so a wake records
`lastBackgroundSyncAt` and composes notifications exactly as a poll does. The FCM
background handler calls `Firebase.initializeApp()` first — its isolate has no
Firebase instance of its own — and, like the WorkManager isolate, must never touch
the platform channel.

Registration is per install. `PushRegistrationController` posts the token to
`POST /v1/devices` after sign-in and on every `onTokenRefresh`, remembers a
SHA-256 fingerprint of what it sent so an unchanged token is not re-POSTed on
every launch, and leaves `fcmTokenRegisteredAt` null when the POST fails so the
next launch retries. Signing out deregisters first, while the access token is
still valid, because a signed-out phone must stop being woken. A phone with
broken or absent Play Services gets a null token, registers nothing, and runs on
polling alone.

`firebase_messaging` never asks for a permission. The notification ask has a
single owner — see the tri-state logic above — and a second asker would silently
undo it.

Settings shows **Push wake**: "Never received on this device" until the first
push lands, then the timestamp of the most recent one. That line is the only way
to tell a working push from a well-timed poll, which is exactly why it is there.

### What FCM does not fix

- Clearing the app from Recents force-stops it on HyperOS/MIUI. Whether a
  data-only message still reaches a force-stopped package is not reliably
  documented, so it is measured on the device rather than assumed; the Autostart
  guidance in Settings stays either way.
- A phone that is offline when the push is sent gets nothing. The fifteen-minute
  poll is what covers it, which is why polling stays.
- Google may still delay a message. "Near-instant" is typical, not promised.
- The battery-exemption and Autostart advisories both stay, though neither is
  prompted at startup any more. FCM makes the good case fast; it does not make the
  bad cases good.
- With no `FIREBASE_SERVICE_ACCOUNT_BASE64` configured on the API, no push is
  ever sent and the app behaves exactly as it did before push existed.

## Background delivery on an idle phone

The measurement that motivated the exemption: with the app closed and the phone
idle, `adb shell am get-standby-bucket com.sumonebrahim.houseexpenses` reported
**40 (RARE)** and `dumpsys jobscheduler` listed `WITHIN_QUOTA` as unsatisfied, so
the fifteen-minute job was deferred for hours. In active use the same app sits in
bucket 10 and runs on time. The power-save whitelist is the lever: an app that is
ignoring battery optimisations moves to bucket **5 (EXEMPTED)** and leaves both
Doze and the JobScheduler quota behind.

The exemption protects the poll rather than the push, and that division is what
makes it safe to stop asking for it up front. Android's own limits put a
high-priority FCM message outside Doze entirely — with the screen off and Doze
active it has no execution limits — and since Android 13 the standby bucket no
longer governs how many high-priority messages an app may receive. The one
documented way to lose that priority is to keep sending high-priority messages
that produce no notification, which is a further reason the API excludes the
author's own devices from every send. A regular job has no such immunity: in
bucket 40 it gets ten minutes of runtime per rolling twenty-four hours with
network **disabled**, which is the "deferred for hours" measured above, and Doze's
exemption list is documented as exempting an app from bucket-based restrictions
altogether.

Nothing asks for that exemption at startup. It was asked for there once,
immediately after the notification permission, and the cost was two system screens
in front of a member who had not yet seen one of the app's own — the second of
which is not a yes/no dialog on this phone but the **Battery details** screen
described below, whose correct answer is not the one Android recommends. A
permission dialog can be answered in a second; that screen cannot be, and asking
for it before the app has given anyone a reason to care is how it gets dismissed.

The Settings advisory asks instead, and only while
`PowerManager.isIgnoringBatteryOptimizations` reports the exemption missing, so the
request arrives with its reason attached and an install that already has it —
including one granted outside the app — never sees the advisory at all. Unlike
`POST_NOTIFICATIONS` this ask can be re-shown at will, which is what makes **Allow
background activity** a real button and what makes recording the ask pointless:
there is no single chance to ration, so Android's live answer is the whole state.
`SyncMetadata.batteryExemptionRequestedAt` is no longer written and survives only
as the record of the startup ask both phones already answered. Nothing invalidates
the provider after that tap either — Android reports only that the screen opened,
never what the member chose — so **Re-check** is the honest way back.

The trade is real and deliberate: a member who never opens Settings stays
throttled, and on this device that means the fifteen-minute backstop keeps running
late. What it does not delay is the push, which is the path that carries almost
every announcement.

What that intent opens is OEM-specific, and on the HyperOS phone this ships to it
is not a dialog at all: it is a **Battery details** screen whose `Battery saver`
section offers four options, defaulted to `Battery saver (recommended)`. The one
equivalent to the power-save whitelist is **No restrictions**; choosing it adds
the `user,com.sumonebrahim.houseexpenses` entry to `dumpsys deviceidle whitelist`
and moves the app to bucket 5. The advisory copy names that option explicitly,
because a member told only to "allow background activity" will pick the
recommended-looking one and change nothing.

`NotificationSettings.batteryExemptionGranted` is deliberately absent from
`willNotify`. Battery optimisation governs *when* a notification arrives, not
whether it can be posted, and folding it in would make Settings claim
notifications are off when they are merely late.

`SyncMetadata.lastBackgroundSyncAt` is written by `backgroundSyncDispatcher` for
every outcome, an offline one included: the question it answers is whether
Android let the worker run at all. It is written in the dispatcher rather than in
`SyncCoordinator` so the coordinator stays ignorant of which isolate it is in,
and it deliberately leaves `updatedAt` alone, which tracks the member's own
settings. Null — the value on every upgraded install until the first run — is the
answer to "has closed-app delivery ever worked here".

Two limits survive a granted exemption. Clearing the app from Recents force-stops
it on HyperOS/MIUI and cancels its jobs until the app is next opened; only the
OEM Autostart toggle mitigates that, and no app can read or set it, so Settings
gives instructions and a shortcut into the app's settings page. And polling alone
is only ever fifteen minutes at best, which is what the push above exists to
shorten — it does not replace the poll, and on a force-stopped package it may not
reach the app either.

Verify on a device after installing: `adb shell dumpsys deviceidle whitelist`
lists the package, `am get-standby-bucket` reports 5, and `dumpsys jobscheduler`
shows `TIMING_DELAY` as the only unsatisfied constraint. Forcing a run with
`cmd jobscheduler run -f` proves nothing — WorkManager answers "Delaying
execution … because it is being executed before schedule" and reschedules.

### Platform channel

`background_work_policy.dart` is the app's only `MethodChannel`
(`com.sumonebrahim.houseexpenses/background-work-policy`), hosted by
`MainActivity.configureFlutterEngine`. It exposes the exemption query, the
exemption dialog, and the app-details settings page; every call answers `false`
rather than throwing, including when `startActivity` finds no activity. **It is
usable only from the UI isolate** — the handler lives on the Activity, so neither
the WorkManager isolate nor the FCM background isolate has a receiver, and neither
must ever call it.
