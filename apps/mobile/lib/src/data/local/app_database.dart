import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'app_database.g.dart';

@DataClassName('LocalExpenseRow')
class LocalExpenses extends Table {
  TextColumn get id => text()();
  IntColumn get amountMinor => integer()();
  TextColumn get category => text()();
  TextColumn get payer => text()();
  DateTimeColumn get occurredAt => dateTime()();
  TextColumn get note => text().nullable()();

  /// Nullable, unlike the server column. An expense recorded before the first
  /// bootstrap has no period to name yet; the wire payload omits it and the
  /// server files the expense into whichever period is open.
  TextColumn get periodId => text().nullable()();
  IntColumn get version => integer()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  TextColumn get syncState => text()();
  DateTimeColumn get localModifiedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

@DataClassName('LocalPeriodRow')
class LocalPeriods extends Table {
  TextColumn get id => text()();
  IntColumn get sequenceNumber => integer()();
  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get closedAt => dateTime().nullable()();
  TextColumn get note => text().nullable()();
  IntColumn get version => integer()();
  DateTimeColumn get updatedAt => dateTime()();
  TextColumn get syncState => text()();
  DateTimeColumn get localModifiedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

@DataClassName('LocalLoanRow')
class LocalLoans extends Table {
  TextColumn get id => text()();
  TextColumn get debtor => text()();
  IntColumn get amountMinor => integer()();
  DateTimeColumn get occurredAt => dateTime()();
  TextColumn get note => text().nullable()();
  IntColumn get version => integer()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  TextColumn get syncState => text()();
  DateTimeColumn get localModifiedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

@DataClassName('OutboxMutationRow')
class OutboxMutations extends Table {
  IntColumn get localSequence => integer().autoIncrement()();
  TextColumn get mutationId => text().unique()();
  TextColumn get entityId => text()();

  /// Which table [entityId] points at. Defaulted so rows queued by an older
  /// build, when the outbox only ever carried expenses, still replay correctly.
  TextColumn get entityType =>
      text().withDefault(const Constant<String>('EXPENSE'))();
  TextColumn get action => text()();
  IntColumn get baseVersion => integer()();
  TextColumn get payloadJson => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  IntColumn get attemptCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get lastAttemptAt => dateTime().nullable()();
  DateTimeColumn get nextAttemptAt => dateTime().nullable()();
  TextColumn get lastErrorCode => text().nullable()();
  TextColumn get status => text()();
}

@DataClassName('SyncMetadataRow')
class SyncMetadata extends Table {
  IntColumn get singletonId => integer()();
  TextColumn get householdId => text().nullable()();
  TextColumn get memberId => text().nullable()();
  TextColumn get memberKey => text().nullable()();
  TextColumn get lastCursor => text().nullable()();
  TextColumn get bootstrapPageToken => text().nullable()();
  TextColumn get bootstrapWatermark => text().nullable()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get lastSuccessfulSyncAt => dateTime().nullable()();

  /// When Android's notification permission was last asked for, or null when it
  /// never has been. Android shows its dialog only once per install, so this is
  /// what keeps the first-launch request from being attempted on every launch.
  DateTimeColumn get notificationPermissionRequestedAt =>
      dateTime().nullable()();

