# ADR 2026-09-13c — Recovery rung 2: the UMK a fresh device recovers into is verified by a human, never taken from the server

**Status: proposed — awaiting owner ratification.** Prepared by escalation lane M7-K3 (13 Sep 2026,
owner-authorised) to resolve the protocol weakness lane M7-K2 found and correctly declined to change
(`.claude/lane-reports/M7-K2.json`, open item 1). A lane never ratifies a 🔒 line: every ruling below is a
recommendation with its reasoning attached, and the ratification checklist at the end lists the answers
the owner has to give. **One half is landed unratified because it only tightens a type and breaks no
caller** (§ Consequences); the protocol half waits for the recovery UI at M11 and for this ADR.

## 1. The weakness, verified

04 §7.3 step 4 says the recovering device "verifies the re-derived public key against **the user's known
UMK**". On the device that needs it — a fresh phone after OTP, uncertified, holding nothing but its own
keys (06 §3 item 3) — nothing user-held pins that value. The only copy in reach is the server's: 06 §3
item 3 has the server hold "the user's registered UMK public key". `GuardianShareSet.reconstructVerified`
accordingly took `expected` as a plain `UmkPublic` (`shamir.dart:578` before this lane), the type
`keys.dart` documents as "UMK public halves **as relayed by the server** … Not yet bound to a human".

A malicious server (04 §1.1 row 1 names it) therefore runs this:

1. The fresh device uploads its candidate public key (04 §7.3 step 1). The server now knows where the
   shares will be addressed.
2. The server generates its own key pair UMK′ and relays UMK′_pub as the user's registered key.
3. The server splits UMK′_priv itself and seals k shares to the candidate key. `crypto_box_seal` (04 §2)
   is sender-anonymous: a box the server made is indistinguishable from one a guardian re-sealed. The
   real guardians need never be contacted.
4. The device reconstructs UMK′_priv, re-derives UMK′_pub, compares it with `expected` = UMK′_pub — **the
   check passes** — self-certifies under UMK′ (step 6) and believes it has recovered.

