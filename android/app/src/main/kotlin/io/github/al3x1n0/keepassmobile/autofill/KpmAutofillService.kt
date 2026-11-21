package io.github.al3x1n0.keepassmobile.autofill

import android.app.PendingIntent
import android.os.Build
import android.os.CancellationSignal
import android.service.autofill.AutofillService
import android.service.autofill.Dataset
import android.service.autofill.FillCallback
import android.service.autofill.FillRequest
import android.service.autofill.FillResponse
import android.service.autofill.InlinePresentation
import android.service.autofill.SaveCallback
import android.service.autofill.SaveRequest
import android.service.autofill.SaveInfo
import android.view.autofill.AutofillId
import android.widget.RemoteViews
import androidx.annotation.RequiresApi
import androidx.autofill.inline.UiVersions
import androidx.autofill.inline.v1.InlineSuggestionUi
import io.github.al3x1n0.keepassmobile.R
import java.util.concurrent.atomic.AtomicInteger

/**
 * Servizio di compilazione automatica (`Kp2aAutofillService` di
 * Keepass2Android, decisione D26, ADR-013).
 *
 * Il servizio non vede il database: risponde con una sola proposta
 * "Sblocca KeePassMobile" che apre [AutofillActivity]; lì si sblocca, si sceglie
 * la voce e i valori tornano al sistema. Nessun nome di voce nella proposta,
 * nessun log. Il salvataggio richiede l'approvazione del sistema e una
 * conferma nella schermata protetta prima della creazione della voce.
 */
@RequiresApi(Build.VERSION_CODES.O)
class KpmAutofillService : AutofillService() {
  override fun onFillRequest(
    request: FillRequest,
    cancellationSignal: CancellationSignal,
    callback: FillCallback,
  ) {
    val structure = request.fillContexts.lastOrNull()?.structure
    val app = structure?.activityComponent?.packageName
    val read = structure?.let { AssistStructureReader.read(it) }
    val recipient = app?.takeUnless { it in excludedPackages() }
      ?.let { AutofillRecipient.resolve(packageManager, it) }
    if (read == null || recipient == null) {
      callback.onSuccess(null)
      return
    }
    val userNameIds = ArrayList<AutofillId>()
    val secretIds = ArrayList<AutofillId>()
    for ((field, hints) in AutofillStructureParser.parse(read.view)) {
      val id = read.ids[field] ?: continue
      when {
        AutofillStructureParser.fillsUserName(hints) -> userNameIds.add(id)
        AutofillStructureParser.fillsPassword(hints) -> secretIds.add(id)
      }
    }
    if (userNameIds.isEmpty() && secretIds.isEmpty()) {
      callback.onSuccess(null)
      return
    }

    val intent = AutofillActivity.intent(this, recipient, read.view.webDomain, userNameIds, secretIds)
    // Il sistema aggiunge la struttura all'intent: serve mutabile (esplicito).
    val flags = PendingIntent.FLAG_CANCEL_CURRENT or
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_MUTABLE else 0
    val sender = PendingIntent.getActivity(this, requestCodes.incrementAndGet(), intent, flags).intentSender
    @Suppress("DEPRECATION")
    val dataset = Dataset.Builder(presentation()).apply {
      // Valori sconosciuti fino allo sblocco: li fornisce AutofillActivity.
      for (id in userNameIds + secretIds) setValue(id, null)
      setAuthentication(sender)
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
        val spec = request.inlineSuggestionsRequest?.inlinePresentationSpecs?.firstOrNull()
        if (spec != null && UiVersions.getVersions(spec.style).contains(UiVersions.INLINE_UI_VERSION_1)) {
          val content = InlineSuggestionUi.newContentBuilder(
            PendingIntent.getActivity(
              this@KpmAutofillService, requestCodes.incrementAndGet(), intent,
              PendingIntent.FLAG_ONE_SHOT or PendingIntent.FLAG_IMMUTABLE,
            ),
          ).setTitle(getString(R.string.autofill_unlock))
            .setContentDescription(getString(R.string.autofill_unlock)).build()
          setInlinePresentation(InlinePresentation(content.slice, spec, true))
        }
      }
    }.build()
    val response = FillResponse.Builder().addDataset(dataset)
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P && secretIds.isNotEmpty()) {
      val save = SaveInfo.Builder(SaveInfo.SAVE_DATA_TYPE_PASSWORD or SaveInfo.SAVE_DATA_TYPE_USERNAME, arrayOf(secretIds.first()))
      val optional = secretIds.drop(1) + if (userNameIds.size == 1) userNameIds else emptyList()
      if (optional.isNotEmpty()) save.setOptionalIds(optional.toTypedArray())
      response.setSaveInfo(save.build())
    }
    callback.onSuccess(response.build())
  }

  override fun onSaveRequest(request: SaveRequest, callback: SaveCallback) {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) { callback.onFailure(null); return }
    val structure = request.fillContexts.lastOrNull()?.structure
    if (structure?.activityComponent == null) { callback.onFailure(null); return }
    val read = AssistStructureReader.read(structure, true)
    val app = structure.activityComponent?.packageName
    val recipient = app?.takeUnless { it in excludedPackages() }
      ?.let { AutofillRecipient.resolve(packageManager, it) }
    if (read == null || recipient == null) { callback.onFailure(null); return }
    val credentials = selectSaveCredentials(AutofillStructureParser.parse(read.view), read.values)
    if (credentials == null) { callback.onFailure(null); return }
    val token = PendingSave.put(recipient, read.view.webDomain, credentials.user, credentials.password)
    val intent = AutofillActivity.saveIntent(this, token)
    val pending = PendingIntent.getActivity(this, requestCodes.incrementAndGet(), intent, PendingIntent.FLAG_ONE_SHOT or PendingIntent.FLAG_IMMUTABLE)
    callback.onSuccess(pending.intentSender)
  }

  private fun presentation() = RemoteViews(packageName, R.layout.autofill_item).apply {
    setTextViewText(R.id.autofill_text, getString(R.string.autofill_unlock))
  }

  /** Sistema, Impostazioni e l'app stessa, come Keepass2Android. */
  private fun excludedPackages() = setOf("android", "com.android.settings", packageName)

  companion object {
    private val requestCodes = AtomicInteger()
  }
}
