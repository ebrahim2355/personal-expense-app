import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import '../application/session_controller.dart';
import '../application/sync_coordinator.dart';
import '../config/app_config.dart';
import '../data/local/app_database.dart';
import '../data/remote/api_client.dart';
import '../data/remote/http_transport.dart';
import '../data/security/token_store.dart';
import '../domain/session.dart';

const String backgroundSyncTask = 'household-expenses.sync';
const String periodicSyncWork = 'household-expenses.periodic-sync';
const String mutationSyncWork = 'household-expenses.mutation-sync';

@pragma('vm:entry-point')
void backgroundSyncDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    if (taskName != backgroundSyncTask) {
      return true;
    }
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();

    final database = AppDatabase.open();
    final tokenStore = SecureTokenStore();
    final session = SessionController(tokenStore);
    final coordinator = SyncCoordinator(
      database: database,
      api: DioExpenseSyncApi(
        AuthenticatedApiClient(
          transport: DioHttpTransport(AppConfig.fromEnvironment().apiBaseUri),
          tokenStore: tokenStore,
          sessionController: session,
        ),
      ),
    );
    try {
      await session.initialize();
      if (session.current.status != SessionStatus.signedIn) {
        return true;
      }
      final result = await coordinator.synchronize();
      return switch (result.outcome) {
        SyncOutcome.completed => true,
        SyncOutcome.authenticationRequired => true,
        SyncOutcome.offline || SyncOutcome.failed => false,
      };
    } finally {
      await coordinator.close();
      await session.close();
      await database.close();
    }
  });
}

abstract interface class BackgroundSyncScheduler {
  Future<void> registerPeriodicSync();

  Future<void> registerMutationSync();
}

final class AndroidBackgroundSyncScheduler implements BackgroundSyncScheduler {
  const AndroidBackgroundSyncScheduler();

  static final Constraints _networkConstraint = Constraints(
    networkType: NetworkType.connected,
  );

  @override
  Future<void> registerPeriodicSync() => Workmanager().registerPeriodicTask(
    periodicSyncWork,
    backgroundSyncTask,
    frequency: const Duration(hours: 6),
    constraints: _networkConstraint,
    existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
    backoffPolicy: BackoffPolicy.exponential,
    backoffPolicyDelay: const Duration(seconds: 30),
  );

  @override
  Future<void> registerMutationSync() => Workmanager().registerOneOffTask(
    mutationSyncWork,
    backgroundSyncTask,
    constraints: _networkConstraint,
    existingWorkPolicy: ExistingWorkPolicy.replace,
    backoffPolicy: BackoffPolicy.exponential,
    backoffPolicyDelay: const Duration(seconds: 30),
  );
}
