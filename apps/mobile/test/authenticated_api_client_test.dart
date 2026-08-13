import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:houseexpenses/src/application/session_controller.dart';
import 'package:houseexpenses/src/data/local/app_database.dart';
import 'package:houseexpenses/src/data/remote/api_client.dart';
import 'package:houseexpenses/src/data/remote/http_transport.dart';
import 'package:houseexpenses/src/data/repositories/expense_repository.dart';
import 'package:houseexpenses/src/data/security/token_store.dart';
import 'package:houseexpenses/src/domain/expense.dart';
import 'package:houseexpenses/src/domain/session.dart';

import 'support/fakes.dart';

void main() {
  SessionTokens tokens(String suffix) => SessionTokens(
    accessToken: 'access-$suffix',
    accessTokenExpiresAt: DateTime.utc(2026, 8, 13, 13),
    refreshToken: 'refresh-$suffix',
    refreshTokenExpiresAt: DateTime.utc(2026, 9, 13),
  );

  Map<String, Object?> refreshBody(String suffix) => <String, Object?>{
    'member': <String, Object?>{
      'id': '00000000-0000-4000-8000-000000000010',
      'householdId': '00000000-0000-4000-8000-000000000020',
      'key': 'SUMON',
      'displayName': 'Sumon',
    },
    'accessToken': 'access-$suffix',
    'accessTokenExpiresAt': '2026-08-13T13:00:00.000Z',
    'refreshToken': 'refresh-$suffix',
    'refreshTokenExpiresAt': '2026-09-13T00:00:00.000Z',
  };

  test('a 401 refreshes once and retries the original request once', () async {
    final store = MemoryTokenStore(tokens('old'));
    final session = SessionController(store);
    await session.initialize();
    addTearDown(session.close);
    final transport = QueueHttpTransport(<TransportResponse>[
      const TransportResponse(statusCode: 401, data: <String, Object?>{}),
      TransportResponse(statusCode: 200, data: refreshBody('new')),
      const TransportResponse(
        statusCode: 200,
        data: <String, Object?>{'ok': true},
      ),
    ]);
    final client = AuthenticatedApiClient(
      transport: transport,
      tokenStore: store,
      sessionController: session,
    );

    final response = await client.send(
      const TransportRequest(method: 'GET', path: '/v1/sync/changes'),
    );

    expect(response.statusCode, 200);
    expect(transport.requests, hasLength(3));
    expect(transport.requests[1].path, '/v1/auth/refresh');
    expect(transport.requests[2].headers['Authorization'], 'Bearer access-new');
    expect(store.tokens!.refreshToken, 'refresh-new');
    expect(session.current.status, SessionStatus.signedIn);
  });

  test(
    'a second 401 signs out without a refresh loop and keeps local data',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      final repository = DriftExpenseRepository(database);
      addTearDown(() async {
        await repository.close();
        await database.close();
      });
      await repository.create(
        ExpenseDraft(
          amountMinor: 700,
          category: ExpenseCategory.medicine,
          payer: HouseholdMember.ebrahim,
          occurredAt: DateTime.utc(2026, 8, 13),
        ),
      );

      final store = MemoryTokenStore(tokens('old'));
      final session = SessionController(store);
      await session.initialize();
      addTearDown(session.close);
      final transport = QueueHttpTransport(<TransportResponse>[
        const TransportResponse(statusCode: 401, data: <String, Object?>{}),
        TransportResponse(statusCode: 200, data: refreshBody('new')),
        const TransportResponse(statusCode: 401, data: <String, Object?>{}),
      ]);
      final client = AuthenticatedApiClient(
        transport: transport,
        tokenStore: store,
        sessionController: session,
      );

      await expectLater(
        client.send(
          const TransportRequest(method: 'GET', path: '/v1/sync/changes'),
        ),
        throwsA(isA<AuthenticationExpiredException>()),
      );

      expect(transport.requests, hasLength(3));
      expect(
        transport.requests.where(
          (request) => request.path == '/v1/auth/refresh',
        ),
        hasLength(1),
      );
      expect(store.tokens, isNull);
      expect(session.current.status, SessionStatus.signedOut);
      expect(await repository.readVisibleExpenses(), hasLength(1));
      expect(
        await database.select(database.outboxMutations).get(),
        hasLength(1),
      );
    },
  );
}
