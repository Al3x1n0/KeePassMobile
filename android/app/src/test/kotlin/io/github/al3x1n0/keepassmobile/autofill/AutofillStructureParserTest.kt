package io.github.al3x1n0.keepassmobile.autofill

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Stessi casi di `AutofillTest` di Keepass2Android, con le sue strutture di
 * esempio (`src/test/resources/autofill`): per ogni campo i suggerimenti
 * assegnati devono essere quelli attesi.
 */
class AutofillStructureParserTest {
  @Test
  fun `passwordAuto senza fuoco con nome utente`() =
    check("com-servicenet-mobile-no-focus.json", "com.servicenet.mobile")

  @Test
  fun `passwordAuto con il fuoco`() = check("com-servicenet-mobile-focused.json", "com.servicenet.mobile")

  @Test
  fun `struttura che faceva fallire Keepass2Android`() =
    check("imdb.json", "com.vivaldi.browser", "m.imdb.com")

  @Test
  fun `più accessi senza fuoco in Firefox`() =
    check("firefox-amazon-it.json", "org.mozilla.firefox", "www.amazon.it")

  @Test
  fun `campi senza suggerimenti in Chrome`() =
    check("chrome-android10-amazon-it.json", "com.android.chrome", "www.amazon.it")

  @Test
  fun `nome utente nonostante passwordAuto`() = check("com-ifs-banking-fiid3364-android13.json", "com.ifs.banking.fiid3364")

  @Test
  fun `suggerimento email`() = check("com-expressvpn-vpn-android13.json", "com.expressvpn.vpn")

  @Test
  fun `impostazioni di Android con campi riconosciuti ed esclusi dal servizio`() =
    check("android14-settings.json", "com.android.settings")

  @Test
  fun `campo di ricerca con tipo password non compilato`() {
    val search = InputField(idEntry = "search_box", className = "android.widget.EditText", inputType = 0x81)
    val result = AutofillStructureParser.parse(AutofillView("app", null, listOf(search)))
    assertTrue(result.isEmpty())
  }

  @Test
  fun `suggerimenti W3C nella forma di Android`() {
    assertEquals("password", AutofillStructureParser.canonicalHint("current-password"))
    assertEquals("emailAddress", AutofillStructureParser.canonicalHint("EMAIL"))
    assertTrue(AutofillStructureParser.fillsUserName(listOf("emailAddress")))
    assertTrue(AutofillStructureParser.fillsPassword(listOf("password")))
    assertFalse(AutofillStructureParser.fillsUserName(listOf("password")))
  }

  private fun check(resource: String, packageId: String, webDomain: String? = null) {
    val json = JSONObject(read(resource))
    val fields = ArrayList<InputField>()
    val expected = HashMap<InputField, List<String>>()
    val nodes = json.getJSONArray("InputFields")
    for (i in 0 until nodes.length()) {
      val node = nodes.getJSONObject(i)
      val field = InputField(
        idEntry = node.stringOrNull("IdEntry"),
        hint = node.stringOrNull("Hint"),
        className = node.stringOrNull("ClassName"),
        autofillHints = node.strings("AutofillHints"),
        isFocused = node.optBoolean("IsFocused"),
        inputType = node.optInt("InputType"),
        htmlTag = node.stringOrNull("HtmlInfoTag"),
        htmlType = node.stringOrNull("HtmlInfoTypeAttribute"),
      )
      fields.add(field)
      expected[field] = node.strings("ExpectedAssignedHints").orEmpty()
    }
    val view = AutofillView(json.stringOrNull("PackageId"), json.stringOrNull("WebDomain"), fields)
    assertEquals(packageId, view.packageId)
    if (webDomain != null) assertEquals(webDomain, view.webDomain)

    val actual = AutofillStructureParser.parse(view)
    fields.forEachIndexed { index, field ->
      assertEquals("campo $index", expected.getValue(field).sorted(), actual[field].orEmpty().sorted())
    }
  }

  private fun read(resource: String): String =
    javaClass.classLoader!!.getResourceAsStream("autofill/$resource")!!
      .bufferedReader(Charsets.UTF_8).use { it.readText() }
      .removePrefix("\uFEFF")

  private fun JSONObject.stringOrNull(key: String): String? = if (isNull(key)) null else getString(key)

  private fun JSONObject.strings(key: String): List<String>? {
    if (isNull(key)) return null
    val array = getJSONArray(key)
    return (0 until array.length()).mapNotNull { if (array.isNull(it)) null else array.getString(it) }
  }
}
