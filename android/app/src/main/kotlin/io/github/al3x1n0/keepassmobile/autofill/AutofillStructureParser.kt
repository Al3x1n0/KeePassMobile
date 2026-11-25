package io.github.al3x1n0.keepassmobile.autofill

// Riferimento: Keepass2Android, src/Kp2aAutofillParser/AutofillParser.cs,
// revisione 8b60a72fc8eb23e8580df053a49ca813a686c838.
// File originale Copyright 2025 Philipp Crocoll, GPL versione 3 o successiva,
// senza garanzia. Implementazione adattata in Kotlin nel 2026; vedi LICENSE.

import java.util.Locale

/**
 * Campo della schermata da compilare, indipendente dalle classi di Android
 * (`InputField` di `Kp2aAutofillParser` di Keepass2Android). Uguaglianza per
 * identità: due campi con gli stessi attributi restano campi diversi.
 */
class InputField(
  val idEntry: String? = null,
  val hint: String? = null,
  val className: String? = null,
  val autofillHints: List<String>? = null,
  val isFocused: Boolean = false,
  val inputType: Int = 0,
  val htmlTag: String? = null,
  val htmlType: String? = null,
  val isVisible: Boolean = true,
  val isTextAutofill: Boolean = false,
)

/** Schermata da compilare: campi in ordine di visita, app e dominio dichiarato. */
class AutofillView(
  val packageId: String?,
  val webDomain: String?,
  val fields: List<InputField>,
)

/**
 * Riconoscimento dei campi nome utente e password con le regole di
 * `StructureParserBase.Parse` di Keepass2Android (GPLv3):
 * - se almeno un campo ha un suggerimento di accesso (`password`, `username`,
 *   `emailAddress`, anche nella forma W3C) valgono solo i suggerimenti;
 * - altrimenti i campi password si riconoscono dal tipo di input (poi da id e
 *   hint), il nome utente da id e hint o, se manca, è l'ultimo campo di testo
 *   prima del password; serve un campo password o un nome utente con il fuoco.
 */
object AutofillStructureParser {
  const val HINT_PASSWORD = "password"
  const val HINT_USERNAME = "username"
  const val HINT_EMAIL = "emailAddress"

  private val loginHints = setOf(HINT_PASSWORD, HINT_USERNAME, HINT_EMAIL)

  /** Suggerimenti W3C con il nome di Android (`hintToCanonicalReplacement`). */
  private val canonical = mapOf(
    "email" to HINT_EMAIL,
    "username" to HINT_USERNAME,
    "current-password" to HINT_PASSWORD,
    "new-password" to HINT_PASSWORD,
    "cc-exp-month" to "creditCardExpirationMonth",
    "cc-exp-year" to "creditCardExpirationYear",
    "cc-exp" to "creditCardExpirationDate",
    "cc-number" to "creditCardNumber",
    "cc-csc" to "creditCardSecurityCode",
    "postal-code" to "postalCode",
  )

  private val passwordHints = setOf("password", "passwort", "passwordAuto", "pswd")
  private val userNameHints = setOf("email", "e-mail", "username", "user id")

  // Valori di android.text.InputType, duplicati per i test senza Android.
  private const val MASK_CLASS = 0x0000000f
  private const val MASK_VARIATION = 0x00000ff0
  private const val CLASS_TEXT = 0x00000001
  private const val VARIATION_PASSWORD = 0x00000080
  private const val VARIATION_VISIBLE_PASSWORD = 0x00000090
  private const val VARIATION_WEB_PASSWORD = 0x000000e0

  fun canonicalHint(hint: String): String = canonical[hint.lowercase(Locale.ROOT)] ?: hint

  /** `true` se un campo con [hints] riceve il nome utente. */
  fun fillsUserName(hints: List<String>): Boolean = HINT_USERNAME in hints || HINT_EMAIL in hints

  /** `true` se un campo con [hints] riceve la password. */
  fun fillsPassword(hints: List<String>): Boolean = HINT_PASSWORD in hints

