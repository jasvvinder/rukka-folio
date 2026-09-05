# ADR 2026-09-05 — Client hardening: what a generic fintech blueprint adds, and what it must not

The owner brought a generic Flutter fintech security blueprint (OWASP MASVS / PCI-DSS framed:
zero-trust client, pinning, RASP, obfuscation, screen security, session hygiene) and asked which of
it we adopt. About two thirds was already decided in 04 / 05 / 06 / 07 / 13 or is compatible. One
principle contradicts the architecture and is **rejected**; the rest are gaps this ADR closes.
Owner confirmed 5 Sep 2026 ("add the gaps … do whatever we can do the best").

## Rejected 🔒 — the server is not the financial authority

The blueprint's first mandate — *treat the client as a presentation layer; all financial
calculations, authorisation checks and state transitions are validated server-side* — is the
standard banking model and the **opposite of ours**. The server cannot see amounts (04 §4), so it
cannot compute a balance, enforce a value limit, or validate a posting. Adopting the line would
mean abandoning zero-knowledge. The same threats are met differently, and this is deliberate:

| Blueprint control | Our equivalent |
|---|---|
| Server validates every state change | Every envelope signed by a certified device (04 §3.4, §8.3); server cannot forge or alter |
| Server computes balances | Pure deterministic projector on every client (03 §3.3); identical balance-vector hash across clients is an acceptance test (09 H) |
| Server evaluates permissions on values | Entry limits enforced client-side; over-limit posts and is **flagged for review** by a human (02 §3) |
| Server authorises structural changes | Quorum of **signed approval envelopes** authored on the owners' own devices (02 §7.2.1) |

Nothing in the rest of this ADR moves any financial decision to the server. If a future proposal
needs the server to read content to "validate" it, 04 §8.6 already says the design has been violated.

## Already decided elsewhere (no change)

Hardware-backed device keys and biometrics that unlock a *signing key* rather than return a boolean
(04 §3.3, 06 §4); 15-min access JWT + rotating refresh with family revocation on replay (06 §4);
SQLCipher at rest keyed from the OS keystore (03 §3); zeroise-after-use and no plaintext financial
data in logs/crash/analytics (CLAUDE.md rules 4, 7; 04 §8.1); privacy cover in the app switcher
(07 §5.6, 13 S15.1); background lock with an MPIN the family does not know (06 §4.4); attestation
field designed now, enforced v2 (06 §3.2); no client secret exists to hardcode — the backend anon
key is public by design and gated by RLS (06 §1.1); PCI scope avoided because the gateway holds
every instrument (08 §4); privacy law is **DPDP**, not GDPR (06 §9.3).

## Rulings 🔒

1. **Public-key pinning (SPKI), key not certificate.** The client pins the SPKI hashes of the API
   host's certificate chain — **two pins minimum** (current + backup) so a rotation is never an
   outage. Pin failure is a hard fail: no fallback, no user override, **in every build that talks
   to a hosted environment, staging included**. Only a local-dev build (`--dart-define`) against a
   local stack may disable pinning, and CI asserts the release lane never carries that define.
   ⚠️ Hosted Supabase terminates TLS on rotating CA-issued leaves; pin at the **intermediate CA**
   level plus a backup CA, verify the exact chain at M4, and write the rotation runbook then.
   Owner-lives in 05 §1.
2. **Transport configs at OS level.** Android `cleartextTrafficPermitted="false"`; iOS App
   Transport Security with no arbitrary loads. Set in the M0 app shell before any network code.
3. **Release binaries obfuscated.** `flutter build … --obfuscate --split-debug-info=<dir>` in the
   release lane of `ci.sh`; the symbol files are kept as **CI artefacts only**, never shipped, so
   crash reports can be symbolised without exposing symbols. Gate: decompile the release build at
   M14 and confirm Dart symbols are unreadable (09 §4).
