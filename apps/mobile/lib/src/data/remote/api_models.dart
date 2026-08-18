import '../../domain/expense.dart';
import '../../domain/loan.dart';
import '../../domain/session.dart';
import '../../domain/spending_period.dart';

Object? _required(Map<String, Object?> json, String key) {
  if (!json.containsKey(key)) {
    throw FormatException('Missing response property: $key');
  }
  return json[key];
}

Map<String, Object?> _objectMap(Object? value, String name) {
  if (value is! Map) {
    throw FormatException('$name must be an object.');
  }
  return value.map((key, item) => MapEntry(key.toString(), item));
}

List<Object?> _list(Object? value, String name) {
  if (value is! List) {
    throw FormatException('$name must be an array.');
  }
  return value.cast<Object?>();
}

String _string(Object? value, String name) {
  if (value is! String) {
    throw FormatException('$name must be a string.');
  }
  return value;
}

int _integer(Object? value, String name) {
  if (value is! int) {
    throw FormatException('$name must be an integer.');
  }
  return value;
}

bool _boolean(Object? value, String name) {
  if (value is! bool) {
    throw FormatException('$name must be a boolean.');
  }
  return value;
}

DateTime _instant(Object? value, String name) {
  final parsed = DateTime.tryParse(_string(value, name));
  if (parsed == null) {
    throw FormatException('$name must be an RFC 3339 timestamp.');
  }
  return parsed.toUtc();
}

final class MemberDto {
  const MemberDto({
    required this.id,
    required this.householdId,
    required this.member,
    required this.displayName,
  });

  factory MemberDto.fromJson(Map<String, Object?> json) => MemberDto(
    id: _string(_required(json, 'id'), 'member.id'),
    householdId: _string(_required(json, 'householdId'), 'member.householdId'),
    member: HouseholdMemberWire.parse(
      _string(_required(json, 'key'), 'member.key'),
    ),
    displayName: _string(_required(json, 'displayName'), 'member.displayName'),
  );

  final String id;
  final String householdId;
  final HouseholdMember member;
  final String displayName;

  MemberIdentity toDomain() => MemberIdentity(
    id: id,
    householdId: householdId,
    member: member,
    displayName: displayName,
  );
}

final class AuthResponseDto {
  const AuthResponseDto({required this.member, required this.tokens});

  factory AuthResponseDto.fromJson(
    Map<String, Object?> json,
  ) => AuthResponseDto(
    member: MemberDto.fromJson(_objectMap(_required(json, 'member'), 'member')),
    tokens: SessionTokens(
      accessToken: _string(_required(json, 'accessToken'), 'accessToken'),
      accessTokenExpiresAt: _instant(
        _required(json, 'accessTokenExpiresAt'),
        'accessTokenExpiresAt',
      ),
      refreshToken: _string(_required(json, 'refreshToken'), 'refreshToken'),
      refreshTokenExpiresAt: _instant(
        _required(json, 'refreshTokenExpiresAt'),
        'refreshTokenExpiresAt',
      ),
    ),
  );

  final MemberDto member;
  final SessionTokens tokens;
}

/// Which of the three synced entities a mutation, change or bootstrap item
/// describes. The wire default is EXPENSE, so a candidate queued before periods
/// and loans existed still names the right entity.
enum SyncEntityType { expense, period, loan }

extension SyncEntityTypeWire on SyncEntityType {
  String get wireName => switch (this) {
    SyncEntityType.expense => 'EXPENSE',
    SyncEntityType.period => 'PERIOD',
    SyncEntityType.loan => 'LOAN',
  };

  String get storedName => wireName;

  /// The payload property this entity's snapshot travels under.
  String get payloadKey => switch (this) {
    SyncEntityType.expense => 'expense',
    SyncEntityType.period => 'period',
    SyncEntityType.loan => 'loan',
  };

  static SyncEntityType parse(String value) => switch (value) {
    'EXPENSE' => SyncEntityType.expense,
    'PERIOD' => SyncEntityType.period,
    'LOAN' => SyncEntityType.loan,
    _ => throw FormatException('Unknown sync entity type: $value'),
  };

  static SyncEntityType parseOrExpense(Object? value) => value == null
      ? SyncEntityType.expense
      : parse(_string(value, 'entityType'));
}

final class ExpenseDto {
  const ExpenseDto({
    required this.id,
    required this.amountMinor,
    required this.category,
    required this.payer,
    required this.occurredAt,
    required this.version,
    required this.updatedAt,
    this.note,
    this.periodId,
    this.deletedAt,
  });

