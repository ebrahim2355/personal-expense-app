import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:workmanager/workmanager.dart';

import 'src/background/background_sync.dart';
import 'src/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Workmanager().initialize(backgroundSyncDispatcher);
  runApp(
    const ProviderScope(child: HouseholdExpensesApp(initializeDataLayer: true)),
  );
}

class HouseholdExpensesApp extends ConsumerWidget {
  const HouseholdExpensesApp({super.key, this.initializeDataLayer = false});

  final bool initializeDataLayer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (initializeDataLayer) {
      ref.watch(appStartupProvider);
    }
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Household Expenses',
      home: Scaffold(
        appBar: AppBar(title: const Text('Household Expenses')),
        body: const Center(child: Text('Development shell ready')),
      ),
    );
  }
}