What it yields, stated precisely (this refines K2's report, which had the ceremony protecting shared books):

- **Nothing already sealed.** Every existing wrapped BK is sealed to the real UMK_pub; UMK′ opens none of
  them, and the server can only withhold them. The real books stay dark to the server.
- **Everything sealed afterwards.** A new personal book's BK is wrapped to UMK′ (04 §5.2) and is
  server-readable. And if the family follows 06 §5's "every rung fails" remedy — re-wrap shared books to
  the user's *new* UMK after a fresh ceremony — those BKs go to UMK′ too, because the 04 §6 ceremony binds
  a key to a **human** (scanned bytes = relayed bytes, both UMK′) and cannot tell a device-generated key
  from a server-generated one that the human's device holds. The ceremony is the right tool for *ghost
  members*; it does not detect a *ghost self*.
- **Detection exists but is human-dependent:** the UMK′ certificate fails under the tenant's
  ceremony-verified copy of the real UMK (`ChainVerifier` → `certInvalid`, security event, 04 §8.3), and
  the user sees a "successful" recovery with an empty vault. Neither stops the flow.

Reconstruction-time verification (ADR 2026-09-06 §2) is still sound for what it was adopted for — a
tampered, truncated or replayed share (B-04-57, B-04-72, B-04-77) — because a *guardian* cannot replace
the pinned public key. A *server* can, when the pinned key is its own copy. The value is only as good as
its provenance, and the provenance was left open.

**No other rung has this gap.** Rung 3 authenticates the UMK by AEAD under RK, which lives on paper and
never on the server — a forged `sealed_RK_blob` fails to decrypt (`openUmkWithRecoveryKey`,
`RecoveryUnsealFailed('aead')`). Rung 1 has the *old* device, which holds the UMK, wrap it to a
ceremony-verified new device (`wrapUmkToDevice(VerifiedDevicePublic)`). Rung 0 rests on Apple/Google, not
on this server, and its compromise is already accepted (04 §1.2 last row). Rung 2 is the one rung in which
the key arrives from *other people's devices, through the server*, at a device that holds nothing to check
it against — which is exactly why it needs a human channel.

## 2. Why this is in scope, and (c) fails

04 §1.1 defends against "server breach / malicious insider" ("server holds only ciphertext and wrapped
keys **it cannot open**") and against "server substituting a fake member key" (row 3). 04 §1.2's accepted
list says a malicious server "**cannot alter or read** it". 04 §3.4 closes with "**Nothing rests on the
server.**" A recovery that lets the server choose the key the user recovers into contradicts all three
lines. Accepting it — option (c) — would mean *weakening* a 🔒 threat-model claim by ADR, to save one QR
scan that reuses machinery already shipped (S9.2/S9.3). It also violates the spirit of 04 §8.2 and
CLAUDE.md rule 5: the UMK is strictly more sensitive than any book key, and the protocol was about to have
a device adopt one on an unverified fingerprint. **(c) does not hold.**

## 3. Option (b) is circular; the variant that is not costs k ceremonies

(b) has each guardian sign the re-sealed share with its device key. The fresh device must then verify:
sig ✓ under guardian device key → guardian cert ✓ under the guardian's UMK → **that UMK verified by
ceremony**. The trust chain of 04 §3.4 bottoms out in `TrustStore.verifiedUmkOf` — a human verification
the reader already holds. A fresh device holds none (`ChainVerifier` → `authorUnverified`, B-04-39). The
user's *old* device had verified the guardian, but that fact reaches the new device only as a
`verification_event` signed record (ADR 2026-09-05d §7) whose chain roots in **the user's own UMK — the
key being recovered.** If the device takes that root from the server, the server fabricates a ghost
guardian — UMK_g′, a self-issued cert, a signed share — and the whole chain verifies (B-04-84 pins both
halves). A signature proves nothing the relay did not already assert. **Confirmed circular; (b) is not a
resolution.**

The non-circular variant — the fresh device first verifies each *guardian's* key by ceremony, then
accepts that guardian's signed share — works, but needs k human ceremonies instead of one, a new
signed-share wire format, and guardian device certificates on the fresh device, to authenticate the
*sources*; whereas the thing `reconstructVerified` actually needs is the *target*. Once the target is
verified (§4), the key itself authenticates the shares (ADR 2026-09-06 §2), and (b) adds nothing.

## 4. Option (a) holds — and it is the existing ceremony, pointed at the user's own key

Every guardian's device already holds the user's UMK as a `VerifiedUmkPublic`: guardian setup is a
**mutual** ceremony (04 §6.4), so the guardian's device compared the user's key byte-for-byte against the
relay at setup and recorded it. During recovery the requester is already told to call a guardian (04 §7.3
step 2); on that call, or in person, the guardian's device renders the user's key as the 04 §6.1
`QrPayload` — the same bytes S9.2 shows for one's own key, now rendered for someone else's — and the fresh
device scans it and runs 04 §6.3's QR check against the server-relayed registered key. Equal → a
`VerifiedUmkPublic` exists and reconstruction may proceed. Unequal → the ceremony's hard fail: *"Do not
proceed. Contact support."*, `verification_mismatch`, no override. The server can no longer substitute
UMK′ without also controlling what the guardian's screen shows.

**Not circular.** The root is the one 04 §3.4 already names — *a human scanned a QR* — plus the guardian's
own earlier ceremony. No signature is verified under the UMK being recovered. The machinery is shipped
(`QrPayload`, `Ceremony.verifyQr`, S9.2/S9.3); the wire format is unchanged; `reconstructVerified` gains
no field.

**Residual, stated honestly.** The attack now needs the server *and* the device the user scanned from
(a colluding guardian, or malware on their phone — 04 §1.2's malware row). That is the same
single-verifier assumption every 04 §6 ceremony makes: one honest human with an honest device on the far
side of a channel the user recognises. Requiring two independent scans would tighten the bound to
server + two devices at the cost of a second call; not recommended (checklist 4), but it is the owner's
knob. Any already-verified active member may show the key, not only a guardian (04 §6.4 *delegated*), so
the user picks whom to trust with the scan.

**Why QR only.** The 8-digit code is `first4bytes(BLAKE2b-256(FP ‖ nonce ‖ "verify-v1")) mod 10⁸`, and
04 §6.3 has the verifier compute it from *server-relayed* keys and a *server-relayed* nonce while the
shower's nonce is *server-issued* — two independent deliveries. A server that substitutes FP′ can search a
nonce′ such that the two codes collide in about 10⁸ offline hashes (minutes on a laptop); with the nonce
held equal it can grind UMK′ itself for the same 10⁸ (hours). Eight digits resist *online* guessing under
rate limits, which is what they were sized for; they do not resist the party that controls one side's
inputs. The QR path compares all 64 key bytes and is unaffected. This is a pre-existing property of the
code path (§ Open 1), not something recovery introduces; the ruling simply does not admit the weak path at
the one moment the UMK itself is at stake.

## Rulings 🔒 (proposed) ⟦tests: n/a — container heading; each ruling below carries its own marker⟧

### 1. `expected` is a `VerifiedUmkPublic`, produced by the recovery ceremony ⟦tests: B-04-82, B-04-83, B-04-84, F1-13c-1 @M11⟧
- `GuardianShareSet.reconstructVerified` accepts only `VerifiedUmkPublic` for `expected`; the server's
  registered copy (`UmkPublic`) cannot be passed. This is the type-level half, **landed 13 Sep 2026**:
  stricter API, no production caller existed, no existing assertion weakened. ⟦tests: B-04-82⟧
- **The recovery ceremony:** before 04 §7.3 step 4 the fresh device scans the user's own UMK from the
  device of an already-verified active member of the tenant — normally the guardian it is calling — which
  renders it as the 04 §6.1 `QrPayload` from its ceremony-verified copy. The fresh device compares the
  scanned keys and `user_id` byte-for-byte against the server-relayed registered key (04 §6.3 QR path).
  Equal → `VerifiedUmkPublic`, and only then may shares be reconstructed. Unequal → hard fail, log
  `verification_mismatch`, no override, recovery attempt closed. ⟦tests: B-04-82, B-04-83, F1-13c-1 @M11⟧
- A server that substitutes both the registered key and the sealed boxes never obtains a reconstruction:
  the ceremony fails before it; a server that relays the true key to pass the ceremony but substitutes the
  boxes fails at `GuardianShareMismatch`. ⟦tests: B-04-83⟧
- The residual is server + the one device scanned from; one scan, as in every other ceremony, unless the
  owner chooses two (checklist 4). ⟦tests: B-04-83⟧
- Option (b) — guardian-signed shares — is not adopted: on a fresh device its chain roots in the key
  being recovered (§ 3), so the signature adds nothing the relay did not already assert. ⟦tests: B-04-84⟧

### 2. QR path only, in person or over video; no code path at recovery ⟦tests: F1-13c-2 @M11⟧
- S11.2 offers *Scan your guardian's screen* and nothing else for this step; *Enter code instead* is
  absent. 04 §6.4's remote mode (scan off a video call) applies. Reason: § 4, *Why QR only*. ⟦tests: F1-13c-2 @M11⟧

### 3. The mirror direction: a guardian re-seals only to a ceremony-verified candidate ⟦tests: B-04-85 @M11, F1-13c-3 @M11⟧
- The same substitution run the other way is worse: a server that swaps the candidate public key in
  04 §7.3 step 2 has k guardians re-seal the **real** shares to a server key and reconstructs the real UMK.
  04 §7.3 step 2 already carries the defence — "new device fingerprint + *Call them before approving*" —
  as **advice**. It becomes a **check**: the fresh device shows its candidate key as the 04 §9.1
  `DeviceQrPayload`; the guardian's device scans it and compares against the relayed recovery request
  (`Ceremony.verifyDeviceQr`); the re-seal accepts only the verified type. Together with ruling 1 this is
  one mutual ceremony on one call — the shape guardian setup already has (04 §6.4). ⟦tests: B-04-85 @M11, F1-13c-3 @M11⟧
- `core_crypto` will expose no function that seals share bytes to a bare `UmkPublic` or X25519 key; the
  M11 re-seal function's recipient parameter is `VerifiedDevicePublic` (or a verified candidate type built
  the same way, by `ceremony.dart` alone). Not landed now: no caller exists and nothing today can be
  misused for it (`sealToVerified` takes a UMK-shaped verified type; `wrapUmkToDevice` seals a
  `UmkKeyPair`, which a guardian does not hold). ⟦tests: B-04-85 @M11⟧

## Consequences
- **Code (landed, `packages/core_crypto`):** `shamir.dart` — `reconstructVerified(…, {required
  VerifiedUmkPublic expected})`, comparing against `expected.public`; doc comment names this ADR. Tests
  B-04-72, B-04-77, B-04-78 and B-04-80 now obtain `expected` through the real ceremony
  (`helpers.verifiedUmk`) — same assertions, stricter input; B-04-80's closing note points here. New
  `test/recovery_provenance_test.dart`: B-04-82 (type + honest mutual-ceremony path end to end),
  B-04-83 (the attack, every combination, and the residual bound), B-04-84 (the circularity of (b) with an
  empty store and with a relay-seeded store). Package 86/86.
- **Code (M11, recovery lane):** S11.2 gains the scan step before *Ask your guardians* can complete;
  S11.7 gains *Show {name}'s key* (renders `QrPayload` from `TrustStore.verifiedUmkOf(user)`) and, for
  ruling 3, *Scan their new phone*; the re-seal function per ruling 3; the verification event for the
  recovery ceremony is authored by the newly certified device after step 6 (its certificate exists only
  then — 05d §7 owner to confirm, or the showing device authors it).
- **Docs (owner applies on ratification — this lane edits no numbered spec):**
  - 04 §7.3 step 4: "…verifies the re-derived public key against the user's known UMK" → "…against the
    user's UMK **as verified in the recovery ceremony — a `VerifiedUmkPublic`, compared against the
    server's registered copy and never taken from it** (ADR 2026-09-13c §1)"; marker gains
    `B-04-82, B-04-83`.
  - 04 §7.3 step 2: "prominent advice: *Call them before approving*" → the mutual check of ruling 3;
    marker gains `B-04-85 @M11`.
  - 04 §7.3 **Recovery** list: a new step between 2 and 3 — the recovery ceremony (ruling 1) — and the
    QR-only sentence (ruling 2).
  - 04 §6 first paragraph: "One component, four uses" → five (recovery: the fresh device verifies its own
    key from a member's screen).
  - 04 §1.2: no change — the claim "cannot alter or read" is *kept true* by this ADR rather than relaxed.
  - 06 §5 "New phone, no old device" row: "guardians → paper sheet" → "guardians (**scan your key from a
    guardian's screen**, then k approvals) → paper sheet".
  - 07 §… S11.2 / S11.7 and 13 §3.2 rows S11.2 / S11.7: the new states (design owner — no such state is
    drawn today, same gap ADR 2026-09-06 Open already lists for *2 of 3 approved*).
- **Milestone:** ruling 1 type half M7 (landed); rulings 1–3 protocol and UI at **M11** (10: "Recovery &
  escrow").

## Ids reserved (`check_coverage` reports the `@M11` ones as planned until the tests land)
| Id | Ruling | One-line test |
|---|---|---|
| B-04-82 (landed) | 1 | signature scan: only `VerifiedUmkPublic expected`; guardian shows the user's verified key as `QrPayload`, fresh device verifies against the honest relay, k re-sealed shares reconstruct |
| B-04-83 (landed) | 1 | server substitutes registered key + boxes → `CeremonyMismatch`, nothing to reconstruct against; true key + forged boxes → `GuardianShareMismatch`, caller's shares intact; mixed sets fail; the collusion bound (scanned device shows UMK′) is documented as the residual |
| B-04-84 (landed) | 3 (reasoning) | empty `TrustStore` → every guardian-signed record `certMissing`/`authorUnverified`; relay-seeded store → a server-fabricated guardian chain verifies end to end; human-verified guardian root → real record verifies, forged one `certInvalid` |
| B-04-85 @M11 | 3 | the share re-seal function's recipient parameter is a `Verified*` type; no seal of share bytes to `UmkPublic`/raw X25519 exists in `lib/` |
| F1-13c-1 @M11 | 1 | S11.2: *Ask your guardians* cannot reach the reconstruction state without a `CeremonyVerified`; a `CeremonyMismatch` renders the hard-fail screen and closes the attempt |
| F1-13c-2 @M11 | 2 | S11.2 recovery ceremony offers scan only — no *Enter code instead* control exists in the tree |
| F1-13c-3 @M11 | 3 | S11.7: *Approve* is disabled until the guardian has scanned the requester's `DeviceQrPayload` and it matched the relayed request |

## Ratification checklist — five answers for the owner 🔒 ⟦tests: n/a — heading; each answer below carries its own marker⟧
1. **Ruling 1** — `expected` is a `VerifiedUmkPublic` from a recovery ceremony against a member's screen;
   the type half is already landed: **yes / no.** ⟦tests: B-04-82, B-04-83⟧
2. **Ruling 2** — QR path only at recovery, video call permitted, no code path: **yes / no.** ⟦tests: F1-13c-2 @M11⟧
3. **Ruling 3** — the guardian's re-seal goes only to a ceremony-verified candidate (advice → check):
   **yes / no.** ⟦tests: B-04-85 @M11, F1-13c-3 @M11⟧
4. **One scan or two** — recommended **one** (matches every other ceremony; residual = server + the
   scanned device). Two tightens to server + two devices at the cost of a second call. ⟦tests: B-04-83⟧
5. **§ Open 1** (the code path against a nonce-choosing server) — a separate ADR on 04 §6.3, or fold into
   this one: **owner's call.** ⟦tests: n/a — process decision⟧

## Open ⚠️
1. **04 §6.3 code path vs a malicious server** (04 §6 owner; not fixed here — outside K3's blocker and a
   🔒 protocol step). Evidence: `ceremony.dart` `CodeChallenge(relayed, nonce)` takes the verifier's nonce
   from the relay (`app/lib/features/ceremony/ceremony_repository.dart:233–237`) while
   `CryptoMyCodeRepository._derive` takes the shower's nonce from the server separately (`:160–164`), and
   the code is 10⁸ values. A server that relays FP′ with a nonce′ chosen so `code(FP′, nonce′) =
   code(FP, nonce)` passes the code-path ghost-member check with ~10⁸ offline hashes. Settles it: a
   commitment-based short-authentication-string exchange, or a longer code over a nonce the *shower's*
   device generates and that travels *with* the code over the human channel; or accept and document in
   04 §1.2 that the code path assumes an honest relay. Not checked: whether 04 §6.4's remote-mode users
   would tolerate a longer code.
2. Design: S11.2 *Scan your guardian's screen* and S11.7 *Show {name}'s key* / *Scan their new phone*
   states — 07/13 owner, before M11 (joins ADR 2026-09-06's *2 of 3 approved* gap).
3. Who authors the recovery ceremony's `verification_event` record — the newly certified device after
   step 6, or the showing device (05d §7 owner).
4. The 04 wording edits listed under Consequences are the owner's to apply; until then 04 §7.3 step 4 reads
   "known UMK" while the code requires a verified one — the code is stricter than the line, not different.
