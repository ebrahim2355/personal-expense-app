import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';

import '../background/background_sync.dart';
import '../data/repositories/expense_repository.dart';
import '../domain/session.dart';
import 'session_controller.dart';
import 'sync_coordinator.dart';

final class SyncTriggerController with WidgetsBindingObserver {
  SyncTriggerController({
    required this._expenseRepository,
    required this._syncCoordinator,
    required this._sessionController,
    required this._backgroundScheduler,
    Connectivity? connectivity,
  }) : _connectivity = connectivity ?? Connectivity();

  final ExpenseRepository _expenseRepository;
  final SyncCoordinator _syncCoordinator;
  final SessionController _sessionController;
  final BackgroundSyncScheduler _backgroundScheduler;
  final Connectivity _connectivity;
  final List<StreamSubscription<Object?>> _subscriptions =
      <StreamSubscription<Object?>>[];
  bool _started = false;

  Future<void> start() async {
    if (_started) {
      return;
    }
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    _subscriptions.add(
      _expenseRepository.localMutations.listen((event) {
        unawaited(_runIfSignedIn());
        unawaited(
          _scheduleBestEffort(_backgroundScheduler.registerMutationSync),
        );
      }),
    );
    _subscriptions.add(
      _connectivity.onConnectivityChanged.listen((states) {
        if (!states.contains(ConnectivityResult.none)) {
          unawaited(_runIfSignedIn());
        }
      }),
    );
    _subscriptions.add(
      _sessionController.changes.listen((session) {
        if (session.status == SessionStatus.signedIn) {
          unawaited(_syncCoordinator.synchronize());
        }
      }),
    );
    await _scheduleBestEffort(_backgroundScheduler.registerPeriodicSync);
    await _runIfSignedIn();
  }

  Future<SyncReport?> manualRefresh() => _runIfSignedIn();

  Future<SyncReport?> _runIfSignedIn() async {
    if (_sessionController.current.status != SessionStatus.signedIn) {
      return null;
    }
    return _syncCoordinator.synchronize();
  }

  Future<void> _scheduleBestEffort(Future<void> Function() schedule) async {
    try {
      await schedule();
    } on Object {
      // Foreground and local-first operation must survive scheduler failures.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_runIfSignedIn());
    }
  }

  Future<void> dispose() async {
    if (!_started) {
      return;
    }
    WidgetsBinding.instance.removeObserver(this);
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    _started = false;
  }
}
