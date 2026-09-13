# ADR 2026-09-13d — Verification ceremony, code path: eight digits the server cannot pre-compute (commitment-based SAS)

**Status: proposed — awaiting owner ratification.** Prepared by escalation lane M7-K4 (13 Sep 2026,
owner-authorised, budget override) to resolve **ADR 2026-09-13c Open 1**, which lane K3 found and correctly
left alone. A lane never ratifies a 🔒 line: every ruling below is a recommendation with its reasoning
attached, and the checklist at the end lists the answers the owner has to give. **The new primitive is
landed alongside the old one, unratified, because it changes no shipped behaviour and has no production
caller** (§ Consequences); S9.2 / S9.3, which shipped today, keep using the 04 §6.1 code until the owner
ratifies and the server can relay three values (S2).

## 1. The weakness, verified — and sharpened

04 §6.1 derives the code as `decimal(first4bytes(BLAKE2b-256(FP ‖ nonce ‖ "verify-v1"))) mod 10⁸` from a
nonce that is "server-generated at invite creation". 04 §6.3 has the verifier compute the expected code
"from the *server-relayed* keys + nonce" and adds: "3 attempts per nonce; nonce lifetime 10 minutes …
**Rate limits make 8 digits sufficient.**" 06 §3 item 3 has the server hold "the user's registered UMK
public key". In code: `CryptoShowMyCodeRepository._derive` derives the invitee's digits from its own key
and a nonce it fetched from the server (`app/lib/features/ceremony/ceremony_repository.dart:159–163`);
`CryptoVerifyMemberRepository` builds `CodeChallenge(relayed: relayedUmk, nonce: nonce.bytes)` from a key
*and* a nonce the server relayed (`:233–237`); `CodeChallenge.attempt` compares the typed digits with
`verificationCode(FP(relayed), nonce)` and nothing else (`ceremony.dart:235–244`).

So the server knows every input to the honest side's digits — `FP_S` (registered) and `n_S` (its own
nonce) — and chooses every input to the verifier's expected digits — `UMK′` (relayed) and `n_V` (relayed).
Its problem is to make `code(FP_S, n_S) = code(FP′, n_V)` over 10⁸ values, **offline, before anyone types
anything**:

- **One nonce honest, one chosen** (K3's figure): fix `n_S`, search `n_V` — ~10⁸ BLAKE2b evaluations of a
  57-byte message. Measured here through `package:sodium`: 14 µs per hash in a Dart loop, so ~24 minutes
  single-threaded in Dart and seconds in C on one core. A 5-digit prefix fell in 14 788 tries.
- **Both nonces chosen** — which is what the two independent fetches allow: the server generates candidate
  `n_S` and candidate `n_V` and looks for *any* cross-collision. That is a birthday search: ~√10⁸ ≈ 10⁴
  candidates per side, **~2·10⁴ hashes**. B-04-87 runs it inside the push lane in under a second, then feeds
  the honest invitee's digits to the verifier's `CodeChallenge` for the ghost key: **`CeremonyVerified`,
  first attempt, `attemptsUsed == 0`.** The ghost is now a `VerifiedUmkPublic`; book keys would be wrapped
  to it (04 §5.1). No wrong code was ever entered, so nothing was logged.

**Do the existing limits suffice?** No — and this is the one point on which the whole question turns.
"3 attempts per nonce" and "10 minutes" bound an adversary who **guesses** a code *online*: each wrong
guess is an observable attempt, and three of them kill the nonce. The substituting server does not guess.
It **computes**, offline, using inputs it holds or chooses, and needs exactly one online attempt — the
honest human's. The limits are correct for what they were written against and irrelevant here; 04 §6.3's
"Rate limits make 8 digits sufficient" conflates the two adversaries. Documenting the limits and stopping
would leave the code path as a trust root (04 §3.4: "a human scanned a QR **or typed a code**") that the
server can forge in seconds. I agree with K3, and the finding is worse than stated: 2·10⁴, not 10⁸.

## 2. The asymmetry, confirmed: the QR path is sound, the weakness is specific to the code path

`Ceremony.verifyQr` compares the 64 public-key bytes and the `user_id` **from the scanned payload** against
the relayed ones, constant-time, and returns the relayed key only when all agree (`ceremony.dart:377–395`).
The payload's `nonce` field is carried and **never enters the comparison**. Everything the check depends on
therefore arrived over the human channel — the invitee's screen, in person or on a video call — and the
server's only contribution is the very value being checked. A substituted key mismatches (B-04-6; B-04-87
repeats it under the same relay with both nonces in play). The QR path is unaffected by this ADR.

