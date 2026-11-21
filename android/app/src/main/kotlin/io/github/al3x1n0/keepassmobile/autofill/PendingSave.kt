package io.github.al3x1n0.keepassmobile.autofill

import android.os.Handler
import android.os.Looper
import java.util.UUID

/** Credenziali transitorie, mai inserite nell'Intent o persistite su disco. */
internal object PendingSave {
  class Request(val recipient: AutofillRecipient, val domain: String?, val user: String?, val password: String)
  private val requests = mutableMapOf<String, Request>()
  private val handler = Handler(Looper.getMainLooper())

  @Synchronized fun put(recipient: AutofillRecipient, domain: String?, user: String?, password: String): String {
    val token = UUID.randomUUID().toString()
    requests[token] = Request(recipient, domain, user, password)
    handler.postDelayed({ remove(token) }, 120_000)
    return token
  }

  @Synchronized fun remove(token: String): Request? = requests.remove(token)
  @Synchronized fun peek(token: String): Request? = requests[token]
}
