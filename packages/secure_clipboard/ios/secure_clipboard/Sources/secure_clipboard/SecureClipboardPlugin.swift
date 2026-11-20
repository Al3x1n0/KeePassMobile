import Flutter
import UIKit
import UniformTypeIdentifiers

/// Copia negli appunti per un password manager: scadenza gestita da iOS
/// (`expirationDate`, vale anche con l'app sospesa o chiusa) e solo locale
/// (`localOnly`, niente Appunti universali verso gli altri dispositivi).
///
/// Il testo copiato non viene mai conservato: per riconoscere la propria copia
/// si usa `changeCount`, che cambia a ogni modifica degli appunti.
public class SecureClipboardPlugin: NSObject, FlutterPlugin {
  private static let channelName = "io.github.al3x1n0.keepassmobile/secure_clipboard"
  private var ownChangeCount: Int?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(SecureClipboardPlugin(), channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "copy":
      guard let args = call.arguments as? [String: Any],
        let text = args["text"] as? String,
        let clearAfterMs = (args["clearAfterMs"] as? NSNumber)?.doubleValue
      else {
        return result(FlutterError(code: "invalid", message: nil, details: nil))
      }
      let pasteboard = UIPasteboard.general
      pasteboard.setItems(
        [[UTType.utf8PlainText.identifier: text]],
        options: [
          .localOnly: true,
          .expirationDate: Date().addingTimeInterval(clearAfterMs / 1000),
        ])
      ownChangeCount = pasteboard.changeCount
      result(nil)
    case "clearOwnCopy":
      let pasteboard = UIPasteboard.general
      guard let own = ownChangeCount, pasteboard.changeCount == own else {
        return result(false)
      }
      pasteboard.items = []
      ownChangeCount = nil
      result(true)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