  /** Campi da compilare con i suggerimenti assegnati, nell'ordine della schermata. */
  fun parse(view: AutofillView): Map<InputField, List<String>> {
    val result = LinkedHashMap<InputField, List<String>>()
    fun add(field: InputField, hints: List<String>) {
      result[field] = result[field].orEmpty() + hints
    }

    val candidates = view.fields.filterNot(::isSearch)
    val allHints = candidates.flatMap { it.autofillHints.orEmpty() }.map(::canonicalHint).toSet()
    if (allHints.any { it in loginHints }) {
      for (field in candidates) {
        val hints = field.autofillHints?.map(::canonicalHint)?.distinct() ?: continue
        if (hints.any { it in loginHints }) add(field, hints)
      }
      return result
    }

    val editTexts = candidates.filter(::isEditText)
    var passwordFields = editTexts.filter(::isPassword)
    if (passwordFields.isEmpty()) passwordFields = editTexts.filter(::hasPasswordHint)

    val userNameFields = editTexts.filter(::hasUserNameHint).toMutableList()
    if (userNameFields.isEmpty()) {
      for (passwordField in passwordFields) {
        val before = editTexts.takeWhile { it !== passwordField && it !in passwordFields }.lastOrNull()
        if (before != null) userNameFields.add(before)
      }
    }

    // Senza suggerimenti serve un campo password o un nome utente con il fuoco.
    if (passwordFields.isNotEmpty() || userNameFields.any { it.isFocused }) {
      for (field in userNameFields) add(field, listOf(HINT_USERNAME))
      for (field in passwordFields) if (field !in userNameFields) add(field, listOf(HINT_PASSWORD))
    }
    return result
  }

  /** La richiesta esplicita usa un solo campo focalizzato, mai un campo arbitrario. */
  fun selectForFill(
    view: AutofillView,
    manualRequest: Boolean,
    addressableFields: Set<InputField>,
  ): Map<InputField, List<String>> {
    val parsed = parse(AutofillView(view.packageId, view.webDomain,
      view.fields.filter { it in addressableFields }))
    if (parsed.isNotEmpty() || !manualRequest) return parsed
    val focused = view.fields.filter { it.isFocused && it.isVisible && it in addressableFields }
      .singleOrNull() ?: return emptyMap()
    // Senza semantica password non inviare mai una password a un campo sconosciuto.
    val hint = if (isPassword(focused) || hasPasswordHint(focused)) HINT_PASSWORD else HINT_USERNAME
    return mapOf(focused to listOf(hint))
  }

  private fun isEditText(field: InputField): Boolean =
    field.className?.substringAfterLast('.')?.let {
      it.endsWith("EditText") || it.endsWith("AutoCompleteTextView")
    } == true || field.isTextAutofill ||
      (field.inputType and MASK_CLASS) == CLASS_TEXT || field.htmlTag == "input"

  private fun isSearch(field: InputField): Boolean =
    field.idEntry?.lowercase(Locale.ROOT)?.contains("search") == true ||
      field.hint?.lowercase(Locale.ROOT)?.contains("search") == true ||
      field.htmlType?.lowercase(Locale.ROOT) == "search"

  private fun isPassword(field: InputField): Boolean {
    if (field.idEntry?.lowercase(Locale.ROOT)?.contains("search") == true) return false
    if (field.hint?.lowercase(Locale.ROOT)?.contains("search") == true) return false
    val variation = field.inputType and MASK_VARIATION
    val textVariation = (field.inputType and MASK_CLASS) == CLASS_TEXT &&
      (variation == VARIATION_PASSWORD || variation == VARIATION_VISIBLE_PASSWORD || variation == VARIATION_WEB_PASSWORD)
    return textVariation ||
      field.autofillHints?.firstOrNull() == "passwordAuto" ||
      field.htmlType == "password"
  }

  private fun hasPasswordHint(field: InputField): Boolean =
    isAny(field.idEntry, passwordHints) || isAny(field.hint, passwordHints)

  private fun hasUserNameHint(field: InputField): Boolean =
    isAny(field.idEntry, userNameHints) || isAny(field.hint, userNameHints)

  /** Valore uguale a uno dei termini, senza distinzione di maiuscole (`IsAny`). */
  private fun isAny(value: String?, terms: Set<String>): Boolean {
    if (value.isNullOrBlank()) return false
    val lower = value.lowercase(Locale.ROOT)
    return terms.any { it == lower }
  }
}
