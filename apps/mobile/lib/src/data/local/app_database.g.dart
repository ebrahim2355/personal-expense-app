// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $LocalExpensesTable extends LocalExpenses
    with TableInfo<$LocalExpensesTable, LocalExpenseRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalExpensesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _amountMinorMeta = const VerificationMeta(
    'amountMinor',
  );
  @override
  late final GeneratedColumn<int> amountMinor = GeneratedColumn<int>(
    'amount_minor',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _categoryMeta = const VerificationMeta(
    'category',
  );
  @override
  late final GeneratedColumn<String> category = GeneratedColumn<String>(
    'category',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payerMeta = const VerificationMeta('payer');
  @override
  late final GeneratedColumn<String> payer = GeneratedColumn<String>(
    'payer',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _occurredAtMeta = const VerificationMeta(
    'occurredAt',
  );
  @override
  late final GeneratedColumn<DateTime> occurredAt = GeneratedColumn<DateTime>(
    'occurred_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  @override
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
    'note',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _versionMeta = const VerificationMeta(
    'version',
  );
  @override
  late final GeneratedColumn<int> version = GeneratedColumn<int>(
    'version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _syncStateMeta = const VerificationMeta(
    'syncState',
  );
  @override
  late final GeneratedColumn<String> syncState = GeneratedColumn<String>(
    'sync_state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _localModifiedAtMeta = const VerificationMeta(
    'localModifiedAt',
  );
  @override
  late final GeneratedColumn<DateTime> localModifiedAt =
      GeneratedColumn<DateTime>(
        'local_modified_at',
        aliasedName,
        false,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: true,
      );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    amountMinor,
    category,
    payer,
    occurredAt,
    note,
    version,
    updatedAt,
    deletedAt,
    syncState,
    localModifiedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_expenses';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalExpenseRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('amount_minor')) {
      context.handle(
        _amountMinorMeta,
        amountMinor.isAcceptableOrUnknown(
          data['amount_minor']!,
          _amountMinorMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_amountMinorMeta);
    }
    if (data.containsKey('category')) {
      context.handle(
        _categoryMeta,
        category.isAcceptableOrUnknown(data['category']!, _categoryMeta),
      );
    } else if (isInserting) {
      context.missing(_categoryMeta);
    }
    if (data.containsKey('payer')) {
      context.handle(
        _payerMeta,
        payer.isAcceptableOrUnknown(data['payer']!, _payerMeta),
      );
    } else if (isInserting) {
      context.missing(_payerMeta);
    }
    if (data.containsKey('occurred_at')) {
      context.handle(
        _occurredAtMeta,
        occurredAt.isAcceptableOrUnknown(data['occurred_at']!, _occurredAtMeta),
      );
    } else if (isInserting) {
      context.missing(_occurredAtMeta);
    }
    if (data.containsKey('note')) {
      context.handle(
        _noteMeta,
        note.isAcceptableOrUnknown(data['note']!, _noteMeta),
      );
    }
    if (data.containsKey('version')) {
      context.handle(
        _versionMeta,
        version.isAcceptableOrUnknown(data['version']!, _versionMeta),
      );
    } else if (isInserting) {
      context.missing(_versionMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('sync_state')) {
      context.handle(
        _syncStateMeta,
        syncState.isAcceptableOrUnknown(data['sync_state']!, _syncStateMeta),
      );
    } else if (isInserting) {
      context.missing(_syncStateMeta);
    }
    if (data.containsKey('local_modified_at')) {
      context.handle(
        _localModifiedAtMeta,
        localModifiedAt.isAcceptableOrUnknown(
          data['local_modified_at']!,
          _localModifiedAtMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_localModifiedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LocalExpenseRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalExpenseRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      amountMinor: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}amount_minor'],
      )!,
      category: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}category'],
      )!,
      payer: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payer'],
      )!,
      occurredAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}occurred_at'],
      )!,
      note: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note'],
      ),
      version: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}version'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
      syncState: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sync_state'],
      )!,
      localModifiedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}local_modified_at'],
      )!,
    );
  }

  @override
  $LocalExpensesTable createAlias(String alias) {
    return $LocalExpensesTable(attachedDatabase, alias);
  }
}

