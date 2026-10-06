import Flutter
import LocalAuthentication
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "RukkaKeystore") {
      RukkaKeystoreChannel.register(messenger: registrar.messenger())
    }
  }
}

/// The app's own keystore helper (ADR 2026-10-05b, ADR 2026-10-06; Dart side:
/// app/lib/features/devices/keystore_platform.dart). Kept in this file so the
/// Xcode project needs no new file reference. Nothing here logs.
///
/// - `qualifyingBiometricEnrolled` (ADR 2026-10-05b §1): Face ID or Touch ID,
///   whichever the phone has, enrolled now. A lockout (too many tries) still
///   means "enrolled". Never the passcode (`.deviceOwnerAuthentication` is not
///   asked — 07 §5.6).
/// - The device-key class (ADR 2026-10-06 §1) is NOT here on iOS: the Dart side
///   keeps it in the Keychain through flutter_secure_storage — service
///   `rukka_folio_device_keys`, `first_unlock_this_device`, not synchronizable,
///   **no access control** — so the `deviceItem*` methods are Android's alone.
/// - The gate (ADR 2026-10-06 §2 🔒) — `armBiometricGate` / `authenticate` /
///   `resetGate`: a Keychain generic-password item (service
///   `rukka_folio_gate`) holding 32 random bytes from `SecRandomCopyBytes`,
///   with access control `biometryCurrentSet` and accessibility
///   `WhenPasscodeSetThisDeviceOnly`, never synchronizable. Reading it needs
///   Face ID / Touch ID of the set enrolled when it was minted — that read is
///   the unlock, and it opens no data. The `LAContext` hides the fallback
///   button, so the passcode is never offered (07 §5.6). Any enrolment change
///   makes the item unreadable; iOS is expected to answer that as
///   `errSecItemNotFound` → "unarmed", which the Dart side reads against its
///   own "armed" record as *re-enrolled* (MPIN, then a new gate). `resetGate`
///   deletes the gate item and nothing else. ⚠️ Not run on an iOS device
///   (ADR 2026-10-06 *Open*): the invalidated-item answer is reasoned from the
///   platform documentation, not observed.
/// - `excludeFromBackup` (03 §6 🔒, ADR 2026-09-05c §8, desk 150): sets
///   `NSURLIsExcludedFromBackupKey` on each path given that exists (the ledger
///   database and its SQLite side files).
enum RukkaKeystoreChannel {
  static let name = "rukka_folio/keystore"
  static let gateService = "rukka_folio_gate"
  static let gateAccount = "rukka.gate"
  /// KEY145B's LAContext-domain-state relock gate, replaced by the item.
  static let legacyGateStateKey = "rukka_folio.relock_gate.domain_state"

  static func gateQuery() -> [String: Any] {
    return [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: gateService,
      kSecAttrAccount as String: gateAccount,
      kSecAttrSynchronizable as String: false,
    ]
  }

  static func deleteGate() {
    SecItemDelete(gateQuery() as CFDictionary)
  }

  static func armGate() -> Bool {
    let context = LAContext()
    var laError: NSError?
    guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &laError)
    else { return false }
    var cfError: Unmanaged<CFError>?
    guard
      let access = SecAccessControlCreateWithFlags(
        nil, kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly, .biometryCurrentSet, &cfError)
    else { return false }
    var secret = Data(count: 32)
    let made = secret.withUnsafeMutableBytes { buffer -> OSStatus in
      guard let base = buffer.baseAddress else { return errSecParam }
      return SecRandomCopyBytes(kSecRandomDefault, 32, base)
    }
    guard made == errSecSuccess else { return false }
    deleteGate()
    var add = gateQuery()
    add[kSecAttrAccessControl as String] = access
    add[kSecValueData as String] = secret
    let status = SecItemAdd(add as CFDictionary, nil)
    secret.resetBytes(in: 0..<secret.count)
    UserDefaults.standard.removeObject(forKey: legacyGateStateKey)
    return status == errSecSuccess
  }

  static func readGate(reason: String, cancel: String, done: @escaping (String) -> Void) {
    let context = LAContext()
    // No "Enter Password": the device passcode is never offered (07 §5.6).
    context.localizedFallbackTitle = ""
    if !cancel.isEmpty { context.localizedCancelTitle = cancel }
    context.localizedReason = reason
    var query = gateQuery()
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    query[kSecUseAuthenticationContext as String] = context
    // SecItemCopyMatching blocks while the sheet is up: off the main thread.
    DispatchQueue.global(qos: .userInitiated).async {
      var out: CFTypeRef?
      let status = SecItemCopyMatching(query as CFDictionary, &out)
      let answer: String
      switch status {
      case errSecSuccess:
        if var data = out as? Data {
          answer = data.count == 32 ? "success" : "failed"
          data.resetBytes(in: 0..<data.count)
        } else {
          answer = "failed"
        }
      case errSecItemNotFound:
        answer = "unarmed"
      case errSecUserCanceled:
        answer = "cancelled"
      case errSecAuthFailed:
        answer = "failed"
      default:
        answer = "unavailable"
      }
      DispatchQueue.main.async { done(answer) }
    }
  }

  static func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: name, binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "qualifyingBiometricEnrolled":
        let context = LAContext()
        var error: NSError?
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
          result(true)
        } else if let code = error?.code, code == LAError.biometryLockout.rawValue {
          result(true)
        } else {
          result(false)
        }
      case "armBiometricGate":
        result(armGate())
      case "resetGate":
        deleteGate()
        result(true)
      case "deviceKeyStorage":
        result("unknown")
      case "authenticate":
        let args = call.arguments as? [String: Any] ?? [:]
        let subtitle = args["subtitle"] as? String ?? ""
        let cancel = args["cancel"] as? String ?? ""
        let title = args["title"] as? String ?? ""
        readGate(reason: subtitle.isEmpty ? title : subtitle, cancel: cancel) { answer in
          result(answer)
        }
      case "excludeFromBackup":
        guard let args = call.arguments as? [String: Any],
          let paths = args["paths"] as? [String]
        else {
          result(FlutterError(code: "bad_args", message: "paths", details: nil))
          return
        }
        var done: [String] = []
        for path in paths where FileManager.default.fileExists(atPath: path) {
          var url = URL(fileURLWithPath: path)
          var values = URLResourceValues()
          values.isExcludedFromBackup = true
          do {
            try url.setResourceValues(values)
            done.append(path)
          } catch {
            result(FlutterError(code: "exclude_failed", message: nil, details: nil))
            return
          }
        }
        result(done)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
