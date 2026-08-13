import 'package:timezone/data/latest.dart' as timezone_data;
import 'package:timezone/timezone.dart' as timezone;

final class CalendarDate implements Comparable<CalendarDate> {
  const CalendarDate(this.year, this.month, this.day);

  final int year;
  final int month;
  final int day;

  @override
  int compareTo(CalendarDate other) {
    final yearComparison = year.compareTo(other.year);
    if (yearComparison != 0) {
      return yearComparison;
    }
    final monthComparison = month.compareTo(other.month);
    return monthComparison != 0 ? monthComparison : day.compareTo(other.day);
  }

  @override
  bool operator ==(Object other) =>
      other is CalendarDate &&
      other.year == year &&
      other.month == month &&
      other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);
}

final class ExpenseDateRange {
  const ExpenseDateRange({
    required this.startDate,
    required this.endDateInclusive,
    required this.startInclusive,
    required this.endExclusive,
  });

  final CalendarDate startDate;
  final CalendarDate endDateInclusive;
  final DateTime startInclusive;
  final DateTime endExclusive;

  bool contains(DateTime instant) {
    final utc = instant.toUtc();
    return !utc.isBefore(startInclusive) && utc.isBefore(endExclusive);
  }
}

final class DhakaTime {
  DhakaTime._(this.location);

  static DhakaTime? _instance;

  final timezone.Location location;

  static DhakaTime initialize() {
    final existing = _instance;
    if (existing != null) {
      return existing;
    }
    timezone_data.initializeTimeZones();
    return _instance = DhakaTime._(timezone.getLocation('Asia/Dhaka'));
  }

  timezone.TZDateTime local(DateTime instant) =>
      timezone.TZDateTime.from(instant.toUtc(), location);

  DateTime toUtc({required CalendarDate date, int hour = 0, int minute = 0}) =>
      timezone.TZDateTime(
        location,
        date.year,
        date.month,
        date.day,
        hour,
        minute,
      ).toUtc();

  ExpenseDateRange currentMonth(DateTime now) {
    final localNow = local(now);
    final start = CalendarDate(localNow.year, localNow.month, 1);
    final nextMonth = localNow.month == 12
        ? CalendarDate(localNow.year + 1, 1, 1)
        : CalendarDate(localNow.year, localNow.month + 1, 1);
    final lastDay = timezone.TZDateTime(
      location,
      nextMonth.year,
      nextMonth.month,
      0,
    );
    return ExpenseDateRange(
      startDate: start,
      endDateInclusive: CalendarDate(lastDay.year, lastDay.month, lastDay.day),
      startInclusive: toUtc(date: start),
      endExclusive: toUtc(date: nextMonth),
    );
  }

  ExpenseDateRange range(CalendarDate start, CalendarDate endInclusive) {
    if (endInclusive.compareTo(start) < 0) {
      throw ArgumentError('The end date must not precede the start date.');
    }
    final nextLocalDay = timezone.TZDateTime(
      location,
      endInclusive.year,
      endInclusive.month,
      endInclusive.day + 1,
    );
    return ExpenseDateRange(
      startDate: start,
      endDateInclusive: endInclusive,
      startInclusive: toUtc(date: start),
      endExclusive: nextLocalDay.toUtc(),
    );
  }

  String formatDate(DateTime instant) {
    final value = local(instant);
    return '${_monthNames[value.month - 1]} ${value.day}, ${value.year}';
  }

  String formatDateTime(DateTime instant) {
    final value = local(instant);
    final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
    final minute = value.minute.toString().padLeft(2, '0');
    final period = value.hour < 12 ? 'AM' : 'PM';
    return '${formatDate(instant)} · $hour:$minute $period';
  }

  String formatRange(ExpenseDateRange range) {
    final start = range.startDate;
    final end = range.endDateInclusive;
    if (start.year == end.year && start.month == end.month && start.day == 1) {
      final nextMonth = DateTime.utc(start.year, start.month + 1, 1);
      final finalDay = DateTime.utc(nextMonth.year, nextMonth.month, 0).day;
      if (end.day == finalDay) {
        return '${_monthNames[start.month - 1]} ${start.year}';
      }
    }
    return '${_shortDate(start)} – ${_shortDate(end)}';
  }

  String _shortDate(CalendarDate date) =>
      '${_monthNames[date.month - 1].substring(0, 3)} ${date.day}, ${date.year}';
}

const List<String> _monthNames = <String>[
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];