  factory ExpenseDto.fromJson(Map<String, Object?> json) {
    final noteValue = _required(json, 'note');
    final deletedValue = _required(json, 'deletedAt');
    return ExpenseDto(
      id: _string(_required(json, 'id'), 'expense.id'),
      amountMinor: _integer(
        _required(json, 'amountMinor'),
        'expense.amountMinor',
      ),
      category: ExpenseCategoryWire.parse(
        _string(_required(json, 'category'), 'expense.category'),
      ),
      payer: HouseholdMemberWire.parse(
        _string(_required(json, 'payer'), 'expense.payer'),
      ),
      occurredAt: _instant(_required(json, 'occurredAt'), 'expense.occurredAt'),
      note: noteValue == null ? null : _string(noteValue, 'expense.note'),
      periodId: _string(_required(json, 'periodId'), 'expense.periodId'),
      version: _integer(_required(json, 'version'), 'expense.version'),
      updatedAt: _instant(_required(json, 'updatedAt'), 'expense.updatedAt'),
      deletedAt: deletedValue == null
          ? null
          : _instant(deletedValue, 'expense.deletedAt'),
    );
  }

  final String id;
  final int amountMinor;
  final ExpenseCategory category;
  final HouseholdMember payer;
  final DateTime occurredAt;
  final String? note;
  final String? periodId;
  final int version;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  Expense toDomain({LocalSyncState syncState = LocalSyncState.synced}) =>
      Expense(
        id: id,
        amountMinor: amountMinor,
        category: category,
        payer: payer,
        occurredAt: occurredAt,
        note: note,
        periodId: periodId,
        version: version,
        updatedAt: updatedAt,
        deletedAt: deletedAt,
        syncState: syncState,
      );
}

final class PeriodDto {
  const PeriodDto({
    required this.id,
    required this.sequenceNumber,
    required this.startedAt,
    required this.version,
    required this.updatedAt,
    this.closedAt,
    this.note,
  });

  factory PeriodDto.fromJson(Map<String, Object?> json) {
    final noteValue = _required(json, 'note');
    final closedValue = _required(json, 'closedAt');
    return PeriodDto(
      id: _string(_required(json, 'id'), 'period.id'),
      sequenceNumber: _integer(
        _required(json, 'sequenceNumber'),
        'period.sequenceNumber',
      ),
      startedAt: _instant(_required(json, 'startedAt'), 'period.startedAt'),
      closedAt: closedValue == null
          ? null
          : _instant(closedValue, 'period.closedAt'),
      note: noteValue == null ? null : _string(noteValue, 'period.note'),
      version: _integer(_required(json, 'version'), 'period.version'),
      updatedAt: _instant(_required(json, 'updatedAt'), 'period.updatedAt'),
    );
  }

  final String id;
  final int sequenceNumber;
  final DateTime startedAt;
  final DateTime? closedAt;
  final String? note;
  final int version;
  final DateTime updatedAt;

  SpendingPeriod toDomain({LocalSyncState syncState = LocalSyncState.synced}) =>
      SpendingPeriod(
        id: id,
        sequenceNumber: sequenceNumber,
        startedAt: startedAt,
        closedAt: closedAt,
        note: note,
        version: version,
        updatedAt: updatedAt,
        syncState: syncState,
      );
}

final class LoanDto {
  const LoanDto({
    required this.id,
    required this.debtor,
    required this.amountMinor,
    required this.occurredAt,
    required this.version,
    required this.updatedAt,
    this.note,
    this.deletedAt,
  });

  factory LoanDto.fromJson(Map<String, Object?> json) {
    final noteValue = _required(json, 'note');
    final deletedValue = _required(json, 'deletedAt');
    return LoanDto(
      id: _string(_required(json, 'id'), 'loan.id'),
      debtor: HouseholdMemberWire.parse(
        _string(_required(json, 'debtor'), 'loan.debtor'),
      ),
      amountMinor: _integer(_required(json, 'amountMinor'), 'loan.amountMinor'),
      occurredAt: _instant(_required(json, 'occurredAt'), 'loan.occurredAt'),
      note: noteValue == null ? null : _string(noteValue, 'loan.note'),
      version: _integer(_required(json, 'version'), 'loan.version'),
      updatedAt: _instant(_required(json, 'updatedAt'), 'loan.updatedAt'),
      deletedAt: deletedValue == null
          ? null
          : _instant(deletedValue, 'loan.deletedAt'),
    );
  }

  final String id;
  final HouseholdMember debtor;
  final int amountMinor;
  final DateTime occurredAt;
  final String? note;
  final int version;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  Loan toDomain({LocalSyncState syncState = LocalSyncState.synced}) => Loan(
    id: id,
    debtor: debtor,
    amountMinor: amountMinor,
    occurredAt: occurredAt,
    note: note,
    version: version,
    updatedAt: updatedAt,
    deletedAt: deletedAt,
    syncState: syncState,
  );
}

