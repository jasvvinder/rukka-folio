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

/// The app's own keystore helper (ADR 2026-10-05b; Dart side:
/// app/lib/features/devices/keystore_platform.dart). Kept in this file so the
/// Xcode project needs no new file reference.
///
/// - `qualifyingBiometricEnrolled` (ruling 1): Face ID or Touch ID, whichever
///   the phone has, enrolled now — the condition under which a
///   `biometryCurrentSet` item guards anything. A lockout (too many tries) still
///   means "enrolled". Never the passcode (`.deviceOwnerAuthentication` is not
///   asked — 07 §5.6).
/// - `resetBiometricDeviceItems` (ruling 3): a no-op on iOS. `SecItemDelete`
///   needs no authentication, so flutter_secure_storage's own `delete` removes an
///   invalidated `biometryCurrentSet` item; the Dart side calls it.
/// - `excludeFromBackup` (03 §6 🔒, ADR 2026-09-05c §8, desk 150): sets
///   `NSURLIsExcludedFromBackupKey` on each path given that exists (the ledger
///   database and its SQLite side files).
/// - `authenticate` / `armBiometricGate` (07 §5.6 🔒 relock auto-prompt; KEY145B
///   review finding 3): the in-app S15's own prompt — `LAContext` with
///   `.deviceOwnerAuthenticationWithBiometrics` (never the passcode; the
///   fallback button is hidden) — bound to the biometric set by the
///   `evaluatedPolicyDomainState` recorded when the gate was armed. Arming is
///   called by Dart only after a proof that the current set is the device keys'
///   own (a correct MPIN, or the cold-start read of the `biometryCurrentSet`
///   device keys). A different state answers "reenrolled" (06 §4.4: a new face
///   needs the PIN once). The recorded state is an opaque enrolment fingerprint,
///   not a secret. ⚠️ Not verified on a device in this lane.
enum RukkaKeystoreChannel {
  static let name = "rukka_folio/keystore"
  static let gateStateKey = "rukka_folio.relock_gate.domain_state"

  /// The enrolled biometric set's fingerprint after a successful
  /// `canEvaluatePolicy` / `evaluatePolicy` on [context].
  static func biometrySetState(_ context: LAContext) -> Data? {
    if #available(iOS 18.0, macOS 15.0, *) {
      return context.domainState.biometry.stateHash
    }
    return context.evaluatedPolicyDomainState
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
      case "resetBiometricDeviceItems":
        result(true)
      case "armBiometricGate":
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error),
          let state = biometrySetState(context)
        else {
          result(false)
          return
        }
        UserDefaults.standard.set(state, forKey: gateStateKey)
        result(true)
      case "authenticate":
        let args = call.arguments as? [String: Any] ?? [:]
        let subtitle = args["subtitle"] as? String ?? ""
        let cancel = args["cancel"] as? String ?? ""
        let title = args["title"] as? String ?? ""
        guard let armed = UserDefaults.standard.data(forKey: gateStateKey) else {
          result("unarmed")
          return
        }
        let context = LAContext()
        // No "Enter Password": the device passcode is never offered (07 §5.6).
        context.localizedFallbackTitle = ""
        if !cancel.isEmpty { context.localizedCancelTitle = cancel }
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        else {
          result("unavailable")
          return
        }
        let reason = subtitle.isEmpty ? title : subtitle
        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) {
          ok, err in
          let answer: String
          if ok {
            answer = biometrySetState(context) == armed ? "success" : "reenrolled"
          } else if let la = err as? LAError {
            switch la.code {
            case .userCancel, .appCancel, .systemCancel, .userFallback:
              answer = "cancelled"
            case .authenticationFailed:
              answer = "failed"
            default:
              answer = "unavailable"
            }
          } else {
            answer = "unavailable"
          }
          DispatchQueue.main.async { result(answer) }
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
