import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/session.dart';
import '../providers.dart';
import 'home_shell.dart';
import 'login_screen.dart';
import 'presentation_providers.dart';

final class HouseholdExpensesApp extends StatelessWidget {
  const HouseholdExpensesApp({super.key, this.initializeDataLayer = false});

  final bool initializeDataLayer;

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF006B5B),
      brightness: Brightness.light,
    );
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Household Expenses',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: colorScheme,
        scaffoldBackgroundColor: const Color(0xFFF7F9F7),
        appBarTheme: const AppBarTheme(centerTitle: false),
        cardTheme: CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
            side: BorderSide(color: colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: colorScheme.surface,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size(48, 52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(48, 48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ),
      home: _SessionGate(initializeDataLayer: initializeDataLayer),
    );
  }
}

final class _SessionGate extends ConsumerWidget {
  const _SessionGate({required this.initializeDataLayer});

  final bool initializeDataLayer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (initializeDataLayer) {
      final startup = ref.watch(appStartupProvider);
      if (startup.hasError) {
        return _StartupError(onRetry: () => ref.invalidate(appStartupProvider));
      }
    }

    final session = ref.watch(sessionSnapshotProvider);
    return session.when(
      loading: () => const _StartupProgress(),
      error: (_, _) =>
          _StartupError(onRetry: () => ref.invalidate(sessionSnapshotProvider)),
      data: (snapshot) => switch (snapshot.status) {
        SessionStatus.unknown => const _StartupProgress(),
        SessionStatus.signedOut => const LoginScreen(),
        SessionStatus.signedIn when snapshot.member != null => HomeShell(
          member: snapshot.member!,
        ),
        SessionStatus.signedIn => const _StartupProgress(),
      },
    );
  }
}

final class _StartupProgress extends StatelessWidget {
  const _StartupProgress();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Semantics(
          label: 'Opening Household Expenses',
          child: const CircularProgressIndicator(),
        ),
      ),
    );
  }
}

final class _StartupError extends StatelessWidget {
  const _StartupError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(Icons.error_outline, size: 48),
                const SizedBox(height: 12),
                Text(
                  'Could not open the app',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 6),
                const Text(
                  'Your local data has not been deleted. Try opening it again.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: onRetry,
                  child: const Text('Try again'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
