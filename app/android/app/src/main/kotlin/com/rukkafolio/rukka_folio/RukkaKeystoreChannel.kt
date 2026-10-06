package com.rukkafolio.rukka_folio

// The app's own keystore helper (ADR 2026-10-05b, ADR 2026-10-06; Dart side:
// app/lib/features/devices/keystore_platform.dart). What flutter_secure_storage
// 11.2.0 cannot do for us, and nothing else. Nothing here logs key material,
// item contents or ids' values (CLAUDE.md rule 4); the log lines name a class
// and a hardware level only.
//
//  1. qualifyingBiometricEnrolled — ADR 2026-10-05b §1: can a Keystore key that
//     needs a *strong* biometric on every use be created on this phone now? The
//     probe builds such a key under a probe alias and deletes it. No screen
//     lock, no enrolled Class 3 biometric, or only a Class 2 (weak) face unlock
//     all fail here (desk 149, conservative reading (a): PIN-only). The device
//     credential is never an authenticator (07 §5.6).
//
//  2. deviceItemRead / deviceItemWrite / deviceItemDelete / deviceItemContains /
//     deviceKeyStorage — ADR 2026-10-06 §1 🔒, the device-key class: the device
//     signing seed, the device agreement seed and the locally wrapped UMK, each
//     sealed with AES-256-GCM (the item id as associated data) under ONE
//     Keystore key, alias <package>.RukkaDeviceKeys, that is
//       • StrongBox-backed (setIsStrongBoxBacked) when the phone declares
//         FEATURE_STRONGBOX_KEYSTORE, TEE otherwise (04 §3.3 "when available";
//         a StrongBox that refuses the key falls back to the TEE);
//       • created with NO user-authentication binding
//         (setUserAuthenticationRequired(false)) and NOT invalidated by
//         enrolment (setInvalidatedByBiometricEnrollment(false)) — so adding a
//         fingerprint can never destroy it;
//       • non-exportable (Keystore), so the seeds never leave the phone except
//         sealed under it, in private prefs the manifest keeps out of backup
//         and device transfer.
//     The plugin cannot make this key: its AES key cipher sets
//     setUserAuthenticationRequired(true) whenever the phone has a screen lock
//     (KeyCipherImplementationAES23.java:166-186) and its RSA-OAEP key cipher
//     never asks for StrongBox (KeyCipherImplementationRSAOAEP.java:145-155).
//     A read never invents a key: a sealed item whose key is gone is an error,
//     never "absent" (absent device keys mean recovery, not a new identity).
//     Nothing in this file ever deletes this key.
//
//  3. armBiometricGate / authenticate / resetGate — ADR 2026-10-06 §2 🔒, the
//     gate: an AES-256-GCM Keystore key (generated inside the Keystore — the
//     key is the random secret), alias <package>.RukkaRelockGate,
//     setUserAuthenticationRequired(true), BIOMETRIC_STRONG only on every use
//     (API 30+ setUserAuthenticationParameters(0, AUTH_BIOMETRIC_STRONG); API
//     28-29 validity -1, which is biometric-only per use), and
//     setInvalidatedByBiometricEnrollment(true). authenticate reads it: a
//     framework BiometricPrompt over a CryptoObject on that key, and success is
//     answered only after the authenticated cipher has run doFinal — the read
//     IS the unlock, and it opens no data. An invalidated gate (a finger or
//     face added or removed) answers "reenrolled" and is removed; it is minted
//     again only by armBiometricGate, which the Dart side calls only after a
//     verified MPIN (ruling 4). resetGate removes the gate alias — and only
//     the gate alias: never the device-key class, never the plugin's
//     namespaces. (KEY145B's resetBiometricDeviceItems, which cleared the
//     device-key namespace, is gone.) Answers: success, failed, cancelled,
//     unavailable, reenrolled, unarmed.
//
// excludeFromBackup is iOS's; Android keeps the app out of backup in the
// manifest, so here it is a no-op that answers true.

import android.app.KeyguardManager
import android.content.Context
import android.content.pm.PackageManager
import android.hardware.biometrics.BiometricManager
import android.hardware.biometrics.BiometricPrompt
import android.os.Build
import android.os.CancellationSignal
import android.os.Handler
import android.os.Looper
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyInfo
import android.security.keystore.KeyPermanentlyInvalidatedException
import android.security.keystore.KeyProperties
import android.util.Base64
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.security.KeyStore
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.SecretKeyFactory
import javax.crypto.spec.GCMParameterSpec