4. **Screenshots and screen recording are blocked 🔒 (owner-ruled 5 Sep 2026).** Android:
   `FLAG_SECURE` on the whole app. iOS has no equivalent API, so the privacy cover (07 §5.6) stays
   and the app additionally listens for screen capture / recording and covers amounts while it is
   active. **Rationale:** the product already gives every legitimate reason to capture a screen a
   proper door — share a statement or receipt as **PDF or over WhatsApp** (07 §14, 04 §7.6) — so a
   screenshot is not a path anyone needs, and a ₹4,81,000 balance in a photo roll that auto-uploads
   to Google Photos is exactly the leak 04 §1.1 exists to stop. The blocked-screenshot toast (Android
   shows the OS's own) needs no copy of ours.
5. **Tap-jacking.** `android:filterTouchesWhenObscured="true"` on the main activity. One line, M0.
6. **Root / jailbreak / debugger / instrumentation: detect, warn, log — never block 🔒.** The app
   checks on launch and on foreground (su binaries, Magisk/Cydia markers, ptrace/debugger attached
   to a release build, known instrumentation agents). On detection it shows **one plain-language
   notice** — *"This phone has been modified. Your books are still encrypted, but anyone who
   controls this phone can see what you see. Make sure your backups are set."* — with a button to
   Devices & security, and records a `device_integrity` flag in the device's `attestation` field
   (03 §2, plaintext metadata, no content). **Why not terminate**, as the blueprint says: our
   audience runs old and second-hand Android phones; 04 §1.2 already accepts that malware on an
   unlocked device sees what the user sees; and a hard block is a dead end (07 §1). The signal
   feeds the v2 attestation decision (06 §11.2). **Emulator detection is not enforced** — the
   two-client test rig (09 §1) runs on emulators.
7. **Foreground inactivity lock.** In addition to the background timeout (06 §4.5, default 2 min),
   the app locks after **5 min with no touch in the foreground** (configurable in the same
   *Auto-lock* setting; the two values are shown together). A half-typed entry is preserved as the
   draft and returns after unlock — the lock never discards work (07 §1 no dead ends).
8. **Memory hygiene made explicit.** Key material, shares and the recovery key live in `Uint8List`
   (libsodium `SecureKey` where available), **never in a Dart `String`**, and are zeroised after
   use (04 §8.1). Keys cross to native only over the libsodium FFI boundary — **never over a
   `MethodChannel`/`EventChannel`**. Platform-channel payloads (biometric prompts, secure-storage
   reads) carry handles or ciphertext, never plaintext keys. `check_purity.sh` gains a grep for
   `String` typed fields in `core_crypto` key types when M3 lands.
9. **Logging discipline enforced by CI, not convention.** Release builds strip all debug logging
   (`kDebugMode` guards, no bare `print`); CI fails on a bare `print(` in `app/lib` and packages.
   Authorization headers, request/response bodies and full stack traces never reach production
   analytics (CLAUDE.md rule 4 already forbids content; this extends it to tokens and bodies).
10. **Supply chain in the gate.** `ci.sh` gains (a) a **secret scan** over the tree and history
    (gitleaks or equivalent) and (b) a **dependency vulnerability audit** of `pubspec.lock` (OSV
    scanner supports pub); either red blocks merge. SAST (MobSF) over release builds joins the
    M14 gate rather than every push.
11. **Temporary files.** Exports and the recovery sheet PDF render into the app's sandboxed cache
    and are deleted after the native share sheet returns; nothing is written to public external
    storage. The **readable export to the user's own Drive (04 §7.6) is not a temp file** — it is a
    disclosed, opt-out artefact and this ruling does not touch it.
12. **Compliance framing.** OWASP **MASVS L2 + R** is the hardening checklist for M14 (10). We do
    not claim PCI-DSS (out of scope by construction, 08 §4) and our privacy regime is DPDP.

## What changed where

- **05 §1** — pinning + transport-config bullet (ruling 1–2).
- **06 §4** — foreground inactivity lock (7), integrity notice (6); **§11** open item on pin chain.
- **07 §5.6** — screenshots blocked; privacy cover extended to iOS capture (4).
- **04 §1.2** — malware line cross-references the warn-not-block ruling (6).
- **09 §4** — release gates: decompile, MITM, screen-capture, log-scrub, secret/dependency scans (3, 9, 10).
- **10 M14** — MASVS L2+R pass added to the exit gate (12); **M0/M3/M4/M5** rows gain the
  build-time items so they are not forgotten.
- Code changes (manifest flags, ci.sh steps, purity greps) land with the milestone that owns the
  file — M0 shell items in the next app-shell session, ci.sh scanners at M4, purity grep at M3.

## Open ⚠️

1. Exact SPKI pin set for the hosted API (intermediate CA + backup) — verify chain at M4.
2. Whether `FLAG_SECURE` should also cover the **Show my code** ceremony screen: the QR is meant to
   be scanned from the screen, not photographed, so blocking is consistent — but confirm the camera
   path is unaffected (it is: `FLAG_SECURE` blocks *this* device's capture, not another's camera).
3. Detection library choice (`flutter_jailbreak_detection`-class vs. a small native check we own);
   prefer owning it — fewer dependencies in the trust path.
