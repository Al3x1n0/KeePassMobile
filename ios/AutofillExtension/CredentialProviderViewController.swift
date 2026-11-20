import AuthenticationServices
import Flutter
import LocalAuthentication
import UIKit
import os

/// Prova tecnica D21: estensione di compilazione automatica di iOS con un
/// motore Flutter (`autofillIosMain`). Attiva solo in debug e profile: nelle
/// build di release il punto di ingresso Dart annulla subito la richiesta,
/// perché qui mancano il controllo di integrità (SEC-07) e lo schermo protetto
/// (SEC-06).
///
/// Canale `autofill_ios`:
/// - `request`: servizi richiesti (dominio o URL) e memoria all'avvio;
/// - `recents`: file recenti copiati dall'app nell'App Group (solo riferimenti);
/// - `readFile`: legge un database dal bookmark creato dall'app (G4);
/// - `readSharedKey`: legge la chiave di prova dal portachiavi condiviso con
///   Face ID (G5) e restituisce solo lo stato e la lunghezza;
/// - `memory`, `startSampling`, `stopSampling`: memoria del processo (G3);
/// - `config` (solo Debug): configurazione dei test automatici nell'App Group;
/// - `report`: risultati della prova nell'App Group, senza dati del database;
/// - `complete`, `cancel`: risposta al sistema (G6).
final class CredentialProviderViewController: ASCredentialProviderViewController {
  static let appGroup = "group.io.github.al3x1n0.keepassmobile"
  private static let bookmarkPrefix = "bookmark:"
  private var engine: FlutterEngine?
  private var identifiers: [ASCredentialServiceIdentifier] = []
  private var monitor: Timer?
  private var sampler: Timer?
  private var windowPeak: Double = 0
  private var overallPeak: Double = 0
  private var startMemory: Double = 0

  override func prepareCredentialList(for serviceIdentifiers: [ASCredentialServiceIdentifier]) {
    identifiers = serviceIdentifiers
    startFlutter()
  }

  override func prepareInterfaceToProvideCredential(for credentialIdentity: ASPasswordCredentialIdentity) {
    identifiers = [credentialIdentity.serviceIdentifier]
    startFlutter()
  }

  override func provideCredentialWithoutUserInteraction(for credentialIdentity: ASPasswordCredentialIdentity) {
    extensionContext.cancelRequest(
      withError: NSError(
        domain: ASExtensionErrorDomain, code: ASExtensionError.userInteractionRequired.rawValue))
  }

