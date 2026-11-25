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

  @Test
  fun `widget moderni riconoscono accesso ed escludono ricerca`() {
    for (className in listOf(
      "androidx.appcompat.widget.AppCompatEditText",
      "com.google.android.material.textfield.TextInputEditText",
      "example.CustomEditText",
      "androidx.compose.ui.platform.AndroidComposeView",
    )) {
      val user = InputField(className = className, inputType = 1)
      val password = InputField(className = className, inputType = 0x81)
      val search = InputField(className = className, idEntry = "search", inputType = 0x81)
      val result = AutofillStructureParser.parse(AutofillView("app", null, listOf(search, user, password)))
      assertEquals(listOf("username"), result[user])
      assertEquals(listOf("password"), result[password])
      assertFalse(search in result)
    }
  }

  @Test
  fun `campo custom con tipo autofill testo riconosciuto`() {
    val user = InputField(className = "example.CustomInput", isTextAutofill = true)
    val password = InputField(className = "example.CustomInput", isTextAutofill = true, hint = "password")
    val result = AutofillStructureParser.parse(AutofillView("app", null, listOf(user, password)))
    assertEquals(listOf("username"), result[user])
    assertEquals(listOf("password"), result[password])
  }

  @Test
  fun `richiesta manuale su campo senza hint propone solo nome utente`() {
    val field = InputField(isFocused = true)
    val view = AutofillView("app", null, listOf(field))
    assertTrue(AutofillStructureParser.selectForFill(view, false, setOf(field)).isEmpty())
    assertEquals(mapOf(field to listOf("username")),
      AutofillStructureParser.selectForFill(view, true, setOf(field)))
    assertTrue(AutofillStructureParser.selectForFill(view, true, emptySet()).isEmpty())
  }

  @Test
  fun `fallback manuale password e campi non utilizzabili`() {
    val password = InputField(isFocused = true, inputType = 0x81)
    val view = AutofillView("app", null, listOf(password))
    assertEquals(listOf("password"), AutofillStructureParser.selectForFill(view, true, setOf(password))[password])
    val hidden = InputField(isFocused = true, isVisible = false)
    val unfocused = InputField()
    for (field in listOf(hidden, unfocused)) {
      assertTrue(AutofillStructureParser.selectForFill(
        AutofillView("app", null, listOf(field)), true, setOf(field)).isEmpty())
    }
    val other = InputField(isFocused = true)
    assertTrue(AutofillStructureParser.selectForFill(
      AutofillView("app", null, listOf(other, password)), true, setOf(other, password)).isNotEmpty())
  }

  @Test
  fun `richiesta manuale conserva parsing standard e rifiuta focus ambiguo`() {
    val user = InputField(autofillHints = listOf("username"))
    val other = InputField(isFocused = true)
    val view = AutofillView("app", null, listOf(user, other))
    assertEquals(mapOf(user to listOf("username")),
      AutofillStructureParser.selectForFill(view, true, setOf(user, other)))
    val second = InputField(isFocused = true)
    assertTrue(AutofillStructureParser.selectForFill(
      AutofillView("app", null, listOf(other, second)), true, setOf(other, second)).isEmpty())
  }

  @Test
  fun `domini iframe conflittuali conservano campi senza attribuire il sito`() {
    for (domains in listOf(listOf("login.example", "captcha.example"),
      listOf("captcha.example", "login.example"), listOf("example", "login.example"))) {
      val collected = AutofillDomains()
      domains.forEach(collected::add)
      assertEquals(null, collected.unambiguousDomain)
      val password = InputField(autofillHints = listOf("password"))
      val view = AutofillView("app", collected.unambiguousDomain, listOf(password))
      assertEquals(listOf("password"), AutofillStructureParser.parse(view)[password])
    }
    val single = AutofillDomains()
    listOf(null, "", " login.example ", "login.example").forEach(single::add)
    assertEquals("login.example", single.unambiguousDomain)
    single.add("other.example")
    single.add("login.example")
    assertEquals(null, single.unambiguousDomain)
  }

  @Test
  fun `iframe differenti non ricevono valori del contesto focalizzato`() {
    val domains = AutofillDomains().apply { add("login.example"); add("captcha.example") }
    val user = InputField(autofillHints = listOf("username"))
    val password = InputField(autofillHints = listOf("password"), isFocused = true)
    val iframe = InputField(autofillHints = listOf("password"))
    val contexts = linkedMapOf(user to "login.example", password to "login.example", iframe to "captcha.example")
    assertEquals(setOf(user, password), domains.fillableFields(contexts))
    val view = AutofillView("app", domains.unambiguousDomain, contexts.keys.toList())
    assertEquals(setOf(user, password), AutofillStructureParser.selectForFill(
      view, false, domains.fillableFields(contexts)).keys)
    assertTrue(domains.fillableFields(mapOf(user to "login.example", iframe to "captcha.example")).isEmpty())
    assertEquals(setOf(password), domains.fillableFields(mapOf(password to null, iframe to "captcha.example")))
  }

  @Test
  fun `ricerca HTML e ricerca con hint esplicito escluse`() {
    val html = InputField(htmlTag = "input", htmlType = "search", inputType = 1)
    val hinted = InputField(idEntry = "search", autofillHints = listOf("password"))
    val password = InputField(className = "example.CustomEditText", inputType = 0x81)
    val result = AutofillStructureParser.parse(AutofillView("app", null, listOf(html, hinted, password)))
    assertEquals(mapOf(password to listOf("password")), result)
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
