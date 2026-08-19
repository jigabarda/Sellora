import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:sellora_mobile/data/notebook/text_recogniser.dart';

/// Geometry is exactly the kind of code that looks obviously right and is off
/// by one band, so the row rebuilder is tested directly.
///
/// What is at stake: ML Kit groups text into blocks by proximity, and on a
/// ruled ledger page the name, the item and the amount routinely land in three
/// different blocks. If they are not put back on one line, every line arrives
/// without its amount — and the amount is the only thing the parser can check
/// anything against.
void main() {
  test('columns from separate blocks are rebuilt into one row', () {
    final text = rowsFromBlocks([
      _block([_line('Nena', top: 100, left: 20)]),
      _block([_line('2 refill', top: 102, left: 200)]),
      _block([_line('50', top: 99, left: 420)]),
    ]);

    expect(text, 'Nena 2 refill 50');
  });

  test('fragments are ordered left to right, not by block order', () {
    // ML Kit returns blocks in its own order, which is not the reading order.
    final text = rowsFromBlocks([
      _block([_line('50', top: 100, left: 420)]),
      _block([_line('Nena', top: 100, left: 20)]),
      _block([_line('2 refill', top: 100, left: 200)]),
    ]);

    expect(text, 'Nena 2 refill 50');
  });

  test('separate rows stay separate, in top-to-bottom order', () {
    final text = rowsFromBlocks([
      _block([_line('Tonyo', top: 180, left: 20)]),
      _block([_line('120', top: 180, left: 420)]),
      _block([_line('Nena', top: 100, left: 20)]),
      _block([_line('50', top: 100, left: 420)]),
    ]);

    expect(text, 'Nena 50\nTonyo 120');
  });

  test('a row that drifts downward keeps its last column', () {
    // Handwriting rarely sits level. Each fragment sits slightly lower than the
    // one before, so the last is well below the first — but each is close to
    // the running mean, which is why the mean is tracked rather than the
    // first fragment's position.
    final text = rowsFromBlocks([
      _block([_line('Ate', top: 100, left: 20)]),
      _block([_line('Baby', top: 108, left: 120)]),
      _block([_line('3 refill', top: 116, left: 240)]),
      _block([_line('75', top: 124, left: 440)]),
    ]);

    expect(text, 'Ate Baby 3 refill 75');
  });

  test('the band scales with text size rather than a fixed pixel gap', () {
    // The same 30px vertical offset: within tolerance for tall glyphs,
    // outside it for short ones. A fixed band would merge rows on a close-up
    // photo and split them on a distant one.
    final tall = rowsFromBlocks([
      _block([_line('Nena', top: 100, left: 20, height: 60)]),
      _block([_line('50', top: 130, left: 420, height: 60)]),
    ]);
    expect(tall, 'Nena 50');

    final short = rowsFromBlocks([
      _block([_line('Nena', top: 100, left: 20, height: 12)]),
      _block([_line('50', top: 130, left: 420, height: 12)]),
    ]);
    expect(short, 'Nena\n50');
  });

  test('several lines inside one block are still split by row', () {
    // The common case where ML Kit gets it right on its own.
    final text = rowsFromBlocks([
      _block([
        _line('Nena 50', top: 100, left: 20),
        _line('Tonyo 120', top: 200, left: 20),
      ]),
    ]);

    expect(text, 'Nena 50\nTonyo 120');
  });

  test('blank fragments are dropped rather than padding the row', () {
    final text = rowsFromBlocks([
      _block([_line('Nena', top: 100, left: 20)]),
      _block([_line('   ', top: 100, left: 200)]),
      _block([_line('50', top: 100, left: 420)]),
    ]);

    expect(text, 'Nena 50');
  });

  test('no blocks yields empty text, not a stray newline', () {
    expect(rowsFromBlocks([]), '');
    expect(rowsFromBlocks([_block([])]), '');
  });
}

TextBlock _block(List<TextLine> lines) => TextBlock(
      text: lines.map((l) => l.text).join('\n'),
      lines: lines,
      boundingBox: lines.isEmpty
          ? Rect.zero
          : lines
              .map((l) => l.boundingBox)
              .reduce((a, b) => a.expandToInclude(b)),
      recognizedLanguages: const [],
      cornerPoints: const [],
    );

TextLine _line(
  String text, {
  required double top,
  required double left,
  double height = 24,
  double width = 120,
}) =>
    TextLine(
      text: text,
      elements: const [],
      boundingBox: Rect.fromLTWH(left, top, width, height),
      recognizedLanguages: const [],
      cornerPoints: const [],
      confidence: null,
      angle: null,
    );