  private func startFlutter() {
    guard engine == nil else { return }
    startMemory = Self.footprintMB()
    overallPeak = startMemory
    monitor = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
      guard let self else { return }
      self.overallPeak = max(self.overallPeak, Self.footprintMB())
    }
    let engine = FlutterEngine(name: "autofill_ios", project: nil, allowHeadlessExecution: false)
    engine.run(withEntrypoint: "autofillIosMain")
    let channel = FlutterMethodChannel(
      name: "io.github.al3x1n0.keepassmobile/autofill_ios", binaryMessenger: engine.binaryMessenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(nil)
        return
      }
      self.handle(call, result)
    }
    let controller = FlutterViewController(engine: engine, nibName: nil, bundle: nil)
    addChild(controller)
    controller.view.frame = view.bounds
    controller.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    view.addSubview(controller.view)
    controller.didMove(toParent: self)
    self.engine = engine
  }

  private func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any]
    switch call.method {
    case "request":
      result([
        "services": identifiers.map {
          ["identifier": $0.identifier, "type": $0.type == .domain ? "domain" : "url"]
        },
        "startMemoryMb": startMemory,
        "availableMb": Self.availableMB(),
      ])
    case "recents":
      result(UserDefaults(suiteName: Self.appGroup)?.stringArray(forKey: "recent_files") ?? [])
    case "readFile":
      guard let uri = args?["uri"] as? String else {
        result(FlutterError(code: "bad_args", message: nil, details: nil))
        return
      }
      DispatchQueue.global(qos: .userInitiated).async {
        let outcome: Any
        do {
          outcome = FlutterStandardTypedData(bytes: try Self.read(uri))
        } catch {
          outcome = FlutterError(code: Self.code(for: error), message: nil, details: nil)
        }
        DispatchQueue.main.async { result(outcome) }
      }
    case "readSharedKey":
      DispatchQueue.global(qos: .userInitiated).async {
        let (status, length) = Self.readSharedKey()
        DispatchQueue.main.async { result(["status": Int(status), "length": length]) }
      }
    case "memory":
      result([
        "footprintMb": Self.footprintMB(), "availableMb": Self.availableMB(),
        "overallPeakMb": overallPeak,
      ])
    case "startSampling":
      windowPeak = Self.footprintMB()
      sampler?.invalidate()
      sampler = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { [weak self] _ in
        guard let self else { return }
        self.windowPeak = max(self.windowPeak, Self.footprintMB())
      }
      result(nil)
    case "stopSampling":
      sampler?.invalidate()
      sampler = nil
      windowPeak = max(windowPeak, Self.footprintMB())
      overallPeak = max(overallPeak, windowPeak)
      result(windowPeak)
    case "config":
      #if DEBUG
        result(Self.groupJSON("spike_config.json"))
      #else
        result(nil)
      #endif
    case "report":
      if let data = try? JSONSerialization.data(
        withJSONObject: call.arguments ?? [:], options: [.prettyPrinted, .sortedKeys]),
        let url = Self.groupURL("spike_report.json")
      {
        try? data.write(to: url, options: .atomic)
      }
      result(nil)
    case "complete":
      let user = args?["user"] as? String ?? ""
      let secret = args?["password"] as? String ?? ""
      monitor?.invalidate()
      extensionContext.completeRequest(
        withSelectedCredential: ASPasswordCredential(user: user, password: secret),
        completionHandler: nil)
      result(nil)
    case "cancel":
      monitor?.invalidate()
      extensionContext.cancelRequest(
        withError: NSError(
          domain: ASExtensionErrorDomain, code: ASExtensionError.userCanceled.rawValue))
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - File (G4)

  /// Contenuto del database indicato da un riferimento `bookmark:` creato
  /// dall'app (plugin document_access).
  private static func read(_ uri: String) throws -> Data {
    guard uri.hasPrefix(bookmarkPrefix),
      let data = Data(base64Encoded: String(uri.dropFirst(bookmarkPrefix.count)))
    else {
      throw CocoaError(.fileReadInvalidFileName)
    }
    var stale = false
    let url = try URL(
      resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
    let accessing = url.startAccessingSecurityScopedResource()
    defer { if accessing { url.stopAccessingSecurityScopedResource() } }
    var coordinationError: NSError?
    var readError: Error?
    var content = Data()
    NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) {
      do { content = try Data(contentsOf: $0) } catch { readError = error }
    }
    if let error = coordinationError ?? readError { throw error }
    return content
  }

  private static func code(for error: Error) -> String {
    let ns = error as NSError
    return "\(ns.domain):\(ns.code)"
  }

  // MARK: - Portachiavi condiviso (G5)

  private static func readSharedKey() -> (OSStatus, Int) {
    guard let group = Bundle.main.object(forInfoDictionaryKey: "KPMSharedKeychainGroup") as? String
    else { return (errSecParam, 0) }
    let context = LAContext()
    context.localizedReason = "Prova tecnica della compilazione automatica"
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "io.github.al3x1n0.keepassmobile.spike",
      kSecAttrAccount as String: "test",
      kSecAttrAccessGroup as String: group,
      kSecReturnData as String: true,
      kSecUseAuthenticationContext as String: context,
    ]
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    return (status, (item as? Data)?.count ?? 0)
  }

  // MARK: - Memoria (G3)

  static func footprintMB() -> Double {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(
      MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
    let kr = withUnsafeMutablePointer(to: &info) {
      $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
        task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
      }
    }
    return kr == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : -1
  }

  /// Memoria ancora disponibile prima del limite (0 se il sistema non lo applica,
  /// come nel simulatore).
  static func availableMB() -> Double {
    Double(os_proc_available_memory()) / 1_048_576
  }

  // MARK: - App Group

  private static func groupURL(_ name: String) -> URL? {
    FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
      .appendingPathComponent(name)
  }

  private static func groupJSON(_ name: String) -> Any? {
    guard let url = groupURL(name), let data = try? Data(contentsOf: url) else { return nil }
    return try? JSONSerialization.jsonObject(with: data)
  }
}
