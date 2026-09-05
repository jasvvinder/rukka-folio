# 04 — Cryptography Specification

**Status:** Draft 1 for build. Decisions marked 🔒 are locked. Items marked ⚠️ need a choice or verification before the affected milestone.

**Design goal:** The server stores and relays data but can never read financial content, never holds a usable key, and can never impersonate a member. All trust is rooted in in-person (or logged-remote) verification between humans.

---

## 1. Threat model

### 1.1 We defend against

| Threat | Defense |
|---|---|
| Server breach / malicious insider / subpoena of server | Server holds only ciphertext and wrapped keys it cannot open |
| SIM-swap attacker passing OTP | OTP grants login only, never data. Keys come from the recovery ladder, which requires humans (§7) |
| Server substituting a fake member key ("ghost member") | Mandatory verification ceremony binds keys to humans (§6); device keys are certified by the user's verified identity key (§3.4) |
| Server forging or tampering with entries | Every entry is signed by its author's certified device key (§8.3) |
| Stolen phone (locked) | Hardware keystore + biometric/PIN gate; remote revocation (§9) |
| Removed member reading future data | Book-key rotation on removal (§5.3) |

### 1.2 We accept (documented, not defended)

- A **malicious server can withhold data or serve stale data** (denial of service). It cannot alter or read it — and since ADR 2026-09-05b §3, withholding is **detected**: every payload carries a per-author sequence, so a missing envelope shows as a gap on every reader and blocks month-close rather than passing as a complete book.
- A **removed member keeps what they already synced.** Rotation protects future entries only. State this honestly in the UI.
- The **escrow timer (§7.5) is server-enforced policy**, not cryptography. A compromised server could release the escrow blob early — but the blob is only decryptable by the designated head, so the damage is bounded to the escrow's intended scope.
- **Malware on an unlocked, activated device** sees what the user sees. Out of scope. Client hardening (pinning, obfuscation, screenshot block, modified-device notice — ADR 2026-09-05) raises the bar but does not change this line; a rooted phone is **warned and logged, never blocked**.
- Traffic metadata (who syncs when, blob sizes) is visible to the server. Required for operation.

---

## 2. Primitives 🔒

All client-side via **libsodium** (Flutter: `sodium_libs`). No hand-rolled crypto anywhere.

| Purpose | Primitive |
|---|---|
| Symmetric content encryption | XChaCha20-Poly1305 (24-byte random nonce) |
| Key wrapping to a person | X25519 sealed box (`crypto_box_seal`) |
| Signatures (entries, device certs, auth) | Ed25519 |
| Hashing / fingerprints | BLAKE2b-256 |
| Secret sharing (guardians) | Shamir over GF(256) — ⚠️ select an audited package; libsodium does not ship one. Fallback if none passes review: for k-of-n, wrap the key under each k-sized guardian combination (fine for n ≤ 5) |
| Randomness | libsodium CSPRNG only |

**No KDF / no Argon2 needed:** the system contains **no low-entropy secrets**. There are no passwords; the recovery sheet carries a full-entropy key. This is a feature — preserve it. If a future feature introduces a user-chosen secret, it must come back through this spec.

**Crypto agility:** every stored artifact (envelope, wrapped key, share, certificate) carries a 1-byte `suite_version`. Current = `0x01` meaning the table above.

---

## 3. Key hierarchy

```
Phone number (identity claim, verified by OTP — login only)
│
User Master Key  UMK  (X25519 pair + Ed25519 pair)     ← the user's cryptographic identity
│    private halves exist only on the user's devices
│
├── wrapped to each Device Key (§3.3)                   ← how your own devices hold it
├── split into Guardian Shares (§7.3)                   ← recovery rung 2
├── wrapped under Recovery Key RK from paper sheet (§7.4) ← recovery rung 3
│
└── Book Keys  BK  (XChaCha20, one per book, versioned)
     │    each BK sealed to every member's UMK public key
     └── Attachment Keys (random per file, wrapped under the book's BK)
```

### 3.1 User Master Key (UMK) 🔒
Generated on the first device at signup. The X25519 half receives wrapped book keys; the Ed25519 half signs device certificates (§3.4). `FP = BLAKE2b-256(UMK_pub_x25519 ‖ UMK_pub_ed25519)` is the user's **fingerprint** — the value the verification ceremony confirms.

