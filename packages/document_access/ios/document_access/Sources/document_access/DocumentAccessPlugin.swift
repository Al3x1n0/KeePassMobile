import Flutter
import UIKit
import UniformTypeIdentifiers

/// Accesso ai documenti scelti dall'utente senza copia, tramite
/// security-scoped bookmark e NSFileCoordinator (file in iCloud Drive e nei
/// File Provider di terze parti).
///
/// Gli errori inviati a Dart hanno solo un codice: mai URL o nomi di file.
public class DocumentAccessPlugin: NSObject, FlutterPlugin, UIDocumentPickerDelegate,
  UIAdaptivePresentationControllerDelegate
{
  private static let channelName = "io.github.al3x1n0.keepassmobile/document_access"
  private static let bookmarkPrefix = "bookmark:"
  private static let maxDocumentBytes = 128 * 1024 * 1024
  private static let cacheLock = NSLock()
  // Inizializzata una volta per processo, anche con più motori Flutter.
  private static let exportStaging = Result<URL, Error> {
    let manager = FileManager.default
    let folder = manager.temporaryDirectory.appendingPathComponent(
      "keepassmobile-document-exports", isDirectory: true)
    if manager.fileExists(atPath: folder.path) {
      try manager.removeItem(at: folder)
    }
    try manager.createDirectory(at: folder, withIntermediateDirectories: false)
    return folder
  }

  private weak var registrar: FlutterPluginRegistrar?
  private var pendingPick: FlutterResult?
  /// Creazione in corso: risultato e cartella temporanea del file da esportare.
  private var pendingCreate: (result: FlutterResult, folder: URL)?
  // Coda seriale: letture e scritture sullo stesso documento restano in ordine.
  private let io = DispatchQueue(label: "io.github.al3x1n0.keepassmobile.document_access.io")

  public static func register(with registrar: FlutterPluginRegistrar) {
    _ = exportStaging
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: registrar.messenger())
    let instance = DocumentAccessPlugin()
    instance.registrar = registrar
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any]
    switch call.method {
    case "pick":
      pick(result)
    case "create":
      guard let name = args?["name"] as? String,
        let bytes = args?["bytes"] as? FlutterStandardTypedData
      else { return result(Self.error("io")) }
      create(name, bytes.data, result)
    case "read":
      guard let uri = args?["uri"] as? String else { return result(Self.error("unavailable")) }
      runIo(result) {
        let (data, refreshed) = try self.read(uri)
        var map: [String: Any] = ["bytes": FlutterStandardTypedData(bytes: data)]
        if let refreshed = refreshed { map["refreshedUri"] = refreshed }
        return map
      }
    case "write":
      guard let uri = args?["uri"] as? String else { return result(Self.error("unavailable")) }
      guard let bytes = args?["bytes"] as? FlutterStandardTypedData else {
        return result(Self.error("io"))
      }
      runIo(result) {
        try self.write(uri, bytes.data)
        return nil
      }
    case "readRemoteCache", "writeRemoteCache", "listRemoteCacheIds", "deleteRemoteCache":
      runIo(result) {
        Self.cacheLock.lock()
        defer { Self.cacheLock.unlock() }
        let manager = FileManager.default
        var folder = try manager.url(for: .applicationSupportDirectory,
          in: .userDomainMask, appropriateFor: nil, create: true)
          .appendingPathComponent("remote_database_cache", isDirectory: true)
        try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try folder.setResourceValues(values)
        if call.method == "listRemoteCacheIds" {
          return try manager.contentsOfDirectory(atPath: folder.path).filter(Self.isCacheId)
        }
        guard let id = args?["id"] as? String, Self.isCacheId(id) else {
          throw Self.cacheError()
        }
        let file = folder.appendingPathComponent(id)
        if call.method == "deleteRemoteCache" {
          guard let expected = (args?["expected"] as? FlutterStandardTypedData)?.data,
            expected.count == 32 else { throw Self.cacheError() }
          guard manager.fileExists(atPath: file.path) else { return false }
          let handle = try FileHandle(forReadingFrom: file)
          defer { try? handle.close() }
          guard try handle.read(upToCount: 32) == expected else { return false }
          try manager.removeItem(at: file)
          return true
        }
        let current = manager.fileExists(atPath: file.path) ? try Data(contentsOf: file) : nil
        if call.method == "readRemoteCache" {
          return current.map { FlutterStandardTypedData(bytes: $0) }
        }
        guard let bytes = args?["bytes"] as? FlutterStandardTypedData,
          bytes.data.count >= 32 else { throw Self.cacheError() }
        let expected = (args?["expected"] as? FlutterStandardTypedData)?.data
        let matches = expected == nil ? current == nil :
          expected?.count == 32 && current?.prefix(32) == expected
        if !matches { return false }
        try bytes.data.write(to: file, options: .atomic)
        return true
      }
    case "release":
      // Su iOS basta dimenticare il bookmark.
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private static func isCacheId(_ value: String) -> Bool {
    value.utf8.count == 64 &&
      value.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil
  }

  private static func cacheError() -> NSError {
    NSError(domain: "document_access", code: 1)
  }

  // MARK: - Scelta del documento

  private func pick(_ result: @escaping FlutterResult) {
    guard pendingPick == nil, pendingCreate == nil else { return result(Self.error("busy")) }
    guard let presenter = topViewController() else { return result(Self.error("no_activity")) }
    let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: false)
    picker.delegate = self
    picker.allowsMultipleSelection = false
    picker.presentationController?.delegate = self
    pendingPick = result
    presenter.present(picker, animated: true)
  }

  // MARK: - Creazione di un documento

  /// Prepara l'esportazione finché il selettore consegna il file alla destinazione.
  private func create(_ name: String, _ data: Data, _ result: @escaping FlutterResult) {
    guard pendingPick == nil, pendingCreate == nil else { return result(Self.error("busy")) }
    guard let presenter = topViewController() else { return result(Self.error("no_activity")) }
    guard let staging = try? Self.exportStaging.get() else { return result(Self.error("io")) }
    let fileManager = FileManager.default
    let folder = staging.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let fileName = (name as NSString).lastPathComponent
    let temp = folder.appendingPathComponent(fileName.isEmpty ? "database.kdbx" : fileName)
    do {
      try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
      try data.write(to: temp, options: [.atomic, .completeFileProtection])
    } catch {
      try? fileManager.removeItem(at: folder)
      return result(Self.error("io"))
    }
    let picker = UIDocumentPickerViewController(forExporting: [temp], asCopy: false)
    picker.delegate = self
    picker.presentationController?.delegate = self
    pendingCreate = (result, folder)
    presenter.present(picker, animated: true)
  }

  private func finishCreate(_ result: @escaping FlutterResult, folder: URL, url: URL?) {
    guard let url = url else {
      try? FileManager.default.removeItem(at: folder)
      return result(nil)
    }
    runIo(result) {
      defer { try? FileManager.default.removeItem(at: folder) }
      let accessing = url.startAccessingSecurityScopedResource()
      defer { if accessing { url.stopAccessingSecurityScopedResource() } }
      let bookmark = try url.bookmarkData(
        options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
      let created: [String: Any] = [
        "uri": Self.bookmarkPrefix + bookmark.base64EncodedString(),
        "name": url.lastPathComponent,
        "persistent": true,
      ]
      return created
    }
  }

  public func documentPicker(
    _ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]
  ) {
    if let create = pendingCreate {
      pendingCreate = nil
      return finishCreate(create.result, folder: create.folder, url: urls.first)
    }
    guard let result = takePendingPick() else { return }
    guard let url = urls.first else { return result(nil) }
    runIo(result) {
      let accessing = url.startAccessingSecurityScopedResource()
      defer { if accessing { url.stopAccessingSecurityScopedResource() } }
      let data = try self.coordinatedRead(url)
      // Il bookmark va creato mentre l'accesso è attivo.
      let bookmark = try url.bookmarkData(
        options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
      let picked: [String: Any] = [
        "uri": Self.bookmarkPrefix + bookmark.base64EncodedString(),
        "name": url.lastPathComponent,
        "bytes": FlutterStandardTypedData(bytes: data),
        // Il bookmark creato sopra resta valido dopo il riavvio dell'app.
        "persistent": true,
      ]
      return picked
    }
  }

  public func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    cancelPending()
  }

  /// Chiusura del selettore con un gesto, senza scelta.
  public func presentationControllerDidDismiss(_ presentationController: UIPresentationController)
  {
    cancelPending()
  }

  private func cancelPending() {
    if let create = pendingCreate {
      pendingCreate = nil
      return finishCreate(create.result, folder: create.folder, url: nil)
    }
    takePendingPick()?(nil)
  }

  private func takePendingPick() -> FlutterResult? {
    let result = pendingPick
    pendingPick = nil
    return result
  }

  private func topViewController() -> UIViewController? {
    var top = registrar?.viewController?.view.window?.windowScene?.keyWindow?.rootViewController
    while let presented = top?.presentedViewController { top = presented }
    return top
  }

  // MARK: - Lettura e scrittura

  private struct Unavailable: Error {}
  private struct DocumentTooLarge: Error {}

  /// URL del documento; `stale` se il bookmark va rigenerato.
  private func resolve(_ uri: String) throws -> (url: URL, stale: Bool) {
    if uri.hasPrefix(Self.bookmarkPrefix) {
      guard let data = Data(base64Encoded: String(uri.dropFirst(Self.bookmarkPrefix.count))) else {
        throw Unavailable()
      }
      var stale = false
      let url = try URL(
        resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
      return (url, stale)
    }
    guard let url = URL(string: uri), url.isFileURL else { throw Unavailable() }
    return (url, false)
  }

  private func read(_ uri: String) throws -> (Data, String?) {
    let (url, stale) = try resolve(uri)
    let accessing = url.startAccessingSecurityScopedResource()
    defer { if accessing { url.stopAccessingSecurityScopedResource() } }
    let data = try coordinatedRead(url)
    var refreshed: String?
    if stale,
      let bookmark = try? url.bookmarkData(
        options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
    {
      refreshed = Self.bookmarkPrefix + bookmark.base64EncodedString()
    }
    return (data, refreshed)
  }

  private func write(_ uri: String, _ data: Data) throws {
    let (url, _) = try resolve(uri)
    let accessing = url.startAccessingSecurityScopedResource()
    defer { if accessing { url.stopAccessingSecurityScopedResource() } }
    var coordinationError: NSError?
    var writeError: Error?
    NSFileCoordinator().coordinate(
      writingItemAt: url, options: .forReplacing, error: &coordinationError
    ) { target in
      do {
        // Niente `.atomic`: per un documento scelto singolarmente non c'è accesso
        // alla cartella, dove andrebbe creato il file temporaneo.
        try data.write(to: target)
      } catch {
        writeError = error
      }
    }
    if let error = coordinationError ?? writeError { throw error }
  }

  private func coordinatedRead(_ url: URL) throws -> Data {
    var coordinationError: NSError?
    var result: Result<Data, Error> = .failure(Unavailable())
    NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) {
      target in
      result = Result {
        let file = try FileHandle(forReadingFrom: target)
        defer { try? file.close() }
        var data = Data()
        while let chunk = try file.read(upToCount: min(64 * 1024, Self.maxDocumentBytes - data.count + 1)),
          !chunk.isEmpty
        {
          if chunk.count > Self.maxDocumentBytes - data.count { throw DocumentTooLarge() }
          data.append(chunk)
        }
        return data
      }
    }
    if let error = coordinationError { throw error }
    return try result.get()
  }

  private func runIo(_ result: @escaping FlutterResult, _ block: @escaping () throws -> Any?) {
    io.async {
      let outcome: Any?
      do {
        outcome = try block()
      } catch {
        outcome = Self.error(Self.code(for: error))
      }
      DispatchQueue.main.async { result(outcome) }
    }
  }

  private static func code(for error: Error) -> String {
    if error is Unavailable { return "unavailable" }
    if error is DocumentTooLarge { return "too_large" }
    let nsError = error as NSError
    guard nsError.domain == NSCocoaErrorDomain else { return "io" }
    switch nsError.code {
    case NSFileNoSuchFileError, NSFileReadNoSuchFileError, NSFileReadNoPermissionError,
      NSFileWriteNoPermissionError, NSFileReadCorruptFileError:
      return "unavailable"
    default:
      return "io"
    }
  }

  private static func error(_ code: String) -> FlutterError {
    FlutterError(code: code, message: nil, details: nil)
  }
}
