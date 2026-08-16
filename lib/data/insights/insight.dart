import 'package:flutter/widgets.dart';

/// How loudly an insight should present itself.
///
/// Maps to the app's semantic tones in the UI layer, not here — the rules
/// decide how urgent something is, the theme decides what urgent looks like.
enum InsightSeverity {
  /// Money or stock is running out now. Acting today changes the outcome.
  critical,

  /// Worth attention this week.
  warning,

  /// Useful to know; nothing is wrong.
  info,
}

/// One thing worth telling the owner about their business, derived entirely
/// from their own records.
///
/// [detail] must carry the numbers it was derived from. "You're losing money"
/// is not an insight; "₱18,350 in expenses against ₱605 in sales over 7 days"
/// is, because the owner can check it against what they already know. An
/// insight the reader cannot verify is indistinguishable from one that is
/// simply wrong.
@immutable
class Insight {
  const Insight({
    required this.id,
    required this.severity,
    required this.icon,
    required this.title,
    required this.detail,
    this.actionLabel,
    this.actionRoute,
  });

  /// Stable across runs for the same underlying fact, so a future "dismiss"
  /// feature has something to key on. Includes the record id where a rule can
  /// produce more than one insight.
  final String id;

  final InsightSeverity severity;
  final IconData icon;

  /// One line, naming the thing. Read on its own in the dashboard card.
  final String title;

  /// The sentence carrying the evidence.
  final String detail;

  final String? actionLabel;
  final String? actionRoute;
}
