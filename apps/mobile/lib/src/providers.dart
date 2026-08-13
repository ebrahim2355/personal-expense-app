import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'application/session_controller.dart';
import 'application/sync_coordinator.dart';
import 'application/sync_triggers.dart';
import 'background/background_sync.dart';
import 'config/app_config.dart';
import 'data/local/app_database.dart';
import 'data/remote/api_client.dart';
import 'data/remote/http_transport.dart';
import 'data/repositories/auth_repository.dart';
import 'data/repositories/expense_repository.dart';
import 'data/security/token_store.dart';
import 'domain/expense.dart';

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

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(
    api: ref.watch(authenticationApiProvider),
    tokenStore: ref.watch(tokenStoreProvider),
    sessionController: ref.watch(sessionControllerProvider),
    database: ref.watch(appDatabaseProvider),
  );
});

final syncCoordinatorProvider = Provider<SyncCoordinator>((ref) {
  final coordinator = SyncCoordinator(
    database: ref.watch(appDatabaseProvider),
    api: ref.watch(expenseSyncApiProvider),
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
    syncCoordinator: ref.watch(syncCoordinatorProvider),
    sessionController: ref.watch(sessionControllerProvider),
    backgroundScheduler: ref.watch(backgroundSyncSchedulerProvider),
  );
  ref.onDispose(controller.dispose);
  return controller;
});

final appStartupProvider = FutureProvider<void>((ref) async {
  await ref.watch(sessionControllerProvider).initialize();
  await ref.watch(syncTriggerControllerProvider).start();
});

final visibleExpensesProvider = StreamProvider<List<Expense>>((ref) {
  return ref.watch(expenseRepositoryProvider).watchVisibleExpenses();
});

final syncNoticesProvider = StreamProvider<SyncNotice>((ref) {
  return ref.watch(syncCoordinatorProvider).notices;
});
