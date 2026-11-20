package io.github.al3x1n0.keepassmobile.document_access

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import android.webkit.MimeTypeMap
import android.util.AtomicFile
import java.io.File
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.PluginRegistry
import java.io.FileNotFoundException
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * Accesso ai documenti tramite Storage Access Framework, con permesso
 * persistente (come AndroidContentStorage di Keepass2Android).
 *
 * Gli errori inviati a Dart hanno solo un codice: mai URI o nomi di file.
 */
class DocumentAccessPlugin :
    FlutterPlugin,
    MethodCallHandler,
    ActivityAware,
    PluginRegistry.ActivityResultListener {

    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    private var activityBinding: ActivityPluginBinding? = null
    private var pendingPick: Result? = null
    private var pendingCreate: Pair<Result, ByteArray>? = null

    // Un solo thread: letture e scritture sullo stesso documento restano in ordine.
    private val io: ExecutorService = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        io.shutdown()
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
        binding.addActivityResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() = onDetachedFromActivity()

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) =
        onAttachedToActivity(binding)

    override fun onDetachedFromActivity() {
        activityBinding?.removeActivityResultListener(this)
        activityBinding = null
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "pick" -> pick(result)
            "create" -> {
                val name = call.argument<String>("name") ?: return result.error(IO, null, null)
                val bytes = call.argument<ByteArray>("bytes") ?: return result.error(IO, null, null)
                create(name, bytes, result)
            }
            "read" -> {
                val uri = call.argument<String>("uri") ?: return result.error(UNAVAILABLE, null, null)
                runIo(result) { mapOf("bytes" to readBytes(Uri.parse(uri))) }
            }
            "write" -> {
                val uri = call.argument<String>("uri") ?: return result.error(UNAVAILABLE, null, null)
                val bytes = call.argument<ByteArray>("bytes") ?: return result.error(IO, null, null)
                runIo(result) {
                    writeBytes(Uri.parse(uri), bytes)
                    null
                }
            }
            "readRemoteCache", "writeRemoteCache" -> {
                val id = call.argument<String>("id") ?: return result.error(IO, null, null)
                if (!id.matches(Regex("[a-f0-9]{64}"))) return result.error(IO, null, null)
                runIo(result) {
                    synchronized(cacheLock) {
                        val folder = File(context.noBackupFilesDir, "remote_database_cache")
                        if (!folder.exists() && !folder.mkdirs()) throw java.io.IOException()
                        val file = AtomicFile(File(folder, id))
                        val current = try { file.readFully() } catch (_: FileNotFoundException) { null }
                        if (call.method == "readRemoteCache") {
                            current
                        } else {
                            val bytes = call.argument<ByteArray>("bytes") ?: throw java.io.IOException()
                            val expected = call.argument<ByteArray>("expected")
                            require(bytes.size >= 32)
                            val matches = if (expected == null) current == null else
                                current != null && expected.size == 32 &&
                                    current.take(32).toByteArray().contentEquals(expected)
                            if (!matches) {
                                false
                            } else {
                                val stream = file.startWrite()
                                try {
                                    stream.write(bytes)
                                    file.finishWrite(stream)
                                } catch (error: Exception) {
                                    file.failWrite(stream)
                                    throw error
                                }
                                true
                            }
                        }
                    }
                }
            }
            "release" -> {
                val uri = call.argument<String>("uri") ?: return result.success(null)
                runIo(result) {
                    release(Uri.parse(uri))
                    null
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun pick(result: Result) {
        if (pendingPick != null || pendingCreate != null) return result.error(BUSY, null, null)
        val activity = activityBinding?.activity ?: return result.error(NO_ACTIVITY, null, null)
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
            addFlags(
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                    Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION,
            )
        }
        pendingPick = result
        try {
            activity.startActivityForResult(intent, REQUEST_PICK)
        } catch (e: ActivityNotFoundException) {
            pendingPick = null
            result.error(UNAVAILABLE, null, null)
        }
    }

    /** Documento nuovo nella posizione scelta dall'utente (CreateDatabaseActivity). */
    private fun create(name: String, bytes: ByteArray, result: Result) {
        if (pendingPick != null || pendingCreate != null) return result.error(BUSY, null, null)
        val activity = activityBinding?.activity ?: return result.error(NO_ACTIVITY, null, null)
        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = mimeTypeFor(name)
            putExtra(Intent.EXTRA_TITLE, name)
            addFlags(READ or WRITE or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
        }
        pendingCreate = result to bytes
        try {
            activity.startActivityForResult(intent, REQUEST_CREATE)
        } catch (e: ActivityNotFoundException) {
            pendingCreate = null
            result.error(UNAVAILABLE, null, null)
        }
    }

    /**
     * Tipo del documento dall'estensione del nome. Con un nome già presente il
     * provider aggiunge il numero prima dell'estensione solo se il tipo
     * corrisponde all'estensione: con un tipo generico `nota.txt` diventava
     * `nota.txt (1)`. Le estensioni sconosciute (`.kdbx`) restano
     * `application/octet-stream`, che dà già `keepass (1).kdbx`.
     */
    private fun mimeTypeFor(name: String): String {
        val extension = name.substringAfterLast('.', "").lowercase()
        if (extension.isEmpty()) return DEFAULT_MIME_TYPE
        return MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension)
            ?: DEFAULT_MIME_TYPE
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode == REQUEST_CREATE) {
            onCreated(resultCode, data)
            return true
        }
        if (requestCode != REQUEST_PICK) return false
        val result = pendingPick ?: return true
        pendingPick = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(null)
            return true
        }
        runIo(result) {
            val persistent = persist(uri)
            mapOf(
                "uri" to uri.toString(),
                "name" to displayName(uri),
                "bytes" to readBytes(uri),
                "persistent" to persistent,
            )
        }
        return true
    }

    private fun onCreated(resultCode: Int, data: Intent?) {
        val (result, bytes) = pendingCreate ?: return
        pendingCreate = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(null)
            return
        }
        runIo(result) {
            val persistent = persist(uri)
            try {
                writeBytes(uri, bytes)
            } catch (e: Exception) {
                // Niente file vuoti lasciati dalla creazione non riuscita.
                try {
                    DocumentsContract.deleteDocument(context.contentResolver, uri)
                } catch (ignored: Exception) {
                    // Il provider non permette di eliminarlo: resta vuoto.
                }
                throw e
            }
            mapOf(
                "uri" to uri.toString(),
                "name" to displayName(uri),
                "persistent" to persistent,
            )
        }
    }

    /**
     * Permesso persistente in lettura e scrittura, o solo lettura se il provider
     * non scrive. `false` se il provider non concede permessi persistenti: il
     * documento resta accessibile solo finché l'app è aperta.
     */
    private fun persist(uri: Uri): Boolean {
        val resolver = context.contentResolver
        for (flags in intArrayOf(READ or WRITE, READ)) {
            try {
                resolver.takePersistableUriPermission(uri, flags)
                return true
            } catch (e: SecurityException) {
                // Si prova con meno permessi.
            }
        }
        return false
    }

    private fun release(uri: Uri) {
        val resolver = context.contentResolver
        for (permission in resolver.persistedUriPermissions) {
            if (permission.uri != uri) continue
            val flags = (if (permission.isReadPermission) READ else 0) or
                (if (permission.isWritePermission) WRITE else 0)
            if (flags != 0) resolver.releasePersistableUriPermission(uri, flags)
        }
    }

    private fun displayName(uri: Uri): String {
        val name = context.contentResolver
            .query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
            ?.use { cursor ->
                val column = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (column >= 0 && cursor.moveToFirst()) cursor.getString(column) else null
            }
        return name ?: uri.lastPathSegment ?: "database.kdbx"
    }

    private fun readBytes(uri: Uri): ByteArray =
        context.contentResolver.openInputStream(uri)?.use { it.readBytes() }
            ?: throw FileNotFoundException()

    /** "wt" tronca il file: senza, un contenuto più corto lascerebbe byte residui. */
    private fun writeBytes(uri: Uri, bytes: ByteArray) {
        val stream = context.contentResolver.openOutputStream(uri, "wt")
            ?: throw FileNotFoundException()
        stream.use {
            it.write(bytes)
            it.flush()
        }
    }

    private fun runIo(result: Result, block: () -> Any?) {
        io.execute {
            val outcome: Pair<String?, Any?> = try {
                null to block()
            } catch (e: FileNotFoundException) {
                UNAVAILABLE to null
            } catch (e: SecurityException) {
                UNAVAILABLE to null
            } catch (e: IllegalArgumentException) {
                UNAVAILABLE to null
            } catch (e: Exception) {
                IO to null
            }
            main.post {
                val code = outcome.first
                if (code == null) result.success(outcome.second) else result.error(code, null, null)
            }
        }
    }

    private companion object {
        val cacheLock = Any()
        const val CHANNEL = "io.github.al3x1n0.keepassmobile/document_access"
        const val REQUEST_PICK = 0x4B50 // "KP"
        const val REQUEST_CREATE = 0x4B43 // "KC"
        const val DEFAULT_MIME_TYPE = "application/octet-stream"
        const val READ = Intent.FLAG_GRANT_READ_URI_PERMISSION
        const val WRITE = Intent.FLAG_GRANT_WRITE_URI_PERMISSION
        const val UNAVAILABLE = "unavailable"
        const val IO = "io"
        const val BUSY = "busy"
        const val NO_ACTIVITY = "no_activity"
    }
}
