# Household Expenses

Production-oriented monorepo scaffold for a private, offline-first Android household expense app and its Railway-hosted API. This milestone contains only development foundations: an Express liveness endpoint, an Android Flutter shell, the initial OpenAPI contract, and validation tooling. Authentication, expenses, synchronization, and database models are intentionally not implemented yet.

## Repository layout

```text
apps/api                    Node.js, TypeScript, Express, Prisma tooling
apps/mobile                 Flutter Android application
packages/contracts          single OpenAPI contract
docs                        product, architecture, and implementation guidance
```

Flutter is not an npm workspace. The root npm workspace contains only `apps/api`.

## Prerequisites

Verified scaffold toolchain:

- Node.js `24.15.0`
- npm `11.12.1`
- Flutter `3.47.0` with Dart `3.13.0`
- Git

For Android run/build commands, also install Android SDK 36 or another Flutter-supported SDK and a JDK compatible with the generated Gradle project (JDK 17 is recommended), set `JAVA_HOME`, and put `%JAVA_HOME%\bin` on `PATH`. Confirm with `flutter doctor -v`.

No Docker configuration is included. The current scaffold neither connects to PostgreSQL nor runs PostgreSQL integration tests; local database infrastructure should be added with that milestone only if the test workflow genuinely requires it.

## Clone and install

### Windows PowerShell

```powershell
git clone https://github.com/ebrahim2355/personal-expense-app.git
Set-Location personal-expense-app

npm.cmd install

Set-Location apps/mobile
flutter pub get
Set-Location ../..
```

### macOS/Linux or a POSIX shell

```bash
git clone https://github.com/ebrahim2355/personal-expense-app.git
cd personal-expense-app

npm install

cd apps/mobile
flutter pub get
cd ../..
```

The API health shell defaults to port `3000` and needs no environment file. Before a future database command or deployment, copy `apps/api/.env.example` to `apps/api/.env` and replace every angle-bracket placeholder. Never commit `.env` or real credentials.

`apps/mobile/.env.example` records the future API base URL placeholder only. The current shell does not load it; networking configuration will use an explicit build-time value when Dio integration is implemented.

## Run the API

### Windows PowerShell

```powershell
npm.cmd run dev --workspace @expenses/api
```

In a second PowerShell window:

```powershell
Invoke-RestMethod http://localhost:3000/health/live
```

Expected response:

```json
{
  "status": "ok"
}
```

Platform-neutral equivalents are `npm run dev --workspace @expenses/api` and `curl http://localhost:3000/health/live`.

To run compiled output instead:

```powershell
npm.cmd run build --workspace @expenses/api
npm.cmd run start --workspace @expenses/api
```

## Run the Flutter shell

List Android devices/emulators, then launch using a returned device ID:

```powershell
Set-Location apps/mobile
flutter devices
flutter run -d <ANDROID_DEVICE_ID>
```

POSIX shells use the same Flutter commands after `cd apps/mobile`.

The Android namespace and application ID are `com.sumonebrahim.houseexpenses`. To change this before distribution, update both `namespace` and `applicationId` in `apps/mobile/android/app/build.gradle.kts`, then move `MainActivity.kt` to the matching directory under `apps/mobile/android/app/src/main/kotlin` and update its `package` declaration. Also update signing/store configuration that refers to the old ID.

## Validation commands

### API and contract

Run from the repository root:

```powershell
npm.cmd install
npm.cmd run openapi:lint
npm.cmd run format:check
npm.cmd run lint
npm.cmd run typecheck
npm.cmd test
npm.cmd run build
```

`npm.cmd run check` runs the contract lint plus all API checks in order. On POSIX shells, replace `npm.cmd` with `npm`.

The Prisma CLI foundation is present without data models. Once `DATABASE_URL` is configured with a non-secret development database URL:

```powershell
npm.cmd run prisma:generate --workspace @expenses/api
npm.cmd run prisma:validate --workspace @expenses/api
```

Do not use `prisma db push`; future schema changes must use committed migrations.

### Flutter

Run from `apps/mobile`:

```powershell
flutter pub get
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
flutter build apk --debug
```

The direct commands are identical on POSIX shells. Root convenience aliases are also available:

```powershell
npm.cmd run mobile:format
npm.cmd run mobile:format:check
npm.cmd run mobile:lint
npm.cmd run mobile:typecheck
npm.cmd run mobile:test
npm.cmd run mobile:build
```

`flutter analyze` is both the Dart/Flutter type-check and lint command. `npm.cmd run mobile:check` runs formatting verification, analysis, and tests; it deliberately omits the Android build because that requires a configured JDK/Android toolchain.

## Environment files and secrets

- Commit only `.env.example` files containing placeholders.
- Keep API `.env`, Railway values, database URLs, JWT material, PINs, Android key properties, and signing stores outside Git.
- The root `.gitignore` excludes common Node, Flutter, Dart, Gradle, IDE, coverage, log, local database, generated-code, environment, and signing artifacts.

## Product and architecture guidance

- [Product specification](docs/PRODUCT_SPEC.md)
- [Architecture](docs/ARCHITECTURE.md)
- [Implementation plan](docs/IMPLEMENTATION_PLAN.md)
- [Repository engineering rules](AGENTS.md)
