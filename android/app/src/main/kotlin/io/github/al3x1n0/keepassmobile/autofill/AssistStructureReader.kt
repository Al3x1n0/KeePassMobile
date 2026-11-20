package io.github.al3x1n0.keepassmobile.autofill

import android.app.assist.AssistStructure
import android.os.Build
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
  /** `null` se la schermata dichiara domini diversi (Keepass2Android la rifiuta). */
  fun read(structure: AssistStructure, includeValues: Boolean = false): ReadStructure? {
    val fields = ArrayList<InputField>()
    val ids = HashMap<InputField, AutofillId>()
    val values = HashMap<InputField, String>()
    var packageId: String? = structure.activityComponent?.packageName
    var domain: String? = null
    var conflict = false

    fun visit(node: AssistStructure.ViewNode) {
      val idPackage = node.idPackage
      if (packageId == null && !idPackage.isNullOrBlank() && idPackage != "android") {
        packageId = idPackage
      }
      val nodeDomain = node.webDomain?.trim()
      if (!nodeDomain.isNullOrEmpty()) {
        if (domain == null) domain = nodeDomain else if (domain != nodeDomain) conflict = true
      }
      val field = InputField(
        idEntry = node.idEntry,
        hint = node.hint,
        className = node.className,
        autofillHints = node.autofillHints?.filterNotNull(),
        isFocused = node.isFocused,
        inputType = node.inputType,
        htmlTag = node.htmlInfo?.tag,
        htmlType = node.htmlInfo?.attributes?.firstOrNull { it.first == "type" }?.second,
      )
      fields.add(field)
      node.autofillId?.let { ids[field] = it }
      for (i in 0 until node.childCount) visit(node.getChildAt(i))
    }

    for (i in 0 until structure.windowNodeCount) visit(structure.getWindowNodeAt(i).rootViewNode)
    if (conflict) return null
    val app = packageId ?: structure.activityComponent?.packageName
    val view = AutofillView(app, domain, fields)
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