object RukkaKeystoreChannel {
    const val CHANNEL = "rukka_folio/keystore"
    private const val TAG = "RukkaKeystore"
    private const val PROBE_ALIAS_SUFFIX = ".RukkaBiometricProbe"
    private const val GATE_ALIAS_SUFFIX = ".RukkaRelockGate"
    private const val DEVICE_KEY_ALIAS_SUFFIX = ".RukkaDeviceKeys"
    private const val DEVICE_PREFS = "rukka_folio_device_keys"
    private const val ITEM_PREFIX = "item."
    private const val HARDWARE_PREF = "hardware"
    private const val AAD_PREFIX = "rukka_folio/device-key/"
    private const val GCM_TAG_BITS = 128

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
                "deviceItemRead", "deviceItemWrite", "deviceItemDelete", "deviceItemContains" -> {
                    val id = call.argument<String>("id")
                    val bytes = call.argument<ByteArray>("bytes")
                    worker.execute {
                        try {
                            if (id.isNullOrEmpty()) throw IllegalArgumentException("id")
                            val answer: Any? = when (call.method) {
                                "deviceItemRead" -> deviceItemRead(context, id)
                                "deviceItemWrite" -> {
                                    deviceItemWrite(context, id, bytes ?: throw IllegalArgumentException("bytes"))
                                    true
                                }
                                "deviceItemDelete" -> {
                                    deviceItemDelete(context, id)
                                    true
                                }
                                else -> devicePrefs(context).contains(ITEM_PREFIX + id)
                            }
                            main.post { result.success(answer) }
                        } catch (e: Throwable) {
                            if (e is VirtualMachineError) throw e
                            // The exception's class only: never a message that
                            // could carry material.
                            main.post { result.error("device_item_failed", e.javaClass.simpleName, null) }
                        }
                    }
                }
                "deviceKeyStorage" -> worker.execute {
                    val answer = try {
                        deviceKeyStorage(context)
                    } catch (e: Throwable) {
                        if (e is VirtualMachineError) throw e
                        "unknown"
                    }
                    main.post { result.success(answer) }
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
                    Log.i(TAG, "gate minted=$armed")
                    main.post { result.success(armed) }
                }
                "resetGate" -> worker.execute {
                    try {
                        resetGate(context)
                    } catch (e: Throwable) {
                        if (e is VirtualMachineError) throw e
                    }
                    main.post { result.success(true) }
                }
                "authenticate" -> {
                    val title = call.argument<String>("title") ?: ""
                    val subtitle = call.argument<String>("subtitle") ?: ""
                    val cancel = call.argument<String>("cancel") ?: ""
                    val once = AtomicBoolean(false)
                    val answer: (String) -> Unit = { a ->
                        if (once.compareAndSet(false, true)) {
                            Log.i(TAG, "gate read: $a")
                            main.post { result.success(a) }
                        }
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

    // ── 1. the enrolment question ───────────────────────────────────────────

    private fun qualifyingBiometricEnrolled(context: Context): Boolean {
        val keyguard = context.getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager?
        if (keyguard == null || !keyguard.isDeviceSecure) return false
        val alias = context.packageName + PROBE_ALIAS_SUFFIX
        val ks = keyStore()
        return try {
            val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, ANDROID_KEYSTORE)
            generator.init(biometricSpec(alias))
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

    private fun keyStore(): KeyStore = KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }

    /** A key that needs a Class 3 biometric on every use and dies with any
     *  enrolment change — the gate's spec, and the probe's. */
    private fun biometricSpec(alias: String): KeyGenParameterSpec {
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

    // ── 2. the device-key class (ruling 1) ──────────────────────────────────

    private fun devicePrefs(context: Context) =
        context.getSharedPreferences(DEVICE_PREFS, Context.MODE_PRIVATE)

    private fun aad(id: String) = (AAD_PREFIX + id).toByteArray(Charsets.UTF_8)

    private fun deviceKeySpec(alias: String, strongBox: Boolean): KeyGenParameterSpec {
        val builder = KeyGenParameterSpec.Builder(
            alias,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
        )
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(256)
            // Ruling 1: no person bound to the device keys, and no enrolment
            // change can invalidate them.
            .setUserAuthenticationRequired(false)
            .setInvalidatedByBiometricEnrollment(false)
        if (strongBox && Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            builder.setIsStrongBoxBacked(true)
        }
        return builder.build()
    }

    /** The device-key class's key; created (StrongBox first) only for a write. */
    private fun deviceKey(context: Context, create: Boolean): SecretKey? {
        val alias = context.packageName + DEVICE_KEY_ALIAS_SUFFIX
        val ks = keyStore()
        (ks.getKey(alias, null) as SecretKey?)?.let { return it }
        if (!create) return null
        val hasStrongBox = Build.VERSION.SDK_INT >= Build.VERSION_CODES.P &&
            context.packageManager.hasSystemFeature(PackageManager.FEATURE_STRONGBOX_KEYSTORE)
        var level = "tee"
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, ANDROID_KEYSTORE)
        if (hasStrongBox) {
            try {
                generator.init(deviceKeySpec(alias, true))
                generator.generateKey()
                level = "strongBox"
            } catch (e: Exception) {
                // StrongBoxUnavailableException (or a StrongBox that refuses
                // AES-256-GCM): the TEE, as 04 §3.3 allows.
                if (ks.containsAlias(alias)) ks.deleteEntry(alias)
            }
        }
        if (level != "strongBox") {
            generator.init(deviceKeySpec(alias, false))
            generator.generateKey()
        }
        devicePrefs(context).edit().putString(HARDWARE_PREF, level).commit()
        Log.i(TAG, "device-key class key created: $level (StrongBox declared: $hasStrongBox)")
        return keyStore().getKey(alias, null) as SecretKey
    }

    private fun deviceItemWrite(context: Context, id: String, bytes: ByteArray) {
        val key = deviceKey(context, create = true)!!
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key)
        cipher.updateAAD(aad(id))
        val sealed = cipher.doFinal(bytes)
        val value = Base64.encodeToString(cipher.iv, Base64.NO_WRAP) + ":" +
            Base64.encodeToString(sealed, Base64.NO_WRAP)
        // commit(), not apply(): durable before the Dart side reads it back.
        if (!devicePrefs(context).edit().putString(ITEM_PREFIX + id, value).commit()) {
            throw IllegalStateException("prefs commit")
        }
    }

    private fun deviceItemRead(context: Context, id: String): ByteArray? {
        val value = devicePrefs(context).getString(ITEM_PREFIX + id, null) ?: return null
        val key = deviceKey(context, create = false)
            ?: throw IllegalStateException("device-key class key missing")
        val parts = value.split(':')
        if (parts.size != 2) throw IllegalStateException("item malformed")
        val iv = Base64.decode(parts[0], Base64.NO_WRAP)
        val sealed = Base64.decode(parts[1], Base64.NO_WRAP)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(GCM_TAG_BITS, iv))
        cipher.updateAAD(aad(id))
        return cipher.doFinal(sealed)
    }

