import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'application/notification_settings.dart';
import 'application/session_controller.dart';
import 'application/sync_coordinator.dart';
import 'application/sync_triggers.dart';
import 'background/background_sync.dart';
import 'background/background_work_policy.dart';
import 'config/app_config.dart';
import 'data/local/app_database.dart';
import 'data/remote/api_client.dart';
import 'data/remote/http_transport.dart';
import 'data/repositories/auth_repository.dart';
import 'data/repositories/expense_repository.dart';
import 'data/repositories/loan_repository.dart';
import 'data/repositories/period_repository.dart';
import 'data/security/token_store.dart';
import 'domain/expense.dart';
import 'domain/loan.dart';
import 'domain/session.dart';
import 'domain/spending_period.dart';
import 'notifications/household_activity_notifier.dart';
import 'notifications/local_notification_presenter.dart';
import 'notifications/notification_permissions.dart';

final appConfigProvider = Provider<AppConfig>((ref) {
  return AppConfig.fromEnvironment();
});

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final database = AppDatabase.open();
  ref.onDispose(database.close);
  return database;
});

final tokenStoreProvider = Provider<TokenStore>((ref) {
  return SecureTokenStore();
});

final sessionControllerProvider = Provider<SessionController>((ref) {
  final controller = SessionController(ref.watch(tokenStoreProvider));
  ref.onDispose(controller.close);
  return controller;
});

final httpTransportProvider = Provider<HttpTransport>((ref) {
  return DioHttpTransport(ref.watch(appConfigProvider).apiBaseUri);
});

final authenticatedApiClientProvider = Provider<AuthenticatedApiClient>((ref) {
  return AuthenticatedApiClient(
    transport: ref.watch(httpTransportProvider),
    tokenStore: ref.watch(tokenStoreProvider),
    sessionController: ref.watch(sessionControllerProvider),
  );
});

final authenticationApiProvider = Provider<AuthenticationApi>((ref) {
  return DioAuthenticationApi(ref.watch(httpTransportProvider));
});

final expenseSyncApiProvider = Provider<ExpenseSyncApi>((ref) {
  return DioExpenseSyncApi(ref.watch(authenticatedApiClientProvider));
});

final expenseRepositoryProvider = Provider<ExpenseRepository>((ref) {
  final repository = DriftExpenseRepository(ref.watch(appDatabaseProvider));
  ref.onDispose(repository.close);
  return repository;
});

final periodRepositoryProvider = Provider<PeriodRepository>((ref) {
  final repository = DriftPeriodRepository(ref.watch(appDatabaseProvider));
  ref.onDispose(repository.close);
  return repository;
});

final loanRepositoryProvider = Provider<LoanRepository>((ref) {
  final repository = DriftLoanRepository(ref.watch(appDatabaseProvider));
  ref.onDispose(repository.close);
  return repository;
});

final authRepositoryProvider = Provider<MemberAuthRepository>((ref) {
  return AuthRepository(
    api: ref.watch(authenticationApiProvider),
    tokenStore: ref.watch(tokenStoreProvider),
    sessionController: ref.watch(sessionControllerProvider),
    database: ref.watch(appDatabaseProvider),
  );
});

/// The one presenter both roles share, so the plugin is initialized once per
/// isolate. The background isolate builds its own — see `background_sync.dart`.
final localNotificationPresenterProvider = Provider<LocalNotificationPresenter>(
  (ref) => LocalNotificationPresenter(),
);

final householdActivityNotifierProvider = Provider<HouseholdActivityNotifier>(
  (ref) => ref.watch(localNotificationPresenterProvider),
);

final notificationPermissionsProvider = Provider<NotificationPermissions>(
  (ref) => ref.watch(localNotificationPresenterProvider),
);

final notificationSettingsControllerProvider =
    Provider<NotificationSettingsController>((ref) {
      return NotificationSettingsController(
        database: ref.watch(appDatabaseProvider),
        permissions: ref.watch(notificationPermissionsProvider),
        policy: ref.watch(backgroundWorkPolicyProvider),
      );
    });

final backgroundWorkPolicyProvider = Provider<BackgroundWorkPolicy>((ref) {
  return const AndroidBackgroundWorkPolicy();
});

