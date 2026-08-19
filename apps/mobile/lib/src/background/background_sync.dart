import 'dart:ui';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
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
import '../notifications/local_notification_presenter.dart';

const String backgroundSyncTask = 'household-expenses.sync';
const String periodicSyncWork = 'household-expenses.periodic-sync';
const String mutationSyncWork = 'household-expenses.mutation-sync';

/// What caused a background sync, which is the one thing the two background
/// entry points disagree about.
///
/// It exists to keep the two health timestamps honest. "Android ran the
/// scheduled worker" and "a push reached this device" are separate questions with
/// separate answers in Settings, and a run cannot be allowed to answer the one
/// it was not.
enum BackgroundSyncTrigger {
  /// The periodic or mutation WorkManager job.
  scheduledWork,

  /// A data-only FCM message, delivered while the app was not in the foreground.
  pushMessage,
}

/// Syncs from a background isolate and reports whether the run should be
/// considered finished.
///
/// Shared by the WorkManager dispatcher and the FCM background handler because
/// the work is identical: both wake into an isolate with no app state at all, so
/// both have to build the database, the token store, the session and a notifier
/// of their own, and both must close all three however they leave.
///
/// The false return only means anything to WorkManager, which retries on it. The
/// push handler has nothing to retry with and ignores it.
Future<bool> runBackgroundSync(BackgroundSyncTrigger trigger) async {
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
    // This is the isolate that matters for the closed app, and it is a separate
    // one from the UI's, so it builds its own presenter. The plugin is
    // registered by the caller; the presenter initializes itself on first use.
    notifier: LocalNotificationPresenter(),
  );
  try {
    await session.initialize();
    if (session.current.status != SessionStatus.signedIn) {
      return true;
    }
    final result = await coordinator.synchronize();
    // Recorded for every outcome, including an offline one. Settings uses these
    // to answer "is Android letting background delivery happen at all" and "has
    // a push ever reached this device", and a run that found no network answers
    // both just as well as one that synced. Written here rather than inside the
    // coordinator so the coordinator stays ignorant of which isolate it is in.
    final now = DateTime.now().toUtc();
    switch (trigger) {
      case BackgroundSyncTrigger.scheduledWork:
        await database.recordBackgroundSync(now);
      case BackgroundSyncTrigger.pushMessage:
        await database.recordPushReceived(now);
    }
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
}

@pragma('vm:entry-point')
void backgroundSyncDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    if (taskName != backgroundSyncTask) {
      return true;
    }
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();
    return runBackgroundSync(BackgroundSyncTrigger.scheduledWork);
  });
}

/// Handles a data-only push that arrived while the app was backgrounded or not
/// running at all.
///
/// Top-level and annotated because Android starts a fresh isolate for this, and
/// the annotation is what stops the tree-shaker removing an entry point nothing
/// in Dart appears to call.
///
/// The message itself is ignored on purpose: it carries only
/// `type: household-activity` and never an amount, a note or a member name. The
/// sync below is what learns what changed, from the change feed, which is what
/// keeps the author-suppression rule and the household-activity toggle working
/// without the server knowing either of them.
@pragma('vm:entry-point')
Future<void> handleBackgroundPush(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  try {
    // This isolate has no Firebase app of its own, and the plugin throws on any
    // call before one exists.
    await Firebase.initializeApp();
    await runBackgroundSync(BackgroundSyncTrigger.pushMessage);
  } on Object {
    // Nothing here has anyone to report to. An exception thrown out of a
    // background handler is logged by Android and otherwise lost, and the
    // fifteen-minute poll is still the backstop that catches whatever this run
    // failed to fetch.
  }
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
    // WorkManager's own floor. Notifications about the other member's activity
    // are only as timely as this poll, and Doze and App Standby can stretch a
    // real interval to hours on an idle phone, so this is the best a
    // polling-only design can promise rather than a guarantee.
    frequency: const Duration(minutes: 15),
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
