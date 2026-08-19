import '../models/entities.dart';

/// How much the parser trusts one line off a photographed page.
///
/// The distinction that matters is not "did OCR return characters" but "does
/// the arithmetic on the page agree with the price list". A line the owner
/// wrote as `Nena 2 refill 50` carries its own proof: two refills at ₱25 is
/// ₱50. When that check passes, a garbled character or two is irrelevant.
enum LineStatus {
  /// Quantity × the catalogue price equals the amount written on the page.
  /// The line proved itself; it does not need the owner's attention.
  reconciled,

  /// Something was read, but nothing confirmed it — the amount was missing,
  /// or it disagreed with the price list. Recordable, but only deliberately.
  needsReview,

  /// Already written to the books by a previous tap on Record.
  ///
  /// This exists because recording a page can partly fail — one line runs the
  /// shelf down while the rest go in. The preview stays open so the owner can
  /// deal with the failure, and without this the lines that succeeded would sit
  /// there still ticked and indistinguishable from the ones that did not.
  /// Restock, tick everything, record again, and the successful lines would be
  /// written a second time. A recorded line is never recordable again.
  recorded,

  /// No product could be identified. Nothing to record.
  unreadable,

  /// A date header, a running total, a stray mark. Not a transaction, and not
  /// a failure — but shown anyway, because a line that silently vanishes is
  /// indistinguishable from one the app never saw.
  ignored,
}

/// One line of a photographed page, and the sale it might become.
class NotebookLine {
  const NotebookLine({
    required this.raw,
    required this.status,
    this.product,
    this.customer,
    this.quantity = 1,
    this.writtenAmount,
    this.note,
  });

  /// Exactly what the recogniser returned, kept verbatim.
  ///
  /// The owner checks the preview against the page in their other hand, so the
  /// original text has to stay visible — a cleaned-up version they cannot match
  /// against the paper is worse than none.
  final String raw;

  final LineStatus status;
  final Product? product;
  final Customer? customer;
  final int quantity;

  /// The peso figure written on the page, when there was one. Null means the
  /// line had no amount to check against, not that it came to zero.
  final double? writtenAmount;

  /// Why this line needs looking at, in the owner's terms. Null when it does
  /// not.
  final String? note;

  /// What Sellora would record — always the catalogue price, never the number
  /// on the page.
  ///
  /// A mismatch is a question to answer, not a discount to honour. If the page
  /// says ₱45 for two ₱25 refills, recording ₱45 would quietly bake a reading
  /// error into the books; the line is flagged instead and the owner decides.
  double get total => (product?.price ?? 0) * quantity;

  /// Whether this line can become a sale at all.
  ///
  /// [LineStatus.recorded] is deliberately absent: a line that is already in
  /// the books must not be selectable, or a partly-failed page could be
  /// recorded twice.
  bool get isRecordable =>
      product != null &&
      quantity > 0 &&
      (status == LineStatus.reconciled || status == LineStatus.needsReview);

  NotebookLine copyWith({
    LineStatus? status,
    Product? product,
    Customer? customer,
    bool clearCustomer = false,
    int? quantity,
    String? note,
    bool clearNote = false,
  }) {
    return NotebookLine(
      raw: raw,
      status: status ?? this.status,
      product: product ?? this.product,
      customer: clearCustomer ? null : (customer ?? this.customer),
      quantity: quantity ?? this.quantity,
      writtenAmount: writtenAmount,
      note: clearNote ? null : (note ?? this.note),
    );
  }
}

/// Everything read off one photograph.
class NotebookPage {
  const NotebookPage({required this.lines});

  const NotebookPage.empty() : lines = const [];

  final List<NotebookLine> lines;

  Iterable<NotebookLine> get recordable => lines.where((l) => l.isRecordable);

  int get reconciledCount =>
      lines.where((l) => l.status == LineStatus.reconciled).length;

  int get needsReviewCount =>
      lines.where((l) => l.status == LineStatus.needsReview).length;

  int get recordedCount =>
      lines.where((l) => l.status == LineStatus.recorded).length;

  /// True when the photo produced nothing worth showing a preview for — a
  /// picture of a wall, a page too blurred to resolve.
  bool get isBlank => lines.every((l) => l.status == LineStatus.ignored);
}
