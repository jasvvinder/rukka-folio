package com.rukkafolio.rukka_folio

// The app's own keystore helper (ADR 2026-10-05b; Dart side:
// app/lib/features/devices/keystore_platform.dart). Two things
// flutter_secure_storage 11.2.0 cannot do for us, and nothing else:
//
//  1. qualifyingBiometricEnrolled — ruling 1: can a Keystore key that needs a
//     *strong* biometric on every use be created on this phone right now? The
//     probe builds exactly the key the plugin builds for the device-key items
//     (KeyCipherImplementationAES23.java:161-181: AES-256-GCM,
//     setUserAuthenticationRequired(true), API 30+ setUserAuthenticationParameters
//     (0, AUTH_BIOMETRIC_STRONG) else validity -1, setInvalidatedByBiometricEnrollment
//     (true)) under a probe alias, then deletes it. So the answer is the plugin's
//     own answer, not a guess from BiometricManager: no screen lock, no enrolled
//     Class 3 biometric, or only a Class 2 (weak) face unlock all fail here
//     (desk 149, conservative reading (a): such a phone runs PIN-only).
//     The device credential is never an authenticator (07 §5.6).
//
//  2. resetBiometricDeviceItems — ruling 3: remove the device-key items of the
//     biometric namespace when the Keystore has invalidated their key. The plugin
//     cannot: every call, delete and deleteAll included, runs initialize first
//     (FlutterSecureStoragePlugin.java:176-178 before :245-256), and initialize
//     fails on the invalidated key (FlutterSecureStorage.java:425-426 →
//     handleKeyMismatch :1016, which with resetOnError=false only reports). The
//     names are the plugin's own, derived from its source for the namespace
//     "rukka_folio_device" ONLY — never the promptless "rukka_folio" namespace
//     that holds the database key and the PIN vault:
//       • Keystore alias  <package>.FlutterSecureStoragePluginKey.rukka_folio_device
//         (KeyCipherImplementationAES23.java:76-77 + FlutterSecureStorageConfig.java:203-204)
//       • data prefs      "rukka_folio_device" (FlutterSecureStorageConfig.java:183-184)
//       • wrapped app key + IV prefs "FlutterSecureKeyStorage:rukka_folio_device"
//         (FlutterSecureStorageConfig.java:192-194; KeyCipherImplementationAES23.java:33,86-87;
//          StorageCipherImplementationAES23.java:22-23)
//     The algorithm markers ("FlutterSecureStorageConfiguration:rukka_folio_device",
//     NamespacedConfigSource.java) are kept, so the next open sees the current
//     algorithm and creates a fresh key instead of reporting "Algorithm changed".
//
// excludeFromBackup is iOS's (NSURLIsExcludedFromBackupKey); Android keeps the app
// out of backup in the manifest (allowBackup=false + data_extraction_rules.xml),
// so here it is a no-op that answers true.
//
//  3. authenticate / armBiometricGate — the in-app S15's own prompt for the
//     background / idle relock (07 §5.6 🔒 "biometric prompting automatically";
//     KEY145B review finding 3). Once the device-key namespace is open the plugin
//     holds its cipher in memory and a read prompts nothing, so the relock needs
//     a prompt of its own. It is a framework BiometricPrompt (API 28+, as the
//     plugin's) over a CryptoObject on a dedicated gate key — AES-256-GCM,
//     setUserAuthenticationRequired, BIOMETRIC_STRONG only on API 30+ (validity -1
//     below), setInvalidatedByBiometricEnrollment(true) — so only a Class 3
//     biometric of the *current* set opens it, never the device credential
//     (07 §5.6). An invalidated gate key answers "reenrolled" and is removed; it
//     is re-created only by armBiometricGate, which the Dart side calls only after
//     a proof that the current set is the device keys' own (a correct MPIN, or the
//     cold-start read of the biometric-bound device keys). Answers: success,
//     failed, cancelled, unavailable, reenrolled, unarmed.
//     ⚠️ Not verified on a device in this lane.