    private fun deviceItemDelete(context: Context, id: String) {
        if (!devicePrefs(context).edit().remove(ITEM_PREFIX + id).commit()) {
            throw IllegalStateException("prefs commit")
        }
    }

    /** Which hardware holds the device-key class's key — asked of the
     *  Keystore itself where the platform answers (API 31+), else the level
     *  recorded when the key was made. */
    private fun deviceKeyStorage(context: Context): String {
        val key = deviceKey(context, create = false) ?: return "unknown"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val factory = SecretKeyFactory.getInstance(key.algorithm, ANDROID_KEYSTORE)
            val info = factory.getKeySpec(key, KeyInfo::class.java) as KeyInfo
            return when (info.securityLevel) {
                KeyProperties.SECURITY_LEVEL_STRONGBOX -> "strongBox"
                KeyProperties.SECURITY_LEVEL_TRUSTED_ENVIRONMENT -> "tee"
                else -> "unknown"
            }
        }
        return devicePrefs(context).getString(HARDWARE_PREF, null) ?: "unknown"
    }

    // ── 3. the gate (rulings 2 and 4) ───────────────────────────────────────

    /** Mints a new gate against the biometric set enrolled now. */
    private fun armBiometricGate(context: Context) {
        val alias = context.packageName + GATE_ALIAS_SUFFIX
        val ks = keyStore()
        if (ks.containsAlias(alias)) ks.deleteEntry(alias)
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, ANDROID_KEYSTORE)
        generator.init(biometricSpec(alias))
        generator.generateKey()
    }

    /** Removes the gate alias. Nothing else. */
    private fun resetGate(context: Context) {
        val alias = context.packageName + GATE_ALIAS_SUFFIX
        val ks = keyStore()
        if (ks.containsAlias(alias)) ks.deleteEntry(alias)
    }

    private fun authenticate(
        context: Context,
        title: String,
        subtitle: String,
        cancel: String,
        answer: (String) -> Unit,
    ) {
        val alias = context.packageName + GATE_ALIAS_SUFFIX
        val ks = keyStore()
        val key = ks.getKey(alias, null) as SecretKey?
        if (key == null) {
            answer("unarmed")
            return
        }
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        try {
            cipher.init(Cipher.ENCRYPT_MODE, key)
        } catch (e: KeyPermanentlyInvalidatedException) {
            // The enrolled set changed since the gate was minted (06 §4.4): the
            // MPIN, once, then a new gate. Only the gate is removed.
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
                // The read itself: the authenticated cipher must run.
                val ok = try {
                    result.cryptoObject?.cipher?.doFinal(ByteArray(16)) != null
                } catch (e: Exception) {
                    false
                }
                answer(if (ok) "success" else "failed")
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
            // onAuthenticationFailed: one finger not recognised — the sheet
            // stays up for another try, so nothing is answered yet.
        }
        builder.build().authenticate(
            BiometricPrompt.CryptoObject(cipher),
            CancellationSignal(),
            executor,
            callback,
        )
    }
}
