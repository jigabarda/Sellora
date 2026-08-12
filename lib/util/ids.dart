import 'dart:math';

String newLocalId(String prefix) {
  final n = Random().nextInt(1 << 20);
  return '${prefix}_${DateTime.now().microsecondsSinceEpoch}_$n';
}
