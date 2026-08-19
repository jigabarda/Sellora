package com.sellora.mobile

import android.content.ContentValues
import android.os.Build
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Hosts one small channel: saving a generated file into the device's Downloads.
 *
 * Written by hand rather than pulled from a package on purpose. This is fifty
 * lines against a stable platform API, and the last dependency added to this
 * app arrived with a telemetry uploader and the INTERNET permission three
 * levels down. Code we own cannot do that.
 */
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "saveToDownloads" -> saveToDownloads(call, result)
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Writes [bytes] into the public Downloads collection and returns where it
     * landed.
     *
     * MediaStore is the whole reason this needs no permission: from Android 10
     * an app may contribute a file to Downloads without holding any storage
     * grant, because it can only ever touch what it wrote itself. Sellora asks
     * for no permissions and an export is not a reason to start.
     *
     * Below Android 10 there is no such API — writing to a public directory
     * there means WRITE_EXTERNAL_STORAGE — so this reports the case rather than
     * quietly widening what the app can reach. Dart turns that into the share
     * sheet instead.
     */
    private fun saveToDownloads(call: MethodCall, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            result.error(
                ERROR_UNSUPPORTED,
                "Saving to Downloads needs Android 10 or newer.",
                null,
            )
            return
        }

        val fileName = call.argument<String>("fileName")
        val bytes = call.argument<ByteArray>("bytes")
        val mimeType = call.argument<String>("mimeType")
        if (fileName == null || bytes == null || mimeType == null) {
            result.error(ERROR_ARGS, "fileName, bytes and mimeType are required.", null)
            return
        }

        try {
            val resolver = applicationContext.contentResolver
            val pending = ContentValues().apply {
                put(MediaStore.Downloads.DISPLAY_NAME, fileName)
                put(MediaStore.Downloads.MIME_TYPE, mimeType)
                // Marked pending until the bytes are all there, so nothing else
                // on the device can open a half-written file.
                put(MediaStore.Downloads.IS_PENDING, 1)
            }

            val uri = resolver.insert(
                MediaStore.Downloads.EXTERNAL_CONTENT_URI,
                pending,
            ) ?: run {
                result.error(ERROR_FAILED, "Downloads is not available on this device.", null)
                return
            }

            resolver.openOutputStream(uri).use { stream ->
                if (stream == null) {
                    resolver.delete(uri, null, null)
                    result.error(ERROR_FAILED, "Could not open the file for writing.", null)
                    return
                }
                stream.write(bytes)
                stream.flush()
            }

            resolver.update(
                uri,
                ContentValues().apply { put(MediaStore.Downloads.IS_PENDING, 0) },
                null,
                null,
            )

            // Read the name back rather than echoing what we asked for:
            // MediaStore renames a clash to "report (1).xlsx", and telling the
            // owner a name that is not on their device is worse than useless.
            // The same channel now carries spreadsheets and backups, so it
            // stays generic about what it is writing.
            val saved = resolver.query(
                uri,
                arrayOf(MediaStore.Downloads.DISPLAY_NAME),
                null,
                null,
                null,
            )?.use { cursor ->
                if (cursor.moveToFirst()) cursor.getString(0) else null
            } ?: fileName

            result.success(saved)
        } catch (e: Exception) {
            result.error(ERROR_FAILED, e.message ?: "Could not save the file.", null)
        }
    }

    companion object {
        private const val CHANNEL = "com.sellora.mobile/downloads"
        const val ERROR_UNSUPPORTED = "unsupported"
        const val ERROR_ARGS = "bad_arguments"
        const val ERROR_FAILED = "save_failed"
    }
}
