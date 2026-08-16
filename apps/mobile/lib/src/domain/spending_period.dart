import 'expense.dart';

/// Matches the API's `MAX_SEQUENCE_NUMBER`, the widest signed 32-bit integer
/// the server's `sequenceNumber` column accepts.
const int maximumSequenceNumber = 2147483647;

/// A stretch of shared spending that the two members settle as one unit.
///
/// A period is not a calendar month. It runs from the moment it is opened until
/// the members agree they are square, at which point it is stamped closed and
/// the next one opens. Exactly one period is open at a time.
final class SpendingPeriodDraft {
  const SpendingPeriodDraft({
    required this.sequenceNumber,
    required this.startedAt,
    this.closedAt,
    this.note,
  });

  final int sequenceNumber;
  final DateTime startedAt;
  final DateTime? closedAt;
  final String? note;

  SpendingPeriodDraft normalized() {
    if (sequenceNumber < 1 || sequenceNumber > maximumSequenceNumber) {
      throw ArgumentError.value(
        sequenceNumber,
        'sequenceNumber',
        'Must be an integer from 1 to $maximumSequenceNumber.',
      );
    }
    if (!startedAt.isUtc) {
      throw ArgumentError.value(
        startedAt,
        'startedAt',
        'Must be a UTC instant.',
      );
    }
    final closed = closedAt;
    if (closed != null) {
      if (!closed.isUtc) {
        throw ArgumentError.value(closed, 'closedAt', 'Must be a UTC instant.');
      }
      if (closed.isBefore(startedAt)) {
        throw ArgumentError.value(
          closed,
          'closedAt',
          'Must not precede startedAt.',
        );
      }
    }
    final normalizedNote = note?.trim();
    if (normalizedNote != null &&
        normalizedNote.runes.length > maximumNoteCodePoints) {
      throw ArgumentError.value(
        note,
        'note',
        'Must not exceed $maximumNoteCodePoints Unicode code points.',
      );
    }
    return SpendingPeriodDraft(
      sequenceNumber: sequenceNumber,
      startedAt: startedAt,
      closedAt: closed,
      note: normalizedNote == null || normalizedNote.isEmpty
          ? null
          : normalizedNote,
    );
  }

  Map<String, Object?> toWireJson() => <String, Object?>{
    'sequenceNumber': sequenceNumber,
    'startedAt': startedAt.toUtc().toIso8601String(),
    'closedAt': closedAt?.toUtc().toIso8601String(),
    'note': note,
  };
}

final class SpendingPeriod {
  const SpendingPeriod({
    required this.id,
    required this.sequenceNumber,
    required this.startedAt,
    required this.version,
    required this.updatedAt,
    required this.syncState,
    this.closedAt,
    this.note,
  });

  final String id;
  final int sequenceNumber;
  final DateTime startedAt;
  final DateTime? closedAt;
  final String? note;
  final int version;
  final DateTime updatedAt;
  final LocalSyncState syncState;

  /// True until the members settle up. Only one period is ever open.
  bool get isOpen => closedAt == null;

  String get displayName => 'Period $sequenceNumber';

  SpendingPeriodDraft get draft => SpendingPeriodDraft(
    sequenceNumber: sequenceNumber,
    startedAt: startedAt,
    closedAt: closedAt,
    note: note,
  );

  SpendingPeriodDraft closedAtDraft(DateTime closedAt) => SpendingPeriodDraft(
    sequenceNumber: sequenceNumber,
    startedAt: startedAt,
    closedAt: closedAt,
    note: note,
  );
}
