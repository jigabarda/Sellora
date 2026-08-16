import '../models/entities.dart';

/// What the parser understood an utterance to mean.
///
/// Nothing here writes. A command is an intention to open a form with fields
/// already filled; the user's tap on that form's save button is the commit.
/// See `docs/QUICK_ENTRY_DESIGN.md` for why that separation is load-bearing.
sealed class QuickCommand {
  const QuickCommand();
}

class RecordSaleCommand extends QuickCommand {
  const RecordSaleCommand({
    required this.product,
    required this.quantity,
    this.customer,
  });

  final Product product;
  final int quantity;
  final Customer? customer;

  double get total => product.price * quantity;
}

class AddExpenseCommand extends QuickCommand {
  const AddExpenseCommand({
    required this.amount,
    required this.category,
    required this.note,
  });

  final double amount;
  final String category;

  /// The original utterance. Better provenance than a blank note, and the user
  /// can edit it on the form like any other field.
  final String note;
}

/// The parser could not decide, or was not confident enough to guess.
///
/// This is a success, not a failure state: it opens an empty form, which is
/// exactly where the user would have started anyway. A wrong guess costs more
/// than an admission of ignorance.
class UnparsedCommand extends QuickCommand {
  const UnparsedCommand(this.input);

  final String input;
}
