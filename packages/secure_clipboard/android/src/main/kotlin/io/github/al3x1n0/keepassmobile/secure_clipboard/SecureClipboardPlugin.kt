package io.github.al3x1n0.keepassmobile.secure_clipboard

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.ClipData
import android.content.ClipDescription
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PersistableBundle
import android.os.SystemClock
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.util.UUID

/**
 * Copia negli appunti per un password manager.
 *
 * - Il contenuto è marcato come sensibile (`EXTRA_IS_SENSITIVE`): tastiere e
 *   anteprima di sistema non lo mostrano.
 * - La pulizia è affidata al sistema con un allarme, così avviene anche se
 *   Android sospende o chiude l'app (il freezer ferma i timer del processo).
 *   Un `Handler` nel processo la anticipa al secondo esatto se l'app è ancora
 *   attiva.
 * - Ogni copia porta un identificativo casuale negli extra della descrizione:
 *   quando gli appunti sono leggibili (app in primo piano) si svuotano solo se
 *   contengono ancora la copia dell'app. In background Android non permette di
 *   leggerli, quindi si svuotano comunque (come KeePassDX).
 *
 * Il testo copiato non viene mai conservato né inviato altrove.
 */
class SecureClipboardPlugin :
    FlutterPlugin,
    MethodCallHandler {

    private lateinit var channel: MethodChannel
    private lateinit var context: Context

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "copy" -> {
                val text = call.argument<String>("text") ?: return result.error(INVALID, null, null)
                val clearAfterMs = call.argument<Number>("clearAfterMs")?.toLong()
                    ?: return result.error(INVALID, null, null)
                copy(context, text, clearAfterMs)
                result.success(null)
            }
            "clearOwnCopy" -> result.success(clearOwnCopy(context, lastToken, cancelSchedule = true))
            else -> result.notImplemented()
        }
    }

    companion object {
        private const val CHANNEL = "io.github.al3x1n0.keepassmobile/secure_clipboard"
        private const val INVALID = "invalid"
        private const val LABEL = "KeePassMobile"
        private const val REQUEST_CLEAR = 0x4B43 // "KC"

        /** Chiave degli extra con l'identificativo della copia. */
        internal const val EXTRA_TOKEN = "io.github.al3x1n0.keepassmobile.CLIP_TOKEN"

        /** Stesso valore di ClipDescription.EXTRA_IS_SENSITIVE (API 33), letto anche da tastiere più vecchie. */
        private const val EXTRA_IS_SENSITIVE = "android.content.extra.IS_SENSITIVE"

        private val main = Handler(Looper.getMainLooper())
        private var pendingClear: Runnable? = null

        /** Identificativo dell'ultima copia di questo processo. */
        @Volatile
        private var lastToken: String? = null

        fun copy(context: Context, text: String, clearAfterMs: Long) {
            val token = UUID.randomUUID().toString()
            val clip = ClipData.newPlainText(LABEL, text)
            clip.description.extras = PersistableBundle().apply {
                putBoolean(EXTRA_IS_SENSITIVE, true)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    putBoolean(ClipDescription.EXTRA_IS_SENSITIVE, true)
                }
                putString(EXTRA_TOKEN, token)
            }
            clipboard(context).setPrimaryClip(clip)
            lastToken = token
            schedule(context, token, clearAfterMs)
        }

        private fun schedule(context: Context, token: String, delayMs: Long) {
            pendingClear?.let(main::removeCallbacks)
            val task = Runnable { clearOwnCopy(context, token, cancelSchedule = true) }
            pendingClear = task
            main.postDelayed(task, delayMs)

            val alarms = context.getSystemService(AlarmManager::class.java) ?: return
            val at = SystemClock.elapsedRealtime() + delayMs
            val intent = clearIntent(context, token)
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S || alarms.canScheduleExactAlarms()) {
                alarms.setExactAndAllowWhileIdle(AlarmManager.ELAPSED_REALTIME_WAKEUP, at, intent)
            } else {
                // Senza permesso per gli allarmi esatti: il sistema può ritardare di qualche secondo.
                alarms.setAndAllowWhileIdle(AlarmManager.ELAPSED_REALTIME_WAKEUP, at, intent)
            }
        }

        private fun clearIntent(context: Context, token: String?): PendingIntent {
            val intent = Intent(context, ClipboardClearReceiver::class.java)
            if (token != null) intent.putExtra(EXTRA_TOKEN, token)
            return PendingIntent.getBroadcast(
                context,
                REQUEST_CLEAR,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }

        private fun cancelSchedule(context: Context) {
            pendingClear?.let(main::removeCallbacks)
            pendingClear = null
            context.getSystemService(AlarmManager::class.java)?.cancel(clearIntent(context, null))
        }

        /**
         * Svuota gli appunti se contengono la copia [token] (o una qualsiasi copia
         * dell'app se [token] è `null`). Se il sistema non permette di leggerli
         * (app in background) li svuota comunque. `true` se li ha svuotati.
         */
        fun clearOwnCopy(context: Context, token: String?, cancelSchedule: Boolean): Boolean {
            if (cancelSchedule) cancelSchedule(context)
            val manager = clipboard(context)
            val description: ClipDescription? = try {
                manager.primaryClipDescription
            } catch (e: SecurityException) {
                null
            }
            if (description != null) {
                val clipToken = description.extras?.getString(EXTRA_TOKEN)
                val ours = clipToken != null && (token == null || clipToken == token)
                if (!ours) return false
            }
            clear(manager)
            if (lastToken == token) lastToken = null
            return true
        }

        private fun clear(manager: ClipboardManager) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                manager.clearPrimaryClip()
            } else {
                manager.setPrimaryClip(ClipData.newPlainText("", ""))
            }
        }

        private fun clipboard(context: Context): ClipboardManager =
            context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
    }
}

/** Riceve l'allarme di pulizia, anche con l'app sospesa o chiusa. */
class ClipboardClearReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        SecureClipboardPlugin.clearOwnCopy(
            context.applicationContext,
            intent.getStringExtra(SecureClipboardPlugin.EXTRA_TOKEN),
            cancelSchedule = false,
        )
    }
}