  /// Whether the other member's activity is announced on this device. Defaults
  /// to on: a member who granted the permission asked to be told.
  BoolColumn get householdActivityNotificationsEnabled =>
      boolean().withDefault(const Constant<bool>(true))();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{singletonId};
}

@DriftDatabase(
  tables: <Type>[
    LocalExpenses,
    LocalPeriods,
    LocalLoans,
    OutboxMutations,
    SyncMetadata,
  ],
)
final class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  AppDatabase.open()
    : super(
        driftDatabase(
          name: 'household_expenses',
          native: const DriftNativeOptions(shareAcrossIsolates: true),
        ),
      );

  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator migrator) async {
      await migrator.createAll();
      await into(syncMetadata).insert(
        SyncMetadataCompanion.insert(
          singletonId: const Value<int>(1),
          updatedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        ),
      );
    },
    onUpgrade: (Migrator migrator, int from, int to) async {
      // Each step checks `to` as well as `from`: on a device `to` is always the
      // current schemaVersion, but the migration tests replay history one
      // version at a time and must stop where they aimed.
      if (from < 2 && to >= 2) {
        await migrator.addColumn(
          syncMetadata,
          syncMetadata.lastSuccessfulSyncAt,
        );
      }
      if (from < 3 && to >= 3) {
        // Spending periods and the lending ledger arrive together. Existing
        // expenses keep a null periodId: the next bootstrap stamps them, and
        // until then their replayed mutations let the server choose the period.
        await migrator.createTable(localPeriods);
        await migrator.createTable(localLoans);
        await migrator.addColumn(localExpenses, localExpenses.periodId);
        await migrator.addColumn(outboxMutations, outboxMutations.entityType);
      }
      if (from < 4 && to >= 4) {
        // Notification preferences only. Echo detection needs no local state:
        // the change feed names each change's author, so an upgrading device
        // needs nothing carried over. The default keeps announcements on, and a
        // null request timestamp means the permission dialog is still owed.
        await migrator.addColumn(
          syncMetadata,
          syncMetadata.notificationPermissionRequestedAt,
        );
        await migrator.addColumn(
          syncMetadata,
          syncMetadata.householdActivityNotificationsEnabled,
        );
      }
      // Every future schema version must add an explicit, tested migration.
      if (to > 4) {
        throw StateError('Missing database migration from $from to $to.');
      }
    },
    beforeOpen: (OpeningDetails details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  Stream<List<LocalExpenseRow>> watchVisibleExpenseRows() {
    final query = select(localExpenses)
      ..where((row) => row.deletedAt.isNull())
      ..orderBy(<OrderingTerm Function(LocalExpenses)>[
        (row) => OrderingTerm.desc(row.occurredAt),
        (row) => OrderingTerm.desc(row.updatedAt),
      ]);
    return query.watch();
  }

  Future<List<LocalExpenseRow>> readVisibleExpenseRows() {
    final query = select(localExpenses)
      ..where((row) => row.deletedAt.isNull())
      ..orderBy(<OrderingTerm Function(LocalExpenses)>[
        (row) => OrderingTerm.desc(row.occurredAt),
        (row) => OrderingTerm.desc(row.updatedAt),
      ]);
    return query.get();
  }

  Future<LocalExpenseRow?> findExpenseRow(String id) {
    return (select(
      localExpenses,
    )..where((row) => row.id.equals(id))).getSingleOrNull();
  }

  /// Newest period first, so the open one leads the list.
  Stream<List<LocalPeriodRow>> watchPeriodRows() {
    final query = select(localPeriods)
      ..orderBy(<OrderingTerm Function(LocalPeriods)>[
        (row) => OrderingTerm.desc(row.sequenceNumber),
      ]);
    return query.watch();
  }

  Future<List<LocalPeriodRow>> readPeriodRows() {
    final query = select(localPeriods)
      ..orderBy(<OrderingTerm Function(LocalPeriods)>[
        (row) => OrderingTerm.desc(row.sequenceNumber),
      ]);
    return query.get();
  }

  /// The single period the household is currently spending against, or null
  /// before the first bootstrap has delivered one.
  Stream<LocalPeriodRow?> watchOpenPeriodRow() {
    final query = select(localPeriods)
      ..where((row) => row.closedAt.isNull())
      ..orderBy(<OrderingTerm Function(LocalPeriods)>[
        (row) => OrderingTerm.desc(row.sequenceNumber),
      ])
      ..limit(1);
    return query.watchSingleOrNull();
  }

  Future<LocalPeriodRow?> readOpenPeriodRow() {
    final query = select(localPeriods)
      ..where((row) => row.closedAt.isNull())
      ..orderBy(<OrderingTerm Function(LocalPeriods)>[
        (row) => OrderingTerm.desc(row.sequenceNumber),
      ])
      ..limit(1);
    return query.getSingleOrNull();
  }

  Future<LocalPeriodRow?> findPeriodRow(String id) {
    return (select(
      localPeriods,
    )..where((row) => row.id.equals(id))).getSingleOrNull();
  }

  Future<int?> readHighestPeriodSequenceNumber() async {
    final highest = localPeriods.sequenceNumber.max();
    final row = await (selectOnly(
      localPeriods,
    )..addColumns(<Expression<Object>>[highest])).getSingle();
    return row.read(highest);
  }

  Stream<List<LocalLoanRow>> watchVisibleLoanRows() {
    final query = select(localLoans)
      ..where((row) => row.deletedAt.isNull())
      ..orderBy(<OrderingTerm Function(LocalLoans)>[
        (row) => OrderingTerm.desc(row.occurredAt),
        (row) => OrderingTerm.desc(row.updatedAt),
      ]);
    return query.watch();
  }

  Future<List<LocalLoanRow>> readVisibleLoanRows() {
    final query = select(localLoans)
      ..where((row) => row.deletedAt.isNull())
      ..orderBy(<OrderingTerm Function(LocalLoans)>[
        (row) => OrderingTerm.desc(row.occurredAt),
        (row) => OrderingTerm.desc(row.updatedAt),
      ]);
    return query.get();
  }

  Future<LocalLoanRow?> findLoanRow(String id) {
    return (select(
      localLoans,
    )..where((row) => row.id.equals(id))).getSingleOrNull();
  }

  Future<SyncMetadataRow> readSyncMetadata() async {
    final existing = await (select(
      syncMetadata,
    )..where((row) => row.singletonId.equals(1))).getSingleOrNull();
    if (existing != null) {
      return existing;
    }
    final row = SyncMetadataCompanion.insert(
      singletonId: const Value<int>(1),
      updatedAt: DateTime.now().toUtc(),
    );
    await into(syncMetadata).insert(row);
    return (select(
      syncMetadata,
    )..where((item) => item.singletonId.equals(1))).getSingle();
  }

  Stream<SyncMetadataRow> watchSyncMetadata() {
    return (select(
      syncMetadata,
    )..where((row) => row.singletonId.equals(1))).watchSingle();
  }

  Stream<int> watchUnresolvedMutationCount() {
    final count = outboxMutations.localSequence.count();
    return (selectOnly(outboxMutations)
          ..addColumns(<Expression<Object>>[count]))
        .watchSingle()
        .map((row) => row.read(count) ?? 0);
  }
}