enum MutationOperation { create, update, delete }

extension MutationOperationWire on MutationOperation {
  String get wireName => switch (this) {
    MutationOperation.create => 'CREATE',
    MutationOperation.update => 'UPDATE',
    MutationOperation.delete => 'DELETE',
  };

  String get storedName => wireName;

  static MutationOperation parse(String value) => switch (value) {
    'CREATE' => MutationOperation.create,
    'UPDATE' => MutationOperation.update,
    'DELETE' => MutationOperation.delete,
    _ => throw FormatException('Unknown mutation operation: $value'),
  };
}

final class MutationCandidateDto {
  const MutationCandidateDto({
    required this.mutationId,
    required this.entityId,
    required this.operation,
    required this.baseVersion,
    this.entityType = SyncEntityType.expense,
    this.expense,
    this.period,
    this.loan,
  });

  final String mutationId;
  final String entityId;
  final SyncEntityType entityType;
  final MutationOperation operation;
  final int baseVersion;
  final Map<String, Object?>? expense;
  final Map<String, Object?>? period;
  final Map<String, Object?>? loan;

  Map<String, Object?> toJson() => <String, Object?>{
    'mutationId': mutationId,
    'entityId': entityId,
    'entityType': entityType.wireName,
    'operation': operation.wireName,
    'baseVersion': baseVersion,
    if (expense != null) 'expense': expense,
    if (period != null) 'period': period,
    if (loan != null) 'loan': loan,
  };
}

enum MutationResultStatus { applied, conflict, rejected }

final class MutationResultDto {
  const MutationResultDto({
    required this.mutationId,
    required this.status,
    this.entityType = SyncEntityType.expense,
    this.code,
    this.expense,
    this.period,
    this.loan,
  });

  factory MutationResultDto.fromJson(Map<String, Object?> json) {
    final statusValue = _string(_required(json, 'status'), 'result.status');
    final status = switch (statusValue) {
      'APPLIED' => MutationResultStatus.applied,
      'CONFLICT' => MutationResultStatus.conflict,
      'REJECTED' => MutationResultStatus.rejected,
      _ => throw FormatException('Unknown mutation result: $statusValue'),
    };
    final expenseJson = json['expense'];
    final periodJson = json['period'];
    final loanJson = json['loan'];
    return MutationResultDto(
      mutationId: _string(_required(json, 'mutationId'), 'result.mutationId'),
      status: status,
      entityType: SyncEntityTypeWire.parseOrExpense(json['entityType']),
      code: json['code'] == null ? null : _string(json['code'], 'result.code'),
      expense: expenseJson == null
          ? null
          : ExpenseDto.fromJson(_objectMap(expenseJson, 'result.expense')),
      period: periodJson == null
          ? null
          : PeriodDto.fromJson(_objectMap(periodJson, 'result.period')),
      loan: loanJson == null
          ? null
          : LoanDto.fromJson(_objectMap(loanJson, 'result.loan')),
    );
  }

  final String mutationId;
  final MutationResultStatus status;
  final SyncEntityType entityType;
  final String? code;
  final ExpenseDto? expense;
  final PeriodDto? period;
  final LoanDto? loan;

  /// The authoritative snapshot the server returned, or null when it sent none —
  /// which is how a REJECTED result arrives.
  EntitySnapshotDto? get snapshot => switch (entityType) {
    SyncEntityType.expense =>
      expense == null
          ? null
          : EntitySnapshotDto(entityType: entityType, expense: expense),
    SyncEntityType.period =>
      period == null
          ? null
          : EntitySnapshotDto(entityType: entityType, period: period),
    SyncEntityType.loan =>
      loan == null
          ? null
          : EntitySnapshotDto(entityType: entityType, loan: loan),
  };
}

/// One entity snapshot as it arrives from the change feed or a bootstrap page.
/// Exactly one of the three payloads is set, matching [entityType].
final class EntitySnapshotDto {
  const EntitySnapshotDto({
    required this.entityType,
    this.expense,
    this.period,
    this.loan,
  });

  factory EntitySnapshotDto.fromJson(Map<String, Object?> json, String name) {
    final entityType = SyncEntityTypeWire.parseOrExpense(json['entityType']);
    return switch (entityType) {
      SyncEntityType.expense => EntitySnapshotDto(
        entityType: entityType,
        expense: ExpenseDto.fromJson(
          _objectMap(_required(json, 'expense'), '$name.expense'),
        ),
      ),
      SyncEntityType.period => EntitySnapshotDto(
        entityType: entityType,
        period: PeriodDto.fromJson(
          _objectMap(_required(json, 'period'), '$name.period'),
        ),
      ),
      SyncEntityType.loan => EntitySnapshotDto(
        entityType: entityType,
        loan: LoanDto.fromJson(
          _objectMap(_required(json, 'loan'), '$name.loan'),
        ),
      ),
    };
  }

