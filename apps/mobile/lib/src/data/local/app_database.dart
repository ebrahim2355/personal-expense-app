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

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{singletonId};
}

@DriftDatabase(tables: <Type>[LocalExpenses, OutboxMutations, SyncMetadata])
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
  int get schemaVersion => 1;

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
      // Every future schema version must add an explicit, tested migration.
      if (from != to) {
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
}
