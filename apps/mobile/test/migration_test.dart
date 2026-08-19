import 'package:drift/drift.dart' hide isNull;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:houseexpenses/src/data/local/app_database.dart';

import 'generated/schema.dart';
import 'generated/schema_v2.dart' as v2;
import 'generated/schema_v3.dart' as v3;
import 'generated/schema_v4.dart' as v4;
import 'generated/schema_v5.dart' as v5;

/// Drift generates the historical schemas as bare `TableInfo`s with no data
/// classes, so fixtures are inserted column by column.
Insertable<Object?> rawRow(Map<String, Expression<Object>> values) =>
    RawValuesInsertable<Object?>(values);

void main() {
  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  test('migrates from v2 to v3', () async {
    final connection = await verifier.startAt(2);
    final database = AppDatabase(connection);
    addTearDown(database.close);

    await verifier.migrateAndValidate(database, 3);
  });

  test('carries a v2 expense forward without a period', () async {
    final schema = await verifier.schemaAt(2);
    final oldDatabase = v2.DatabaseAtV2(schema.newConnection());
    const expenseId = 'b2f2b1d4-5c8f-4a2e-9f1b-2c3d4e5f6a7b';
    final recordedAt = DateTime.utc(2026, 8, 1, 10);
    await oldDatabase
        .into(oldDatabase.localExpenses)
        .insert(
          rawRow(<String, Expression<Object>>{
            'id': const Variable<String>(expenseId),
            'amount_minor': const Variable<int>(40000),
            'category': const Variable<String>('GROCERIES'),
            'payer': const Variable<String>('SUMON'),
            'occurred_at': Variable<DateTime>(recordedAt),
            'note': const Variable<String>('Rice'),
            'version': const Variable<int>(3),
            'updated_at': Variable<DateTime>(recordedAt),
            'sync_state': const Variable<String>('SYNCED'),
            'local_modified_at': Variable<DateTime>(recordedAt),
          }),
        );
    await oldDatabase.close();

    final database = AppDatabase(schema.newConnection());
    addTearDown(database.close);
    await verifier.migrateAndValidate(database, 3);

    final migrated = await database.readVisibleExpenseRows();
    expect(migrated, hasLength(1));
    expect(migrated.single.id, expenseId);
    expect(migrated.single.note, 'Rice');
    // A pre-period expense has no period to name. The next bootstrap stamps it;
    // until then the server decides where a replayed mutation lands.
    expect(migrated.single.periodId, isNull);
    expect(await database.readOpenPeriodRow(), isNull);
    expect(await database.readVisibleLoanRows(), isEmpty);
  });

  test(
    'defaults an outbox row queued before periods existed to EXPENSE',
    () async {
      final schema = await verifier.schemaAt(2);
      final oldDatabase = v2.DatabaseAtV2(schema.newConnection());
      await oldDatabase
          .into(oldDatabase.outboxMutations)
          .insert(
            rawRow(<String, Expression<Object>>{
              'mutation_id': const Variable<String>(
                '9c1a7e26-3f4b-4d5c-8a9b-0c1d2e3f4a5b',
              ),
              'entity_id': const Variable<String>(
                'b2f2b1d4-5c8f-4a2e-9f1b-2c3d4e5f6a7b',
              ),
              'action': const Variable<String>('CREATE'),
              'base_version': const Variable<int>(0),
              'payload_json': const Variable<String>('{"amountMinor":40000}'),
              'created_at': Variable<DateTime>(DateTime.utc(2026, 8, 1, 10)),
              'status': const Variable<String>('PENDING'),
            }),
          );
      await oldDatabase.close();

      final database = AppDatabase(schema.newConnection());
      addTearDown(database.close);
      await verifier.migrateAndValidate(database, 3);

      final pending = await database.select(database.outboxMutations).get();
      expect(pending, hasLength(1));
      expect(pending.single.entityType, 'EXPENSE');
    },
  );

  test('migrates from v3 to v4', () async {
    final connection = await verifier.startAt(3);
    final database = AppDatabase(connection);
    addTearDown(database.close);

    await verifier.migrateAndValidate(database, 4);
  });

  test('leaves an upgraded device announcing and still owed the ask', () async {
    final schema = await verifier.schemaAt(3);
    final oldDatabase = v3.DatabaseAtV3(schema.newConnection());
    final recordedAt = DateTime.utc(2026, 8, 14, 9);
    await oldDatabase
        .into(oldDatabase.syncMetadata)
        .insert(
          rawRow(<String, Expression<Object>>{
            'singleton_id': const Variable<int>(1),
            'member_key': const Variable<String>('EBRAHIM'),
            'last_cursor': const Variable<String>('cursor-9'),
            'updated_at': Variable<DateTime>(recordedAt),
          }),
        );
    await oldDatabase.close();

    final database = AppDatabase(schema.newConnection());
    addTearDown(database.close);
    await verifier.migrateAndValidate(database, 4);

    final metadata = await database.readSyncMetadata();
    // The sync state the device already had must survive untouched: a member who
    // upgrades does not re-bootstrap.
    expect(metadata.memberKey, 'EBRAHIM');
    expect(metadata.lastCursor, 'cursor-9');
    // Announcements default to on, and a null timestamp means the permission
    // dialog has not been shown yet — so the next launch asks for it.
    expect(metadata.householdActivityNotificationsEnabled, isTrue);
    expect(metadata.notificationPermissionRequestedAt, isNull);
  });

  test('migrates from v4 to v5', () async {
    final connection = await verifier.startAt(4);
    final database = AppDatabase(connection);
    addTearDown(database.close);

    await verifier.migrateAndValidate(database, 5);
  });

  test(
    'leaves an upgraded device owed the exemption ask and unproven',
    () async {
      final schema = await verifier.schemaAt(4);
      final oldDatabase = v4.DatabaseAtV4(schema.newConnection());
      final recordedAt = DateTime.utc(2026, 8, 18, 16);
      await oldDatabase
          .into(oldDatabase.syncMetadata)
          .insert(
            rawRow(<String, Expression<Object>>{
              'singleton_id': const Variable<int>(1),
              'member_key': const Variable<String>('EBRAHIM'),
              'last_cursor': const Variable<String>('cursor-11'),
              'updated_at': Variable<DateTime>(recordedAt),
              'notification_permission_requested_at': Variable<DateTime>(
                recordedAt,
              ),
              'household_activity_notifications_enabled': const Variable<bool>(
                false,
              ),
            }),
          );
      await oldDatabase.close();

      final database = AppDatabase(schema.newConnection());
      addTearDown(database.close);
      await verifier.migrateAndValidate(database, 5);

      final metadata = await database.readSyncMetadata();
      // Everything the device had chosen survives, including a switch it had
      // deliberately turned off.
      expect(metadata.memberKey, 'EBRAHIM');
      expect(metadata.lastCursor, 'cursor-11');
      expect(metadata.householdActivityNotificationsEnabled, isFalse);
      expect(metadata.notificationPermissionRequestedAt?.toUtc(), recordedAt);
      // Null is the honest answer to both new questions: this install has never
      // been asked about battery optimization, and no background run has been
      // observed. Neither is inferable from the columns that already existed.
      expect(metadata.batteryExemptionRequestedAt, isNull);
      expect(metadata.lastBackgroundSyncAt, isNull);
    },
  );

  test('migrates from v5 to v6', () async {
    final connection = await verifier.startAt(5);
    final database = AppDatabase(connection);
    addTearDown(database.close);

    await verifier.migrateAndValidate(database, 6);
  });

  test('leaves an upgraded device unregistered and never pushed to', () async {
    final schema = await verifier.schemaAt(5);
    final oldDatabase = v5.DatabaseAtV5(schema.newConnection());
    final recordedAt = DateTime.utc(2026, 8, 18, 17);
    await oldDatabase
        .into(oldDatabase.syncMetadata)
        .insert(
          rawRow(<String, Expression<Object>>{
            'singleton_id': const Variable<int>(1),
            'member_key': const Variable<String>('EBRAHIM'),
            'last_cursor': const Variable<String>('cursor-13'),
            'updated_at': Variable<DateTime>(recordedAt),
            'notification_permission_requested_at': Variable<DateTime>(
              recordedAt,
            ),
            'battery_exemption_requested_at': Variable<DateTime>(recordedAt),
            'last_background_sync_at': Variable<DateTime>(recordedAt),
          }),
        );
    await oldDatabase.close();

    final database = AppDatabase(schema.newConnection());
    addTearDown(database.close);
    await verifier.migrateAndValidate(database, 6);

    final metadata = await database.readSyncMetadata();
    // The evidence the device had already gathered about background delivery
    // survives: push is added alongside polling, not in place of it.
    expect(metadata.memberKey, 'EBRAHIM');
    expect(metadata.lastCursor, 'cursor-13');
    expect(metadata.batteryExemptionRequestedAt?.toUtc(), recordedAt);
    expect(metadata.lastBackgroundSyncAt?.toUtc(), recordedAt);
    // All three start null, and each is truthful: this install has registered no
    // token with the API, so the next launch registers, and it has received no
    // push because this is the first build that can.
    expect(metadata.fcmTokenFingerprint, isNull);
    expect(metadata.fcmTokenRegisteredAt, isNull);
    expect(metadata.lastPushReceivedAt, isNull);
  });
}
