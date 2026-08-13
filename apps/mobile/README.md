# Household Expenses mobile

Android Flutter client for the Sumon/Ebrahim household. Screens consume domain
models, repositories, and Riverpod presentation providers; they do not depend
on raw Dio or Drift implementation types.

## Implemented screens

- Login: fixed Sumon/Ebrahim selector, obscured numeric PIN, generic credential
  errors, and explicit first-login connectivity guidance.
- Dashboard: current `Asia/Dhaka` month by default, exact BDT totals, paid and
  allocated amounts, settlement, recent expenses, date-range selection, and
  non-blocking sync/offline state.
- Add/edit: string-to-poisha amount validation, category and payer selectors,
  Dhaka date/time, 500-code-point note, and a duplicate-submit guard.
- History: newest-first local rows with date, payer, and category filters plus
  edit and confirmed soft deletion.
- Settings: signed-in member, API environment, app version, manual sync, logout,
  and a concise local-data/background-sync explanation.

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
secure storage; Drift stores expense/outbox/sync metadata but no credentials.

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

- Drift is the UI source of truth. Local create/edit/delete changes the row and
  appends a frozen UUID mutation in one transaction.
- The sync coordinator serializes jobs, pushes dependency-ready outbox items,
  handles per-item results, bootstraps a new device, and pulls every cursor page.
- Conflicts use the server snapshot and emit a short notice; permanent rejects
  remain visible as needing attention.
- Dio refreshes a 401 once with refresh-token rotation and retries the original
  request once. Refresh failure clears secure tokens without deleting Drift data.
- Launch, resume, mutation, manual refresh, live connectivity recovery, and
  network-constrained WorkManager jobs trigger attempts. Connectivity is never
  treated as proof that the API is reachable.

Android schedules background work on a best-effort basis. It cannot guarantee
an immediate run or an exact interval, so foreground and manual triggers remain
authoritative for freshness.
