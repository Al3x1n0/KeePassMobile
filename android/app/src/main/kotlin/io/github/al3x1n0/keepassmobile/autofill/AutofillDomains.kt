package io.github.al3x1n0.keepassmobile.autofill

/** Un dominio secondario non deve diventare il destinatario della schermata. */
internal class AutofillDomains {
  private val domains = LinkedHashSet<String>()

  fun add(domain: String?) {
    domain?.trim()?.takeIf { it.isNotEmpty() }?.let { domains.add(it) }
  }

  /** In presenza di iframe diversi compila solo il contesto focalizzato. */
  fun fillableFields(contexts: Map<InputField, String?>): Set<InputField> {
    if (domains.size < 2) return contexts.keys
    val focused = contexts.keys.filter { it.isFocused && it.isVisible }.singleOrNull()
      ?: return emptySet()
    val domain = contexts[focused] ?: return setOf(focused)
    return contexts.filterValues { it == domain }.keys
  }

  val unambiguousDomain: String? get() = domains.singleOrNull()
}
