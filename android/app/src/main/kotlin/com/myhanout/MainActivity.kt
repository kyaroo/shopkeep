package com.myhanout

import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Hosts the `.myhanout` catalog-delta file flow.
 *
 * Android routes a VIEW intent for a `.myhanout` file (WhatsApp, Downloads,
 * a file manager) to this activity. We capture the URI and let Dart read and
 * apply it — see lib/data/myhanout_file.dart.
 */
class MainActivity : FlutterActivity() {
    private var pendingUri: String? = null
    private var channel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "myhanout/view")
        ch.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialUri" -> result.success(pendingUri)
                "readUri" -> {
                    val uri = call.argument<String>("uri")
                    if (uri == null) {
                        result.error("no-uri", "uri argument missing", null)
                    } else {
                        result.success(readUri(uri))
                    }
                }
                else -> result.notImplemented()
            }
        }
        channel = ch
        capture(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        capture(intent)
        pendingUri?.let { channel?.invokeMethod("newUri", it) }
    }

    private fun capture(intent: Intent?) {
        if (intent?.action == Intent.ACTION_VIEW) {
            intent.data?.let { pendingUri = it.toString() }
        }
    }

    /** Reads a `file://` or `content://` URI as UTF-8 text. */
    private fun readUri(uri: String): String? {
        return try {
            contentResolver.openInputStream(Uri.parse(uri))?.bufferedReader()?.use { it.readText() }
        } catch (e: Exception) {
            null
        }
    }
}
