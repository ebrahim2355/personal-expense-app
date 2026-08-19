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

  /// When this app last opened Android's battery-optimization screen, or null.
  ///
  /// No longer written. It existed to stop a startup ask from reappearing on
  /// every launch, and that ask is gone: the exemption is now requested only from
  /// the Settings advisory, where the member initiates it and Android's live
  /// answer is the only state needed. The column stays because dropping it would
  /// cost a schema version and a table-rewriting migration against the
  /// household's live database to reclaim one nullable field of one row — and
  /// because what the two phones already have stored is a true record of when
  /// each was asked.
  DateTimeColumn get batteryExemptionRequestedAt => dateTime().nullable()();

  /// When the WorkManager isolate last finished a run, or null when it never has
  /// on this install. Distinct from [lastSuccessfulSyncAt], which any foreground
  /// sync also moves: this one answers "is the OS letting background delivery
  /// happen at all", which is otherwise invisible from inside the app.
  DateTimeColumn get lastBackgroundSyncAt => dateTime().nullable()();

  /// The SHA-256 of the FCM registration token this device last successfully
  /// registered with the API, or null when it has registered none.
  ///
  /// A digest rather than the token so the plain local database never holds a
  /// value that could be used to send this phone a message. It exists to answer
  /// one question — has the token changed since the server was last told? —
  /// because the client cannot otherwise tell a token the server already has
  /// from one whose registration never arrived.
  TextColumn get fcmTokenFingerprint => text().nullable()();

  /// When [fcmTokenFingerprint] was accepted by the API. Null while a
  /// registration is still owed, which is what makes a failed attempt retry on
  /// the next launch instead of being mistaken for a completed one.
  DateTimeColumn get fcmTokenRegisteredAt => dateTime().nullable()();

  /// When a push last woke this device, or null when none ever has.
  ///
  /// The diagnostic that separates a working push from a well-timed poll: it is
  /// written only by the two push paths, never by the scheduled worker, so
  /// "never received on this device" is an honest answer rather than an absence
  /// of evidence.
  DateTimeColumn get lastPushReceivedAt => dateTime().nullable()();

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
  int get schemaVersion => 6;

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
      if (from < 5 && to >= 5) {
        // Background-delivery health. Both start null on an upgrading device,
        // and null is the honest answer in each case: the exemption has not been
        // asked for on this install, and no background run has been observed
        // yet. Neither is inferable from the columns that already exist.
        await migrator.addColumn(
          syncMetadata,
          syncMetadata.batteryExemptionRequestedAt,
        );
        await migrator.addColumn(
          syncMetadata,
          syncMetadata.lastBackgroundSyncAt,
        );
      }
      if (from < 6 && to >= 6) {
        // Push arrives. All three start null on an upgrading device, and null is
        // the truthful value in each case: nothing has been registered with the
        // API yet, so the next launch registers, and no push has been received
        // because this build is the first that can receive one.
        await migrator.addColumn(
          syncMetadata,
          syncMetadata.fcmTokenFingerprint,
        );
        await migrator.addColumn(
          syncMetadata,
          syncMetadata.fcmTokenRegisteredAt,
        );
        await migrator.addColumn(syncMetadata, syncMetadata.lastPushReceivedAt);
      }
      // Every future schema version must add an explicit, tested migration.
      if (to > 6) {
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

  /// Records that the background isolate reached the end of a run.
  ///
  /// Written for every outcome, including an offline one. The question this
  /// answers is whether Android let the worker run at all, and a run that found
  /// no network answers that just as well as one that synced. Deliberately does
  /// not touch `updatedAt`, which tracks changes to the member's own settings.
  Future<void> recordBackgroundSync(DateTime at) async {
    // Ensures the singleton exists before updating it.
    await readSyncMetadata();
    await (update(
      syncMetadata,
    )..where((row) => row.singletonId.equals(1))).write(
      SyncMetadataCompanion(lastBackgroundSyncAt: Value<DateTime>(at)),
    );
  }

  /// Records that a push woke this device, from whichever isolate received it.
  ///
  /// Deliberately separate from [recordBackgroundSync]: that column answers
  /// whether Android runs the scheduled worker, and a push arriving says nothing
  /// about it. Writing both from here would let a healthy push report background
  /// polling as working when it is not.
  Future<void> recordPushReceived(DateTime at) async {
    // Ensures the singleton exists before updating it.
    await readSyncMetadata();
    await (update(syncMetadata)..where((row) => row.singletonId.equals(1)))
        .write(SyncMetadataCompanion(lastPushReceivedAt: Value<DateTime>(at)));
  }

  /// Records the token the API has accepted, so the next launch can tell an
  /// already registered token from one whose registration never landed.
  Future<void> recordDeviceRegistration({
    required String fingerprint,
    required DateTime at,
  }) async {
    await readSyncMetadata();
    await (update(
      syncMetadata,
    )..where((row) => row.singletonId.equals(1))).write(
      SyncMetadataCompanion(
        fcmTokenFingerprint: Value<String>(fingerprint),
        fcmTokenRegisteredAt: Value<DateTime>(at),
      ),
    );
  }

  /// Forgets the registration, so the next sign-in registers again from scratch.
  Future<void> clearDeviceRegistration() async {
    await readSyncMetadata();
    await (update(
      syncMetadata,
    )..where((row) => row.singletonId.equals(1))).write(
      const SyncMetadataCompanion(
        fcmTokenFingerprint: Value<String?>(null),
        fcmTokenRegisteredAt: Value<DateTime?>(null),
      ),
    );
  }

  Stream<int> watchUnresolvedMutationCount() {
    final count = outboxMutations.localSequence.count();
    return (selectOnly(outboxMutations)
          ..addColumns(<Expression<Object>>[count]))
        .watchSingle()
        .map((row) => row.read(count) ?? 0);
  }
}
