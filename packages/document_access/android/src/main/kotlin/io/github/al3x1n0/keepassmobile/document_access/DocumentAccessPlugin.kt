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

    private class DocumentTooLarge : Exception()

    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    private var activityBinding: ActivityPluginBinding? = null
    private var pendingPick: Result? = null
    private var pendingCreate: Pair<Result, ByteArray>? = null
    private var heldDemoLeases = 0

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
        io.execute {
            synchronized(demoLock) {
                try {
                    releaseDemoLeases(all = true)
                } catch (_: Exception) {
                    // Il tombstone conserva la pulizia da completare al prossimo avvio.
                }
            }
        }
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
            "ensureDemoDatabase" -> {
                val bytes = call.argument<ByteArray>("bytes") ?: return result.error(IO, null, null)
                runIo(result) {
                    synchronized(demoLock) {
                        val folder = demoFolder()
                        if (atomicExists(AtomicFile(File(folder, "removed")))) {
                            false
                        } else {
                            val file = AtomicFile(File(folder, DEMO_NAME))
                            if (!atomicExists(file)) writeAtomic(file, bytes)
                            true
                        }
                    }
                }
            }
            "deleteDemoDatabase" -> runIo(result) {
                synchronized(demoLock) {
                    val folder = demoFolder()
                    writeAtomic(AtomicFile(File(folder, "removed")), byteArrayOf(1))
                    if (call.argument<Boolean>("keepFile") != true && demoLeaseCount == 0) {
                        deleteDemoFile(folder)
                    }
                    null
                }
            }
            "isDemoDatabaseRemoved" -> runIo(result) {
                synchronized(demoLock) {
                    atomicExists(AtomicFile(File(demoFolder(), "removed")))
                }
            }
            "retainDemoDatabase" -> runIo(result) {
                synchronized(demoLock) {
                    val folder = demoFolder()
                    if (atomicExists(AtomicFile(File(folder, "removed"))) ||
                        !atomicExists(AtomicFile(File(folder, DEMO_NAME)))) {
                        false
                    } else {
                        heldDemoLeases++
                        demoLeaseCount++
                        true
                    }
                }
            }
            "releaseDemoDatabase" -> runIo(result) {
                synchronized(demoLock) {
                    releaseDemoLeases()
                    null
                }
            }
            "readRemoteCache", "writeRemoteCache", "listRemoteCacheIds", "deleteRemoteCache" -> {
                val id = call.argument<String>("id")
                if (call.method != "listRemoteCacheIds" && (id == null || !cacheId.matches(id))) {
                    return result.error(IO, null, null)
                }
                runIo(result) {
                    synchronized(cacheLock) {
                        val folder = File(context.noBackupFilesDir, "remote_database_cache")
                        if (!folder.exists() && !folder.mkdirs()) throw java.io.IOException()
                        if (call.method == "listRemoteCacheIds") {
                            val names = folder.list() ?: throw java.io.IOException()
                            return@synchronized names.map { it.removeSuffix(".bak") }
                                .filter(cacheId::matches).distinct()
                        }
                        requireNotNull(id)
                        val file = AtomicFile(File(folder, id))
                        if (call.method == "deleteRemoteCache") {
                            val expected = call.argument<ByteArray>("expected")
                                ?: throw java.io.IOException()
                            return@synchronized deleteRemoteCache(file, expected)
                        }
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

    private fun demoFolder(): File {
        val folder = File(context.noBackupFilesDir, "demo_database")
        if (!folder.exists() && !folder.mkdirs()) throw java.io.IOException()
        return folder
    }

    private fun writeAtomic(file: AtomicFile, bytes: ByteArray) {
        val stream = file.startWrite()
        try {
            stream.write(bytes)
            file.finishWrite(stream)
        } catch (error: Exception) {
            file.failWrite(stream)
            throw error
        }
    }

    private fun atomicExists(file: AtomicFile): Boolean =
        file.baseFile.exists() || File(file.baseFile.path + ".bak").exists()

    private fun deleteDemoFile(folder: File) {
        val file = AtomicFile(File(folder, DEMO_NAME))
        file.delete()
        if (atomicExists(file) || File(folder, "$DEMO_NAME.new").exists()) {
            throw java.io.IOException()
        }
    }

    // Tutti gli accessi ai contatori avvengono sotto demoLock, condiviso fra engine.
    private fun releaseDemoLeases(all: Boolean = false) {
        val count = if (all) heldDemoLeases else minOf(heldDemoLeases, 1)
        if (count == 0) return
        heldDemoLeases -= count
        demoLeaseCount -= count
        val folder = demoFolder()
        if (demoLeaseCount == 0 && atomicExists(AtomicFile(File(folder, "removed")))) {
            deleteDemoFile(folder)
        }
    }

    private fun deleteRemoteCache(file: AtomicFile, expected: ByteArray): Boolean {
        require(expected.size == 32)
        val token = ByteArray(32)
        try {
            java.io.DataInputStream(file.openRead()).use { it.readFully(token) }
        } catch (_: FileNotFoundException) {
            return false
        } catch (_: java.io.EOFException) {
            return false
        }
        if (!token.contentEquals(expected)) return false
        val base = file.baseFile
        file.delete()
        if (base.exists() || File(base.path + ".bak").exists() || File(base.path + ".new").exists()) {
            throw java.io.IOException()
        }
        return true
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
            val name = displayName(uri)
            val bytes = readBytes(uri)
            val persistent = persist(uri)
            mapOf(
                "uri" to uri.toString(),
                "name" to name,
                "bytes" to bytes,
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
        if (uri.toString() == DEMO_URI) return
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

    private fun readBytes(uri: Uri): ByteArray {
        if (uri.toString() == DEMO_URI) return synchronized(demoLock) {
            val file = AtomicFile(File(demoFolder(), DEMO_NAME))
            file.openRead().use { readDocumentBytes(it) }
        }
        return context.contentResolver.openInputStream(uri)?.use { readDocumentBytes(it) }
            ?: throw FileNotFoundException()
    }

    private fun readDocumentBytes(stream: java.io.InputStream): ByteArray {
        val chunks = ArrayList<ByteArray>()
        var buffer = ByteArray(DOCUMENT_CHUNK_BYTES)
        var buffered = 0
        var size = 0
        while (true) {
            val count = stream.read(
                buffer,
                buffered,
                minOf(buffer.size - buffered, MAX_DOCUMENT_BYTES - size + 1),
            )
            if (count < 0) break
            if (count > MAX_DOCUMENT_BYTES - size) throw DocumentTooLarge()
            buffered += count
            size += count
            if (buffered == buffer.size) {
                chunks.add(buffer)
                buffer = ByteArray(DOCUMENT_CHUNK_BYTES)
                buffered = 0
            }
        }
        val bytes = ByteArray(size)
        var offset = 0
        for (chunk in chunks) {
            chunk.copyInto(bytes, offset)
            offset += chunk.size
        }
        buffer.copyInto(bytes, offset, endIndex = buffered)
        return bytes
    }

    /** "wt" tronca il file: senza, un contenuto più corto lascerebbe byte residui. */
    private fun writeBytes(uri: Uri, bytes: ByteArray) {
        if (uri.toString() == DEMO_URI) return synchronized(demoLock) {
            val file = AtomicFile(File(demoFolder(), DEMO_NAME))
            if (!atomicExists(file)) throw FileNotFoundException()
            writeAtomic(file, bytes)
        }
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
            } catch (e: DocumentTooLarge) {
                TOO_LARGE to null
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
        val demoLock = Any()
        var demoLeaseCount = 0
        const val DEMO_URI = "app-private:demo"
        const val DEMO_NAME = "Rifugio-Aurora.kdbx"
        val cacheLock = Any()
        val cacheId = Regex("[a-f0-9]{64}")
        const val CHANNEL = "io.github.al3x1n0.keepassmobile/document_access"
        const val REQUEST_PICK = 0x4B50 // "KP"
        const val REQUEST_CREATE = 0x4B43 // "KC"
        const val DEFAULT_MIME_TYPE = "application/octet-stream"
        const val READ = Intent.FLAG_GRANT_READ_URI_PERMISSION
        const val WRITE = Intent.FLAG_GRANT_WRITE_URI_PERMISSION
        const val UNAVAILABLE = "unavailable"
        const val TOO_LARGE = "too_large"
        const val MAX_DOCUMENT_BYTES = 128 * 1024 * 1024
        const val DOCUMENT_CHUNK_BYTES = 64 * 1024
        const val IO = "io"
        const val BUSY = "busy"
        const val NO_ACTIVITY = "no_activity"
    }
}
