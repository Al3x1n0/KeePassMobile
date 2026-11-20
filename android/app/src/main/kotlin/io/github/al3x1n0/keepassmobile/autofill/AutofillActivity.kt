package io.github.al3x1n0.keepassmobile.autofill

import android.content.Context
import android.content.BroadcastReceiver
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.service.autofill.Dataset
import android.view.autofill.AutofillId
import android.view.autofill.AutofillManager
import android.view.autofill.AutofillValue
import android.widget.RemoteViews
import androidx.annotation.RequiresApi
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.github.al3x1n0.keepassmobile.R

/**
 * Schermata della compilazione automatica (`ChooseForAutofillActivity` di
 * Keepass2Android): motore Flutter proprio con il punto di ingresso
 * `autofillMain`, che sblocca un database dei recenti e sceglie la voce.
 *
 * Canale `autofill`: `request` (app, dominio dichiarato, campi presenti),
 * `fill` (valori della voce, una volta sola: costruisce la risposta e chiude),
 * `cancel`. Alla chiusura il motore e il database in memoria si liberano.
 */
@RequiresApi(Build.VERSION_CODES.O)
class AutofillActivity : FlutterActivity() {
  private val screenOffReceiver = object : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
      if (intent.action == Intent.ACTION_SCREEN_OFF) {
        this@AutofillActivity.intent.getStringExtra(EXTRA_SAVE_TOKEN)?.let {
          PendingSave.remove(it)
          this@AutofillActivity.intent.removeExtra(EXTRA_SAVE_TOKEN)
          finish()
        }
      }
    }
  }

  override fun onCreate(savedInstanceState: android.os.Bundle?) {
    super.onCreate(savedInstanceState)
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
      registerReceiver(screenOffReceiver, IntentFilter(Intent.ACTION_SCREEN_OFF), Context.RECEIVER_NOT_EXPORTED)
    } else {
      @Suppress("DEPRECATION")
      registerReceiver(screenOffReceiver, IntentFilter(Intent.ACTION_SCREEN_OFF))
    }
  }

  override fun getDartEntrypointFunctionName(): String = "autofillMain"

  override fun onDestroy() {
    unregisterReceiver(screenOffReceiver)
    if (!isChangingConfigurations) {
      intent.getStringExtra(EXTRA_SAVE_TOKEN)?.let { PendingSave.remove(it) }
    }
    super.onDestroy()
  }

  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
      .setMethodCallHandler(::onMethodCall)
  }

  private fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    when (call.method) {
      "request" -> result.success(request())
      "takeSavePassword" -> {
        val token = intent.getStringExtra(EXTRA_SAVE_TOKEN)
        intent.removeExtra(EXTRA_SAVE_TOKEN)
        result.success(token?.let { PendingSave.remove(it)?.password })
      }
      "fill" -> {
        fill(call.argument<String>("userName"), call.argument<String>("password"))
        result.success(null)
      }
      "cancel" -> {
        intent.getStringExtra(EXTRA_SAVE_TOKEN)?.let { PendingSave.remove(it) }
        intent.removeExtra(EXTRA_SAVE_TOKEN)
        setResult(RESULT_CANCELED)
        finish()
        result.success(null)
      }
      else -> result.notImplemented()
    }
  }

  private fun request(): Map<String, Any?>? {
    val token = intent.getStringExtra(EXTRA_SAVE_TOKEN)
    if (token != null) {
      val save = PendingSave.peek(token) ?: return null
      return mapOf("packageName" to save.app, "webDomain" to save.domain,
        "isBrowser" to (save.app in KpmAutofillService.TRUSTED_BROWSERS),
        "save" to true, "userName" to save.user)
    }
    val app = intent.getStringExtra(EXTRA_PACKAGE) ?: return null
    return mapOf(
      "packageName" to app,
      "webDomain" to intent.getStringExtra(EXTRA_DOMAIN),
      "isBrowser" to (app in KpmAutofillService.TRUSTED_BROWSERS),
      "hasUserName" to ids(EXTRA_USER_NAME_IDS).isNotEmpty(),
      "hasPassword" to ids(EXTRA_SECRET_IDS).isNotEmpty(),
    )
  }

  @Suppress("DEPRECATION")
  private fun ids(key: String): List<AutofillId> =
    intent.getParcelableArrayListExtra<AutofillId>(key).orEmpty()

  /** Risposta all'autenticazione: i campi si compilano subito. */
  private fun fill(userName: String?, secret: String?) {
    val presentation = RemoteViews(packageName, R.layout.autofill_item).apply {
      setTextViewText(R.id.autofill_text, getString(R.string.autofill_unlock))
    }
    @Suppress("DEPRECATION")
    val builder = Dataset.Builder(presentation)
    var values = 0
    if (!userName.isNullOrEmpty()) {
      for (id in ids(EXTRA_USER_NAME_IDS)) {
        builder.setValue(id, AutofillValue.forText(userName))
        values++
      }
    }
    if (!secret.isNullOrEmpty()) {
      for (id in ids(EXTRA_SECRET_IDS)) {
        builder.setValue(id, AutofillValue.forText(secret))
        values++
      }
    }
    if (values == 0) {
      setResult(RESULT_CANCELED)
    } else {
      val response = Intent().putExtra(AutofillManager.EXTRA_AUTHENTICATION_RESULT, builder.build())
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        response.putExtra(AutofillManager.EXTRA_AUTHENTICATION_RESULT_EPHEMERAL_DATASET, true)
      }
      setResult(RESULT_OK, response)
    }
    finish()
  }

  companion object {
    private const val CHANNEL = "io.github.al3x1n0.keepassmobile/autofill"
    private const val EXTRA_SAVE_TOKEN = "io.github.al3x1n0.keepassmobile.autofill.SAVE_TOKEN"
    private const val EXTRA_PACKAGE = "io.github.al3x1n0.keepassmobile.autofill.PACKAGE"
    private const val EXTRA_DOMAIN = "io.github.al3x1n0.keepassmobile.autofill.DOMAIN"
    private const val EXTRA_USER_NAME_IDS = "io.github.al3x1n0.keepassmobile.autofill.USER_NAME_IDS"
    private const val EXTRA_SECRET_IDS = "io.github.al3x1n0.keepassmobile.autofill.SECRET_IDS"

    fun saveIntent(context: Context, token: String): Intent =
      Intent(context, AutofillActivity::class.java).putExtra(EXTRA_SAVE_TOKEN, token)

    fun intent(
      context: Context,
      app: String,
      webDomain: String?,
      userNameIds: ArrayList<AutofillId>,
      secretIds: ArrayList<AutofillId>,
    ): Intent = Intent(context, AutofillActivity::class.java)
      .putExtra(EXTRA_PACKAGE, app)
      .putExtra(EXTRA_DOMAIN, webDomain)
      .putParcelableArrayListExtra(EXTRA_USER_NAME_IDS, userNameIds)
      .putParcelableArrayListExtra(EXTRA_SECRET_IDS, secretIds)
  }
}