### 3.2 Book Keys (BK) 🔒
One symmetric key per book, per version: `(book_id, key_version)`. Every entry records the `key_version` it was encrypted under. Old versions are retained (wrapped) so history stays readable; new entries always use the highest version. Rotation triggers: member removal, device reported stolen, suspected compromise.

### 3.3 Device Keys 🔒
Each device generates an Ed25519 signing pair **inside hardware keystore** (StrongBox / Secure Enclave when available) — used for auth (doc 06) and entry signing. The device also generates an X25519 pair for receiving the wrapped UMK; since mobile secure hardware does not natively host X25519, its private half is stored encrypted under a hardware-backed AES key from the OS keystore. ⚠️ Verify current platform support at build time; this is the accepted pattern as of spec date.

**Platform nuance:** Android Keystore entries are destroyed on uninstall → reinstall on the same Android phone is a **new device**. iOS Keychain items survive reinstall → attempt Keychain restore first; only fall back to recovery if absent.

### 3.4 Device certificates — the trust chain 🔒
The server's word about which devices belong to a user is never trusted. Instead:

- At signup, the first device holds the UMK and **self-certifies**: `cert = Sign_UMK_ed(device_id ‖ device_pub_ed ‖ device_pub_x ‖ issued_at)`.
- Every later device gets its certificate issued by an existing certified device (linking, §9.1) or during recovery completion (§7.3 step 6).
- Verifiers (other members' apps) accept an entry signature only if: entry sig ✓ under device key → device cert ✓ under author's UMK → author's UMK fingerprint was **verified by ceremony** for this tenant.

Root of all trust = a human scanned a QR or typed a code. Nothing rests on the server.

---

## 4. Encryption envelope 🔒

Everything synced (entries, account definitions, book names, party names, comments) travels and rests as:

```
Envelope {
  suite_version   : 0x01
  tenant_id       : uuid          (plaintext — routing & RLS)
  book_id         : uuid          (plaintext — routing & RLS)
  object_id       : uuid          (plaintext — sync identity/idempotency)
  object_type     : enum          (plaintext — entry | account | attachment_meta | ...)
  key_version     : int
  nonce           : 24 bytes
  ciphertext      : XChaCha20-Poly1305( plaintext_json )
  aad             : tenant_id ‖ book_id ‖ object_id ‖ object_type ‖ key_version ‖ suite_version
  author_device_id: uuid          (plaintext)
  author_sig      : Ed25519( BLAKE2b(ciphertext ‖ aad) )
  created_hlc     : hybrid logical clock (plaintext — sync ordering)
}
```

The AAD binds ciphertext to its identity — the server cannot move an envelope between books or objects without Poly1305 failing. **The server validates nothing about content** (it can't); it checks only shape, membership, size caps, and idempotency.

**Plaintext on server (complete list):** user ids, phone numbers, display names, language, tenant/book/membership/role records, device records + certs, wrapped keys and shares (opaque), invite records, subscription/billing refs, envelope routing fields above, timestamps, sizes, audit events. **Everything else is ciphertext — including book names, account names, party names, amounts, notes, and attachments.**

Push notifications carry object ids and generic text only ("Ramesh added an entry"), never amounts or names.

---

## 5. Membership and key distribution

### 5.1 Granting access 🔒
Performed only on a member device, never by the server: seal `BK` (all live versions) to the new member's **ceremony-verified** UMK public key; upload the wrapped blobs. The server relays. Wrapping before verification completes is forbidden (enforced client-side; the state machine in doc 06 §7 makes it structural).

### 5.2 Personal books 🔒
BK wrapped only to the owner's UMK (+ optional escrow §7.5). No admin path exists. Privacy is a property, not a policy.

### 5.3 Removal / revocation 🔒
1. Ledger precondition (doc 02): open advances settled or written off.
2. Any remaining member's device generates `BK(v+1)` for every book the leaver could read, seals to all remaining members, uploads.
3. Server marks the old wrapped copies revoked and rejects new envelopes under old versions after a **48 h grace**, answering `rejected:key_version_stale` (05 §3). **The grace covers the in-flight race only** — a device already mid-push when rotation lands. It is *not* how long-offline devices are accommodated: an offline device cannot learn of a rotation by waiting, so it instead **re-seals its queued envelopes under the new `BK` before pushing** (05 §3, mandatory ordering: key sync precedes outbox drain). That path is unbounded in time, so a device offline for a month loses nothing while the rotation guarantee still holds — no envelope authored after the rotation is ever *stored* under a key the removed member holds.
4. Leaver keeps their personal book — it was always theirs.
5. UI copy tells the truth: "Removed members keep entries they already had; everything new is sealed from them."

---

## 6. Verification ceremony 🔒

**Purpose:** bind a UMK fingerprint to a human. **Mandatory** before any shared-book key is wrapped to a new member, before guardian activation, before device linking, and before trustee handover. One component, four uses.

### 6.1 Material
- Per-invite `nonce` (128-bit, server-generated at invite creation; not secret — it scopes and expires codes).
- **QR payload:** `base64url( suite_version ‖ user_id ‖ UMK_pub_ed ‖ UMK_pub_x ‖ nonce )`.
- **8-digit code:** `decimal( first4bytes( BLAKE2b-256( FP ‖ nonce ‖ "verify-v1" ) ) ) mod 10⁸`, zero-padded.

### 6.2 Screens
- Invitee → **Show my code**: large QR, the 8 digits printed beneath. One screen for every mode.
- Verifier → **Verify member**: camera open by default; button *Enter code instead*.

### 6.3 Checks
- **QR path:** verifier's device compares scanned public keys **byte-for-byte** against the server-relayed keys for that user. Equal → verified. Unequal → hard-fail red screen: *"Do not proceed. Contact support."* Log a `verification_mismatch` security event. There is no override.
- **Code path:** verifier's device computes the expected code from the *server-relayed* keys + nonce and compares to the typed digits. 3 attempts per nonce; nonce lifetime 10 minutes; *Regenerate* issues a fresh nonce. Rate limits make 8 digits sufficient.

### 6.4 Modes & policy 🔒
- **Default: QR, in person.**
- **Remote:** admin toggles *Verify remotely* per invite → verifier scans the QR off a **video call**, or the code is read aloud on a **voice call** and typed. Direction is irrelevant (the code originates on the invitee's device; either side may read it) — the UI never mentions direction.
- **Channel rule:** the code must travel over a channel where the verifier recognizes the *person* (voice/video/in person). Therefore **no share/copy button** on the code — the remote screen says *"Call them and ask them to read the code aloud."* SMS/WhatsApp-text delivery would hand the code to precisely the attacker this ceremony exists to stop.
- **Delegated:** any already-verified, active member of the tenant may perform the ceremony on the tenant's behalf (the cousin who is physically with the NRI invitee).
- Every verification is logged: who verified whom, method (`qr_in_person` | `code_remote`), timestamp — visible to the tenant's members permanently.
- **Guardian setup is mutual:** both directions must complete before a guardian becomes active.

---

## 7. Recovery ladder

Order tried on a new device after OTP (doc 06 §5). Login without key recovery yields an empty vault and a clear explanation — never silent data loss, never a fake "reset."

### 7.1 Rung 0 — iOS Keychain remnant
Reinstall on the same iPhone may find device keys intact → normal certified device, done.

### 7.2 Rung 1 — another of your own devices
Standard device linking (§9.1).

### 7.3 Rung 2 — guardians (flagship) 🔒
**Setup:** choose guardians (default **2-of-3**; allowed n=2..5 with k=⌈(n+1)/2⌉; 2-of-2 permitted with an explicit data-loss warning). Mutual ceremony per guardian. Split `UMK_priv` via Shamir; seal `share_i` to guardian *i*'s UMK public key; upload. Re-split and re-upload on any guardian change or UMK rotation; shares carry `share_set_version`.

**Recovery:**
1. New device generates fresh device keys + a *candidate* X25519 pair; requests recovery.
2. Guardians get a push (no financial content): requester name + photo + **new device fingerprint** + prominent advice: *"Call them before approving."*
3. Guardian approves with biometric → guardian's device opens its sealed share and re-seals it to the candidate public key. The share transits and rests sealed; the server never sees plaintext shares.
4. At k shares, the new device reconstructs `UMK_priv`, immediately zeroizes shares from memory.
5. Its possession of UMK lets it decrypt all wrapped BKs → full restore.
6. The device **self-issues its certificate** under the recovered UMK and 🔒 notifies all members and revokes all *previous* device sessions of this user (a recovery event is exactly when old devices should die).
7. Guardian denial → requester notified; 3 denials or 72 h → recovery attempt closed and logged.

### 7.4 Rung 3 — paper sheet 🔒
- `RK` = random 256-bit, generated at signup. Server stores `sealed_RK_blob = XChaCha20(RK, UMK_priv)`.
- Sheet = one-page PDF: QR `base64url(version ‖ user_id ‖ RK)` + typed fallback (Crockford Base32, groups of 4, 2-char checksum) + instructions in English + the user's language (ਪੰਜਾਬੀ/हिन्दी). Framed as a document to keep with the Aadhaar and LIC papers.
- **Verified-storage nag:** persistent badge until the user scans their *printed* sheet back. Re-verify prompt annually. Regenerating a sheet rotates RK and invalidates the old sheet.
- Recovery: scan/type RK → fetch blob → decrypt UMK → same completion as §7.3 step 6.
- Mandatory for solo users (no guardians possible); strongly nudged for everyone.

### 7.0 Rung 0 — platform key sync 🔒 (owner-directed, 31 Aug 2026; tried before every other rung)
**iOS: iCloud Keychain. Android: Block Store.** Both are end-to-end encrypted by the platform — Apple and Google cannot read them — so storing the wrapped UMK there does **not** weaken zero-knowledge; it adds a second device-class custodian the vendor still cannot open.

- Default **on**, with a plain explanation at signup and a switch in Devices & security.
- Effect: a new iPhone signed into the same Apple ID **recovers silently** — no guardians, no paper, no OTP beyond activation. This will be the common case, and it removes most recovery traffic.
- Limits stated honestly in the UI: it only works on the **same Apple/Google account**; it does not survive losing that account; and a user who has disabled iCloud Keychain has nothing here.
- ⚠️ Verify current Block Store and iCloud Keychain guarantees and size limits at build; both have changed before.

### 7.6 Backup files — what they can and cannot do 🔒 (owner-directed, 31 Aug 2026)

**State the true position in the UI, because it is reassuring and correct:** entries are already stored, encrypted, on the server and are never lost with a phone. Backup exists to protect the **key**, and to leave a readable record that outlives even total key loss. Three optional artefacts, each with its trade-off written on the screen that offers it:

| Artefact | What it holds | Restores the app? | Honest risk shown to the user |
|---|---|---|---|
| **Recovery sheet as a file** — Files, iCloud Drive, Google Drive, or print | the same key as the paper sheet | **Yes**, fully | *"Anyone who opens this file can open your books."* Cryptographically identical to the paper sheet; the paper's safety came from being offline |
| **Readable export** — XLSX + PDF, on demand or a monthly schedule | your books in plain, readable form | **No** — it is a record, not a restore | *"This file is readable. Anyone with your Drive can read your books."* Google or Apple **can** read it, unlike anything in the app |
| **Encrypted vault file** — a local `.rukka` file | every envelope, still encrypted | Only **with** a key from another rung | Useless to a thief without the key; equally useless to *you* without it |

🔒 **Defaults 🔒 (owner-directed, 31 Aug 2026): backup is ON, and it is set up during onboarding, not hidden in Settings.**

| Artefact | Default | Set where |
|---|---|---|
| Platform key sync (§7.0) | **On** | stated at onboarding, toggle in Settings |
| Encrypted vault file to the user's own cloud | **On** | onboarding; destination = iCloud Drive / Google Drive |
| Readable export, monthly | **On** ⚠️ *see the tension below* | onboarding, destination picker |
| Recovery sheet saved as a file | **Off** — an explicit action, never automatic | onboarding offers Print / Save |

⚠️ **The one tension, for the owner to hold consciously.** The readable export puts *plain, readable* books into the user's own Drive, where Apple or Google **can** read them — the single place in this product where that is true. Defaulting it on serves this audience correctly: for a shopkeeper or a gurudwara treasurer, losing the books is catastrophic while Google reading them is abstract. It is defensible because it is *their* storage, *their* choice, disclosed in one plain sentence at the moment of setup, with a one-tap off. But it is a real trade against the brand's central claim, so the disclosure must be prominent rather than buried, and must never be reworded into something softer.

**Why the encrypted vault is also on:** it answers a question this audience does ask — *"what if this company disappears?"* With the vault plus any key rung, a family can reopen its books without us. That is worth the storage.

🔒 **The rule that governs all three:** *a backup that can restore without a human is a backup that can be stolen without a human.* The paper sheet is safe because it is offline. Every convenience above trades some of that away, so each is **opt-in**, each states its risk in one plain sentence at the moment of choosing, and none is ever enabled silently.

🔒 **Never backed up anywhere, by any route:** a member's personal-book key wrapped for anyone else, guardian shares in reconstructable form, or any device private key.

🔒 **Every rung restores the personal book too (clarified 31 Aug 2026).** Platform key sync, guardians and the recovery sheet all return the **UMK**, and the UMK unwraps *every* book key the user holds — personal included. There is no separate personal-book backup because there is no need for one: the UMK is the root. The personal book is unreachable only when **all** rungs have failed, and even then not necessarily permanently — recovering the Apple/Google account or finding the sheet later restores it, because the ciphertext is still on the server.

**Answering "the books must never be lost":** the layered answer is platform key sync (§7.0) for almost everyone · guardians (§7.3) when the phone and the Apple account both go · the sheet, paper or file (§7.4) as the offline backstop · and the readable export as the last line — because a family that has lost every key still has a PDF of its books, and can start a fresh book from those closing balances.

### 7.5 Rung 4 — head escrow (opt-in, per member) 🔒
- Scope: the member's **Personal-Book BK only** — never the UMK. Least privilege: the head can eventually read the book; they can never *become* the member.
- Member's device seals Personal BK to the head's UMK; server stores it under a policy object: release only on (a) member's live approval, or (b) head's request + **30-day veto window** during which every member device alarms daily; any member veto cancels and logs.
- Intended for death/incapacity. Opt-in with plain-language disclosure; revocable (revocation rotates the Personal BK).

---

## 8. Rules the implementation must enforce

1. Private keys, shares, and RK never leave a device unencrypted. No plaintext key in logs, crash reports, analytics, or memory dumps (zeroize after use where the platform allows).
2. No book key is wrapped to an unverified fingerprint. Ever.
3. Every envelope's signature chain (§3.4) is verified on read; failures quarantine the envelope and raise a security event — never display unverified content as trusted.
4. All random values from libsodium CSPRNG.
5. Any schema/suite change bumps `suite_version`; old suites remain readable (decrypt-only) for ≥ 2 years.
6. The server's crypto surface is minimal by design: verify Ed25519 auth challenges, store opaque blobs, enforce timers. If server code ever needs a content key, the design has been violated.

---

## 9. Device lifecycle crypto (protocol details in doc 06)

### 9.1 Linking a new device 🔒
Old device runs *Verify member* against the new device's *Show my code* (same ceremony; the QR carries the new device's keys) → old device wraps UMK to the new device's X25519 key and issues its certificate.

### 9.2 Revocation 🔒
**Cut-off is the server `seq` of the signed revocation record, never the HLC (ADR 2026-09-05b §5):** envelopes the device authored before that `seq` stay valid; anything after is quarantined by every reader. A device wipes only on a *verified* signed record — never on a bare server assertion (ADR 2026-09-05b §2).

Any certified device (or k guardians) revokes a device: server deletes its wrapped UMK + sessions and pushes a best-effort remote-wipe. Because the device may retain cache, the UI offers **"This phone was stolen"** → additionally rotates BKs of every book the user can read and (recommended) rotates UMK, re-running §7.3/§7.4 distribution.

---

## 10. Acceptance tests (excerpt — full set in 09-acceptance-tests.md)

- **Given** a raw database dump of the server, **when** inspected, **then** no amounts, party names, account names, or book names are recoverable.
- **Given** an invite in `joined_pending_verification`, **when** any client attempts to wrap a BK to it, **then** the client refuses (unit test) and no wrapped-key upload exists (integration test).
- **Given** a server that swaps the invitee's public key, **when** the inviter scans the true QR, **then** hard-fail mismatch + `verification_mismatch` event.
- **Given** a wrong 8-digit code entered 3×, **then** the nonce is dead and a new *Regenerate* is required.
- **Given** 2 of 3 guardian approvals, **then** the new device decrypts all books and every prior session of that user is revoked.
- **Given** a removed member's device, **when** it pulls post-rotation envelopes, **then** decryption fails for all of them.
- **Given** an envelope re-uploaded under a different `book_id`, **then** AEAD verification fails and the envelope is quarantined.
- **Given** a Personal-Book escrow release request with no member veto for 30 days, **then** and only then the head's device can decrypt that book — and nothing else of the member's.

---

## 11. Open items ⚠️

1. Audited Shamir GF(256) package for Dart/Flutter — or adopt the combination-wrapping fallback (§2).
2. Confirm current Android StrongBox / iOS Secure Enclave capabilities and the X25519 at-rest pattern (§3.3) on target OS versions.
3. Decide guardian minimum at launch: allow 2-of-2, or require ≥3 with paper-sheet mandatory below that.
4. Key-transparency log (append-only public log of key changes per tenant) — valuable hardening; defer to v2, keep table design compatible.