import android.app.KeyguardManager
import android.content.Context
import android.hardware.biometrics.BiometricManager
import android.hardware.biometrics.BiometricPrompt
import android.os.Build
import android.os.CancellationSignal
import android.os.Handler
import android.os.Looper
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyPermanentlyInvalidatedException
import android.security.keystore.KeyProperties
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.security.KeyStore
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey

object RukkaKeystoreChannel {
    const val CHANNEL = "rukka_folio/keystore"
    private const val DEVICE_NAMESPACE = "rukka_folio_device"
    private const val PROBE_ALIAS_SUFFIX = ".RukkaBiometricProbe"
    private const val GATE_ALIAS_SUFFIX = ".RukkaRelockGate"

    /** BiometricManager / androidx ERROR_NEGATIVE_BUTTON (13); the framework
     *  BiometricPrompt class has no constant for it. */
    private const val NEGATIVE_BUTTON_ERROR = 13
    private const val ANDROID_KEYSTORE = "AndroidKeyStore"

    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    fun register(context: Context, messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "qualifyingBiometricEnrolled" -> worker.execute {
                    val answer = try {
                        qualifyingBiometricEnrolled(context)
                    } catch (e: Throwable) {
                        if (e is VirtualMachineError) throw e
                        false
                    }
                    main.post { result.success(answer) }
                }
                "resetBiometricDeviceItems" -> worker.execute {
                    try {
                        resetBiometricDeviceItems(context)
                        main.post { result.success(true) }
                    } catch (e: Throwable) {
                        if (e is VirtualMachineError) throw e
                        main.post { result.error("reset_failed", e.javaClass.simpleName, null) }
                    }
                }
                "excludeFromBackup" -> result.success(true)
                "armBiometricGate" -> worker.execute {
                    val armed = try {
                        armBiometricGate(context)
                        true
                    } catch (e: Throwable) {
                        if (e is VirtualMachineError) throw e
                        false
                    }
                    main.post { result.success(armed) }
                }
                "authenticate" -> {
                    val title = call.argument<String>("title") ?: ""
                    val subtitle = call.argument<String>("subtitle") ?: ""
                    val cancel = call.argument<String>("cancel") ?: ""
                    val once = AtomicBoolean(false)
                    val answer: (String) -> Unit = { a ->
                        if (once.compareAndSet(false, true)) main.post { result.success(a) }
                    }
                    try {
                        authenticate(context, title, subtitle, cancel, answer)
                    } catch (e: Throwable) {
                        if (e is VirtualMachineError) throw e
                        answer("unavailable")
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun qualifyingBiometricEnrolled(context: Context): Boolean {
        val keyguard = context.getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager?
        if (keyguard == null || !keyguard.isDeviceSecure) return false
        val alias = context.packageName + PROBE_ALIAS_SUFFIX
        val ks = KeyStore.getInstance(ANDROID_KEYSTORE)
        ks.load(null)
        return try {
            val builder = KeyGenParameterSpec.Builder(
                alias,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .setUserAuthenticationRequired(true)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                builder.setUserAuthenticationParameters(0, KeyProperties.AUTH_BIOMETRIC_STRONG)
            } else {
                @Suppress("DEPRECATION")
                builder.setUserAuthenticationValidityDurationSeconds(-1)
            }
            builder.setInvalidatedByBiometricEnrollment(true)
            val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, ANDROID_KEYSTORE)
            generator.init(builder.build())
            generator.generateKey()
            true
        } catch (e: Exception) {
            false
        } finally {
            try {
                if (ks.containsAlias(alias)) ks.deleteEntry(alias)
            } catch (_: Exception) {
            }
        }
    }

    private fun gateSpec(alias: String): KeyGenParameterSpec {
        val builder = KeyGenParameterSpec.Builder(
            alias,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
        )
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(256)
            .setUserAuthenticationRequired(true)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            builder.setUserAuthenticationParameters(0, KeyProperties.AUTH_BIOMETRIC_STRONG)
        } else {
            @Suppress("DEPRECATION")
            builder.setUserAuthenticationValidityDurationSeconds(-1)
        }
        builder.setInvalidatedByBiometricEnrollment(true)
        return builder.build()
    }

    /** (Re-)creates the gate key against the biometric set enrolled now. */
    private fun armBiometricGate(context: Context) {
        val alias = context.packageName + GATE_ALIAS_SUFFIX
        val ks = KeyStore.getInstance(ANDROID_KEYSTORE)
        ks.load(null)
        if (ks.containsAlias(alias)) ks.deleteEntry(alias)
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, ANDROID_KEYSTORE)
        generator.init(gateSpec(alias))
        generator.generateKey()
    }

