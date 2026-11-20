package io.github.al3x1n0.keepassmobile

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.view.autofill.AutofillManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Activity dell'app. Canale `autofill_settings` per l'impostazione
 * "Compilazione automatica": stato del servizio (`status`) e apertura della
 * scelta di sistema del servizio (`openSettings`).
 */
class MainActivity : FlutterActivity() {
  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, AUTOFILL_SETTINGS)
      .setMethodCallHandler { call, result ->
        when (call.method) {
          "status" -> result.success(autofillStatus())
          "openSettings" -> result.success(openAutofillSettings())
          else -> result.notImplemented()
        }
      }
  }

  private fun autofillStatus(): Map<String, Boolean> {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
      return mapOf("supported" to false, "enabled" to false)
    }
    val manager = getSystemService(AutofillManager::class.java)
    return mapOf(
      "supported" to (manager?.isAutofillSupported ?: false),
      "enabled" to (manager?.hasEnabledAutofillServices() ?: false),
    )
  }

  private fun openAutofillSettings(): Boolean {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
    return try {
      startActivity(
        Intent(Settings.ACTION_REQUEST_SET_AUTOFILL_SERVICE, Uri.parse("package:$packageName")),
      )
      true
    } catch (e: ActivityNotFoundException) {
      false
    }
  }

  private companion object {
    const val AUTOFILL_SETTINGS = "io.github.al3x1n0.keepassmobile/autofill_settings"
  }
}
