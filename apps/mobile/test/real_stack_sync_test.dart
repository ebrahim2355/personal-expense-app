import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:houseexpenses/src/application/session_controller.dart';
import 'package:houseexpenses/src/application/sync_coordinator.dart';
import 'package:houseexpenses/src/data/local/app_database.dart';
import 'package:houseexpenses/src/data/remote/api_client.dart';
import 'package:houseexpenses/src/data/remote/http_transport.dart';
import 'package:houseexpenses/src/data/repositories/auth_repository.dart';
import 'package:houseexpenses/src/data/repositories/expense_repository.dart';
import 'package:houseexpenses/src/data/security/token_store.dart';
import 'package:houseexpenses/src/domain/dhaka_time.dart';
import 'package:houseexpenses/src/domain/expense.dart';
import 'package:houseexpenses/src/domain/money.dart';
import 'package:houseexpenses/src/domain/session.dart';

const apiBaseUrl = String.fromEnvironment('REAL_STACK_API_BASE_URL');
const sumonPin = String.fromEnvironment('REAL_STACK_SUMON_PIN');
const ebrahimPin = String.fromEnvironment('REAL_STACK_EBRAHIM_PIN');
const realStackSkip = apiBaseUrl == ''
    ? 'Run through npm run test:real-stack to start PostgreSQL and the API.'
    : false;