    private fun authenticate(
        context: Context,
        title: String,
        subtitle: String,
        cancel: String,
        answer: (String) -> Unit,
    ) {
        val alias = context.packageName + GATE_ALIAS_SUFFIX
        val ks = KeyStore.getInstance(ANDROID_KEYSTORE)
        ks.load(null)
        val key = ks.getKey(alias, null) as SecretKey?
        if (key == null) {
            answer("unarmed")
            return
        }
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        try {
            cipher.init(Cipher.ENCRYPT_MODE, key)
        } catch (e: KeyPermanentlyInvalidatedException) {
            // The enrolled set changed since the gate was armed (06 §4.4): the
            // PIN, once, re-arms it. Never re-created here.
            ks.deleteEntry(alias)
            answer("reenrolled")
            return
        }
        val executor = context.mainExecutor
        val builder = BiometricPrompt.Builder(context)
            .setTitle(title)
            .setSubtitle(subtitle)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            builder.setAllowedAuthenticators(BiometricManager.Authenticators.BIOMETRIC_STRONG)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            builder.setConfirmationRequired(false)
        }
        // The negative button is S15's "Use PIN instead"; its listener answers,
        // because the framework calls no error callback for it.
        builder.setNegativeButton(cancel, executor) { _, _ -> answer("cancelled") }
        val callback = object : BiometricPrompt.AuthenticationCallback() {
            override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) {
                answer("success")
            }

            override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                answer(
                    when (errorCode) {
                        BiometricPrompt.BIOMETRIC_ERROR_CANCELED,
                        BiometricPrompt.BIOMETRIC_ERROR_USER_CANCELED,
                        NEGATIVE_BUTTON_ERROR -> "cancelled"
                        BiometricPrompt.BIOMETRIC_ERROR_LOCKOUT,
                        BiometricPrompt.BIOMETRIC_ERROR_LOCKOUT_PERMANENT,
                        BiometricPrompt.BIOMETRIC_ERROR_HW_UNAVAILABLE,
                        BiometricPrompt.BIOMETRIC_ERROR_HW_NOT_PRESENT,
                        BiometricPrompt.BIOMETRIC_ERROR_NO_BIOMETRICS -> "unavailable"
                        else -> "failed"
                    },
                )
            }
            // onAuthenticationFailed: one face/finger not recognised — the sheet
            // stays up for another try, so nothing is answered yet.
        }
        builder.build().authenticate(
            BiometricPrompt.CryptoObject(cipher),
            CancellationSignal(),
            executor,
            callback,
        )
    }

    private fun resetBiometricDeviceItems(context: Context) {
        val ks = KeyStore.getInstance(ANDROID_KEYSTORE)
        ks.load(null)
        val alias = context.packageName + ".FlutterSecureStoragePluginKey." + DEVICE_NAMESPACE
        if (ks.containsAlias(alias)) ks.deleteEntry(alias)
        context.getSharedPreferences(DEVICE_NAMESPACE, Context.MODE_PRIVATE)
            .edit().clear().commit()
        context.getSharedPreferences("FlutterSecureKeyStorage:$DEVICE_NAMESPACE", Context.MODE_PRIVATE)
            .edit().clear().commit()
    }
}
