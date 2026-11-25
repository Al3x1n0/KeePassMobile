package io.github.al3x1n0.keepassmobile.autofill

import android.app.assist.AssistStructure
import android.os.Build
import android.view.View
import android.view.autofill.AutofillId
import androidx.annotation.RequiresApi

/** Schermata letta dal sistema, con l'identificatore di ogni campo. */
internal class ReadStructure(val view: AutofillView, val ids: Map<InputField, AutofillId>, val values: Map<InputField, String>)

/**
 * Da `AssistStructure` ad [AutofillView], come
 * `AutofillViewFromAssistStructureFinder` di Keepass2Android: tutti i nodi in
 * ordine di visita, app dall'activity oppure dal primo `idPackage` diverso da
 * `android` come ripiego, dominio dichiarato dai nodi web.
 */
@RequiresApi(Build.VERSION_CODES.O)
internal object AssistStructureReader {
  /** Domini conflittuali non invalidano i campi: il contesto web resta non attribuito. */
  fun read(structure: AssistStructure, includeValues: Boolean = false): ReadStructure? {
    val fields = ArrayList<InputField>()
    val ids = HashMap<InputField, AutofillId>()
    val values = HashMap<InputField, String>()
    var packageId: String? = structure.activityComponent?.packageName
    val domains = AutofillDomains()
    val contexts = LinkedHashMap<InputField, String?>()

    fun visit(node: AssistStructure.ViewNode, parentDomain: String? = null) {
      val contextDomain = node.webDomain?.trim()?.takeIf { it.isNotEmpty() } ?: parentDomain
      val idPackage = node.idPackage
      if (packageId == null && !idPackage.isNullOrBlank() && idPackage != "android") {
        packageId = idPackage
      }
      domains.add(node.webDomain)
      val field = InputField(
        idEntry = node.idEntry,
        hint = node.hint,
        className = node.className,
        autofillHints = node.autofillHints?.filterNotNull(),
        isFocused = node.isFocused,
        inputType = node.inputType,
        isVisible = node.visibility == View.VISIBLE,
        isTextAutofill = node.autofillType == View.AUTOFILL_TYPE_TEXT,
        htmlTag = node.htmlInfo?.tag,
        htmlType = node.htmlInfo?.attributes?.firstOrNull { it.first == "type" }?.second,
      )
      fields.add(field)
      contexts[field] = contextDomain
      node.autofillId?.let { ids[field] = it }
      for (i in 0 until node.childCount) visit(node.getChildAt(i), contextDomain)
    }

    for (i in 0 until structure.windowNodeCount) visit(structure.getWindowNodeAt(i).rootViewNode)
    ids.keys.retainAll(domains.fillableFields(contexts))
    val app = packageId ?: structure.activityComponent?.packageName
    val view = AutofillView(app, domains.unambiguousDomain, fields)
    if (includeValues) {
      val selected = AutofillStructureParser.parse(view).keys.mapNotNull { field -> ids[field]?.let { it to field } }.toMap()
      fun readValue(node: AssistStructure.ViewNode) {
        val field = selected[node.autofillId]
        if (field != null) node.autofillValue?.takeIf { it.isText }?.textValue?.toString()?.let { values[field] = it }
        for (i in 0 until node.childCount) readValue(node.getChildAt(i))
      }
      for (i in 0 until structure.windowNodeCount) readValue(structure.getWindowNodeAt(i).rootViewNode)
    }
    return ReadStructure(view, ids, values)
  }
}
