import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Prova tecnica D21: file recenti (solo riferimenti) per l'estensione.
    AutofillSpikeBridge.syncRecentFiles()
    recentsObserver = NotificationCenter.default.addObserver(
      forName: UserDefaults.didChangeNotification, object: nil, queue: .main
    ) { _ in AutofillSpikeBridge.syncRecentFiles() }
    #if DEBUG
      if ProcessInfo.processInfo.arguments.contains("-kpmSpikeStoreKey") {
        AutofillSpikeBridge.storeTestKey()
      }
    #endif
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private var recentsObserver: NSObjectProtocol?

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}

/// Prova tecnica D21: dati per l'estensione di compilazione automatica
/// nell'App Group e nel portachiavi condiviso. La chiave di prova si salva
/// solo nelle build Debug.
enum AutofillSpikeBridge {
  static let appGroup = "group.io.github.al3x1n0.keepassmobile"

  /// Copia `recent_files` di shared_preferences (riferimenti e bookmark, mai
  /// chiavi) nell'App Group.
  static func syncRecentFiles() {
    guard let shared = UserDefaults(suiteName: appGroup) else { return }
    let recents = UserDefaults.standard.stringArray(forKey: "flutter.recent_files") ?? []
    if shared.stringArray(forKey: "recent_files") != recents {
      shared.set(recents, forKey: "recent_files")
    }
  }

  /// Chiave casuale di prova (non è una chiave di un database) nel portachiavi
  /// condiviso, protetta dalla biometria: la legge l'estensione (G5). Stato in
  /// `spike_store_status` dell'App Group.
  static func storeTestKey() {
    guard let group = Bundle.main.object(forInfoDictionaryKey: "KPMSharedKeychainGroup") as? String,
      let shared = UserDefaults(suiteName: appGroup)
    else { return }
    let base: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "io.github.al3x1n0.keepassmobile.spike",
      kSecAttrAccount as String: "test",
      kSecAttrAccessGroup as String: group,
    ]
    SecItemDelete(base as CFDictionary)
    var statuses: [String: Int] = [:]
    for (name, accessibility) in [
      ("passcode", kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly),
      ("unlocked", kSecAttrAccessibleWhenUnlockedThisDeviceOnly),
    ] {
      var error: Unmanaged<CFError>?
      guard
        let access = SecAccessControlCreateWithFlags(
          nil, accessibility, .biometryCurrentSet, &error)
      else { continue }
      var add = base
      add[kSecValueData as String] = Data((0..<32).map { _ in UInt8.random(in: 0...255) })
      add[kSecAttrAccessControl as String] = access
      let status = SecItemAdd(add as CFDictionary, nil)
      statuses[name] = Int(status)
      if status == errSecSuccess { break }
    }
    shared.set(statuses, forKey: "spike_store_status")
  }
}