  final SyncEntityType entityType;
  final ExpenseDto? expense;
  final PeriodDto? period;
  final LoanDto? loan;

  /// The id of whichever entity this snapshot carries.
  String get entityId => switch (entityType) {
    SyncEntityType.expense => expense!.id,
    SyncEntityType.period => period!.id,
    SyncEntityType.loan => loan!.id,
  };

  /// The server-assigned version of whichever entity this snapshot carries.
  int get version => switch (entityType) {
    SyncEntityType.expense => expense!.version,
    SyncEntityType.period => period!.version,
    SyncEntityType.loan => loan!.version,
  };
}

typedef BootstrapItemDto = EntitySnapshotDto;

/// What the change feed says happened to an entity. Distinct from
/// [MutationOperation]: that names what a client asked for, this names what the
/// server recorded.
enum ChangeOperation { created, updated, deleted }

extension ChangeOperationWire on ChangeOperation {
  String get wireName => switch (this) {
    ChangeOperation.created => 'CREATED',
    ChangeOperation.updated => 'UPDATED',
    ChangeOperation.deleted => 'DELETED',
  };

  static ChangeOperation parse(String value) => switch (value) {
    'CREATED' => ChangeOperation.created,
    'UPDATED' => ChangeOperation.updated,
    'DELETED' => ChangeOperation.deleted,
    _ => throw FormatException('Unknown change operation: $value'),
  };
}

final class ChangeDto {
  const ChangeDto({
    required this.cursor,
    required this.operation,
    required this.originMutationId,
    required this.snapshot,
    this.actorMember,
  });

  factory ChangeDto.fromJson(Map<String, Object?> json) {
    final actorValue = json['actorMember'];
    return ChangeDto(
      cursor: _string(_required(json, 'cursor'), 'change.cursor'),
      operation: ChangeOperationWire.parse(
        _string(_required(json, 'operation'), 'change.operation'),
      ),
      // The contract requires an author, but this stays lenient on purpose so an
      // app pointed at an API deployed before change authorship keeps syncing.
      // An unattributed change is simply never announced.
      actorMember: actorValue == null
          ? null
          : HouseholdMemberWire.parse(
              _string(actorValue, 'change.actorMember'),
            ),
      originMutationId: _string(
        _required(json, 'originMutationId'),
        'change.originMutationId',
      ),
      snapshot: EntitySnapshotDto.fromJson(json, 'change'),
    );
  }

  final String cursor;
  final ChangeOperation operation;

  /// Which member authored the change, or null when the server did not say.
  final HouseholdMember? actorMember;
  final String originMutationId;
  final EntitySnapshotDto snapshot;

  SyncEntityType get entityType => snapshot.entityType;
  ExpenseDto? get expense => snapshot.expense;
  PeriodDto? get period => snapshot.period;
  LoanDto? get loan => snapshot.loan;
}

final class ChangePageDto {
  const ChangePageDto({
    required this.changes,
    required this.nextCursor,
    required this.hasMore,
  });

  factory ChangePageDto.fromJson(Map<String, Object?> json) => ChangePageDto(
    changes: _list(_required(json, 'changes'), 'changes')
        .map((item) => ChangeDto.fromJson(_objectMap(item, 'changes[]')))
        .toList(growable: false),
    nextCursor: _string(_required(json, 'nextCursor'), 'nextCursor'),
    hasMore: _boolean(_required(json, 'hasMore'), 'hasMore'),
  );

  final List<ChangeDto> changes;
  final String nextCursor;
  final bool hasMore;
}

final class BootstrapPageDto {
  const BootstrapPageDto({
    required this.items,
    required this.watermarkCursor,
    required this.nextPageToken,
    required this.hasMore,
  });

  factory BootstrapPageDto.fromJson(Map<String, Object?> json) {
    final nextToken = _required(json, 'nextPageToken');
    return BootstrapPageDto(
      items: _list(_required(json, 'items'), 'items')
          .map(
            (item) => BootstrapItemDto.fromJson(
              _objectMap(item, 'items[]'),
              'items[]',
            ),
          )
          .toList(growable: false),
      watermarkCursor: _string(
        _required(json, 'watermarkCursor'),
        'watermarkCursor',
      ),
      nextPageToken: nextToken == null
          ? null
          : _string(nextToken, 'nextPageToken'),
      hasMore: _boolean(_required(json, 'hasMore'), 'hasMore'),
    );
  }

  final List<BootstrapItemDto> items;
  final String watermarkCursor;
  final String? nextPageToken;
  final bool hasMore;
}
