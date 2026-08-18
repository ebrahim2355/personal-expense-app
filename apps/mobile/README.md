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
  a notifications card with the background-delivery advisories, and a concise
  local-data/background-sync explanation.

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

## Generate and verify

`timezone` supplies the IANA `Asia/Dhaka` calendar boundaries; `package_info_plus`
supplies the Settings version label. Both are resolved through Flutter pub and
pinned in `pubspec.lock`.

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
- Launch, resume, mutation, manual refresh, live connectivity recovery, and
  network-constrained WorkManager jobs trigger attempts. Connectivity is never
  treated as proof that the API is reachable.
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

The status-bar icon is listed in `android/app/src/main/res/raw/keep.xml`. The
plugin resolves it from a name string at runtime, so nothing references it
statically and the release resource shrinker deletes it as unreachable — after
which the name fails to resolve, `initialize()` throws, and the app silently
loses both the permission dialog and every notification. Debug builds do not
shrink resources, so this only ever appears in a release APK. Verify a release
build with `aapt2 dump resources build/app/outputs/flutter-apk/app-release.apk`
and confirm `drawable/ic_stat_notification` is listed.

Announcements ride on background sync, which runs every fifteen minutes at best.
Fifteen minutes is WorkManager's floor rather than a guarantee — see the caveat
below — so a notification can be late by much more than that. Opening the app or
pulling to refresh syncs and announces immediately. Near-instant delivery would
need FCM, which is deliberately out of scope for now.

The Settings notifications card carries a household-activity switch, a
background-sync line, and up to two advisories. Whenever Android reports that
notifications are blocked, a warning explains how to re-enable them and offers
**Open settings** and **Re-check** buttons. There is no in-app "ask again":
Android does not re-show its dialog after a denial, so a button claiming to would
be a lie. Turning the switch off silences announcements only; sync keeps running.

Android schedules background work on a best-effort basis. It cannot guarantee
an immediate run or an exact interval, so foreground and manual triggers remain
authoritative for freshness, and notification timing inherits the same limit —
Doze and App Standby can stretch a fifteen-minute period to hours on an idle
phone.

## Background delivery on an idle phone

The measurement that motivated the exemption: with the app closed and the phone
idle, `adb shell am get-standby-bucket com.sumonebrahim.houseexpenses` reported
**40 (RARE)** and `dumpsys jobscheduler` listed `WITHIN_QUOTA` as unsatisfied, so
the fifteen-minute job was deferred for hours. In active use the same app sits in
bucket 10 and runs on time. The power-save whitelist is the lever: an app that is
ignoring battery optimisations moves to bucket **5 (EXEMPTED)** and leaves both
Doze and the JobScheduler quota behind.

`ensureBackgroundExemption()` therefore runs at startup immediately after the
notification ask, in that order — allow notifications first, then keep them
timely. It is gated on `PowerManager.isIgnoringBatteryOptimizations` rather than
on the stored flag, so an install granted the exemption outside the app is never
nagged, and it does **not** record an ask whose dialog failed to launch: some OEM
builds have removed the activity, and recording that would spend the prompt on
something nobody saw. Unlike `POST_NOTIFICATIONS` this dialog can be re-shown, so
Settings offers a real **Allow background activity** button. Nothing invalidates
the provider after that tap — Android reports only that the dialog opened, never
what the member chose — so **Re-check** is the honest way back.

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
gives instructions and a shortcut into the app's settings page. And this is still
polling: FCM is the only route to near-instant delivery that survives a
force-stop, and it stays out of scope.

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
usable only from the UI isolate** — the handler lives on the Activity, so the
WorkManager isolate has no receiver and must never call it.