void main() {
  // Every simulated device owns a distinct SQLite file and query executor.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  group('real PostgreSQL/API with two independent mobile databases', () {
    late Directory sandbox;
    late List<RealMobileClient> clients;

    setUp(() async {
      if (sumonPin.isEmpty || ebrahimPin.isEmpty) {
        fail('The real-stack runner must supply both temporary test PINs.');
      }
      sandbox = await Directory.systemTemp.createTemp('expenses-e2e-');
      clients = <RealMobileClient>[];
    });

    tearDown(() async {
      for (final client in clients.reversed) {
        await client.close();
      }
      if (await sandbox.exists()) {
        await sandbox.delete(recursive: true);
      }
    });

    Future<RealMobileClient> signedInClient(
      String name,
      HouseholdMember member, {
      int pageSize = 100,
      DateTime Function()? clock,
      HttpTransport Function(HttpTransport inner)? decorateTransport,
    }) async {
      final client = await RealMobileClient.open(
        databaseFile: File('${sandbox.path}/$name.sqlite'),
        member: member,
        pin: member == HouseholdMember.sumon ? sumonPin : ebrahimPin,
        pageSize: pageSize,
        clock: clock,
        decorateTransport: decorateTransport,
      );
      clients.add(client);
      await client.syncCompleted();
      return client;
    }

    test('1. offline Sumon create reaches Ebrahim after reconnect', () async {
      final sumon = await signedInClient(
        'scenario-1-sumon',
        HouseholdMember.sumon,
      );
      final ebrahim = await signedInClient(
        'scenario-1-ebrahim',
        HouseholdMember.ebrahim,
      );

      final created = await sumon.repository.create(
        fixtureDraft(amountMinor: 10101, note: 'scenario-1'),
      );
      expect((await sumon.only(created.id)).syncState, LocalSyncState.pending);
      expect(await ebrahim.find(created.id), isNull);

      await sumon.syncCompleted();
      await ebrahim.syncCompleted();

      expect((await ebrahim.only(created.id)).amountMinor, 10101);
      expect((await ebrahim.only(created.id)).version, 1);
    });

    test('2. concurrent offline creates converge exactly once', () async {
      final sumon = await signedInClient(
        'scenario-2-sumon',
        HouseholdMember.sumon,
      );
      final ebrahim = await signedInClient(
        'scenario-2-ebrahim',
        HouseholdMember.ebrahim,
      );
      final fromSumon = await sumon.repository.create(
        fixtureDraft(amountMinor: 20001, note: 'scenario-2-sumon'),
      );
      final fromEbrahim = await ebrahim.repository.create(
        fixtureDraft(
          amountMinor: 20002,
          payer: HouseholdMember.ebrahim,
          note: 'scenario-2-ebrahim',
        ),
      );

      await sumon.syncCompleted();
      await ebrahim.syncCompleted();
      await sumon.syncCompleted();

      for (final client in <RealMobileClient>[sumon, ebrahim]) {
        final ids = (await client.repository.readVisibleExpenses())
            .where(
              (expense) =>
                  expense.id == fromSumon.id || expense.id == fromEbrahim.id,
            )
            .map((expense) => expense.id)
            .toList(growable: false);
        expect(ids, hasLength(2));
        expect(ids.toSet(), <String>{fromSumon.id, fromEbrahim.id});
      }
    });

    test('3. a lost mutation response retries without duplication', () async {
      var now = DateTime.utc(2026, 8, 13, 12);
      late LostFirstMutationResponseTransport lossy;
      final sumon = await signedInClient(
        'scenario-3-sumon',
        HouseholdMember.sumon,
        clock: () => now,
        decorateTransport: (inner) =>
            lossy = LostFirstMutationResponseTransport(inner),
      );
      final ebrahim = await signedInClient(
        'scenario-3-ebrahim',
        HouseholdMember.ebrahim,
      );
      final created = await sumon.repository.create(
        fixtureDraft(amountMinor: 30003, note: 'scenario-3'),
      );

      expect(
        (await sumon.coordinator.synchronize()).outcome,
        SyncOutcome.offline,
      );
      expect(lossy.lostResponses, 1);
      now = now.add(const Duration(minutes: 16));
      await sumon.syncCompleted();
      await ebrahim.syncCompleted();

      expect(
        (await ebrahim.repository.readVisibleExpenses()).where(
          (expense) => expense.id == created.id,
        ),
        hasLength(1),
      );
      expect(
        await sumon.database.select(sumon.database.outboxMutations).get(),
        isEmpty,
      );
    });

    test('4. an edit made while Ebrahim is offline propagates later', () async {
      final sumon = await signedInClient(
        'scenario-4-sumon',
        HouseholdMember.sumon,
      );
      final ebrahim = await signedInClient(
        'scenario-4-ebrahim',
        HouseholdMember.ebrahim,
      );
      final created = await sumon.repository.create(
        fixtureDraft(amountMinor: 40000, note: 'scenario-4-original'),
      );
      await sumon.syncCompleted();
      await ebrahim.syncCompleted();

      await sumon.repository.edit(
        created.id,
        fixtureDraft(amountMinor: 44444, note: 'scenario-4-updated'),
      );
      await sumon.syncCompleted();
      expect((await ebrahim.only(created.id)).amountMinor, 40000);

      await ebrahim.syncCompleted();
      expect((await ebrahim.only(created.id)).amountMinor, 44444);
      expect((await ebrahim.only(created.id)).note, 'scenario-4-updated');
      expect((await ebrahim.only(created.id)).version, 2);
    });

    test(
      '5. stale concurrent edit keeps server data and emits conflict',
      () async {
        final sumon = await signedInClient(
          'scenario-5-sumon',
          HouseholdMember.sumon,
        );
        final ebrahim = await signedInClient(
          'scenario-5-ebrahim',
          HouseholdMember.ebrahim,
        );
        final created = await sumon.repository.create(
          fixtureDraft(amountMinor: 50000, note: 'scenario-5-original'),
        );
        await sumon.syncCompleted();
        await ebrahim.syncCompleted();

        await sumon.repository.edit(
          created.id,
          fixtureDraft(amountMinor: 51111, note: 'scenario-5-winner'),
        );
        await ebrahim.repository.edit(
          created.id,
          fixtureDraft(
            amountMinor: 52222,
            payer: HouseholdMember.ebrahim,
            note: 'scenario-5-stale',
          ),
        );
        await sumon.syncCompleted();
        final notice = ebrahim.coordinator.notices.first;
        await ebrahim.syncCompleted();

        expect((await notice).kind, SyncNoticeKind.conflict);
        expect((await ebrahim.only(created.id)).amountMinor, 51111);
        expect((await ebrahim.only(created.id)).note, 'scenario-5-winner');
        expect((await ebrahim.only(created.id)).version, 2);
        expect(
          await ebrahim.database.select(ebrahim.database.outboxMutations).get(),
          isEmpty,
        );
      },
    );

    test('6. tombstone reaches the other client and updates totals', () async {
      final sumon = await signedInClient(
        'scenario-6-sumon',
        HouseholdMember.sumon,
      );
      final ebrahim = await signedInClient(
        'scenario-6-ebrahim',
        HouseholdMember.ebrahim,
      );
      final created = await sumon.repository.create(
        fixtureDraft(amountMinor: 60000, note: 'scenario-6'),
      );
      await sumon.syncCompleted();
      await ebrahim.syncCompleted();
      expect(
        summarizeExpenses(<Expense>[await ebrahim.only(created.id)]).totalMinor,
        60000,
      );

      await sumon.repository.delete(created.id);
      await sumon.syncCompleted();
      await ebrahim.syncCompleted();

      expect(await ebrahim.find(created.id), isNull);
      final tombstone = await ebrahim.database.findExpenseRow(created.id);
      expect(tombstone?.deletedAt, isNotNull);
      final active = (await ebrahim.repository.readVisibleExpenses()).where(
        (expense) => expense.id == created.id,
      );
      expect(summarizeExpenses(active).totalMinor, 0);
    });

    test('7. interrupted cursor pagination resumes without gaps', () async {
      late InterruptingChangeTransport interrupted;
      final receiver = await signedInClient(
        'scenario-7-receiver',
        HouseholdMember.ebrahim,
        pageSize: 1,
        decorateTransport: (inner) =>
            interrupted = InterruptingChangeTransport(inner),
      );
      final sender = await signedInClient(
        'scenario-7-sender',
        HouseholdMember.sumon,
      );
      final baselineCursor =
          (await receiver.database.readSyncMetadata()).lastCursor;
      final created = <Expense>[];
      for (var index = 0; index < 3; index += 1) {
        created.add(
          await sender.repository.create(
            fixtureDraft(amountMinor: 70000 + index, note: 'scenario-7-$index'),
          ),
        );
      }
      await sender.syncCompleted();

      interrupted.arm(failOnRequest: 2);
      expect(
        (await receiver.coordinator.synchronize()).outcome,
        SyncOutcome.offline,
      );
      final committedAfterFirstPage =
          (await receiver.database.readSyncMetadata()).lastCursor;
      expect(committedAfterFirstPage, isNot(equals(baselineCursor)));

      await receiver.syncCompleted();
      final expectedIds = created.map((expense) => expense.id).toSet();
      final receivedIds = (await receiver.repository.readVisibleExpenses())
          .where((expense) => expectedIds.contains(expense.id))
          .map((expense) => expense.id)
          .toList(growable: false);
      expect(receivedIds, hasLength(3));
      expect(receivedIds.toSet(), expectedIds);
    });

    test(
      '8. refresh happens once and revoked credentials preserve local intent',
      () async {
        late RecordingTransport recording;
        final sumon = await signedInClient(
          'scenario-8-sumon',
          HouseholdMember.sumon,
          decorateTransport: (inner) => recording = RecordingTransport(inner),
        );
        recording.clear();
        final valid = sumon.tokenStore.tokens!;
        sumon.tokenStore.tokens = withAccessToken(
          valid,
          'expired-access-token',
        );

        await sumon.syncCompleted();
        expect(recording.count('/v1/auth/refresh'), 1);
        expect(sumon.session.current.status, SessionStatus.signedIn);

        recording.clear();
        final rotated = sumon.tokenStore.tokens!;
        await DioAuthenticationApi(sumon.transport).logout(rotated);
        sumon.tokenStore.tokens = withAccessToken(
          rotated,
          'expired-access-token',
        );
        final pending = await sumon.repository.create(
          fixtureDraft(amountMinor: 80008, note: 'scenario-8-pending'),
        );

        expect(
          (await sumon.coordinator.synchronize()).outcome,
          SyncOutcome.authenticationRequired,
        );
        expect(recording.count('/v1/auth/refresh'), 1);
        expect(sumon.session.current.status, SessionStatus.signedOut);
        expect(
          (await sumon.only(pending.id)).syncState,
          LocalSyncState.pending,
        );
        expect(
          await sumon.database.select(sumon.database.outboxMutations).get(),
          isNotEmpty,
        );
      },
    );

    test(
      '9. a process restart retains and later sends the durable outbox',
      () async {
        final databaseFile = File('${sandbox.path}/scenario-9-sumon.sqlite');
        final first = await RealMobileClient.open(
          databaseFile: databaseFile,
          member: HouseholdMember.sumon,
          pin: sumonPin,
        );
        clients.add(first);
        await first.syncCompleted();
        final pending = await first.repository.create(
          fixtureDraft(amountMinor: 90009, note: 'scenario-9'),
        );
        final storedTokens = first.tokenStore.tokens!;
        await first.close();

        final restarted = await RealMobileClient.open(
          databaseFile: databaseFile,
          existingTokens: storedTokens,
        );
        clients.add(restarted);
        expect(
          (await restarted.only(pending.id)).syncState,
          LocalSyncState.pending,
        );
        expect(
          await restarted.database
              .select(restarted.database.outboxMutations)
              .get(),
          hasLength(1),
        );

        await restarted.syncCompleted();
        expect(
          await restarted.database
              .select(restarted.database.outboxMutations)
              .get(),
          isEmpty,
        );
        expect((await restarted.only(pending.id)).version, 1);

        final ebrahim = await signedInClient(
          'scenario-9-ebrahim',
          HouseholdMember.ebrahim,
        );
        expect((await ebrahim.only(pending.id)).amountMinor, 90009);
      },
    );

    test('10. UTC boundary rows filter into the correct Dhaka month', () async {
      final sumon = await signedInClient(
        'scenario-10-sumon',
        HouseholdMember.sumon,
      );
      final ebrahim = await signedInClient(
        'scenario-10-ebrahim',
        HouseholdMember.ebrahim,
      );
      final july = await sumon.repository.create(
        fixtureDraft(
          amountMinor: 100010,
          note: 'scenario-10-july',
          occurredAt: DateTime.utc(2026, 7, 31, 17, 59, 59),
        ),
      );
      final august = await sumon.repository.create(
        fixtureDraft(
          amountMinor: 100011,
          note: 'scenario-10-august',
          occurredAt: DateTime.utc(2026, 7, 31, 18),
        ),
      );
      await sumon.syncCompleted();
      await ebrahim.syncCompleted();

      final augustRange = DhakaTime.initialize().range(
        const CalendarDate(2026, 8, 1),
        const CalendarDate(2026, 8, 31),
      );
      final selected = (await ebrahim.repository.readVisibleExpenses())
          .where(
            (expense) =>
                (expense.id == july.id || expense.id == august.id) &&
                augustRange.contains(expense.occurredAt),
          )
          .toList(growable: false);
      expect(selected.map((expense) => expense.id), <String>[august.id]);
      expect(summarizeExpenses(selected).totalMinor, 100011);
    });
  }, skip: realStackSkip);
}

