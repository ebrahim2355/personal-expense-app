import 'package:drift/drift.dart' hide isNull;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:houseexpenses/src/data/local/app_database.dart';

import 'generated/schema.dart';
import 'generated/schema_v2.dart' as v2;

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
}