class LocalExpenseRow extends DataClass implements Insertable<LocalExpenseRow> {
  final String id;
  final int amountMinor;
  final String category;
  final String payer;
  final DateTime occurredAt;
  final String? note;
  final int version;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final String syncState;
  final DateTime localModifiedAt;
  const LocalExpenseRow({
    required this.id,
    required this.amountMinor,
    required this.category,
    required this.payer,
    required this.occurredAt,
    this.note,
    required this.version,
    required this.updatedAt,
    this.deletedAt,
    required this.syncState,
    required this.localModifiedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['amount_minor'] = Variable<int>(amountMinor);
    map['category'] = Variable<String>(category);
    map['payer'] = Variable<String>(payer);
    map['occurred_at'] = Variable<DateTime>(occurredAt);
    if (!nullToAbsent || note != null) {
      map['note'] = Variable<String>(note);
    }
    map['version'] = Variable<int>(version);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    map['sync_state'] = Variable<String>(syncState);
    map['local_modified_at'] = Variable<DateTime>(localModifiedAt);
    return map;
  }

  LocalExpensesCompanion toCompanion(bool nullToAbsent) {
    return LocalExpensesCompanion(
      id: Value(id),
      amountMinor: Value(amountMinor),
      category: Value(category),
      payer: Value(payer),
      occurredAt: Value(occurredAt),
      note: note == null && nullToAbsent ? const Value.absent() : Value(note),
      version: Value(version),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      syncState: Value(syncState),
      localModifiedAt: Value(localModifiedAt),
    );
  }

  factory LocalExpenseRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalExpenseRow(
      id: serializer.fromJson<String>(json['id']),
      amountMinor: serializer.fromJson<int>(json['amountMinor']),
      category: serializer.fromJson<String>(json['category']),
      payer: serializer.fromJson<String>(json['payer']),
      occurredAt: serializer.fromJson<DateTime>(json['occurredAt']),
      note: serializer.fromJson<String?>(json['note']),
      version: serializer.fromJson<int>(json['version']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
      syncState: serializer.fromJson<String>(json['syncState']),
      localModifiedAt: serializer.fromJson<DateTime>(json['localModifiedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'amountMinor': serializer.toJson<int>(amountMinor),
      'category': serializer.toJson<String>(category),
      'payer': serializer.toJson<String>(payer),
      'occurredAt': serializer.toJson<DateTime>(occurredAt),
      'note': serializer.toJson<String?>(note),
      'version': serializer.toJson<int>(version),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
      'syncState': serializer.toJson<String>(syncState),
      'localModifiedAt': serializer.toJson<DateTime>(localModifiedAt),
    };
  }

  LocalExpenseRow copyWith({
    String? id,
    int? amountMinor,
    String? category,
    String? payer,
    DateTime? occurredAt,
    Value<String?> note = const Value.absent(),
    int? version,
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
    String? syncState,
    DateTime? localModifiedAt,
  }) => LocalExpenseRow(
    id: id ?? this.id,
    amountMinor: amountMinor ?? this.amountMinor,
    category: category ?? this.category,
    payer: payer ?? this.payer,
    occurredAt: occurredAt ?? this.occurredAt,
    note: note.present ? note.value : this.note,
    version: version ?? this.version,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    syncState: syncState ?? this.syncState,
    localModifiedAt: localModifiedAt ?? this.localModifiedAt,
  );
  LocalExpenseRow copyWithCompanion(LocalExpensesCompanion data) {
    return LocalExpenseRow(
      id: data.id.present ? data.id.value : this.id,
      amountMinor: data.amountMinor.present
          ? data.amountMinor.value
          : this.amountMinor,
      category: data.category.present ? data.category.value : this.category,
      payer: data.payer.present ? data.payer.value : this.payer,
      occurredAt: data.occurredAt.present
          ? data.occurredAt.value
          : this.occurredAt,
      note: data.note.present ? data.note.value : this.note,
      version: data.version.present ? data.version.value : this.version,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      syncState: data.syncState.present ? data.syncState.value : this.syncState,
      localModifiedAt: data.localModifiedAt.present
          ? data.localModifiedAt.value
          : this.localModifiedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalExpenseRow(')
          ..write('id: $id, ')
          ..write('amountMinor: $amountMinor, ')
          ..write('category: $category, ')
          ..write('payer: $payer, ')
          ..write('occurredAt: $occurredAt, ')
          ..write('note: $note, ')
          ..write('version: $version, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('syncState: $syncState, ')
          ..write('localModifiedAt: $localModifiedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    amountMinor,
    category,
    payer,
    occurredAt,
    note,
    version,
    updatedAt,
    deletedAt,
    syncState,
    localModifiedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalExpenseRow &&
          other.id == this.id &&
          other.amountMinor == this.amountMinor &&
          other.category == this.category &&
          other.payer == this.payer &&
          other.occurredAt == this.occurredAt &&
          other.note == this.note &&
          other.version == this.version &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.syncState == this.syncState &&
          other.localModifiedAt == this.localModifiedAt);
}

class LocalExpensesCompanion extends UpdateCompanion<LocalExpenseRow> {
  final Value<String> id;
  final Value<int> amountMinor;
  final Value<String> category;
  final Value<String> payer;
  final Value<DateTime> occurredAt;
  final Value<String?> note;
  final Value<int> version;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<String> syncState;
  final Value<DateTime> localModifiedAt;
  final Value<int> rowid;
  const LocalExpensesCompanion({
    this.id = const Value.absent(),
    this.amountMinor = const Value.absent(),
    this.category = const Value.absent(),
    this.payer = const Value.absent(),
    this.occurredAt = const Value.absent(),
    this.note = const Value.absent(),
    this.version = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.syncState = const Value.absent(),
    this.localModifiedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalExpensesCompanion.insert({
    required String id,
    required int amountMinor,
    required String category,
    required String payer,
    required DateTime occurredAt,
    this.note = const Value.absent(),
    required int version,
    required DateTime updatedAt,
    this.deletedAt = const Value.absent(),
    required String syncState,
    required DateTime localModifiedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       amountMinor = Value(amountMinor),
       category = Value(category),
       payer = Value(payer),
       occurredAt = Value(occurredAt),
       version = Value(version),
       updatedAt = Value(updatedAt),
       syncState = Value(syncState),
       localModifiedAt = Value(localModifiedAt);
  static Insertable<LocalExpenseRow> custom({
    Expression<String>? id,
    Expression<int>? amountMinor,
    Expression<String>? category,
    Expression<String>? payer,
    Expression<DateTime>? occurredAt,
    Expression<String>? note,
    Expression<int>? version,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<String>? syncState,
    Expression<DateTime>? localModifiedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (amountMinor != null) 'amount_minor': amountMinor,
      if (category != null) 'category': category,
      if (payer != null) 'payer': payer,
      if (occurredAt != null) 'occurred_at': occurredAt,
      if (note != null) 'note': note,
      if (version != null) 'version': version,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (syncState != null) 'sync_state': syncState,
      if (localModifiedAt != null) 'local_modified_at': localModifiedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalExpensesCompanion copyWith({
    Value<String>? id,
    Value<int>? amountMinor,
    Value<String>? category,
    Value<String>? payer,
    Value<DateTime>? occurredAt,
    Value<String?>? note,
    Value<int>? version,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<String>? syncState,
    Value<DateTime>? localModifiedAt,
    Value<int>? rowid,
  }) {
    return LocalExpensesCompanion(
      id: id ?? this.id,
      amountMinor: amountMinor ?? this.amountMinor,
      category: category ?? this.category,
      payer: payer ?? this.payer,
      occurredAt: occurredAt ?? this.occurredAt,
      note: note ?? this.note,
      version: version ?? this.version,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      syncState: syncState ?? this.syncState,
      localModifiedAt: localModifiedAt ?? this.localModifiedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (amountMinor.present) {
      map['amount_minor'] = Variable<int>(amountMinor.value);
    }
    if (category.present) {
      map['category'] = Variable<String>(category.value);
    }
    if (payer.present) {
      map['payer'] = Variable<String>(payer.value);
    }
    if (occurredAt.present) {
      map['occurred_at'] = Variable<DateTime>(occurredAt.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (version.present) {
      map['version'] = Variable<int>(version.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (syncState.present) {
      map['sync_state'] = Variable<String>(syncState.value);
    }
    if (localModifiedAt.present) {
      map['local_modified_at'] = Variable<DateTime>(localModifiedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalExpensesCompanion(')
          ..write('id: $id, ')
          ..write('amountMinor: $amountMinor, ')
          ..write('category: $category, ')
          ..write('payer: $payer, ')
          ..write('occurredAt: $occurredAt, ')
          ..write('note: $note, ')
          ..write('version: $version, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('syncState: $syncState, ')
          ..write('localModifiedAt: $localModifiedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $OutboxMutationsTable extends OutboxMutations
    with TableInfo<$OutboxMutationsTable, OutboxMutationRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $OutboxMutationsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _localSequenceMeta = const VerificationMeta(
    'localSequence',
  );
  @override
  late final GeneratedColumn<int> localSequence = GeneratedColumn<int>(
    'local_sequence',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _mutationIdMeta = const VerificationMeta(
    'mutationId',
  );
  @override
  late final GeneratedColumn<String> mutationId = GeneratedColumn<String>(
    'mutation_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _entityIdMeta = const VerificationMeta(
    'entityId',
  );
  @override
  late final GeneratedColumn<String> entityId = GeneratedColumn<String>(
    'entity_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _actionMeta = const VerificationMeta('action');
  @override
  late final GeneratedColumn<String> action = GeneratedColumn<String>(
    'action',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _baseVersionMeta = const VerificationMeta(
    'baseVersion',
  );
  @override
  late final GeneratedColumn<int> baseVersion = GeneratedColumn<int>(
    'base_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadJsonMeta = const VerificationMeta(
    'payloadJson',
  );
  @override
  late final GeneratedColumn<String> payloadJson = GeneratedColumn<String>(
    'payload_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _attemptCountMeta = const VerificationMeta(
    'attemptCount',
  );
  @override
  late final GeneratedColumn<int> attemptCount = GeneratedColumn<int>(
    'attempt_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _lastAttemptAtMeta = const VerificationMeta(
    'lastAttemptAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastAttemptAt =
      GeneratedColumn<DateTime>(
        'last_attempt_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _nextAttemptAtMeta = const VerificationMeta(
    'nextAttemptAt',
  );
  @override
  late final GeneratedColumn<DateTime> nextAttemptAt =
      GeneratedColumn<DateTime>(
        'next_attempt_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _lastErrorCodeMeta = const VerificationMeta(
    'lastErrorCode',
  );
  @override
  late final GeneratedColumn<String> lastErrorCode = GeneratedColumn<String>(
    'last_error_code',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    localSequence,
    mutationId,
    entityId,
    action,
    baseVersion,
    payloadJson,
    createdAt,
    attemptCount,
    lastAttemptAt,
    nextAttemptAt,
    lastErrorCode,
    status,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'outbox_mutations';
  @override
  VerificationContext validateIntegrity(
    Insertable<OutboxMutationRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('local_sequence')) {
      context.handle(
        _localSequenceMeta,
        localSequence.isAcceptableOrUnknown(
          data['local_sequence']!,
          _localSequenceMeta,
        ),
      );
    }
    if (data.containsKey('mutation_id')) {
      context.handle(
        _mutationIdMeta,
        mutationId.isAcceptableOrUnknown(data['mutation_id']!, _mutationIdMeta),
      );
    } else if (isInserting) {
      context.missing(_mutationIdMeta);
    }
    if (data.containsKey('entity_id')) {
      context.handle(
        _entityIdMeta,
        entityId.isAcceptableOrUnknown(data['entity_id']!, _entityIdMeta),
      );
    } else if (isInserting) {
      context.missing(_entityIdMeta);
    }
    if (data.containsKey('action')) {
      context.handle(
        _actionMeta,
        action.isAcceptableOrUnknown(data['action']!, _actionMeta),
      );
    } else if (isInserting) {
      context.missing(_actionMeta);
    }
    if (data.containsKey('base_version')) {
      context.handle(
        _baseVersionMeta,
        baseVersion.isAcceptableOrUnknown(
          data['base_version']!,
          _baseVersionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_baseVersionMeta);
    }
    if (data.containsKey('payload_json')) {
      context.handle(
        _payloadJsonMeta,
        payloadJson.isAcceptableOrUnknown(
          data['payload_json']!,
          _payloadJsonMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('attempt_count')) {
      context.handle(
        _attemptCountMeta,
        attemptCount.isAcceptableOrUnknown(
          data['attempt_count']!,
          _attemptCountMeta,
        ),
      );
    }
    if (data.containsKey('last_attempt_at')) {
      context.handle(
        _lastAttemptAtMeta,
        lastAttemptAt.isAcceptableOrUnknown(
          data['last_attempt_at']!,
          _lastAttemptAtMeta,
        ),
      );
    }
    if (data.containsKey('next_attempt_at')) {
      context.handle(
        _nextAttemptAtMeta,
        nextAttemptAt.isAcceptableOrUnknown(
          data['next_attempt_at']!,
          _nextAttemptAtMeta,
        ),
      );
    }
    if (data.containsKey('last_error_code')) {
      context.handle(
        _lastErrorCodeMeta,
        lastErrorCode.isAcceptableOrUnknown(
          data['last_error_code']!,
          _lastErrorCodeMeta,
        ),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {localSequence};
  @override
  OutboxMutationRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return OutboxMutationRow(
      localSequence: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}local_sequence'],
      )!,
      mutationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mutation_id'],
      )!,
      entityId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity_id'],
      )!,
      action: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}action'],
      )!,
      baseVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}base_version'],
      )!,
      payloadJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload_json'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      attemptCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempt_count'],
      )!,
      lastAttemptAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_attempt_at'],
      ),
      nextAttemptAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}next_attempt_at'],
      ),
      lastErrorCode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_error_code'],
      ),
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
    );
  }

  @override
  $OutboxMutationsTable createAlias(String alias) {
    return $OutboxMutationsTable(attachedDatabase, alias);
  }
}

class OutboxMutationRow extends DataClass
    implements Insertable<OutboxMutationRow> {
  final int localSequence;
  final String mutationId;
  final String entityId;
  final String action;
  final int baseVersion;
  final String? payloadJson;
  final DateTime createdAt;
  final int attemptCount;
  final DateTime? lastAttemptAt;
  final DateTime? nextAttemptAt;
  final String? lastErrorCode;
  final String status;
  const OutboxMutationRow({
    required this.localSequence,
    required this.mutationId,
    required this.entityId,
    required this.action,
    required this.baseVersion,
    this.payloadJson,
    required this.createdAt,
    required this.attemptCount,
    this.lastAttemptAt,
    this.nextAttemptAt,
    this.lastErrorCode,
    required this.status,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['local_sequence'] = Variable<int>(localSequence);
    map['mutation_id'] = Variable<String>(mutationId);
    map['entity_id'] = Variable<String>(entityId);
    map['action'] = Variable<String>(action);
    map['base_version'] = Variable<int>(baseVersion);
    if (!nullToAbsent || payloadJson != null) {
      map['payload_json'] = Variable<String>(payloadJson);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['attempt_count'] = Variable<int>(attemptCount);
    if (!nullToAbsent || lastAttemptAt != null) {
      map['last_attempt_at'] = Variable<DateTime>(lastAttemptAt);
    }
    if (!nullToAbsent || nextAttemptAt != null) {
      map['next_attempt_at'] = Variable<DateTime>(nextAttemptAt);
    }
    if (!nullToAbsent || lastErrorCode != null) {
      map['last_error_code'] = Variable<String>(lastErrorCode);
    }
    map['status'] = Variable<String>(status);
    return map;
  }

  OutboxMutationsCompanion toCompanion(bool nullToAbsent) {
    return OutboxMutationsCompanion(
      localSequence: Value(localSequence),
      mutationId: Value(mutationId),
      entityId: Value(entityId),
      action: Value(action),
      baseVersion: Value(baseVersion),
      payloadJson: payloadJson == null && nullToAbsent
          ? const Value.absent()
          : Value(payloadJson),
      createdAt: Value(createdAt),
      attemptCount: Value(attemptCount),
      lastAttemptAt: lastAttemptAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastAttemptAt),
      nextAttemptAt: nextAttemptAt == null && nullToAbsent
          ? const Value.absent()
          : Value(nextAttemptAt),
      lastErrorCode: lastErrorCode == null && nullToAbsent
          ? const Value.absent()
          : Value(lastErrorCode),
      status: Value(status),
    );
  }

  factory OutboxMutationRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return OutboxMutationRow(
      localSequence: serializer.fromJson<int>(json['localSequence']),
      mutationId: serializer.fromJson<String>(json['mutationId']),
      entityId: serializer.fromJson<String>(json['entityId']),
      action: serializer.fromJson<String>(json['action']),
      baseVersion: serializer.fromJson<int>(json['baseVersion']),
      payloadJson: serializer.fromJson<String?>(json['payloadJson']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      attemptCount: serializer.fromJson<int>(json['attemptCount']),
      lastAttemptAt: serializer.fromJson<DateTime?>(json['lastAttemptAt']),
      nextAttemptAt: serializer.fromJson<DateTime?>(json['nextAttemptAt']),
      lastErrorCode: serializer.fromJson<String?>(json['lastErrorCode']),
      status: serializer.fromJson<String>(json['status']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'localSequence': serializer.toJson<int>(localSequence),
      'mutationId': serializer.toJson<String>(mutationId),
      'entityId': serializer.toJson<String>(entityId),
      'action': serializer.toJson<String>(action),
      'baseVersion': serializer.toJson<int>(baseVersion),
      'payloadJson': serializer.toJson<String?>(payloadJson),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'attemptCount': serializer.toJson<int>(attemptCount),
      'lastAttemptAt': serializer.toJson<DateTime?>(lastAttemptAt),
      'nextAttemptAt': serializer.toJson<DateTime?>(nextAttemptAt),
      'lastErrorCode': serializer.toJson<String?>(lastErrorCode),
      'status': serializer.toJson<String>(status),
    };
  }

  OutboxMutationRow copyWith({
    int? localSequence,
    String? mutationId,
    String? entityId,
    String? action,
    int? baseVersion,
    Value<String?> payloadJson = const Value.absent(),
    DateTime? createdAt,
    int? attemptCount,
    Value<DateTime?> lastAttemptAt = const Value.absent(),
    Value<DateTime?> nextAttemptAt = const Value.absent(),
    Value<String?> lastErrorCode = const Value.absent(),
    String? status,
  }) => OutboxMutationRow(
    localSequence: localSequence ?? this.localSequence,
    mutationId: mutationId ?? this.mutationId,
    entityId: entityId ?? this.entityId,
    action: action ?? this.action,
    baseVersion: baseVersion ?? this.baseVersion,
    payloadJson: payloadJson.present ? payloadJson.value : this.payloadJson,
    createdAt: createdAt ?? this.createdAt,
    attemptCount: attemptCount ?? this.attemptCount,
    lastAttemptAt: lastAttemptAt.present
        ? lastAttemptAt.value
        : this.lastAttemptAt,
    nextAttemptAt: nextAttemptAt.present
        ? nextAttemptAt.value
        : this.nextAttemptAt,
    lastErrorCode: lastErrorCode.present
        ? lastErrorCode.value
        : this.lastErrorCode,
    status: status ?? this.status,
  );
  OutboxMutationRow copyWithCompanion(OutboxMutationsCompanion data) {
    return OutboxMutationRow(
      localSequence: data.localSequence.present
          ? data.localSequence.value
          : this.localSequence,
      mutationId: data.mutationId.present
          ? data.mutationId.value
          : this.mutationId,
      entityId: data.entityId.present ? data.entityId.value : this.entityId,
      action: data.action.present ? data.action.value : this.action,
      baseVersion: data.baseVersion.present
          ? data.baseVersion.value
          : this.baseVersion,
      payloadJson: data.payloadJson.present
          ? data.payloadJson.value
          : this.payloadJson,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      attemptCount: data.attemptCount.present
          ? data.attemptCount.value
          : this.attemptCount,
      lastAttemptAt: data.lastAttemptAt.present
          ? data.lastAttemptAt.value
          : this.lastAttemptAt,
      nextAttemptAt: data.nextAttemptAt.present
          ? data.nextAttemptAt.value
          : this.nextAttemptAt,
      lastErrorCode: data.lastErrorCode.present
          ? data.lastErrorCode.value
          : this.lastErrorCode,
      status: data.status.present ? data.status.value : this.status,
    );
  }

  @override
  String toString() {
    return (StringBuffer('OutboxMutationRow(')
          ..write('localSequence: $localSequence, ')
          ..write('mutationId: $mutationId, ')
          ..write('entityId: $entityId, ')
          ..write('action: $action, ')
          ..write('baseVersion: $baseVersion, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('createdAt: $createdAt, ')
          ..write('attemptCount: $attemptCount, ')
          ..write('lastAttemptAt: $lastAttemptAt, ')
          ..write('nextAttemptAt: $nextAttemptAt, ')
          ..write('lastErrorCode: $lastErrorCode, ')
          ..write('status: $status')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    localSequence,
    mutationId,
    entityId,
    action,
    baseVersion,
    payloadJson,
    createdAt,
    attemptCount,
    lastAttemptAt,
    nextAttemptAt,
    lastErrorCode,
    status,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OutboxMutationRow &&
          other.localSequence == this.localSequence &&
          other.mutationId == this.mutationId &&
          other.entityId == this.entityId &&
          other.action == this.action &&
          other.baseVersion == this.baseVersion &&
          other.payloadJson == this.payloadJson &&
          other.createdAt == this.createdAt &&
          other.attemptCount == this.attemptCount &&
          other.lastAttemptAt == this.lastAttemptAt &&
          other.nextAttemptAt == this.nextAttemptAt &&
          other.lastErrorCode == this.lastErrorCode &&
          other.status == this.status);
}

class OutboxMutationsCompanion extends UpdateCompanion<OutboxMutationRow> {
  final Value<int> localSequence;
  final Value<String> mutationId;
  final Value<String> entityId;
  final Value<String> action;
  final Value<int> baseVersion;
  final Value<String?> payloadJson;
  final Value<DateTime> createdAt;
  final Value<int> attemptCount;
  final Value<DateTime?> lastAttemptAt;
  final Value<DateTime?> nextAttemptAt;
  final Value<String?> lastErrorCode;
  final Value<String> status;
  const OutboxMutationsCompanion({
    this.localSequence = const Value.absent(),
    this.mutationId = const Value.absent(),
    this.entityId = const Value.absent(),
    this.action = const Value.absent(),
    this.baseVersion = const Value.absent(),
    this.payloadJson = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.attemptCount = const Value.absent(),
    this.lastAttemptAt = const Value.absent(),
    this.nextAttemptAt = const Value.absent(),
    this.lastErrorCode = const Value.absent(),
    this.status = const Value.absent(),
  });
  OutboxMutationsCompanion.insert({
    this.localSequence = const Value.absent(),
    required String mutationId,
    required String entityId,
    required String action,
    required int baseVersion,
    this.payloadJson = const Value.absent(),
    required DateTime createdAt,
    this.attemptCount = const Value.absent(),
    this.lastAttemptAt = const Value.absent(),
    this.nextAttemptAt = const Value.absent(),
    this.lastErrorCode = const Value.absent(),
    required String status,
  }) : mutationId = Value(mutationId),
       entityId = Value(entityId),
       action = Value(action),
       baseVersion = Value(baseVersion),
       createdAt = Value(createdAt),
       status = Value(status);
  static Insertable<OutboxMutationRow> custom({
    Expression<int>? localSequence,
    Expression<String>? mutationId,
    Expression<String>? entityId,
    Expression<String>? action,
    Expression<int>? baseVersion,
    Expression<String>? payloadJson,
    Expression<DateTime>? createdAt,
    Expression<int>? attemptCount,
    Expression<DateTime>? lastAttemptAt,
    Expression<DateTime>? nextAttemptAt,
    Expression<String>? lastErrorCode,
    Expression<String>? status,
  }) {
    return RawValuesInsertable({
      if (localSequence != null) 'local_sequence': localSequence,
      if (mutationId != null) 'mutation_id': mutationId,
      if (entityId != null) 'entity_id': entityId,
      if (action != null) 'action': action,
      if (baseVersion != null) 'base_version': baseVersion,
      if (payloadJson != null) 'payload_json': payloadJson,
      if (createdAt != null) 'created_at': createdAt,
      if (attemptCount != null) 'attempt_count': attemptCount,
      if (lastAttemptAt != null) 'last_attempt_at': lastAttemptAt,
      if (nextAttemptAt != null) 'next_attempt_at': nextAttemptAt,
      if (lastErrorCode != null) 'last_error_code': lastErrorCode,
      if (status != null) 'status': status,
    });
  }

  OutboxMutationsCompanion copyWith({
    Value<int>? localSequence,
    Value<String>? mutationId,
    Value<String>? entityId,
    Value<String>? action,
    Value<int>? baseVersion,
    Value<String?>? payloadJson,
    Value<DateTime>? createdAt,
    Value<int>? attemptCount,
    Value<DateTime?>? lastAttemptAt,
    Value<DateTime?>? nextAttemptAt,
    Value<String?>? lastErrorCode,
    Value<String>? status,
  }) {
    return OutboxMutationsCompanion(
      localSequence: localSequence ?? this.localSequence,
      mutationId: mutationId ?? this.mutationId,
      entityId: entityId ?? this.entityId,
      action: action ?? this.action,
      baseVersion: baseVersion ?? this.baseVersion,
      payloadJson: payloadJson ?? this.payloadJson,
      createdAt: createdAt ?? this.createdAt,
      attemptCount: attemptCount ?? this.attemptCount,
      lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
      nextAttemptAt: nextAttemptAt ?? this.nextAttemptAt,
      lastErrorCode: lastErrorCode ?? this.lastErrorCode,
      status: status ?? this.status,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (localSequence.present) {
      map['local_sequence'] = Variable<int>(localSequence.value);
    }
    if (mutationId.present) {
      map['mutation_id'] = Variable<String>(mutationId.value);
    }
    if (entityId.present) {
      map['entity_id'] = Variable<String>(entityId.value);
    }
    if (action.present) {
      map['action'] = Variable<String>(action.value);
    }
    if (baseVersion.present) {
      map['base_version'] = Variable<int>(baseVersion.value);
    }
    if (payloadJson.present) {
      map['payload_json'] = Variable<String>(payloadJson.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (attemptCount.present) {
      map['attempt_count'] = Variable<int>(attemptCount.value);
    }
    if (lastAttemptAt.present) {
      map['last_attempt_at'] = Variable<DateTime>(lastAttemptAt.value);
    }
    if (nextAttemptAt.present) {
      map['next_attempt_at'] = Variable<DateTime>(nextAttemptAt.value);
    }
    if (lastErrorCode.present) {
      map['last_error_code'] = Variable<String>(lastErrorCode.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('OutboxMutationsCompanion(')
          ..write('localSequence: $localSequence, ')
          ..write('mutationId: $mutationId, ')
          ..write('entityId: $entityId, ')
          ..write('action: $action, ')
          ..write('baseVersion: $baseVersion, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('createdAt: $createdAt, ')
          ..write('attemptCount: $attemptCount, ')
          ..write('lastAttemptAt: $lastAttemptAt, ')
          ..write('nextAttemptAt: $nextAttemptAt, ')
          ..write('lastErrorCode: $lastErrorCode, ')
          ..write('status: $status')
          ..write(')'))
        .toString();
  }
}

class $SyncMetadataTable extends SyncMetadata
    with TableInfo<$SyncMetadataTable, SyncMetadataRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncMetadataTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _singletonIdMeta = const VerificationMeta(
    'singletonId',
  );
  @override
  late final GeneratedColumn<int> singletonId = GeneratedColumn<int>(
    'singleton_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _householdIdMeta = const VerificationMeta(
    'householdId',
  );
  @override
  late final GeneratedColumn<String> householdId = GeneratedColumn<String>(
    'household_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _memberIdMeta = const VerificationMeta(
    'memberId',
  );
  @override
  late final GeneratedColumn<String> memberId = GeneratedColumn<String>(
    'member_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _memberKeyMeta = const VerificationMeta(
    'memberKey',
  );
  @override
  late final GeneratedColumn<String> memberKey = GeneratedColumn<String>(
    'member_key',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastCursorMeta = const VerificationMeta(
    'lastCursor',
  );
  @override
  late final GeneratedColumn<String> lastCursor = GeneratedColumn<String>(
    'last_cursor',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _bootstrapPageTokenMeta =
      const VerificationMeta('bootstrapPageToken');
  @override
  late final GeneratedColumn<String> bootstrapPageToken =
      GeneratedColumn<String>(
        'bootstrap_page_token',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _bootstrapWatermarkMeta =
      const VerificationMeta('bootstrapWatermark');
  @override
  late final GeneratedColumn<String> bootstrapWatermark =
      GeneratedColumn<String>(
        'bootstrap_watermark',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    singletonId,
    householdId,
    memberId,
    memberKey,
    lastCursor,
    bootstrapPageToken,
    bootstrapWatermark,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_metadata';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncMetadataRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('singleton_id')) {
      context.handle(
        _singletonIdMeta,
        singletonId.isAcceptableOrUnknown(
          data['singleton_id']!,
          _singletonIdMeta,
        ),
      );
    }
    if (data.containsKey('household_id')) {
      context.handle(
        _householdIdMeta,
        householdId.isAcceptableOrUnknown(
          data['household_id']!,
          _householdIdMeta,
        ),
      );
    }
    if (data.containsKey('member_id')) {
      context.handle(
        _memberIdMeta,
        memberId.isAcceptableOrUnknown(data['member_id']!, _memberIdMeta),
      );
    }
    if (data.containsKey('member_key')) {
      context.handle(
        _memberKeyMeta,
        memberKey.isAcceptableOrUnknown(data['member_key']!, _memberKeyMeta),
      );
    }
    if (data.containsKey('last_cursor')) {
      context.handle(
        _lastCursorMeta,
        lastCursor.isAcceptableOrUnknown(data['last_cursor']!, _lastCursorMeta),
      );
    }
    if (data.containsKey('bootstrap_page_token')) {
      context.handle(
        _bootstrapPageTokenMeta,
        bootstrapPageToken.isAcceptableOrUnknown(
          data['bootstrap_page_token']!,
          _bootstrapPageTokenMeta,
        ),
      );
    }
    if (data.containsKey('bootstrap_watermark')) {
      context.handle(
        _bootstrapWatermarkMeta,
        bootstrapWatermark.isAcceptableOrUnknown(
          data['bootstrap_watermark']!,
          _bootstrapWatermarkMeta,
        ),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {singletonId};
  @override
  SyncMetadataRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncMetadataRow(
      singletonId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}singleton_id'],
      )!,
      householdId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}household_id'],
      ),
      memberId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}member_id'],
      ),
      memberKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}member_key'],
      ),
      lastCursor: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_cursor'],
      ),
      bootstrapPageToken: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}bootstrap_page_token'],
      ),
      bootstrapWatermark: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}bootstrap_watermark'],
      ),
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $SyncMetadataTable createAlias(String alias) {
    return $SyncMetadataTable(attachedDatabase, alias);
  }
}

class SyncMetadataRow extends DataClass implements Insertable<SyncMetadataRow> {
  final int singletonId;
  final String? householdId;
  final String? memberId;
  final String? memberKey;
  final String? lastCursor;
  final String? bootstrapPageToken;
  final String? bootstrapWatermark;
  final DateTime updatedAt;
  const SyncMetadataRow({
    required this.singletonId,
    this.householdId,
    this.memberId,
    this.memberKey,
    this.lastCursor,
    this.bootstrapPageToken,
    this.bootstrapWatermark,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['singleton_id'] = Variable<int>(singletonId);
    if (!nullToAbsent || householdId != null) {
      map['household_id'] = Variable<String>(householdId);
    }
    if (!nullToAbsent || memberId != null) {
      map['member_id'] = Variable<String>(memberId);
    }
    if (!nullToAbsent || memberKey != null) {
      map['member_key'] = Variable<String>(memberKey);
    }
    if (!nullToAbsent || lastCursor != null) {
      map['last_cursor'] = Variable<String>(lastCursor);
    }
    if (!nullToAbsent || bootstrapPageToken != null) {
      map['bootstrap_page_token'] = Variable<String>(bootstrapPageToken);
    }
    if (!nullToAbsent || bootstrapWatermark != null) {
      map['bootstrap_watermark'] = Variable<String>(bootstrapWatermark);
    }
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  SyncMetadataCompanion toCompanion(bool nullToAbsent) {
    return SyncMetadataCompanion(
      singletonId: Value(singletonId),
      householdId: householdId == null && nullToAbsent
          ? const Value.absent()
          : Value(householdId),
      memberId: memberId == null && nullToAbsent
          ? const Value.absent()
          : Value(memberId),
      memberKey: memberKey == null && nullToAbsent
          ? const Value.absent()
          : Value(memberKey),
      lastCursor: lastCursor == null && nullToAbsent
          ? const Value.absent()
          : Value(lastCursor),
      bootstrapPageToken: bootstrapPageToken == null && nullToAbsent
          ? const Value.absent()
          : Value(bootstrapPageToken),
      bootstrapWatermark: bootstrapWatermark == null && nullToAbsent
          ? const Value.absent()
          : Value(bootstrapWatermark),
      updatedAt: Value(updatedAt),
    );
  }

  factory SyncMetadataRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncMetadataRow(
      singletonId: serializer.fromJson<int>(json['singletonId']),
      householdId: serializer.fromJson<String?>(json['householdId']),
      memberId: serializer.fromJson<String?>(json['memberId']),
      memberKey: serializer.fromJson<String?>(json['memberKey']),
      lastCursor: serializer.fromJson<String?>(json['lastCursor']),
      bootstrapPageToken: serializer.fromJson<String?>(
        json['bootstrapPageToken'],
      ),
      bootstrapWatermark: serializer.fromJson<String?>(
        json['bootstrapWatermark'],
      ),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'singletonId': serializer.toJson<int>(singletonId),
      'householdId': serializer.toJson<String?>(householdId),
      'memberId': serializer.toJson<String?>(memberId),
      'memberKey': serializer.toJson<String?>(memberKey),
      'lastCursor': serializer.toJson<String?>(lastCursor),
      'bootstrapPageToken': serializer.toJson<String?>(bootstrapPageToken),
      'bootstrapWatermark': serializer.toJson<String?>(bootstrapWatermark),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  SyncMetadataRow copyWith({
    int? singletonId,
    Value<String?> householdId = const Value.absent(),
    Value<String?> memberId = const Value.absent(),
    Value<String?> memberKey = const Value.absent(),
    Value<String?> lastCursor = const Value.absent(),
    Value<String?> bootstrapPageToken = const Value.absent(),
    Value<String?> bootstrapWatermark = const Value.absent(),
    DateTime? updatedAt,
  }) => SyncMetadataRow(
    singletonId: singletonId ?? this.singletonId,
    householdId: householdId.present ? householdId.value : this.householdId,
    memberId: memberId.present ? memberId.value : this.memberId,
    memberKey: memberKey.present ? memberKey.value : this.memberKey,
    lastCursor: lastCursor.present ? lastCursor.value : this.lastCursor,
    bootstrapPageToken: bootstrapPageToken.present
        ? bootstrapPageToken.value
        : this.bootstrapPageToken,
    bootstrapWatermark: bootstrapWatermark.present
        ? bootstrapWatermark.value
        : this.bootstrapWatermark,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  SyncMetadataRow copyWithCompanion(SyncMetadataCompanion data) {
    return SyncMetadataRow(
      singletonId: data.singletonId.present
          ? data.singletonId.value
          : this.singletonId,
      householdId: data.householdId.present
          ? data.householdId.value
          : this.householdId,
      memberId: data.memberId.present ? data.memberId.value : this.memberId,
      memberKey: data.memberKey.present ? data.memberKey.value : this.memberKey,
      lastCursor: data.lastCursor.present
          ? data.lastCursor.value
          : this.lastCursor,
      bootstrapPageToken: data.bootstrapPageToken.present
          ? data.bootstrapPageToken.value
          : this.bootstrapPageToken,
      bootstrapWatermark: data.bootstrapWatermark.present
          ? data.bootstrapWatermark.value
          : this.bootstrapWatermark,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncMetadataRow(')
          ..write('singletonId: $singletonId, ')
          ..write('householdId: $householdId, ')
          ..write('memberId: $memberId, ')
          ..write('memberKey: $memberKey, ')
          ..write('lastCursor: $lastCursor, ')
          ..write('bootstrapPageToken: $bootstrapPageToken, ')
          ..write('bootstrapWatermark: $bootstrapWatermark, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    singletonId,
    householdId,
    memberId,
    memberKey,
    lastCursor,
    bootstrapPageToken,
    bootstrapWatermark,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncMetadataRow &&
          other.singletonId == this.singletonId &&
          other.householdId == this.householdId &&
          other.memberId == this.memberId &&
          other.memberKey == this.memberKey &&
          other.lastCursor == this.lastCursor &&
          other.bootstrapPageToken == this.bootstrapPageToken &&
          other.bootstrapWatermark == this.bootstrapWatermark &&
          other.updatedAt == this.updatedAt);
}

class SyncMetadataCompanion extends UpdateCompanion<SyncMetadataRow> {
  final Value<int> singletonId;
  final Value<String?> householdId;
  final Value<String?> memberId;
  final Value<String?> memberKey;
  final Value<String?> lastCursor;
  final Value<String?> bootstrapPageToken;
  final Value<String?> bootstrapWatermark;
  final Value<DateTime> updatedAt;
  const SyncMetadataCompanion({
    this.singletonId = const Value.absent(),
    this.householdId = const Value.absent(),
    this.memberId = const Value.absent(),
    this.memberKey = const Value.absent(),
    this.lastCursor = const Value.absent(),
    this.bootstrapPageToken = const Value.absent(),
    this.bootstrapWatermark = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  SyncMetadataCompanion.insert({
    this.singletonId = const Value.absent(),
    this.householdId = const Value.absent(),
    this.memberId = const Value.absent(),
    this.memberKey = const Value.absent(),
    this.lastCursor = const Value.absent(),
    this.bootstrapPageToken = const Value.absent(),
    this.bootstrapWatermark = const Value.absent(),
    required DateTime updatedAt,
  }) : updatedAt = Value(updatedAt);
  static Insertable<SyncMetadataRow> custom({
    Expression<int>? singletonId,
    Expression<String>? householdId,
    Expression<String>? memberId,
    Expression<String>? memberKey,
    Expression<String>? lastCursor,
    Expression<String>? bootstrapPageToken,
    Expression<String>? bootstrapWatermark,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (singletonId != null) 'singleton_id': singletonId,
      if (householdId != null) 'household_id': householdId,
      if (memberId != null) 'member_id': memberId,
      if (memberKey != null) 'member_key': memberKey,
      if (lastCursor != null) 'last_cursor': lastCursor,
      if (bootstrapPageToken != null)
        'bootstrap_page_token': bootstrapPageToken,
      if (bootstrapWatermark != null) 'bootstrap_watermark': bootstrapWatermark,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  SyncMetadataCompanion copyWith({
    Value<int>? singletonId,
    Value<String?>? householdId,
    Value<String?>? memberId,
    Value<String?>? memberKey,
    Value<String?>? lastCursor,
    Value<String?>? bootstrapPageToken,
    Value<String?>? bootstrapWatermark,
    Value<DateTime>? updatedAt,
  }) {
    return SyncMetadataCompanion(
      singletonId: singletonId ?? this.singletonId,
      householdId: householdId ?? this.householdId,
      memberId: memberId ?? this.memberId,
      memberKey: memberKey ?? this.memberKey,
      lastCursor: lastCursor ?? this.lastCursor,
      bootstrapPageToken: bootstrapPageToken ?? this.bootstrapPageToken,
      bootstrapWatermark: bootstrapWatermark ?? this.bootstrapWatermark,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (singletonId.present) {
      map['singleton_id'] = Variable<int>(singletonId.value);
    }
    if (householdId.present) {
      map['household_id'] = Variable<String>(householdId.value);
    }
    if (memberId.present) {
      map['member_id'] = Variable<String>(memberId.value);
    }
    if (memberKey.present) {
      map['member_key'] = Variable<String>(memberKey.value);
    }
    if (lastCursor.present) {
      map['last_cursor'] = Variable<String>(lastCursor.value);
    }
    if (bootstrapPageToken.present) {
      map['bootstrap_page_token'] = Variable<String>(bootstrapPageToken.value);
    }
    if (bootstrapWatermark.present) {
      map['bootstrap_watermark'] = Variable<String>(bootstrapWatermark.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncMetadataCompanion(')
          ..write('singletonId: $singletonId, ')
          ..write('householdId: $householdId, ')
          ..write('memberId: $memberId, ')
          ..write('memberKey: $memberKey, ')
          ..write('lastCursor: $lastCursor, ')
          ..write('bootstrapPageToken: $bootstrapPageToken, ')
          ..write('bootstrapWatermark: $bootstrapWatermark, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $LocalExpensesTable localExpenses = $LocalExpensesTable(this);
  late final $OutboxMutationsTable outboxMutations = $OutboxMutationsTable(
    this,
  );
  late final $SyncMetadataTable syncMetadata = $SyncMetadataTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    localExpenses,
    outboxMutations,
    syncMetadata,
  ];
}

typedef $$LocalExpensesTableCreateCompanionBuilder =
    LocalExpensesCompanion Function({
      required String id,
      required int amountMinor,
      required String category,
      required String payer,
      required DateTime occurredAt,
      Value<String?> note,
      required int version,
      required DateTime updatedAt,
      Value<DateTime?> deletedAt,
      required String syncState,
      required DateTime localModifiedAt,
      Value<int> rowid,
    });
typedef $$LocalExpensesTableUpdateCompanionBuilder =
    LocalExpensesCompanion Function({
      Value<String> id,
      Value<int> amountMinor,
      Value<String> category,
      Value<String> payer,
      Value<DateTime> occurredAt,
      Value<String?> note,
      Value<int> version,
      Value<DateTime> updatedAt,
      Value<DateTime?> deletedAt,
      Value<String> syncState,
      Value<DateTime> localModifiedAt,
      Value<int> rowid,
    });

class $$LocalExpensesTableFilterComposer
    extends Composer<_$AppDatabase, $LocalExpensesTable> {
  $$LocalExpensesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get amountMinor => $composableBuilder(
    column: $table.amountMinor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get category => $composableBuilder(
    column: $table.category,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payer => $composableBuilder(
    column: $table.payer,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get occurredAt => $composableBuilder(
    column: $table.occurredAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get syncState => $composableBuilder(
    column: $table.syncState,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get localModifiedAt => $composableBuilder(
    column: $table.localModifiedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalExpensesTableOrderingComposer
    extends Composer<_$AppDatabase, $LocalExpensesTable> {
  $$LocalExpensesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get amountMinor => $composableBuilder(
    column: $table.amountMinor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get category => $composableBuilder(
    column: $table.category,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payer => $composableBuilder(
    column: $table.payer,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get occurredAt => $composableBuilder(
    column: $table.occurredAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get syncState => $composableBuilder(
    column: $table.syncState,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get localModifiedAt => $composableBuilder(
    column: $table.localModifiedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalExpensesTableAnnotationComposer
    extends Composer<_$AppDatabase, $LocalExpensesTable> {
  $$LocalExpensesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get amountMinor => $composableBuilder(
    column: $table.amountMinor,
    builder: (column) => column,
  );

  GeneratedColumn<String> get category =>
      $composableBuilder(column: $table.category, builder: (column) => column);

  GeneratedColumn<String> get payer =>
      $composableBuilder(column: $table.payer, builder: (column) => column);

  GeneratedColumn<DateTime> get occurredAt => $composableBuilder(
    column: $table.occurredAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get note =>
      $composableBuilder(column: $table.note, builder: (column) => column);

  GeneratedColumn<int> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<String> get syncState =>
      $composableBuilder(column: $table.syncState, builder: (column) => column);

  GeneratedColumn<DateTime> get localModifiedAt => $composableBuilder(
    column: $table.localModifiedAt,
    builder: (column) => column,
  );
}

class $$LocalExpensesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $LocalExpensesTable,
          LocalExpenseRow,
          $$LocalExpensesTableFilterComposer,
          $$LocalExpensesTableOrderingComposer,
          $$LocalExpensesTableAnnotationComposer,
          $$LocalExpensesTableCreateCompanionBuilder,
          $$LocalExpensesTableUpdateCompanionBuilder,
          (
            LocalExpenseRow,
            BaseReferences<_$AppDatabase, $LocalExpensesTable, LocalExpenseRow>,
          ),
          LocalExpenseRow,
          PrefetchHooks Function()
        > {
  $$LocalExpensesTableTableManager(_$AppDatabase db, $LocalExpensesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalExpensesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalExpensesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalExpensesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<int> amountMinor = const Value.absent(),
                Value<String> category = const Value.absent(),
                Value<String> payer = const Value.absent(),
                Value<DateTime> occurredAt = const Value.absent(),
                Value<String?> note = const Value.absent(),
                Value<int> version = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<String> syncState = const Value.absent(),
                Value<DateTime> localModifiedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalExpensesCompanion(
                id: id,
                amountMinor: amountMinor,
                category: category,
                payer: payer,
                occurredAt: occurredAt,
                note: note,
                version: version,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                syncState: syncState,
                localModifiedAt: localModifiedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required int amountMinor,
                required String category,
                required String payer,
                required DateTime occurredAt,
                Value<String?> note = const Value.absent(),
                required int version,
                required DateTime updatedAt,
                Value<DateTime?> deletedAt = const Value.absent(),
                required String syncState,
                required DateTime localModifiedAt,
                Value<int> rowid = const Value.absent(),
              }) => LocalExpensesCompanion.insert(
                id: id,
                amountMinor: amountMinor,
                category: category,
                payer: payer,
                occurredAt: occurredAt,
                note: note,
                version: version,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                syncState: syncState,
                localModifiedAt: localModifiedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalExpensesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $LocalExpensesTable,
      LocalExpenseRow,
      $$LocalExpensesTableFilterComposer,
      $$LocalExpensesTableOrderingComposer,
      $$LocalExpensesTableAnnotationComposer,
      $$LocalExpensesTableCreateCompanionBuilder,
      $$LocalExpensesTableUpdateCompanionBuilder,
      (
        LocalExpenseRow,
        BaseReferences<_$AppDatabase, $LocalExpensesTable, LocalExpenseRow>,
      ),
      LocalExpenseRow,
      PrefetchHooks Function()
    >;
typedef $$OutboxMutationsTableCreateCompanionBuilder =
    OutboxMutationsCompanion Function({
      Value<int> localSequence,
      required String mutationId,
      required String entityId,
      required String action,
      required int baseVersion,
      Value<String?> payloadJson,
      required DateTime createdAt,
      Value<int> attemptCount,
      Value<DateTime?> lastAttemptAt,
      Value<DateTime?> nextAttemptAt,
      Value<String?> lastErrorCode,
      required String status,
    });
typedef $$OutboxMutationsTableUpdateCompanionBuilder =
    OutboxMutationsCompanion Function({
      Value<int> localSequence,
      Value<String> mutationId,
      Value<String> entityId,
      Value<String> action,
      Value<int> baseVersion,
      Value<String?> payloadJson,
      Value<DateTime> createdAt,
      Value<int> attemptCount,
      Value<DateTime?> lastAttemptAt,
      Value<DateTime?> nextAttemptAt,
      Value<String?> lastErrorCode,
      Value<String> status,
    });

class $$OutboxMutationsTableFilterComposer
    extends Composer<_$AppDatabase, $OutboxMutationsTable> {
  $$OutboxMutationsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get localSequence => $composableBuilder(
    column: $table.localSequence,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mutationId => $composableBuilder(
    column: $table.mutationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entityId => $composableBuilder(
    column: $table.entityId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get action => $composableBuilder(
    column: $table.action,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get baseVersion => $composableBuilder(
    column: $table.baseVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get attemptCount => $composableBuilder(
    column: $table.attemptCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastAttemptAt => $composableBuilder(
    column: $table.lastAttemptAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastErrorCode => $composableBuilder(
    column: $table.lastErrorCode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );
}

class $$OutboxMutationsTableOrderingComposer
    extends Composer<_$AppDatabase, $OutboxMutationsTable> {
  $$OutboxMutationsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get localSequence => $composableBuilder(
    column: $table.localSequence,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mutationId => $composableBuilder(
    column: $table.mutationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entityId => $composableBuilder(
    column: $table.entityId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get action => $composableBuilder(
    column: $table.action,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get baseVersion => $composableBuilder(
    column: $table.baseVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get attemptCount => $composableBuilder(
    column: $table.attemptCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastAttemptAt => $composableBuilder(
    column: $table.lastAttemptAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastErrorCode => $composableBuilder(
    column: $table.lastErrorCode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$OutboxMutationsTableAnnotationComposer
    extends Composer<_$AppDatabase, $OutboxMutationsTable> {
  $$OutboxMutationsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get localSequence => $composableBuilder(
    column: $table.localSequence,
    builder: (column) => column,
  );

  GeneratedColumn<String> get mutationId => $composableBuilder(
    column: $table.mutationId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get entityId =>
      $composableBuilder(column: $table.entityId, builder: (column) => column);

  GeneratedColumn<String> get action =>
      $composableBuilder(column: $table.action, builder: (column) => column);

  GeneratedColumn<int> get baseVersion => $composableBuilder(
    column: $table.baseVersion,
    builder: (column) => column,
  );

  GeneratedColumn<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get attemptCount => $composableBuilder(
    column: $table.attemptCount,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get lastAttemptAt => $composableBuilder(
    column: $table.lastAttemptAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get nextAttemptAt => $composableBuilder(
    column: $table.nextAttemptAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastErrorCode => $composableBuilder(
    column: $table.lastErrorCode,
    builder: (column) => column,
  );

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);
}

class $$OutboxMutationsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $OutboxMutationsTable,
          OutboxMutationRow,
          $$OutboxMutationsTableFilterComposer,
          $$OutboxMutationsTableOrderingComposer,
          $$OutboxMutationsTableAnnotationComposer,
          $$OutboxMutationsTableCreateCompanionBuilder,
          $$OutboxMutationsTableUpdateCompanionBuilder,
          (
            OutboxMutationRow,
            BaseReferences<
              _$AppDatabase,
              $OutboxMutationsTable,
              OutboxMutationRow
            >,
          ),
          OutboxMutationRow,
          PrefetchHooks Function()
        > {
  $$OutboxMutationsTableTableManager(
    _$AppDatabase db,
    $OutboxMutationsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$OutboxMutationsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$OutboxMutationsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$OutboxMutationsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> localSequence = const Value.absent(),
                Value<String> mutationId = const Value.absent(),
                Value<String> entityId = const Value.absent(),
                Value<String> action = const Value.absent(),
                Value<int> baseVersion = const Value.absent(),
                Value<String?> payloadJson = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> attemptCount = const Value.absent(),
                Value<DateTime?> lastAttemptAt = const Value.absent(),
                Value<DateTime?> nextAttemptAt = const Value.absent(),
                Value<String?> lastErrorCode = const Value.absent(),
                Value<String> status = const Value.absent(),
              }) => OutboxMutationsCompanion(
                localSequence: localSequence,
                mutationId: mutationId,
                entityId: entityId,
                action: action,
                baseVersion: baseVersion,
                payloadJson: payloadJson,
                createdAt: createdAt,
                attemptCount: attemptCount,
                lastAttemptAt: lastAttemptAt,
                nextAttemptAt: nextAttemptAt,
                lastErrorCode: lastErrorCode,
                status: status,
              ),
          createCompanionCallback:
              ({
                Value<int> localSequence = const Value.absent(),
                required String mutationId,
                required String entityId,
                required String action,
                required int baseVersion,
                Value<String?> payloadJson = const Value.absent(),
                required DateTime createdAt,
                Value<int> attemptCount = const Value.absent(),
                Value<DateTime?> lastAttemptAt = const Value.absent(),
                Value<DateTime?> nextAttemptAt = const Value.absent(),
                Value<String?> lastErrorCode = const Value.absent(),
                required String status,
              }) => OutboxMutationsCompanion.insert(
                localSequence: localSequence,
                mutationId: mutationId,
                entityId: entityId,
                action: action,
                baseVersion: baseVersion,
                payloadJson: payloadJson,
                createdAt: createdAt,
                attemptCount: attemptCount,
                lastAttemptAt: lastAttemptAt,
                nextAttemptAt: nextAttemptAt,
                lastErrorCode: lastErrorCode,
                status: status,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$OutboxMutationsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $OutboxMutationsTable,
      OutboxMutationRow,
      $$OutboxMutationsTableFilterComposer,
      $$OutboxMutationsTableOrderingComposer,
      $$OutboxMutationsTableAnnotationComposer,
      $$OutboxMutationsTableCreateCompanionBuilder,
      $$OutboxMutationsTableUpdateCompanionBuilder,
      (
        OutboxMutationRow,
        BaseReferences<_$AppDatabase, $OutboxMutationsTable, OutboxMutationRow>,
      ),
      OutboxMutationRow,
      PrefetchHooks Function()
    >;
typedef $$SyncMetadataTableCreateCompanionBuilder =
    SyncMetadataCompanion Function({
      Value<int> singletonId,
      Value<String?> householdId,
      Value<String?> memberId,
      Value<String?> memberKey,
      Value<String?> lastCursor,
      Value<String?> bootstrapPageToken,
      Value<String?> bootstrapWatermark,
      required DateTime updatedAt,
    });
typedef $$SyncMetadataTableUpdateCompanionBuilder =
    SyncMetadataCompanion Function({
      Value<int> singletonId,
      Value<String?> householdId,
      Value<String?> memberId,
      Value<String?> memberKey,
      Value<String?> lastCursor,
      Value<String?> bootstrapPageToken,
      Value<String?> bootstrapWatermark,
      Value<DateTime> updatedAt,
    });

class $$SyncMetadataTableFilterComposer
    extends Composer<_$AppDatabase, $SyncMetadataTable> {
  $$SyncMetadataTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get singletonId => $composableBuilder(
    column: $table.singletonId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get householdId => $composableBuilder(
    column: $table.householdId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get memberId => $composableBuilder(
    column: $table.memberId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get memberKey => $composableBuilder(
    column: $table.memberKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastCursor => $composableBuilder(
    column: $table.lastCursor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get bootstrapPageToken => $composableBuilder(
    column: $table.bootstrapPageToken,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get bootstrapWatermark => $composableBuilder(
    column: $table.bootstrapWatermark,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SyncMetadataTableOrderingComposer
    extends Composer<_$AppDatabase, $SyncMetadataTable> {
  $$SyncMetadataTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get singletonId => $composableBuilder(
    column: $table.singletonId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get householdId => $composableBuilder(
    column: $table.householdId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get memberId => $composableBuilder(
    column: $table.memberId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get memberKey => $composableBuilder(
    column: $table.memberKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastCursor => $composableBuilder(
    column: $table.lastCursor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get bootstrapPageToken => $composableBuilder(
    column: $table.bootstrapPageToken,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get bootstrapWatermark => $composableBuilder(
    column: $table.bootstrapWatermark,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SyncMetadataTableAnnotationComposer
    extends Composer<_$AppDatabase, $SyncMetadataTable> {
  $$SyncMetadataTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get singletonId => $composableBuilder(
    column: $table.singletonId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get householdId => $composableBuilder(
    column: $table.householdId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get memberId =>
      $composableBuilder(column: $table.memberId, builder: (column) => column);

  GeneratedColumn<String> get memberKey =>
      $composableBuilder(column: $table.memberKey, builder: (column) => column);

  GeneratedColumn<String> get lastCursor => $composableBuilder(
    column: $table.lastCursor,
    builder: (column) => column,
  );

  GeneratedColumn<String> get bootstrapPageToken => $composableBuilder(
    column: $table.bootstrapPageToken,
    builder: (column) => column,
  );

  GeneratedColumn<String> get bootstrapWatermark => $composableBuilder(
    column: $table.bootstrapWatermark,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$SyncMetadataTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SyncMetadataTable,
          SyncMetadataRow,
          $$SyncMetadataTableFilterComposer,
          $$SyncMetadataTableOrderingComposer,
          $$SyncMetadataTableAnnotationComposer,
          $$SyncMetadataTableCreateCompanionBuilder,
          $$SyncMetadataTableUpdateCompanionBuilder,
          (
            SyncMetadataRow,
            BaseReferences<_$AppDatabase, $SyncMetadataTable, SyncMetadataRow>,
          ),
          SyncMetadataRow,
          PrefetchHooks Function()
        > {
  $$SyncMetadataTableTableManager(_$AppDatabase db, $SyncMetadataTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncMetadataTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncMetadataTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncMetadataTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> singletonId = const Value.absent(),
                Value<String?> householdId = const Value.absent(),
                Value<String?> memberId = const Value.absent(),
                Value<String?> memberKey = const Value.absent(),
                Value<String?> lastCursor = const Value.absent(),
                Value<String?> bootstrapPageToken = const Value.absent(),
                Value<String?> bootstrapWatermark = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => SyncMetadataCompanion(
                singletonId: singletonId,
                householdId: householdId,
                memberId: memberId,
                memberKey: memberKey,
                lastCursor: lastCursor,
                bootstrapPageToken: bootstrapPageToken,
                bootstrapWatermark: bootstrapWatermark,
                updatedAt: updatedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> singletonId = const Value.absent(),
                Value<String?> householdId = const Value.absent(),
                Value<String?> memberId = const Value.absent(),
                Value<String?> memberKey = const Value.absent(),
                Value<String?> lastCursor = const Value.absent(),
                Value<String?> bootstrapPageToken = const Value.absent(),
                Value<String?> bootstrapWatermark = const Value.absent(),
                required DateTime updatedAt,
              }) => SyncMetadataCompanion.insert(
                singletonId: singletonId,
                householdId: householdId,
                memberId: memberId,
                memberKey: memberKey,
                lastCursor: lastCursor,
                bootstrapPageToken: bootstrapPageToken,
                bootstrapWatermark: bootstrapWatermark,
                updatedAt: updatedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SyncMetadataTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SyncMetadataTable,
      SyncMetadataRow,
      $$SyncMetadataTableFilterComposer,
      $$SyncMetadataTableOrderingComposer,
      $$SyncMetadataTableAnnotationComposer,
      $$SyncMetadataTableCreateCompanionBuilder,
      $$SyncMetadataTableUpdateCompanionBuilder,
      (
        SyncMetadataRow,
        BaseReferences<_$AppDatabase, $SyncMetadataTable, SyncMetadataRow>,
      ),
      SyncMetadataRow,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$LocalExpensesTableTableManager get localExpenses =>
      $$LocalExpensesTableTableManager(_db, _db.localExpenses);
  $$OutboxMutationsTableTableManager get outboxMutations =>
      $$OutboxMutationsTableTableManager(_db, _db.outboxMutations);
  $$SyncMetadataTableTableManager get syncMetadata =>
      $$SyncMetadataTableTableManager(_db, _db.syncMetadata);
}
