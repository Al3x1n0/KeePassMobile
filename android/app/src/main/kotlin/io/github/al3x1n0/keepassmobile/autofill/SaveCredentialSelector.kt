package io.github.al3x1n0.keepassmobile.autofill

internal class SaveCredentials(val user: String?, val password: String)

internal fun selectSaveCredentials(
  parsed: Map<InputField, List<String>>,
  values: Map<InputField, String>,
): SaveCredentials? {
  val passwords = parsed.filter { AutofillStructureParser.fillsPassword(it.value) }
    .keys.mapNotNull { values[it] }.filter { it.isNotEmpty() }
  val users = parsed.filter { AutofillStructureParser.fillsUserName(it.value) }
    .keys.mapNotNull { values[it] }.filter { it.isNotEmpty() }
  if (passwords.isEmpty() || passwords.distinct().size != 1 || users.size > 1) return null
  return SaveCredentials(users.firstOrNull(), passwords.first())
}