Two consequences follow. **The repair is confined to the code path**: `QrPayload`, the invite nonce inside
it, `verifyQr`, device linking (`verifyDeviceQr`, QR-only) and ADR 2026-09-13c's QR-only recovery ceremony
all stand. And **the code path cannot be treated as a degraded remote-only mode**: design-system §3.1
rule 7 🔒 makes it "an equal alternative, so a blind user or a broken camera never blocks joining" — it is
used *in person* too. Whatever replaces it must be as sound as the scan.

## 3. Option (c) — an honest-relay assumption — is not available

04 §1.1 row 3 names "server substituting a fake member key ('ghost member')" as a threat *defended*, and
names the ceremony as the defence. 04 §3.4 closes with "Root of all trust = a human scanned a QR or typed a
code. **Nothing rests on the server.**" 04 §6.4's channel rule forbids a share button because a forwarded
code "would hand the code to precisely the attacker this ceremony exists to stop". Writing into 04 §1.2
that the code path assumes an honest relay would weaken a 🔒 threat-model row, contradict §3.4's sentence
about typed codes, and contradict rule 7's "equal alternative" — three owner decisions, all to keep a
derivation that was sized against the wrong adversary. As in ADR 2026-09-13c §2: **(c) does not hold.**

## 4. Option (b) — a longer code over a locally generated nonce — is sound, and costs sixteen digits

The invitee's device draws `r_S` itself (never uploaded), shows `r_S ‖ code(FP_S, r_S)` and the human reads
**both** aloud; the verifier's device recomputes `code(FP_relayed, r_S_typed)`. The server never sees `r_S`,
so it must fix `UMK′` blind: its success per attempt is `10^-|r_S| + 10^-8` (guess `r_S`, pre-grind `UMK′`
for the guess; or hope for the collision). Full 8-digit security therefore needs **`r_S` of 8 digits too —
16 digits read aloud**, in groups of four, like a card number. Properties: no server involvement in the
code path at all (the invitee can show a code offline), no live interaction, ~10 lines in `core_crypto`.
Costs: it flips the 🔒 line of **07 §12** ("eight separate character boxes") and the 🔒 line of
**design-system §3.1 rule 7** ("the 8-digit code"), the 13 §3.2 S9.2 row ("QR + 8-digit"), `ceremonyCodeLength`, `MyCode`, the S9.3 entry field
and the ARB copy in three languages ("eight digits"); and it has **no freshness anchor** — a photographed
`(r_S, code)` pair stays valid for that key until the owner adds a coarse time bucket to the hash (which
needs the two clocks to agree within a window). Sound, and the right fallback if the owner will not have
a live relay in the ceremony. **Not recommended**, because (a) keeps every one of those decisions intact.

## 5. Option (a) — commitment-based SAS — holds, keeps eight digits, and is the textbook answer