ExpenseDraft fixtureDraft({
  required int amountMinor,
  required String note,
  HouseholdMember payer = HouseholdMember.sumon,
  DateTime? occurredAt,
}) {
  return ExpenseDraft(
    amountMinor: amountMinor,
    category: ExpenseCategory.household,
    payer: payer,
    occurredAt: occurredAt ?? DateTime.utc(2026, 8, 13, 6),
    note: note,
  );
}

SessionTokens withAccessToken(SessionTokens tokens, String accessToken) {
  return SessionTokens(
    accessToken: accessToken,
    accessTokenExpiresAt: DateTime.utc(2020),
    refreshToken: tokens.refreshToken,
    refreshTokenExpiresAt: tokens.refreshTokenExpiresAt,
  );
}

final class RealMobileClient {
  RealMobileClient._({
    required this.database,
    required this.repository,
    required this.tokenStore,
    required this.session,
    required this.transport,
    required this.authRepository,
    required this.coordinator,
  });

  static Future<RealMobileClient> open({
    required File databaseFile,
    HouseholdMember? member,
    String? pin,
    SessionTokens? existingTokens,
    int pageSize = 100,
    DateTime Function()? clock,
    HttpTransport Function(HttpTransport inner)? decorateTransport,
  }) async {
    final database = AppDatabase(NativeDatabase(databaseFile));
    final repository = DriftExpenseRepository(database);
    final tokenStore = MemoryTokenStore(existingTokens);
    final session = SessionController(tokenStore);
    await session.initialize();
    final baseTransport = DioHttpTransport(Uri.parse(apiBaseUrl));
    final transport = decorateTransport?.call(baseTransport) ?? baseTransport;
    final authenticationApi = DioAuthenticationApi(transport);
    final authRepository = AuthRepository(
      api: authenticationApi,
      tokenStore: tokenStore,
      sessionController: session,
      database: database,
    );
    final authenticatedClient = AuthenticatedApiClient(
      transport: transport,
      tokenStore: tokenStore,
      sessionController: session,
    );
    final coordinator = SyncCoordinator(
      database: database,
      api: DioExpenseSyncApi(authenticatedClient),
      pageSize: pageSize,
      clock: clock,
    );
    final client = RealMobileClient._(
      database: database,
      repository: repository,
      tokenStore: tokenStore,
      session: session,
      transport: transport,
      authRepository: authRepository,
      coordinator: coordinator,
    );
    if (member != null) {
      await authRepository.login(member, pin ?? '');
    }
    return client;
  }

