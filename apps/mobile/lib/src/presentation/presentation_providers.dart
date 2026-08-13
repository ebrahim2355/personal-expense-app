import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../application/sync_coordinator.dart';
import '../domain/dhaka_time.dart';
import '../domain/expense.dart';
import '../domain/session.dart';
import '../providers.dart';

final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

final sessionSnapshotProvider = StreamProvider<SessionSnapshot>((ref) async* {
  final controller = ref.watch(sessionControllerProvider);
  yield controller.current;
  yield* controller.changes;
});

final lastSuccessfulSyncProvider = StreamProvider<DateTime?>((ref) {
  return ref
      .watch(appDatabaseProvider)
      .watchSyncMetadata()
      .map((metadata) => metadata.lastSuccessfulSyncAt?.toUtc());
});

final unresolvedMutationCountProvider = StreamProvider<int>((ref) {
  return ref.watch(appDatabaseProvider).watchUnresolvedMutationCount();
});

final dashboardRangeProvider = StateProvider<ExpenseDateRange>((ref) {
  return DhakaTime.initialize().currentMonth(ref.watch(clockProvider)());
});

final historyFilterProvider = StateProvider<HistoryFilter>((ref) {
  return HistoryFilter(
    range: DhakaTime.initialize().currentMonth(ref.watch(clockProvider)()),
  );
});

final apiEnvironmentLabelProvider = Provider<String>((ref) {
  final config = ref.watch(appConfigProvider);
  return '${config.environmentLabel} · ${config.apiBaseUri.host}';
});

final packageInfoProvider = FutureProvider<PackageInfo>((ref) {
  return PackageInfo.fromPlatform();
});

final manualSyncControllerProvider =
    StateNotifierProvider<ManualSyncController, ManualSyncState>((ref) {
      return ManualSyncController(
        synchronize: ref.watch(syncTriggerControllerProvider).manualRefresh,
      );
    });

final class HistoryFilter {
  const HistoryFilter({required this.range, this.payer, this.category});

  final ExpenseDateRange range;
  final HouseholdMember? payer;
  final ExpenseCategory? category;

  HistoryFilter copyWith({
    ExpenseDateRange? range,
    HouseholdMember? payer,
    bool clearPayer = false,
    ExpenseCategory? category,
    bool clearCategory = false,
  }) {
    return HistoryFilter(
      range: range ?? this.range,
      payer: clearPayer ? null : payer ?? this.payer,
      category: clearCategory ? null : category ?? this.category,
    );
  }

  bool includes(Expense expense) {
    return range.contains(expense.occurredAt) &&
        (payer == null || expense.payer == payer) &&
        (category == null || expense.category == category);
  }
}

final class ManualSyncState {
  const ManualSyncState({this.isRunning = false, this.lastReport});

  final bool isRunning;
  final SyncReport? lastReport;
}

final class ManualSyncController extends StateNotifier<ManualSyncState> {
  ManualSyncController({required this.synchronize})
    : super(const ManualSyncState());

  final Future<SyncReport?> Function() synchronize;

  Future<SyncReport?> run() async {
    if (state.isRunning) {
      return state.lastReport;
    }
    state = ManualSyncState(isRunning: true, lastReport: state.lastReport);
    final report = await synchronize();
    state = ManualSyncState(lastReport: report);
    return report;
  }
}
