import Flutter
import LocalAuthentication
import UIKit

/// Eventi di sicurezza per KeePassMobile: blocco del dispositivo.
///
/// iOS non notifica lo spegnimento dello schermo; la notifica più vicina è
/// `protectedDataWillBecomeUnavailableNotification`, inviata quando il
/// dispositivo si blocca e i file protetti diventano illeggibili. Arriva solo
/// se l'utente ha impostato un codice di sblocco.
///
/// `hasStrongBiometrics`: Face ID o Touch ID registrato.
public class AppSecurityPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  private static let channelName = "io.github.al3x1n0.keepassmobile/app_security/screen_off"
  private static let methodsName = "io.github.al3x1n0.keepassmobile/app_security"
  private var observer: NSObjectProtocol?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterEventChannel(name: channelName, binaryMessenger: registrar.messenger())
    let instance = AppSecurityPlugin()
    channel.setStreamHandler(instance)
    let methods = FlutterMethodChannel(name: methodsName, binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(instance, channel: methods)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "hasStrongBiometrics":
      var error: NSError?
      result(
        LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error))
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  public func onListen(
    withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    removeObserver()
    observer = NotificationCenter.default.addObserver(
      forName: UIApplication.protectedDataWillBecomeUnavailableNotification,
      object: nil,
      queue: .main
    ) { _ in
      events("screen_off")
    }
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    removeObserver()
    return nil
  }

  private func removeObserver() {
    if let registered = observer {
      NotificationCenter.default.removeObserver(registered)
    }
    observer = nil
  }
}
