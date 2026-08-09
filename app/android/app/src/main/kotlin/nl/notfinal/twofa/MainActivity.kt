package nl.notfinal.twofa

import android.content.ClipData
import android.content.ClipDescription
import android.content.ClipboardManager
import android.content.Context
import android.os.Build
import android.os.Bundle
import android.os.PersistableBundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// Must be a FlutterFragmentActivity, not FlutterActivity: the local_auth
// plugin shows the biometric/device-credential prompt via a Fragment, and on a
// plain FlutterActivity every authenticate() call throws PlatformException
// ("no_fragment_activity") — which silently breaks every biometric gate
// (approval, export, unlock).
class MainActivity : FlutterFragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Codes and recovery words must never appear in screenshots, screen
        // recordings, or the recents thumbnail. Debug builds stay capturable
        // so development and UI review remain possible.
        val debuggable =
            (applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE) != 0
        if (!debuggable) {
            window.setFlags(
                WindowManager.LayoutParams.FLAG_SECURE,
                WindowManager.LayoutParams.FLAG_SECURE
            )
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "twokeys/platform"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                // Clipboard write with the sensitive-content flag so the code
                // is hidden from clipboard previews and keyboard suggestions.
                "copySensitive" -> {
                    val text = call.argument<String>("text") ?: ""
                    val clipboard =
                        getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                    val clip = ClipData.newPlainText("code", text)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                        val extras = PersistableBundle()
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                            extras.putBoolean(ClipDescription.EXTRA_IS_SENSITIVE, true)
                        } else {
                            extras.putBoolean("android.content.extra.IS_SENSITIVE", true)
                        }
                        clip.description.extras = extras
                    }
                    clipboard.setPrimaryClip(clip)
                    result.success(true)
                }
                // Best-effort self-clear ~45s after a copy (Android 13's own
                // auto-clear waits an hour — far too long for an OTP).
                "clearClipboardIfCode" -> {
                    val expected = call.argument<String>("text") ?: ""
                    val clipboard =
                        getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                    val current =
                        clipboard.primaryClip?.getItemAt(0)?.text?.toString()
                    if (current == expected) {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                            clipboard.clearPrimaryClip()
                        } else {
                            clipboard.setPrimaryClip(ClipData.newPlainText("", ""))
                        }
                    }
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }
}
