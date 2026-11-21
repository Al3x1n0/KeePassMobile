package io.github.al3x1n0.keepassmobile.autofill

import android.content.pm.PackageManager
import android.content.pm.Signature
import android.os.Build
import java.security.MessageDigest

internal data class AutofillRecipient(
  val packageName: String,
  val signingIds: List<String>,
) {
  val currentSigningId get() = signingIds.last()

  companion object {
    @Suppress("DEPRECATION")
    fun resolve(manager: PackageManager, packageName: String): AutofillRecipient? {
      val signingIds = try {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
          val info = manager.getPackageInfo(packageName, PackageManager.GET_SIGNING_CERTIFICATES)
            .signingInfo ?: return null
          if (info.hasMultipleSigners()) {
            signerSet(info.apkContentsSigners)
          } else {
            info.signingCertificateHistory.orEmpty().map(::fingerprint)
          }
        } else {
          signerSet(manager.getPackageInfo(packageName, PackageManager.GET_SIGNATURES).signatures)
        }
      } catch (_: PackageManager.NameNotFoundException) {
        return null
      } catch (_: SecurityException) {
        return null
      }
      return if (signingIds.isEmpty()) null else AutofillRecipient(packageName, signingIds)
    }

    private fun signerSet(signatures: Array<Signature>?): List<String> {
      val fingerprints = signatures.orEmpty().map(::fingerprint).sorted()
      return if (fingerprints.isEmpty()) emptyList() else listOf(fingerprints.joinToString("."))
    }

    private fun fingerprint(signature: Signature): String =
      MessageDigest.getInstance("SHA-256").digest(signature.toByteArray())
        .joinToString("") { "%02x".format(it) }
  }
}
