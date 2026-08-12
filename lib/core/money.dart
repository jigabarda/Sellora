import 'package:intl/intl.dart';

final _php = NumberFormat.currency(locale: 'en_PH', symbol: '₱');

String formatPhp(num amount) => _php.format(amount);
