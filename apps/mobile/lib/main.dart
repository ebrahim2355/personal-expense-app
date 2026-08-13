import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:workmanager/workmanager.dart';

import 'src/background/background_sync.dart';
import 'src/presentation/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Workmanager().initialize(backgroundSyncDispatcher);
  runApp(
    const ProviderScope(child: HouseholdExpensesApp(initializeDataLayer: true)),
  );
}
