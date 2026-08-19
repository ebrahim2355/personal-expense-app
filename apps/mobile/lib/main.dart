import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:workmanager/workmanager.dart';

import 'src/background/background_sync.dart';
import 'src/presentation/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Workmanager().initialize(backgroundSyncDispatcher);
  await _initializePush();
  runApp(
    const ProviderScope(child: HouseholdExpensesApp(initializeDataLayer: true)),
  );
}

/// Starts Firebase and claims the background message handler.
///
/// Awaited before `runApp` because the handler has to be registered before the
/// first message can arrive, and a push that lands during startup would
/// otherwise be dropped.
///
/// Every failure is swallowed. A build with no `google-services.json`, a phone
/// with no Play Services, and a Firebase outage all land here, and none of them
/// may stop the app opening: push is an accelerator over the fifteen-minute
/// background poll, never a prerequisite for it.
Future<void> _initializePush() async {
  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(handleBackgroundPush);
  } on Object {
    // No push on this install. Everything else, including closed-app
    // notifications on the poll, works exactly as it did before.
  }
}
