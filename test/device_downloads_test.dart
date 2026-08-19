import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sellora_mobile/data/export/device_downloads.dart';

/// The native half of saving to Downloads cannot be unit tested from here, so
/// what these pin down is the contract between the two: what gets sent across,
/// and — the part that actually matters — how each failure is classified.
/// Mistaking "this phone cannot" for "this failed" is the difference between
/// falling back to the share sheet and telling the owner their export broke.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('test/downloads');
  const downloads = DeviceDownloads(channel: channel);
  final bytes = Uint8List.fromList([0x50, 0x4b, 0x03, 0x04]);

  void mock(Future<Object?>? Function(MethodCall call)? handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, handler);
  }

  tearDown(() => mock(null));

  test('sends the name, the bytes and the type across', () async {
    MethodCall? seen;
    mock((call) async {
      seen = call;
      return 'report.xlsx';
    });

    await downloads.save(
      fileName: 'report.xlsx',
      bytes: bytes,
      mimeType: 'application/vnd.ms-excel',
    );

    expect(seen!.method, 'saveToDownloads');
    final args = seen!.arguments as Map;
    expect(args['fileName'], 'report.xlsx');
    expect(args['mimeType'], 'application/vnd.ms-excel');
    expect(args['bytes'], bytes);
  });

  test('returns the name the file was actually stored under', () async {
    // MediaStore renames a clash, so the caller must report what came back
    // rather than what it asked for — otherwise the toast names a file that is
    // not on the device.
    mock((call) async => 'report (1).xlsx');

    final saved = await downloads.save(
      fileName: 'report.xlsx',
      bytes: bytes,
      mimeType: 'application/vnd.ms-excel',
    );

    expect(saved, 'report (1).xlsx');
  });

  test('an old Android reads as unsupported, not as a failure', () async {
    mock((call) async {
      throw PlatformException(
        code: 'unsupported',
        message: 'Saving to Downloads needs Android 10 or newer.',
      );
    });

    // This is the branch that sends the owner to the share sheet instead.
    await expectLater(
      downloads.save(
          fileName: 'r.xlsx', bytes: bytes, mimeType: 'application/x'),
      throwsA(isA<DownloadsUnsupported>()),
    );
  });

  test('a genuine write failure is reported as a failure', () async {
    mock((call) async {
      throw PlatformException(code: 'save_failed', message: 'disk full');
    });

    await expectLater(
      downloads.save(
          fileName: 'r.xlsx', bytes: bytes, mimeType: 'application/x'),
      throwsA(isA<DownloadFailed>()),
    );
  });

  test('a host with no channel at all falls back rather than crashing',
      () async {
    // No handler registered: desktop, a test, or any build without the native
    // side. Treated as "cannot save here" so the UI offers sharing.
    mock(null);

    await expectLater(
      downloads.save(
          fileName: 'r.xlsx', bytes: bytes, mimeType: 'application/x'),
      throwsA(isA<DownloadsUnsupported>()),
    );
  });

  test('a null answer is a failure, not a success', () async {
    mock((call) async => null);

    await expectLater(
      downloads.save(
          fileName: 'r.xlsx', bytes: bytes, mimeType: 'application/x'),
      throwsA(isA<DownloadFailed>()),
    );
  });
}