The class of problem — authenticate a public key over a low-bandwidth channel the humans trust, against a
data channel the adversary controls — is solved by *short authentication string* protocols (Vaudenay 2005;
Bluetooth Secure Simple Pairing's *numeric comparison* uses six digits with exactly this structure). The
principle: **each device contributes randomness the other side cannot see in time**, so no relayed value
can be tuned against the value it would have to collide with.

**Protocol** (three opaque values through the server; nothing else changes):

1. Invitee's device (*Show my code*): draws `r_S` (128-bit), computes `c = BLAKE2b-256("rf-sas-commit-v1" ‖
   FP_S ‖ user_id ‖ r_S)`, relays `c`. Shows the QR as today; the digits are not yet shown.
2. Verifier's device (*Enter code instead*): holding the relayed key, the relayed `user_id` **and `c`** —
   and only then — draws `r_V` (128-bit) and relays it.
3. Invitee's device: on receiving `r_V`, reveals `r_S` (relays it) and shows
   `code = decimal(first4bytes(BLAKE2b-256("rf-sas-code-v1" ‖ FP_S ‖ user_id ‖ r_S ‖ r_V))) mod 10⁸`.
   **Exactly once per `r_S`**; another verifier attempt means a fresh session (*Regenerate*).
4. Verifier's device: checks `c == commit(FP_relayed, user_id_relayed, r_S_relayed)` — a failure here is a
   relay that lied, treated exactly as a QR mismatch (04 §6.3 hard fail, `verification_mismatch`, no
   override) — then compares the typed digits with `code(FP_relayed, user_id, r_S, r_V)` under 04 §6.3's
   unchanged attempt and lifetime rules.

**Why it holds.** The verifier's expected digits are fixed by `(FP′, r′, r_V)`, and the relay had to fix
`(FP′, r′)` inside `c′` *before* `r_V` existed — the verifier does not draw `r_V` without a commitment in
hand (structural: `SasVerifier.begin` takes it). The invitee's shown digits are fixed by `(FP_S, r_S, r_V′)`,
and the relay had to choose `r_V′` *before* it learned `r_S` — the invitee's device opens only in response.
Once it has opened, the session is spent: there is no second code under the same `r_S` to search `r_V″`
against. Every relayed value is therefore fixed before the value it would be tuned against exists, and the
substituting relay is left with **one blind guess in 10⁸ per attempt** — the adversary "3 attempts per
nonce" was always sized for. A replayed honest commitment carries `FP_S` and `user_id` inside it, so it can
open only to the true key and the true person (B-04-89). B-04-88 runs the relay with every power — its own
commitment, its choice of `r_V′`, its choice of opening, 2 000 alternative openings after `r_V` is drawn, a
second response demanded of the invitee's device — and gets `SasOpeningMismatch`, `CodeWrong` or
`StateError` every time.

**Residual, stated honestly.** The same one every 04 §6 ceremony has: one honest device on each side of a
channel where the verifier recognises the person (04 §6.4). A relay can still *withhold* — stall `c`,
`r_V` or the opening, forcing *Regenerate* or a time-out — which is denial of service, already accepted in
04 §1.2 bullet 1. A relay can force a fresh blind guess per session, bounded by the humans' patience and
the permanent verification log (04 §6.4). Eight digits are now sufficient for the reason 04 §6.3 gave,
because the reason is now true.

**Remote mode, checked against 04 §6.4.** On a voice call the verifier taps *Enter code instead*; within a
relay round-trip the invitee's screen shows eight digits; the invitee reads them; the verifier types them.
The code still originates on the invitee's device — the verifier's device is told never to display its
expected digits (§ Rulings 5), so typing stays a real check and there is nothing to share (no share or copy
button, unchanged). Direction stays irrelevant to the UI: the number is the same on both devices, and the
ceremony shape (invitee shows, verifier types) is exactly today's. In person with a broken camera or a
blind invitee: identical, both devices in the same room and online — the nonce fetch already assumed
connectivity for the invitee's device.

**Costs — the switch-over.** (i) Server: a per-invite *ceremony session* record the server stores and
forwards — `commitment` (32 bytes), `verifier_random` (16), `opening` (16), server timestamps — opaque
bytes, no computation (04 §8.6 holds); written by the invitee's device (commitment, opening) and by an
active member's device (`verifier_random`); delivered by realtime or short polling. **S2 is not yet built**
(PLAN Phase B), so this is a design input, not a migration. (ii) `core_crypto`: landed (below). (iii) App:
S9.2 gains one state — *Waiting for {name} to enter the code* — and shows the digits when `r_V` arrives;
S9.3's repository swaps `CodeChallenge` for `SasVerifier` + `SasChallenge` and hands the same sealed
results to the same screen; the eight boxes, the entry field, the countdown and the ARB copy are unchanged.
(iv) Tests: B-04-4 (the 04 §6.1 formula), B-04-7, B-04-9 and B-04-10 (`CodeChallenge`) assert the rule the
switch retires from the member ceremony; **they stay green until the switch — they are correct today —
and take `@Skip('superseded by ADR 2026-09-13d §1; re-lands at M11')` in the switch-over commit**
(ADR 2026-09-05i §4); their behaviour re-lands as B-04-86 and B-04-90, already green.

## Rulings 🔒 (proposed) ⟦tests: n/a — container heading; each ruling below carries its own marker⟧

### 1. The code is a commitment-based SAS over both devices' randomness ⟦tests: B-04-86, B-04-87, B-04-88⟧
- The invitee's device commits to a fresh 128-bit `r_S` as `BLAKE2b-256("rf-sas-commit-v1" ‖ FP ‖ user_id ‖
  r_S)`; the verifier's device draws its 128-bit `r_V` only once it holds the relayed key, the relayed
  `user_id` and that commitment; the invitee's device reveals `r_S` only after `r_V` has arrived. The eight
  digits are `decimal(first4bytes(BLAKE2b-256("rf-sas-code-v1" ‖ FP ‖ user_id ‖ r_S ‖ r_V))) mod 10⁸`,
  zero-padded, on both devices. The invite nonce of 04 §6.1 remains in the QR payload only. ⟦tests: B-04-86⟧
- The 04 §6.1 derivation `BLAKE2b-256(FP ‖ nonce ‖ "verify-v1")` is retired from the member ceremony
  because a relay that holds the registered key and issues the nonces pre-computes it: ~2·10⁴ hashes when
  it relays independent nonces, ~10⁸ when one is honest, one online attempt, rate limits never engaged.
  ⟦tests: B-04-87⟧
- A relay that substitutes the key and controls every relayed value cannot make the honest digits verify:
  its commitment is fixed before `r_V` exists, its `r_V′` before `r_S` is revealed, and neither device
  answers twice. ⟦tests: B-04-88⟧

### 2. One session, one opening, on both sides; a bad opening is a mismatch ⟦tests: B-04-88, B-04-89⟧
- The invitee's device shows at most one code per commitment; a second request under the same `r_S` is
  refused (`StateError`), and *Regenerate* opens a new session. The verifier's device accepts one opening
  per session. ⟦tests: B-04-88⟧
- The commitment binds `FP` and `user_id`: an opening that does not reproduce the relayed commitment
  under the relayed key and id — substituted key, other person, flipped bit, replayed commitment under a
  different key — is `SasOpeningMismatch`, handled exactly as 04 §6.3's QR mismatch: hard fail, *"Do not
  proceed. Contact support."*, `verification_mismatch` logged, no override. ⟦tests: B-04-89⟧

### 3. 04 §6.3's attempt and lifetime rules carry over unchanged ⟦tests: B-04-90⟧
- Three wrong attempts kill the session; the session expires ten minutes after the commitment's **server
  timestamp** (expired at 10:00.001, not at 10:00.000 — the 09 §2 convention); expiry spends no attempt; a
  malformed entry is a wrong attempt; success retires the session; whitespace read in pairs is tolerated.
  ⟦tests: B-04-90⟧

### 4. The wire: three opaque values the server stores and forwards ⟦tests: E-13d-1 @M11⟧
- Per ceremony session the server holds `commitment` (32 bytes), `verifier_random` (16), `opening` (16)
  and their timestamps, and computes nothing (04 §8.6). The invitee's device writes the commitment and the
  opening; only an already-verified active member's device (04 §6.4 *delegated*) writes `verifier_random`;
  a session is immutable once written (append-only, like the invite row). ⟦tests: E-13d-1 @M11⟧

### 5. Screens: the digits appear on demand; the verifier's device never shows its expected code ⟦tests: F1-13d-1 @M11, F1-13d-2 @M11⟧
- S9.2 shows the QR at once and the eight boxes filled only once `r_V` has arrived; until then the boxes
  read *Waiting for {name} to enter the code* (a 13 §4.3 state, design owner). The eight boxes, the
  countdown and the no-share rule (04 §6.4, 07 §12) are unchanged. ⟦tests: F1-13d-1 @M11⟧
- S9.3 keeps its camera-first shape and *Enter code instead*; its device never displays the digits it
  expects, so typing remains the check and nothing on either screen can be forwarded. `SasOpeningMismatch`
  routes to S9.4 exactly as `CeremonyMismatch` does. ⟦tests: F1-13d-2 @M11⟧

### 6. Nothing switches before ratification and the relay ⟦tests: n/a — sequencing rule, not behaviour⟧
- Until the owner ratifies and S2 relays the three values, S9.2 / S9.3 keep the 04 §6.1 code as shipped
  on 13 Sep 2026. `verificationCode` and `CodeChallenge` are not removed by this ADR; the switch-over
  commit `@Skip`s B-04-4, B-04-7, B-04-9 and B-04-10 per ADR 2026-09-05i §4 and swaps the repository.
  Option (b) of § 4 is the recorded fallback if the owner declines a live relay in the ceremony.

## Consequences
- **Code (landed, `packages/core_crypto`):** `lib/src/ceremony.dart` gains, *below* the unchanged existing
  code, `sasCommitment`, `sasCode`, `SasShower` / `SasResponse` (invitee side), `SasVerifier` /
  `SasOpenResult` (`SasOpened`, `SasOpeningMismatch`) and `SasChallenge` (verifier side), reusing the
  sealed `CeremonyResult` family so the S9.3 seam is unchanged at switch-over. Kept inside `ceremony.dart`
  so K2's B-04-80 ("`VerifiedUmkPublic.internal` only in keys.dart and ceremony.dart") stays true and
  green. Purity unchanged: randomness from the injected suite, the clock as `nowMs`, no I/O; all hashing
  BLAKE2b-256 through libsodium; every hashed field fixed-length under a distinct domain tag. New
  `test/sas_test.dart`: B-04-86 … B-04-90. Package **91/91**; no existing test or assertion touched.
- **Code (not landed — needs the owner and S2):** the app switch (S9.2 waiting state, S9.3 repository) and
  the server session record. Nothing in `app/lib/features/ceremony` was changed by this lane: the screens
  shipped today and the switch cannot land without the relay.
- **Docs (owner applies on ratification — this lane edits no numbered spec):**
  - 04 §6.1 third bullet → the ruling-1 derivation and commitment; note that the invite nonce stays in the
    QR payload only. Marker on the §6 heading gains `B-04-86, B-04-87, B-04-88, B-04-89, B-04-90`.
  - 04 §6.2 *Show my code*: "the 8 digits printed beneath" → "the 8 digits printed beneath once the
    verifier has begun (ADR 2026-09-13d §5)".
  - 04 §6.3 code path → "verifier's device holds the server-relayed keys and the relayed commitment before
    drawing `r_V`; checks the relayed opening against the commitment (mismatch → hard-fail as for QR); then
    compares the typed digits. 3 attempts per session; lifetime 10 minutes from the commitment's server
    timestamp; *Regenerate* opens a fresh session. **Rate limits bound guessing; the commitment is what
    makes 8 digits sufficient against the relay** (ADR 2026-09-13d §1)." Delete "Rate limits make 8 digits
    sufficient."
  - 04 §10: add "Given a server that substitutes the invitee's key and relays commitments, contributions or
    nonces of its choosing, when the inviter types the code the invitee reads aloud, then the result is a
    mismatch or a wrong code — never verified." ⟦B-04-87 (old path fails it), B-04-88 (new path meets it)⟧
  - 04 §1.2 and §3.4: **no change** — "Nothing rests on the server" and "typed a code" are kept true by
    this ADR rather than relaxed.
  - 06 §7 *invited* row: the 128-bit ceremony nonce stays (QR payload); the code path's per-session values
    live in the ceremony session record of ruling 4 (S2).
  - 07 §12 ceremony line: the eight boxes fill when the verifier has begun; wording per ruling 5 — a
    presentation change to a 🔒 owner-approved line, so the owner's to make.
  - 13 §3.2 S9.2 row: state *waiting for verifier*; 13 §4.3: the state's copy (design owner).
- **Milestone:** rulings 1–3 landed as `core_crypto` API at M7 (unratified, alongside); rulings 4–5 and the
  switch-over at **M11** per the lane brief (`@M11` markers below) — the owner may pull them forward to
  M7's S2 / U4 lanes on ratification, since the relay is S2's to build and the members+ceremony lane is
  U4's; the markers then move with them.

## Ids reserved (`check_coverage` reports the `@M11` ones as planned until the tests land)
| Id | Ruling | One-line test |
|---|---|---|
| B-04-86 (landed) | 1, 3 | honest run end to end; commitment and code formulas pinned by hand; determinism under the seeded suite; fresh `r_S` per session; lengths and ids refused, never guessed |
| B-04-87 (landed) | 1 (finding) | the shipped path falls: both nonces relay-chosen → birthday collision in the push lane → honest digits verify the ghost key first attempt, `attemptsUsed == 0`; one-sided 4-digit prefix grind; the QR path under the same relay hard-fails |
| B-04-88 (landed) | 1, 2 | the relay with every power — honest commitment forwarded, own commitment, own `r_V′`, own opening, 2 000 alternative openings after `r_V`, a second response demanded — never gets the honest digits verified; both sides single-use |
| B-04-89 (landed) | 2 | commitment binds FP and user_id: substituted key, other person, half-swapped key, flipped bit in opening or commitment → `SasOpeningMismatch`; replay of an honest session opens only to the true key and its old code no longer verifies |
| B-04-90 (landed) | 3 | 3 wrong → exhausted, right code dead; 10:00.000 live, 10:00.001 expired, no attempt spent; garbage is wrong; success retires |
| E-13d-1 @M11 | 4 | ceremony session row: opaque bytes, invitee writes commitment/opening, only an active member writes `verifier_random`, immutable once written, no server-side computation |
| F1-13d-1 @M11 | 5 | S9.2: boxes empty with *Waiting for {name}…* until `r_V` arrives, then eight digits; no share/copy control in the tree |
| F1-13d-2 @M11 | 5 | S9.3: *Enter code instead* runs `SasVerifier`; the expected digits are nowhere in the tree; `SasOpeningMismatch` hands off to S9.4 with the event written |

## Ratification checklist — five answers for the owner 🔒 ⟦tests: n/a — heading; each answer below carries its own marker⟧
1. **Rulings 1–3** — the code path becomes the commitment-based SAS, eight digits kept: **yes / no.**
   ⟦tests: B-04-86, B-04-88, B-04-90⟧
2. **(a) or (b)** — if the live relay in the ceremony is unwelcome, adopt § 4's sixteen-digit local code
   instead (flips the 🔒 lines of 07 §12 and design-system §3.1 rule 7; no server surface): **(a) / (b).**
   ⟦tests: n/a — the choice; (a) is B-04-86…90, (b) would mint B-04-91⟧
3. **Ruling 4** — the ceremony session record as S2 design input: **yes / no.** ⟦tests: E-13d-1 @M11⟧
4. **Ruling 5** — digits appear on demand on S9.2; the verifier's device never displays its expected code:
   **yes / no.** ⟦tests: F1-13d-1 @M11, F1-13d-2 @M11⟧
5. **Milestone** — leave the switch-over at M11 as briefed, or pull it to M7 (S2 + U4) so the shipped code
   path is never in production: **M11 / M7.** ⟦tests: n/a — scheduling⟧

## Open ⚠️
1. Design (07/13 owner): S9.2's *Waiting for {name} to enter the code* state and its copy in EN/PA/HI;
   S9.3 unchanged in shape.
2. S2 (server lane): the ceremony session record and its RLS per ruling 4; delivery — realtime channel or
   short polling of the invite — is the sync/server owners' call (05d).
3. Whether the `verification_event` of a SAS ceremony should carry the session's commitment hash for the
   permanent log (04 §6.4) — useful for audit, no security role; 05d §7 owner.
4. Not checked: nothing in the S2 or U4 lane briefs yet names this ADR — the orchestrator should add it to
   both rows so the relay and the switch are built once, not retrofitted.
5. The other 04 §6 uses of the code path (guardian setup, trustee handover) inherit the change through the
   same two screens; no separate ruling needed, but the owner should confirm that reading.
