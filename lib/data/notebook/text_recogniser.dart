import 'dart:ui';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// Turns an image file into text, one physical row of the page per line.
///
/// An interface rather than a direct call so the parser above it can be tested
/// without a camera, an emulator, or a photograph.
abstract class TextRecogniser {
  Future<String> recognise(String imagePath);

  /// Releases the native recogniser. Cheap to call more than once.
  Future<void> dispose();
}

/// On-device recognition via ML Kit.
///
/// The model is compiled into the APK (`com.google.mlkit:text-recognition`,
/// the bundled artifact — not the variant that fetches itself through Play
/// Services). Nothing here reaches the network, and the release manifest
/// removes the INTERNET permission that ML Kit's telemetry dependency would
/// otherwise have added. See android/app/src/release/AndroidManifest.xml.
class MlKitTextRecogniser implements TextRecogniser {
  MlKitTextRecogniser();

  TextRecognizer? _recogniser;

  @override
  Future<String> recognise(String imagePath) async {
    // Built on first use, not in the constructor: constructing it opens a
    // platform channel, and this class is referenced from code paths that run
    // in tests where no channel exists.
    final recogniser =
        _recogniser ??= TextRecognizer(script: TextRecognitionScript.latin);

    final result =
        await recogniser.processImage(InputImage.fromFilePath(imagePath));
    return rowsFromBlocks(result.blocks);
  }

  @override
  Future<void> dispose() async {
    await _recogniser?.close();
    _recogniser = null;
  }
}

/// Rebuilds the page's rows from the recogniser's blocks.
///
/// This is the whole reason the adapter is more than one line. ML Kit groups
/// text into blocks by proximity, and on a ruled ledger page the columns are
/// far enough apart that the name, the item and the amount frequently land in
/// three different blocks. Reading `result.text` straight through would hand
/// the parser "Nena", "2 refill" and "50" as three separate lines — and a line
/// with no amount cannot be checked against anything, which throws away the
/// one signal the whole feature depends on.
///
/// So rows are reconstructed geometrically: fragments sharing a horizontal
/// band belong to the same row, and within it they read left to right.
///
/// Exposed for testing — geometry is exactly the kind of thing that looks
/// obviously right and is off by one band.
String rowsFromBlocks(List<TextBlock> blocks) {
  final fragments = <({Rect box, String text})>[];
  for (final block in blocks) {
    for (final line in block.lines) {
      final text = line.text.trim();
      if (text.isEmpty) continue;
      fragments.add((box: line.boundingBox, text: text));
    }
  }
  if (fragments.isEmpty) return '';

  fragments.sort((a, b) => a.box.center.dy.compareTo(b.box.center.dy));

  final rows = <List<({Rect box, String text})>>[];
  var current = <({Rect box, String text})>[fragments.first];
  var previousCentre = fragments.first.box.center.dy;

  for (final fragment in fragments.skip(1)) {
    // Tolerance scales with the text: the same page photographed closer has
    // taller glyphs and proportionally taller gaps, so a fixed pixel band
    // would merge rows on one photo and split them on the next.
    final tolerance = fragment.box.height * _bandRatio;

    // Measured against the nearest fragment already in the row — which, since
    // these are sorted top-down, is the one before it — rather than against the
    // row's first fragment or its running mean.
    //
    // Handwriting rarely sits level, and a row that sags steadily across the
    // page can end several fragments' worth below where it started. Both a
    // fixed anchor and a mean fall behind that drift and shed the last column,
    // which is usually the amount: the one value the parser most needs.
    if ((fragment.box.center.dy - previousCentre).abs() <= tolerance) {
      current.add(fragment);
    } else {
      rows.add(current);
      current = [fragment];
    }
    previousCentre = fragment.box.center.dy;
  }
  rows.add(current);

  return rows.map((row) {
    row.sort((a, b) => a.box.left.compareTo(b.box.left));
    return row.map((f) => f.text).join(' ');
  }).join('\n');
}

/// How far off a row's centre a fragment can sit and still belong to it, as a
/// fraction of its own height. Roughly half a line of text.
const _bandRatio = 0.6;