  final AppDatabase database;
  final DriftExpenseRepository repository;
  final MemoryTokenStore tokenStore;
  final SessionController session;
  final HttpTransport transport;
  final AuthRepository authRepository;
  final SyncCoordinator coordinator;
  bool _closed = false;

  Future<void> syncCompleted() async {
    final report = await coordinator.synchronize();
    expect(report.outcome, SyncOutcome.completed, reason: '${report.error}');
  }

  Future<Expense?> find(String id) async {
    final expenses = await repository.readVisibleExpenses();
    return expenses.where((expense) => expense.id == id).firstOrNull;
  }

  Future<Expense> only(String id) async {
    final expenses = await repository.readVisibleExpenses();
    return expenses.singleWhere((expense) => expense.id == id);
  }

  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    await coordinator.close();
    await repository.close();
    await session.close();
    await database.close();
  }
}

class RecordingTransport implements HttpTransport {
  RecordingTransport(this.inner);

  final HttpTransport inner;
  final List<String> paths = <String>[];

  @override
  Future<TransportResponse> send(TransportRequest request) {
    paths.add(request.path);
    return inner.send(request);
  }

  int count(String path) => paths.where((value) => value == path).length;

  void clear() => paths.clear();
}

final class LostFirstMutationResponseTransport extends RecordingTransport {
  LostFirstMutationResponseTransport(super.inner);

  int lostResponses = 0;

  @override
  Future<TransportResponse> send(TransportRequest request) async {
    paths.add(request.path);
    final response = await inner.send(request);
    if (request.path == '/v1/sync/mutations' && lostResponses == 0) {
      lostResponses += 1;
      throw const NetworkException('Simulated timeout after server commit.');
    }
    return response;
  }
}

final class InterruptingChangeTransport extends RecordingTransport {
  InterruptingChangeTransport(super.inner);

  bool _armed = false;
  int _changesSinceArm = 0;
  int _failOnRequest = 0;

  void arm({required int failOnRequest}) {
    _armed = true;
    _changesSinceArm = 0;
    _failOnRequest = failOnRequest;
  }

  @override
  Future<TransportResponse> send(TransportRequest request) {
    paths.add(request.path);
    if (_armed && request.path == '/v1/sync/changes') {
      _changesSinceArm += 1;
      if (_changesSinceArm == _failOnRequest) {
        _armed = false;
        throw const NetworkException('Simulated interrupted change page.');
      }
    }
    return inner.send(request);
  }
}
