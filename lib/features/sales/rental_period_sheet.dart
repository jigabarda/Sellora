import 'package:flutter/material.dart';

/// Asks for the two dates a rental was actually agreed on.
///
/// A day count is what the money is made of, but it is not what anyone agrees
/// to — a customer says "Saturday to Monday", and turning that into a number in
/// their head is exactly the arithmetic this is meant to do for them. Picking
/// dates also makes the due date real rather than implied, which is what the
/// return screen chases.
///
/// The day count is `end - start`, so the 19th to the 22nd is three days and
/// the 22nd is the day it comes back. Same-day is charged as one day: nobody
/// hires chairs for nothing, and a zero would zero the money.
///
/// Returns the chosen range, or null if it was dismissed.
Future<DateTimeRange?> askRentalPeriod(
  BuildContext context, {
  required String productName,
  DateTimeRange? current,
}) async {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);

  return showDateRangePicker(
    context: context,
    // Backdated a year because a rental is sometimes written up after the
    // fact, and forward two because bookings are taken well ahead.
    firstDate: DateTime(today.year - 1),
    lastDate: DateTime(today.year + 2, 12, 31),
    initialDateRange: current ??
        DateTimeRange(
          start: today,
          end: DateTime(today.year, today.month, today.day + 1),
        ),
    helpText: 'Rented $productName',
    fieldStartLabelText: 'Date out',
    fieldEndLabelText: 'Date back',
    saveText: 'Set period',
  );
}

/// How many days a range is charged as. Kept beside the picker so the screens,
/// the cart and the tests cannot disagree about it.
int daysInPeriod(DateTimeRange range) {
  final from = DateTime(range.start.year, range.start.month, range.start.day);
  final to = DateTime(range.end.year, range.end.month, range.end.day);
  final span = to.difference(from).inDays;
  return span < 1 ? 1 : span;
}
