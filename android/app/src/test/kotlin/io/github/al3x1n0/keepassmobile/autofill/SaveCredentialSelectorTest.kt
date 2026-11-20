package io.github.al3x1n0.keepassmobile.autofill

import org.junit.Assert.*
import org.junit.Test

class SaveCredentialSelectorTest {
  private val user = InputField()
  private val otherUser = InputField()
  private val password = InputField()
  private val confirmation = InputField()
  private val fields = mapOf(user to listOf("username"), password to listOf("password"), confirmation to listOf("password"))

  @Test fun acceptsMatchingConfirmation() {
    val result = selectSaveCredentials(fields, mapOf(user to "sample-user", password to "sample-secret", confirmation to "sample-secret"))
    assertEquals("sample-user", result?.user)
    assertEquals("sample-secret", result?.password)
  }

  @Test fun rejectsAmbiguousOrMissingValues() {
    assertNull(selectSaveCredentials(fields, mapOf(password to "one", confirmation to "two")))
    assertNull(selectSaveCredentials(fields, mapOf(user to "sample-user")))
    assertNull(selectSaveCredentials(fields + (otherUser to listOf("username")), mapOf(user to "one", otherUser to "two", password to "secret")))
  }
}
