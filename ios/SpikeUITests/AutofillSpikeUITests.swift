import XCTest

/// Prova tecnica D21 (build Debug sul simulatore): guida il simulatore per
/// aprire il database dal selettore (G4) e per la compilazione automatica in
/// Safari con l'estensione (G5, G6). Il database è quello demo, con dati finti.
final class AutofillSpikeUITests: XCTestCase {
  override func setUp() {
    continueAfterFailure = false
  }

  /// Apre `KeePassMobile_spike.kdbx` da "Sul mio iPhone" e lo sblocca: il file
  /// entra tra i recenti, che l'app copia nell'App Group.
  func testOpenDatabaseFromFiles() throws {
    let app = XCUIApplication()
    app.launchArguments = ["-kpmSpikeStoreKey"]
    app.launch()
    tap(app.buttons["Apri file"], "Apri file", in: app)
    let browse = app.buttons["Sfoglia"].firstMatch
    if browse.waitForExistence(timeout: 5) { browse.tap() }
    // "Sul mio iPhone" nella lista o "iPhone" tra le posizioni, secondo la vista.
    let local = app.staticTexts.matching(
      NSPredicate(format: "label IN {'Sul mio iPhone', 'iPhone'}")
    ).firstMatch
    if local.waitForExistence(timeout: 5) { local.tap() }
    let file = app.descendants(matching: .any).matching(
      NSPredicate(format: "label BEGINSWITH 'KeePassMobile_spike'")
    ).firstMatch
    tap(file, "file di prova", in: app)
    let field = app.secureTextFields.firstMatch
    tap(field, "campo della chiave", in: app)
    field.typeText(ProcessInfo.processInfo.environment["KPM_SPIKE_KEY"] ?? "")
    tap(app.buttons["Sblocca"], "Sblocca", in: app)
    let never = app.buttons["Non chiedere più"]
    if never.waitForExistence(timeout: 30) { never.tap() }
    XCTAssertTrue(app.buttons["Blocca database"].waitForExistence(timeout: 30), app.debugDescription)
  }

  /// Pagina di accesso in Safari, proposta delle Password, KeePassMobile: con la
  /// configurazione `autoRun` l'estensione sblocca e risponde da sola.
  func testSafariAutofill() throws {
    let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
    safari.launch()
    XCUIDevice.shared.system.open(URL(string: "https://github.com/login")!)
    let user = safari.webViews.textFields.firstMatch
    tap(user, "campo utente", in: safari)
    let bar = safari.otherElements["Scrittura predittiva"].buttons["Password"]
    tap(bar, "Password nella barra della tastiera", in: safari)
    tap(safari.sheets.buttons["KeePassMobile"], "KeePassMobile tra i fornitori", in: safari)
    // L'estensione (configurazione autoRun) sblocca, legge la chiave condivisa
    // con Face ID e risponde: il campo del nome utente si compila.
    let filled = NSPredicate(format: "value != nil AND value != '' AND value != 'Username or email address'")
    let result = XCTWaiter.wait(for: [expectation(for: filled, evaluatedWith: user)], timeout: 90)
    print("SPIKE-RESULT: \(result.rawValue) value=\(String(describing: user.value))")
    if result != .completed { print("SPIKE-SAFARI-AFTER:\n" + safari.debugDescription) }
    XCTAssertEqual(result, .completed)
  }

  private func tap(_ element: XCUIElement, _ name: String, in app: XCUIApplication) {
    XCTAssertTrue(element.waitForExistence(timeout: 20), "non trovato: \(name)\n\(app.debugDescription)")
    element.tap()
  }
}
