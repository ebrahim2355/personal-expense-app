import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../application/sync_coordinator.dart';
import '../domain/dhaka_time.dart';
import '../domain/expense.dart';
import '../domain/loan.dart';
import '../domain/money.dart';
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

final syncCursorProvider = StreamProvider<String?>((ref) {
  return ref
      .watch(appDatabaseProvider)
      .watchSyncMetadata()
      .map((metadata) => metadata.lastCursor);
});

final syncReportProvider = StreamProvider<SyncReport>((ref) async* {
  final coordinator = ref.watch(syncCoordinatorProvider);
  final current = coordinator.lastReport;
  if (current != null) {
    yield current;
  }
  yield* coordinator.reports;
});

final unresolvedMutationCountProvider = StreamProvider<int>((ref) {
  return ref.watch(appDatabaseProvider).watchUnresolvedMutationCount();
});

/// History starts unfiltered: search reaches every period, closed ones included,
/// and the member narrows it down from there.
final historyFilterProvider = StateProvider<HistoryFilter>((ref) {
  return const HistoryFilter();
});

final loanFilterProvider = StateProvider<LoanFilter>((ref) {
  return const LoanFilter();
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
  const HistoryFilter({
    this.range,
    this.periodId,
    this.payer,
    this.category,
    this.query = '',
  });

  /// Null means every date. The dashboard no longer picks a range, so history is
  /// the only place a range narrows anything.
  final ExpenseDateRange? range;

  /// Null means every period, open and closed alike.
  final String? periodId;
  final HouseholdMember? payer;
  final ExpenseCategory? category;

  /// One search box over amount, note, category and payer.
  final String query;

  HistoryFilter copyWith({
    ExpenseDateRange? range,
    bool clearRange = false,
    String? periodId,
    bool clearPeriod = false,
    HouseholdMember? payer,
    bool clearPayer = false,
    ExpenseCategory? category,
    bool clearCategory = false,
    String? query,
  }) {
    return HistoryFilter(
      range: clearRange ? null : range ?? this.range,
      periodId: clearPeriod ? null : periodId ?? this.periodId,
      payer: clearPayer ? null : payer ?? this.payer,
      category: clearCategory ? null : category ?? this.category,
      query: query ?? this.query,
    );
  }

  bool includes(Expense expense) {
    final range = this.range;
    return (range == null || range.contains(expense.occurredAt)) &&
        (periodId == null || expense.periodId == periodId) &&
        (payer == null || expense.payer == payer) &&
        (category == null || expense.category == category) &&
        _matchesSearch(query, <String?>[
          formatBdtInput(expense.amountMinor),
          formatBdt(expense.amountMinor),
          expense.category.displayName,
          expense.payer.displayName,
          expense.note,
        ]);
  }
}

final class LoanFilter {
  const LoanFilter({this.debtor, this.query = ''});

  final HouseholdMember? debtor;
  final String query;

  LoanFilter copyWith({
    HouseholdMember? debtor,
    bool clearDebtor = false,
    String? query,
  }) {
    return LoanFilter(
      debtor: clearDebtor ? null : debtor ?? this.debtor,
      query: query ?? this.query,
    );
  }

  bool includes(Loan loan) {
    return (debtor == null || loan.debtor == debtor) &&
        _matchesSearch(query, <String?>[
          formatBdtInput(loan.amountMinor),
          formatBdt(loan.amountMinor),
          loan.debtor.displayName,
          loan.creditor.displayName,
          loan.note,
        ]);
  }
}

/// Case-insensitive substring search over the fields a member would think to
/// type. Both the grouped and bare amount are offered, so `1,200` and `1200`
/// find the same entry.
bool _matchesSearch(String query, List<String?> fields) {
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) {
    return true;
  }
  return fields.any(
    (field) => field != null && field.toLowerCase().contains(needle),
  );
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
