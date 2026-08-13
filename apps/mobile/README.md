# Household Expenses mobile

Android Flutter client for the Sumon/Ebrahim household. The current milestone
implements the offline-first data layer and keeps the development shell UI.
Screens consume repositories and Riverpod providers; they do not depend on raw
Dio or Drift types.

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
