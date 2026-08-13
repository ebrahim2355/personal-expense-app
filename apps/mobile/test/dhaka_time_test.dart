import 'package:flutter_test/flutter_test.dart';
import 'package:houseexpenses/src/domain/dhaka_time.dart';

void main() {
  final dhaka = DhakaTime.initialize();

  test('current month uses Asia/Dhaka boundaries', () {
    final range = dhaka.currentMonth(DateTime.utc(2026, 7, 31, 20));

    expect(range.startDate, const CalendarDate(2026, 8, 1));
    expect(range.endDateInclusive, const CalendarDate(2026, 8, 31));
    expect(range.startInclusive, DateTime.utc(2026, 7, 31, 18));
    expect(range.endExclusive, DateTime.utc(2026, 8, 31, 18));
  });

  test('midnight expenses land in the correct Dhaka calendar month', () {
    final august = dhaka.range(
      const CalendarDate(2026, 8, 1),
      const CalendarDate(2026, 8, 31),
    );

    expect(august.contains(DateTime.utc(2026, 7, 31, 17, 59, 59)), isFalse);
    expect(august.contains(DateTime.utc(2026, 7, 31, 18)), isTrue);
    expect(august.contains(DateTime.utc(2026, 8, 31, 17, 59, 59)), isTrue);
    expect(august.contains(DateTime.utc(2026, 8, 31, 18)), isFalse);
  });

  test('an inclusive local date range converts to a half-open UTC range', () {
    final range = dhaka.range(
      const CalendarDate(2026, 8, 13),
      const CalendarDate(2026, 8, 13),
    );

    expect(range.startInclusive, DateTime.utc(2026, 8, 12, 18));
    expect(range.endExclusive, DateTime.utc(2026, 8, 13, 18));
    expect(range.contains(DateTime.utc(2026, 8, 12, 18)), isTrue);
    expect(range.contains(DateTime.utc(2026, 8, 13, 18)), isFalse);
  });
}