final syncCoordinatorProvider = Provider<SyncCoordinator>((ref) {
  final coordinator = SyncCoordinator(
    database: ref.watch(appDatabaseProvider),
    api: ref.watch(expenseSyncApiProvider),
    // The user asked for notifications even while the app is open, so the
    // foreground coordinator announces on the same terms as the background one.
    notifier: ref.watch(householdActivityNotifierProvider),
  );
  ref.onDispose(coordinator.close);
  return coordinator;
});

final backgroundSyncSchedulerProvider = Provider<BackgroundSyncScheduler>((
  ref,
) {
  return const AndroidBackgroundSyncScheduler();
});

final syncTriggerControllerProvider = Provider<SyncTriggerController>((ref) {
  final controller = SyncTriggerController(
    expenseRepository: ref.watch(expenseRepositoryProvider),
    periodRepository: ref.watch(periodRepositoryProvider),
    loanRepository: ref.watch(loanRepositoryProvider),
    syncCoordinator: ref.watch(syncCoordinatorProvider),
    sessionController: ref.watch(sessionControllerProvider),
    backgroundScheduler: ref.watch(backgroundSyncSchedulerProvider),
  );
  ref.onDispose(controller.dispose);
  return controller;
});

final appStartupProvider = FutureProvider<void>((ref) async {
  final session = ref.watch(sessionControllerProvider);
  final auth = ref.watch(authRepositoryProvider);
  await session.initialize();
  final identity = await auth.restoreStoredIdentity();
  if (session.current.status == SessionStatus.signedIn && identity == null) {
    await auth.signOutLocally();
  }
  // Before sync starts, and regardless of sign-in state: the ask belongs to the
  // first open after install, which is often the sign-in screen. It never
  // throws, so a denial or an unavailable platform cannot block startup.
  await ref
      .watch(notificationSettingsControllerProvider)
      .ensureNotificationPermission();
  // Immediately after, and in this order deliberately: allow notifications
  // first, then keep them timely. Also never throws.
  await ref
      .watch(notificationSettingsControllerProvider)
      .ensureBackgroundExemption();
  await ref.watch(syncTriggerControllerProvider).start();
});

/// Whether Android will show this app's notifications. A `FutureProvider` rather
/// than a stream because the platform offers no change notification — the
/// Settings screen invalidates it to re-check after a trip to Android Settings.
final systemNotificationsEnabledProvider = FutureProvider<bool>((ref) {
  return ref
      .watch(notificationSettingsControllerProvider)
      .read()
      .then((settings) => settings.systemEnabled);
});

final householdActivityNotificationsEnabledProvider = StreamProvider<bool>((
  ref,
) {
  return ref
      .watch(notificationSettingsControllerProvider)
      .watchHouseholdActivityEnabled();
});

/// Whether Android is willing to run this app's background work on time. A
/// `FutureProvider` for the same reason as [systemNotificationsEnabledProvider]:
/// the platform announces no change, so Settings invalidates this after showing
/// the dialog.
final batteryExemptionGrantedProvider = FutureProvider<bool>((ref) {
  return ref
      .watch(notificationSettingsControllerProvider)
      .read()
      .then((settings) => settings.batteryExemptionGranted);
});

/// When the WorkManager isolate last finished a run. Null means never on this
/// install, which is the answer to "is closed-app delivery working at all".
final lastBackgroundSyncProvider = StreamProvider<DateTime?>((ref) {
  return ref
      .watch(notificationSettingsControllerProvider)
      .watchLastBackgroundSync();
});

final visibleExpensesProvider = StreamProvider<List<Expense>>((ref) {
  return ref.watch(expenseRepositoryProvider).watchVisibleExpenses();
});

/// Every period, newest first, so History can offer a period selector.
final visiblePeriodsProvider = StreamProvider<List<SpendingPeriod>>((ref) {
  return ref.watch(periodRepositoryProvider).watchPeriods();
});

/// The period the dashboard is scoped to. Null only before the first bootstrap.
final openPeriodProvider = StreamProvider<SpendingPeriod?>((ref) {
  return ref.watch(periodRepositoryProvider).watchOpenPeriod();
});

final visibleLoansProvider = StreamProvider<List<Loan>>((ref) {
  return ref.watch(loanRepositoryProvider).watchVisibleLoans();
});

final syncNoticesProvider = StreamProvider<SyncNotice>((ref) {
  return ref.watch(syncCoordinatorProvider).notices;
});
