import 'package:intl/intl.dart';

final _dayMonth = DateFormat('d MMM');
final _dayMonthYear = DateFormat('d MMM y');
final _time = DateFormat('h:mm a');

/// "Today, 2:05 PM" / "Yesterday, 9:12 AM" / "3 Aug, 9:12 AM", dropping to a
/// full date once the year differs. Used by every list that shows a timestamp.
String formatTimestamp(DateTime at, [DateTime? now]) {
  final reference = now ?? DateTime.now();
  final today = startOfTodayLocal(reference);
  final day = startOfTodayLocal(at);
  final time = _time.format(at);

  if (day == today) return 'Today, $time';
  if (day == addDays(today, -1)) return 'Yesterday, $time';
  if (at.year == reference.year) return '${_dayMonth.format(at)}, $time';
  return '${_dayMonthYear.format(at)}, $time';
}

/// Date without the time, for range pickers and report headers.
String formatDay(DateTime at, [DateTime? now]) {
  final reference = now ?? DateTime.now();
  return at.year == reference.year
      ? _dayMonth.format(at)
      : _dayMonthYear.format(at);
}

DateTime startOfTodayLocal([DateTime? now]) {
  final n = now ?? DateTime.now();
  return DateTime(n.year, n.month, n.day);
}

DateTime addDays(DateTime d, int days) => d.add(Duration(days: days));

/// Monday as first day of week (matches common business week).
DateTime startOfWeekMondayLocal([DateTime? now]) {
  final n = now ?? DateTime.now();
  final today = startOfTodayLocal(n);
  final weekday = today.weekday; // Mon=1 ... Sun=7
  return today.subtract(Duration(days: weekday - 1));
}
