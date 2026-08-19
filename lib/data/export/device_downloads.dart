import 'package:flutter/services.dart';

/// Thrown when the device cannot save to Downloads and the caller should offer
/// the share sheet instead.
///
/// A distinct type rather than a flag: the fallback is a real branch in the UI,
/// and a caller that forgets to handle it should fail loudly in review rather
/// than silently swallow a save that never happened.
class DownloadsUnsupported implements Exception {
  const DownloadsUnsupported(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Thrown when saving was attempted and genuinely failed.
class DownloadFailed implements Exception {
  const DownloadFailed(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Puts a generated file into the device's public Downloads folder.
///
/// This exists because "export" that only offers a share sheet is not really an
/// export: on some devices the sheet has no Files entry at all, and the owner is
/// left with no way to put the spreadsheet somewhere they can find it again.
///
/// Costs no permission. From Android 10 an app may contribute to Downloads
/// through MediaStore without holding a storage grant, because it can only
/// touch what it wrote itself. See MainActivity.kt for the other side.
class DeviceDownloads {
  const DeviceDownloads({MethodChannel channel = _defaultChannel})
      : _channel = channel;

  static const _defaultChannel = MethodChannel('com.sellora.mobile/downloads');

  final MethodChannel _channel;

  /// Saves [bytes] as [fileName] and returns the name it was actually stored
  /// under — which is not always the one asked for, since a clash is renamed.
  ///
  /// Throws [DownloadsUnsupported] on Android 9 and older, where writing to a
  /// public folder would mean asking for WRITE_EXTERNAL_STORAGE.
  Future<String> save({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
  }) async {
    try {
      final saved = await _channel.invokeMethod<String>('saveToDownloads', {
        'fileName': fileName,
        'bytes': bytes,
        'mimeType': mimeType,
      });
      if (saved == null) {
        throw const DownloadFailed('The file was not saved.');
      }
      return saved;
    } on PlatformException catch (e) {
      if (e.code == 'unsupported') {
        throw DownloadsUnsupported(e.message ?? 'Saving is not supported here.');
      }
      throw DownloadFailed(e.message ?? 'Could not save the file.');
    } on MissingPluginException {
      // Desktop, tests, or any host without the channel. Treated as "cannot
      // save here" rather than as a crash, so the caller falls back to sharing.
      throw const DownloadsUnsupported('Saving is not supported on this device.');
    }
  }
}
