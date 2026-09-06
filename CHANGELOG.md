# Changelog — Rukka Folio

Running record of what changed in this repository and in the development environment, one entry per working session. Newest first. Kept by hand at the end of every session, before the owner commits; the commit hash is filled in afterwards.

**How to write an entry**

- Heading: `## YYYY-MM-DD — <milestone or slice>` (use `env` for toolchain/environment work, `docs` for spec-only sessions).
- Sections, each optional: **Added**, **Changed**, **Decided** (link the ADR in `docs/decisions/`), **Open** (⚠️ items handed to the owner), **Commits** (hashes once committed).
- Record *what* and *why*, not the diff — git holds the diff. One line per item.
- A 🔒 change is never recorded here alone; it needs an ADR in the same commit.
- No financial data, keys or secrets — this file is committed.

---

## 2026-09-06 — M3 follow-up: Shamir ADR reviewed — verified reconstruction, independent known-answer vector, ruling 3 sharpened

Evening pass over `docs/decisions/2026-09-06-shamir-and-guardian-revocation-records.md` at the owner's request ("what does it mean, any suggestions — do the best of your knowledge"). Three findings acted on, two owner decisions surfaced, and the ADR now ends in a four-line ratification checklist. Still **proposed**. `core_crypto`: 75 tests (+B-04-72, B-04-73), all green.

**Added**
- `GuardianShareSet.reconstructVerified(suite, shares, expected:)` + `GuardianShareMismatch` — reconstruct, re-derive both UMK public halves from the 64 bytes, compare (constant time) with the UMK public key the recovering device already holds; fail closed with the bytes zeroised. Closes the "tampered share yields a wrong secret silently" gap (B-04-57) **without a new field** — the BLAKE2b(UMK_priv)-beside-the-shares option is withdrawn (a digest travelling with the shares can be replaced with them; the pinned key cannot). B-04-72.
- `packages/core_crypto/test/vectors/shamir_ref.py` — a second, table-free GF(256) Shamir (Russian-peasant multiply, brute-force inverse) written without consulting `shamir.dart`; B-04-73 replays its 3-of-5 vector on the combine side (every subset, both orders) and, through a scripted RNG, reproduces the shares byte for byte on the split side. Every earlier test was self-consistent; this is the first cross-implementation check. A third-party vector (libgfshare / Vault) is still wanted before the external review.

**Changed**
- ADR 2026-09-06 §3 gains the two rules a counting scheme needs: (a) the cut-off is the k-th *smallest* `seq`, so it can only move **earlier** as approvals arrive — deterministic across devices, conservative, but it means re-quarantine on Recompute and the cut-off is never cached as final; (b) a **re-split does not reset the count** — the device under revocation is still certified and could otherwise bump `share_set_version` to discard k−1 approvals; records count against the version they name, carry across versions, threshold = k of the earliest counted version (⚠️ SPEC: proposer's choice). Counting set reworded from "current set" to "set at the version the record names".
- ADR §3 marker `n/a` → reserved ids **D-06a-1…4** with one-line tests (table in the ADR); `check_coverage` reports them dangling until M4 — intended (05i §1 warn-only until then).
- ADR §1/§2 markers gain B-04-73 / B-04-72; 04 §2 (ADR quote line) and §7.3 markers likewise. ADR consequences: M4 meta channel needs guardian-set *history* by `share_set_version`; 07 has no state for "2 of 3 approved" or a moved cut-off.

**Decided** — nothing 🔒 ratified; recommendation recorded for 04 §11.3: default 2-of-3, n = 2 allowed only behind a typed confirmation (2-of-2 has no loss tolerance *and* needs both guardians — but forbidding it excludes a two-person household).

**Open** ⚠️
- **Owner: the four-line ratification checklist at the end of the ADR** (rulings 1, 2, 3 incl. earliest-k vs current-k, and 04 §11.3).
- 07 owner: screen states for a pending k-of-n revocation and for a re-quarantine after the cut-off moved — before M11.
- External review of `shamir.dart` before M14, with a third-party KAT pasted in first.

**Commits** — pending.

---

## 2026-09-06 — M3: crypto core (suite B) — envelopes, key hierarchy, ceremony, signed records, trust chain, Shamir

First and only M3 slice. A shared skeleton (suite, bytes, key types, test helpers) was written first; three agents then filled disjoint modules in parallel — ceremony/wrapping/recovery · padding/envelope/certs/signed records/chain · Shamir — and the data package was wired to the new crypto boundary. One agent lost its session to a rate limit after its five library files; its three missing test files were written by hand. `core_crypto`: 73 tests (B-04-1…71 with gaps, B-05b-1…8, B-10-1). `data`: 30 tests (+E-04-1…3). Push gate green. **M3 exit reached** (10 M3 row: suite B) — tag after committing: `git tag m3-crypto-core`.

**Added — `packages/core_crypto`**
- **Foundation.** `sodium: ^4.1.0` (pure-Dart libsodium FFI; v4 builds libsodium 1.0.22 through Dart build hooks, so `dart test` needs no system library — the Homebrew libsodium installed today is unused). `CryptoSuite` is the single injection point (`Sodium` + `RandomBytes`; `blake2b256`, `randomBytes`, `randomSecureKey`, `constantTimeEquals`, `zeroize`); `suiteVersion = 0x01`. `Bytes`/`Uuid16` canonical encodings for everything that enters AAD or a signature (uuids as 16 bytes, u32/i64 big-endian, length-prefixed UTF-8). Test helpers: deterministic `testSuite(seed:)` (RNG = BLAKE2b(seed ‖ counter)), `verifiedUmk(...)` through the real ceremony, `MapTrustStore`.
- **Key types (04 §3).** `Fingerprint` = BLAKE2b-256(x25519 ‖ ed25519); `UmkPublic` (server-relayed, unverified) vs `VerifiedUmkPublic` (ceremony-only `@internal` constructor — 04 §8.2 is structural: a book key, guardian share or UMK can only be sealed to a verified type; `VerifiedDevicePublic` likewise for linking); `UmkKeyPair` (⚠️ SPEC: `UMK_priv` = 64 bytes `x25519_seed ‖ ed25519_seed`, pairs re-derived with `seedKeyPair`); `DevicePublic`/`DeviceKeyPair`; `BookKeyRef`/`BookKey`. Every holder has an idempotent `dispose()` and throws `StateError` on use after dispose — reading freed guarded memory segfaults the VM (found by B-04-70).
- **Ceremony (04 §6, §9.1).** `QrPayload` (`base64url(suite ‖ user_id ‖ UMK_pub_ed ‖ UMK_pub_x ‖ nonce)`), `verificationCode` (8 digits from BLAKE2b-256(FP ‖ nonce ‖ "verify-v1")), `Ceremony.verifyQr` (byte-for-byte, constant time; mismatch has no override), immutable `CodeChallenge.attempt(typed, nowMs)` (3 attempts per nonce, 10-minute lifetime, exhausted nonce dead even for the right code), `DeviceQrPayload` + `verifyDeviceQr` for linking.
- **Wrapping (04 §5, §7.5, §9.1).** Generic `sealToVerified`/`openSealed` (`crypto_box_seal`, typed `UnsealFailed`); `wrapBookKey`/`unwrapBookKey`; `wrapUmkToDevice`/`unwrapUmk`; `rotateBookKey` → v+1 wrapped to each remaining member, never the leaver; `sealPersonalBookKeyForHead` (BK only, never the UMK).
- **Recovery (04 §7.4).** `RecoveryKey`, `sealUmkUnderRecoveryKey`/`openUmkWithRecoveryKey` (XChaCha20-Poly1305 over the 64 secret bytes), sheet QR `base64url(version ‖ user_id ‖ RK)` and typed Crockford-Base32 fallback in groups of 4 with a 2-char checksum (⚠️ SPEC: first 10 bits of BLAKE2b-256(version ‖ user_id ‖ RK); decoder accepts O/I/L aliases and lowercase).
- **Padding (ADR 05b §8).** `padPlaintext`/`unpadPlaintext` via `sodium_pad`: 1 KiB buckets up to 16 KiB, then 4 KiB; the unpad block size is derived from the padded length (unambiguous: a 4 KiB result is ≥ 20,480). B-05b-8: 3-char and 900-char notes → identical ciphertext length; 1,025 → next bucket.
- **Envelope (04 §4).** `Envelope` + `EnvelopeBuilder.seal/reseal` + `Envelope.open`. Payload `{author_seq, object}` (ADR 05b §3) → UTF-8 → pad → XChaCha20-Poly1305 with AAD `uuid16(tenant) ‖ uuid16(book) ‖ uuid16(object) ‖ lenPrefixedUtf8(object_type) ‖ u32be(key_version) ‖ u8(suite_version)`; `author_sig = Ed25519(BLAKE2b-256(ciphertext ‖ aad))`. ⚠️ SPEC blob layout for the server `blob` column / `envelopes_local.blob`: `nonce(24) ‖ author_sig(64) ‖ ciphertext`; `blob_hash = BLAKE2b-256(blob)` (05c §2). Re-seal (05 §3) keeps envelope_id, object_id, hlc, header and the padded plaintext byte-for-byte; changes only key_version, nonce, ciphertext, sig; refuses a non-increasing version. Unknown top-level payload fields round-trip (rule 6). A header the server changes (book_id, object_id, object_type, key_version, tenant) fails the AEAD (04 §10).
- **Device certificates (04 §3.4).** `DeviceCert.issue/verify` over `uuid16(device_id) ‖ pub_ed ‖ pub_x ‖ i64be(issued_at)`; `issued_at` injected. ⚠️ SPEC: `user_id` and `suite_version` are carried plaintext beside the signature, as 04 writes it.
- **Signed records (ADR 05b §1).** `SignedRecord.sign/verifySignature/withSeq`, `SignedRecordKind` constants (membership_status, book_role, member_removal, device_revocation, device_added, key_rotation, verification_event, designation). Payload bytes are kept exactly as signed (a re-serialised payload does not verify — that is the point); ⚠️ SPEC header order `u8(suite) ‖ uuid16(tenant) ‖ lenPrefixedUtf8(kind) ‖ uuid16(author_device) ‖ i64be(hlc)`; `seq` is server-stamped and excluded from the signature.
- **Trust chain (04 §3.4, §8.3; ADR 05b §5; ADR 05c §2).** `TrustStore` interface (verified UMK per user, cert per device, revocation seq per device) and `ChainVerifier.verifyEnvelope/verifySignedRecord` → `ChainVerified` | `ChainCorrupt` (hash mismatch: corruption, no security event, checked first) | `ChainQuarantine(reason)` with `suiteUnsupported · certMissing · certInvalid · authorUnverified · sigInvalid · revoked` (seq ≥ revocation seq; ⚠️ SPEC: unknown seq with a revocation on file is refused conservatively; a backdated HLC never rescues a post-revocation envelope).
- **Shamir (04 §2, §7.3).** GF(2⁸) with the AES polynomial; branch-free multiply on the secret path, exp/log tables only for the public Lagrange basis; one polynomial per byte, coefficients from the injected RNG in one draw; `GuardianPolicy.defaultThreshold` (k = ⌈(n+1)/2⌉, n ∈ 2..5, 2-of-2 allowed), `GuardianShare` wire form `u8(suite) ‖ u32be(share_set_version) ‖ u8(k) ‖ u8(n) ‖ u8(index) ‖ bytes`, `GuardianShareSet.create/reconstruct` (refuses mixed versions, < k, duplicates). Tests include FIPS-197 known answers, an exhaustive table-vs-loop check over all 65,536 products, every k-subset for n ≤ 5, the k−1 zero-information proof, and a shrinking `kiri_check` property (B-04-69; `kiri_check` is now a `core_crypto` dev dependency too).
- **Hygiene (ADR 2026-09-05 §8).** `B-04-8` greps `core_crypto/lib` for `String`-typed key/secret/seed/share/nonce/signature/ciphertext names and platform channels; `B-04-70/71` zeroise + dispose + no key bytes in `toString`. `scripts/check_purity.sh` carries the same two greps for CI.

**Added — `packages/data`**
- Depends on `core_crypto`. `blake2bHasher(suite)` for `Mirror`; `CryptoPayloadOpener(suite, KeySource)` rebuilds the `Envelope` from a mirror row's columns + blob, decrypts, unpads and returns the object with the wrapper's `author_seq` at the top level (⚠️ SPEC: it overrides an `author_seq` inside the object); `KeySource`/`InMemoryKeySource`; typed `KeyUnavailable` (05 §4 `key_wait`, not a quarantine). Tests `E-04-1` (hasher = BLAKE2b; flipped blob byte → `BlobCorrupt`), `E-04-2` (a book sealed by core_crypto replays through Mirror + Recompute: balances right, integrity 1, `author_seq` from inside the ciphertext), `E-04-3` (server moves an envelope to another book → AEAD fails → quarantined `payload: EnvelopeOpenFailed(aeadFailed)`; missing key → `KeyUnavailable`).

**Changed**
- `PayloadOpener.open(blob, BlobHeader)` — the opener now receives the row's routing fields (envelope_id, book_id, object_id, object_type, key_version, author_device, hlc) so the AAD can be rebuilt; `JsonPayloadOpener` and Recompute's call site updated; the harness needed no change.
- ⟦tests⟧ markers on 04 §2, §3.1–§3.4, §4, §5.1–§5.3, §6, §7.3, §7.4, §7.5, §9.1, §9.2; ADR 05b §1, §5, §8; ADR 05c §2; ADR 2026-09-05 §8; 09 §1 (determinism ids) and the suite B sentence in 09 §2. Coverage at close: 316 🔒 lines · 68 marked + 10 heading-covered · 238 unmarked (from 252) · 6 `n/a` · 240 tests · 240 ids · 0 orphans · 0 dangling · 0 tests without id.
- `pubspec.lock` — sodium and its build-hook dependencies; `kiri_check` for core_crypto; `sodium` as a `data` dev dependency (tests initialise the binding).

**Decided** — nothing 🔒 ratified. `docs/decisions/2026-09-06-shamir-and-guardian-revocation-records.md` is **proposed, owner to confirm**: (1) Shamir over GF(256) in-house — the pub.dev audit found no package with an audit statement, none that is Flutter-free *and* GF(256) *and* uses injected randomness (`sss256`/`ntcdcrypto` are prime-field with `String` secrets and `dart:math`; `slip39` pulls `pinenacl`; `shamir_secret_plg` is a Flutter plugin; `dart_ssss` is Dart 2); combination wrapping not adopted (C(n,k) whole-UMK copies and a multi-recipient sealing scheme libsodium also lacks). (2) `share_set_version` wire form. (3) Guardians' k-of-n device revocation = k separate signed records counted by the client, cut-off at the k-th record's `seq` (closes ADR 05b Open 2 when ratified). 04 §2 carries a cross-reference line marked proposed.

**Open** ⚠️
- **Owner to ratify** the proposed ADR above; until then the code stands as `⚠️ SPEC`. External one-hour review of `shamir.dart` requested before M14.
- **`hlc` is unsigned** (04 §4: `author_sig` covers `ciphertext ‖ aad` only; `created_hlc` is plaintext outside both). A server could alter an envelope's HLC without any reader noticing, and 02 §8 late-arrival handling depends on it. Recommend adding `hlc` (and `envelope_id`) to the AAD or the signed digest in an ADR before M4 — a one-line change in `envelope.dart` today, a suite bump later.
- **`envelopes_local` lacks `suite_version` and `payload_schema`** (03 §3.1 vs the server row 03 §2.3). `CryptoPayloadOpener` assumes the current suite; a future suite would fail to open rather than be misread. 03 §3.1 should gain both columns (🔒 line — owner).
- `crypto_box_seal` draws its ephemeral key from libsodium's own RNG, so sealed boxes are **not** reproducible under the injected RNG; determinism tests assert on the AEAD paths instead (B-04-19). Fine for tests; noted so nobody expects golden sealed blobs.
- Shares carry no integrity check (a tampered share yields a wrong secret silently — integrity rests on the sealed transit); a `BLAKE2b-256(UMK_priv)` beside the share set would detect it if the owner wants that.
- The sync engine (M4) must mark a row `verified` only after `ChainVerifier` passes **and** the blob decrypted once, so Recompute never sees an un-keyed row (which it would quarantine `payload: KeyUnavailable`).
- 04 §11.2 (StrongBox / Secure Enclave, X25519 at-rest pattern) and §11.3 (guardian minimum) stay open for M5/M6; 04 §7.0/§7.6 backup defaults are app-level and unmarked by design.

**Commits** — pending.

---

## 2026-09-06 — M2 close-out: duplicate author_seq at the mirror, dead violation kinds pruned, first two-device tests on the harness

Third M2 session of the day, three forks. Part A (data + core_ledger follow-ups) and part B (the first behavioural suite D tests on `/testing/harness`) landed; part B exposed two seams in Recompute's author-sequence handling, fixed by part C so the harness needs no local workaround.

**Added**
- `packages/data` — derived table `author_duplicates(book_id, author_device, author_seq, kept_envelope_id, duplicate_envelope_id)` (schema version still 1, unshipped); `Mirror.recomputeAuthorDuplicates(book)` keeps the earliest by `(hlc, envelope_id)` and reports every later carrier of the same seq; Recompute step 0 quarantines each duplicate with reason `author_seq_duplicate` and holds `integrity_ok` at 0 while one exists. Test `E-05b-4` (seqs 1, 2, 2 → later 2 quarantined, earlier counted, no gap, stable across a second Recompute). Data package: 25 tests.
- `testing/harness` — `SimulatedDevice` (in-memory `LedgerDatabase` via `openLedgerDatabase`, `Mirror` with an FNV `BlobHasher`, `Recompute` with `JsonPayloadOpener`, HLC ticked from the scheduler's virtual clock; `author`, `receive`, `dump`, `integrityOk`, `balance`, `gaps`, `state`) and `Relay` (content-blind stand-in for the server: broadcasts every authored envelope to every other device through the seeded `Network`, applies arrivals in scheduler order). Harness pubspec depends on `core_ledger`, `data`, `drift`. `Scheduler.run(untilMs)` now advances `now` to `untilMs` even when later events remain queued (D-09-4 adjusted).
- Suite D behavioural tests (`test/two_device_test.dart`): **D-05b-2** orphan amendment — seed 1 delivers the amendment to device B 845 ms before its original; B holds it (`held_for` = original, not in `entries_p`, Cash unchanged, `integrity_ok` 0), then folds both once (Cash −₹300, `superseded_by` set, integrity 1), A and B dumps byte-identical, and the whole run replays from `model.log` through `ReplayNetwork` with the same intermediate observation. **D-05b-3** withheld envelope — seed 10 at drop rate 0.34 drops seq 2 (asserted); B shows the gap, keeps counting seqs 1 and 3 live, and both `monthLockPreconditions` and `yearClosePreconditions` refuse with `authorGapOpen`; a re-send clears everything and dumps match. **D-05b-4** twenty interleaved entries from two authors under reordering — arrival orders differ, dumps identical. Setup envelopes reach the peer out of band (bootstrap pull, 05 §8) so pinned seeds address entries only.
- `packages/data` Recompute (part C) ranks every event of an author uniformly over its projected seqs ∪ the mirror's missing seqs — a hole keeps its rank and nothing occupies it — so `project()` reports the gap with the exact device, `monthLockPreconditions` / `yearClosePreconditions` refuse with `authorGapOpen` from Recompute's own state, and healthy config/account objects never fake a gap. An inner `author_seq` that disagrees with the mirror row is quarantined `author_seq_mismatch` (⚠️ SPEC). `BookRecompute.state/chart` and `Recompute.stateOf(book)` expose the ranked state (a real Recompute, so it can never disagree with the rows). Tests `E-05b-5` (setup objects + entries with one reserved seq missing → one hole, provisional, preconditions refuse, integrity 0; arrival clears all; `stateOf` agrees with `run`) and `E-05b-6` (inner seq ≠ row → `author_seq_mismatch`). The harness's local ranking and its ⚠️ SPEC workaround are deleted; `SimulatedDevice.state()` is `recompute.stateOf`. Data 27 tests, harness 8.

**Changed**
- `packages/core_ledger` — `ViolationKind.amendTargetMissing`, `reverseTargetMissing`, `decisionTargetMissing` removed (no reference anywhere in packages/, testing/, app/); `targetMissing` stays. 155 tests green.
- ADR 05b §3 marker gains `E-05b-4`.
- ADR 05b §3 marker also gains `D-05b-3, E-05b-5, E-05b-6`, §4 `D-05b-2`; 09 §2 suite D sentence names `D-05b-2..4`.
- Coverage at close: 315 🔒 lines · 63 marked or heading-covered · 252 unmarked · 165 tests · 165 ids · 0 dangling · 0 orphans · 0 tests without id · 0 live skips. Push gate green.

**Decided** — nothing 🔒. Duplicates are caught at the mirror before Recompute's dense-rank pass, so the projector's own `authorSeqDuplicate` rule is unreachable from Recompute by design (it still guards direct `project()` callers).

**Fixed the same day (surfaced by the harness, closed by part C)** — (1) Recompute took an entry's inner `author_seq` verbatim while dense-ranking every other event, so a healthy single device that numbers its config/account objects too reported a gap. (2) Recompute gave a gap author no seqs at all, so `project()` saw no gap and the close preconditions could not refuse — the harness had to rank over present ∪ missing seqs itself. Both were Recompute's job; the rig's workaround is gone.

**Open** ⚠️
- **M2 exit reached** (10 M2 row: suite E client half green, harness created, held/gaps/as-of/shape/projectorVersion landed, skip re-landed). Tag after committing: `git tag m2-local-persistence`. Test-id rule learned: ids must end in digits (`E-05b-5b` is rejected), so sibling cases take the next integer.
- Platform backup exclusion (ADR 05c §8) remains app-level work at M5.

**Commits** — pending.

---

## 2026-09-06 — M2: ledger time boundary (ADR 05e/05b/05c in core_ledger) + local persistence (packages/data)

Second M2 slice, run as three forked agents on disjoint file sets (core_ledger rulings · data persistence · re-pointing data to the new projector output), then one gate. `projectorVersion` is now **2**: the certified-vector as-of rule and `held` change results for existing envelope sets (ADR 05c §3), so this bump also requires a min-client-version bump when the app ships (06 §4.5). Goldens unchanged and green.

**Added — `packages/core_ledger` (154 → 155 tests incl. the shrink pilot; ids `A-05b-1…6`, `A-05e-1…11`, `A-05c-1…2`, `A-05i-1`)**
- **`held` (ADR 05b §4, 05e §10):** an amendment, reversal or decision whose target is absent goes to `LedgerState.held` (event, `heldFor`, reason) — not counted, not quarantined; when the target is in the set the chain folds once, whatever the arrival order. `targetMissing` quarantine only when every author in the set carries `authorSeq` and no author has a gap (the target provably never existed). The M1 skip on `A-02-45` is gone; `A-02-57` (decision for an unknown entry) now asserts held.
- **Author sequence (ADR 05b §3):** `LedgerEvent.authorDevice` / `authorSeq` on every event; `Entry` JSON gains `author_seq` (positive int, validated, round-tripped). The projector reports `authorGaps` (device, expectedSeq, sinceHlc) and `isProvisional`; a duplicate seq refuses the later event.
- **Close blocks (05e §4):** `yearClosePreconditions` and new `monthLockPreconditions` refuse on `authorGapOpen` / `heldEnvelope`. The projector still records any lock it receives (all-time object, 05e §5) and re-verifies its vector — `lockVerification`.
- **Certified vector (05e §2):** `closingVector(state, chart, fy)` — money/party/advance/partner/equity_system only, cut by `accounting_date ≤ FY last day` regardless of HLC; categories not carried; one `net_result:<fy>` line per year; `trialBalance` shows net-result lines so a seeded state balances. `netProfit(state, chart, fy)` is FY-scoped (minus distributions in that FY) — **breaking: the FY argument is now required**. `accumulatedSurplus` and `distributionHeadroom` (returns the excess for the wizard's "by how much").
- **Loss distribution (05e §8):** `splitByRatio` takes a negative total as the exact mirror of `|total|`; `Verbs.profitDistribution` posts a loss (Dr partners · Cr Profit Distributed) and handles interest > profit (interest in full, negative remainder shared as loss). Actual/365 verified across leap-year 2028.
- **Shape invariants (05e §6):** `checkShape` for all six kinds (`shapeViolation`), extended with ⚠️ SPEC interpretations for classes the ADR table omits — `partner` party-like; `advance` beside money; Due to/from stands in for money on the far side of a transfer and the payee half of a pocket expense; reversals exempt (the projector proves the mirror). Table-driven `A-05e-8` over 6 wrong + 17 right shapes. The golden parser's kind inference was tightened to the same shapes; no figure changed.
- **`projectorVersion` (05c §3):** exported constant, recorded on `PeriodLock`/`YearClose`; `CloseVerification {verified, mismatch, readerOutdated, certifierOutdated}` — an older reader shows *update to verify*, never a false mismatch.
- Statement order locked to `(accounting_date, hlc, envelope_id)` (05e §12); `InterBook.reconcile` reports a sealed side as `unconfirmed`, never mismatch (05e §7); `negativeCashWarnings` for the `cash` subtype only (05e §12).
- **Shrinking property tests (ADR 05i §5, closes its Open 1):** `kiri_check` 1.3.1 adopted as a dev dependency (Dart 3, no Flutter dependency, maintained Jan 2026; `glados` is Dart-2-era and unmaintained, `propcheck` Dart 1). Pilot `A-05i-1` shrinks counter-examples over the ratio-split rule incl. the loss mirror, seeded from the same `PROPTEST_SEED`. `forEachSeed` stays for generators the combinators cannot express. `check_coverage` recognises `property(` declarations.

**Added — `packages/data` (24 tests; ids `E-03-1…14`, `E-05b-1…3`, `E-05c-1…6`)**
- Drift 2.34 + sqlite3 3.5, pure Dart; `database.g.dart` committed. `openLedgerDatabase(executor, {cipherKey})` → `Opened | MigrationFailed | QuickCheckFailed | OpenFailed`: migrations (downgrade fails closed, 03 §5), `PRAGMA quick_check` on every open (05c §6), key buffer zeroised. `sqlcipherSetup(key32)` is the `NativeDatabase(setup:)` hook that issues `PRAGMA key` from raw bytes — ⚠️ SPEC: the key cannot go through `openLedgerDatabase` itself because drift reads `user_version` inside the executor's own open. The app supplies the SQLCipher executor at M5; tests use in-memory sqlite.
- Schema v1 = 03 §3.1 + §3.2 verbatim (all Layer-1 and Layer-2 tables, key indexes incl. the partial Inbox and advance-request indexes, `push_state`/`review_state` checks, single-row `store_epoch`), plus append-only triggers on the mirror (UPDATE of blob/hlc and DELETE throw; only flag columns change). Rebuildable additions to §3.2, ⚠️ SPEC: `books_p.needs_rebootstrap`, `accounts_p.{system_role, member_id, counterpart_book_id, created_order}`, `entry_lines_p.line_index`, `year_close_p.{projector_version, verification}`, `periods_p.verification`.
- `Mirror`: idempotent append, `blob_hash` re-verified on every read via an injected hasher (core_crypto at M3) — mismatch is `BlobCorrupt`, never quarantine (05c §2); outbox state machine `queued→inflight→acked→observed` (+`rejected` with reason) with the legal-move table, prune only at `observed`; `nextAuthorSeq` atomic 1…n per (book, device) under concurrency; `observeStoreEpoch` resets all cursors and returns acked rows to queued (05b §6); `recomputeAuthorGaps` derived from the mirror; `rebootstrapBook` guarded delete that never touches the outbox.
- `Recompute`: per-book transaction; drops Layer 2, seeds from the latest `year_close_p` vector when that FY's entries are absent locally (03 §3.3 rule 3), replays verified/non-quarantined envelopes in `(hlc, envelope_id)` order through `core_ledger.project()` with an injected `PayloadOpener` (JSON in tests; M3 supplies decryption), mirrors `state.held` into the flag columns, writes every projection table; `integrity_ok` = 0 while anything is unverified, corrupt, held or gapped. Determinism: three insertion orders → byte-identical dumps of every projection table (`dumpProjections`, ⚠️ SPEC format). `verifyBalances` / `checkAndRepair` detect tampered or deleted `balances` rows and repair by Recompute.
- ⚠️ SPEC (in code): the projector sees only projected object types while `author_seq` numbers every object, so for an author with no mirror gap Recompute feeds the projector a dense rank of its projected events (contiguous ⇒ a missing target is provably absent), and for an author with a mirror gap it feeds null seqs so dangling refs stay `held`. The mirror's `author_gaps` table is authoritative. Payload wire shapes for `approval_decision`, `period_lock`, `period_unlock`, `year_close`, `cash_count`, `account`, `book_config` are M2 interpretations (snake_case, paise ints, `YYYY-MM`).

**Changed**
- `docs/02-ledger-rules.md` markers extended on §1.3, §1.4, §2, §5, §6, §7.1, §8, §8.1, §9; ADR 05e §1–§8, §10–§12, ADR 05b §3, §4, §6, ADR 05c §3, §6, ADR 05i §2 (`n/a`), §5, §7 and 03 §3.1, §3.2, §3.3, §5 carry markers. Coverage now: 315 🔒 lines · 62 marked or heading-covered · 253 unmarked · 5 `n/a` · 159 tests · 159 ids · 0 orphans · 0 dangling · 0 live superseded skips.
- `docs/09-acceptance-tests.md` §1 property line names the pilot.
- `scripts/check_coverage.dart` — counts `property(` declarations.
- `pubspec.lock` — drift, sqlite3, drift_dev, build_runner, kiri_check and transitive deps.

**Decided** — no 🔒 change. All interpretations are `⚠️ SPEC` comments in code and listed above; the owner may promote any of them to an ADR. Notable: negative `splitByRatio` as the mirror of the positive rule; net-result vector lines keyed `net_result:<fy>`; a quarantined target counts as absent for `held`; version-outdated states decided on mismatch only.

**Open** ⚠️
- **Authoring-time gap checks:** `yearClosePreconditions` sees only the projector's (dense-rank) gaps; the authoring client at M9 must also consult the mirror's `author_gaps` before offering a close. Follow-up: `Mirror.recomputeAuthorGaps` does not yet flag duplicate `author_seq`.
- `ViolationKind.{amend,reverse,decision}TargetMissing` are no longer emitted; prune once nothing serialises them (M3).
- ADR 05c §8 (backup attribute, private bucket, sweeper) is untested by design at M2 — app (M5) and server (M4) work.
- Two agents each needed one round of API reconciliation; both landed. Remaining M2 roadmap item not in code: platform backup exclusion (app-level, M5).

**Commits** — `e5acd22` (together with the test-contract slice).

---

## 2026-09-06 — M2: test contract infrastructure (ADR 2026-09-05i)

First M2 slice. Lands the traceability, lane, seed and harness machinery that ADR 2026-09-05i assigned to M2, and pays down M1's traceability backlog: every suite A test now carries an id and every 02 🔒 line those tests cover names them. Persistence (Drift + projector, 03 §3) is the next slice.

**Added**
- `scripts/check_coverage.dart` — 🔒 ↔ test-id checker (ADR 05i §1) + golden governance (§3). Scans `docs/`, `design/*.md`, `CLAUDE.md` (not `requirements-architecture.md`, not the canvas mirror) for lock marks; a heading's marker covers its section; a 🔒 followed by a lowercase word or `=` is a mention, not a mark. Fails on unmarked 🔒 lines, marker ids no test declares, malformed ids, superseded skips past their `--milestone`, and a `content_hash` that no longer matches the five worked-example files (BLAKE2b-256 via `pointycastle`, root dev dependency). Warns on orphan ids and tests without an id; lists live `superseded by ADR …` skips. **Warn-only** (exit 0) until M4 — `--strict` / `COVERAGE_STRICT=1` enforce. Wired into `ci.sh` after the strings step. Today: 315 🔒 lines · 58 marked or heading-covered · 257 unmarked (backlog, annotated milestone by milestone) · 3 `n/a` · 116 tests · 116 ids · 0 orphans · 0 tests without an id. Push and nightly lanes both green.
- **Test ids everywhere they exist.** All 111 `core_ledger` tests renamed `A-02-1 … A-02-93`, `A-03-1 … A-03-5` (HLC, unknown-field round-trip, determinism), `A-09-1` (property), `A-ref-1 … A-ref-7` (golden replay), `A-10-1`; M0 hello-worlds `B-10-1`, `D-10-1`, `E-10-1`, `F1-10-1`; harness `D-09-1 … D-09-5`. Numbering is a running integer per source, in test-file order — ids are stable from here.
- **`⟦tests: …⟧` markers** on 34 lines of 02 (§1.1–§1.4, §2, §3, §4, §5, §6, §7, §7.1 rules that have engine tests, §8, §8.1, §8.2, §9), 3 of 03 (§1, §3.3, unknown-field rule), 3 of the worked-examples README, 3 of the accounting standards, 09 §1, CLAUDE.md (Accounting authority; Precedence = `n/a`), 10 (Platform / Cross-references = `n/a`; Sequencing → the four hello-world ids). UI-only, M9+ and §10 import lines were **left unmarked on purpose** — an unmarked line is honest backlog; `n/a` is reserved for rules that are untestable by nature.
- `dart_test.yaml` at the workspace root (tags `A B C D E F1 G property flaky slow`, per-tag timeouts, `flaky` skipped by default and re-enabled by `--preset nightly`), included by every package's own `dart_test.yaml`. `@Tags(['A'])` on every suite A file, `tags: 'property'` on the three generators, `D` on the harness, `F1` on the app shell test. Probe-tested: a `flaky` test is skipped in the default preset and runs under `nightly`.
- **Seeds (ADR 05i §5):** `forEachSeed(testId, body)` in `core_ledger/test/helpers.dart` replays every seed listed for the test in `test/regress/seeds.txt`, then one fresh seed (`PROPTEST_SEED` pins it, else drawn from the clock — test code, not lib/). A failure re-throws with the seed, the replay command and the pin instruction. The three M1 generators (`Random(20260904)`, `Random(71)`, `Random(7)`) moved to the seeds file as permanent regression cases.
- **Golden path fix (ADR 05i §9):** `workspaceRoot()` walks up to `CLAUDE.md`; `dart test packages/core_ledger/test/golden_worked_examples_test.dart` now passes from the repository root as well as from the package.
- **`/testing/harness`** (workspace package `harness`, pure Dart, `dart:math` allowed — not a `core_*` package): `Scheduler` (discrete-event, virtual clock, `(at, seq)` order, `run(untilMs)`, `cancel`, `trace`), `NetworkModel` (one seed → uniform delay, reorder by delay, drop rate, `OfflineWindow`s that hold sender and receiver traffic until reconnect), `NetworkLog` (JSON round-trip) and `ReplayNetwork` (drives the identical run from the log and refuses a drifted scenario) behind a `Network` interface for M4's devices and server. Five self-tests. `/testing/fixtures` and `/testing/goldens` created with READMEs stating the synthetic-only and goldens-stay-in-docs rules.
- `.github/workflows/ci.yml` — nightly schedule (03:00 IST) runs `LANE=nightly`; `workflow_dispatch` takes a lane input.

**Changed**
- `scripts/ci.sh` — `LANE=push|nightly|rc|release` (default push); nightly runs `dart test --preset nightly`; steps a lane does not own yet print *scheduled — lands at M<n>* instead of pretending to run; test loop now includes `testing/harness`; coverage step added.
- `scripts/check_purity.sh` — Flutter-import check extends to `testing/`; test-data hygiene grep (ADR 05i §7) over `packages/*/test`, `app/test`, `testing/` for real-looking Indian mobile numbers (standalone `[6-9]\d{9}`, or `+91` outside the reserved `99999` block), Aadhaar-shaped and PAN-shaped strings. Zero false positives on the current trees — the ₹-amount concern in ADR 05i Open 3 does not bite because paise in tests are written as `rs(…)` expressions.
- `pubspec.yaml` (workspace) — `testing/harness` joins the workspace; `pointycastle` root dev dependency.
- `docs/10-roadmap.md` — parking-lot status line says "locked" in words (the emoji was a mention the checker would otherwise read as a mark).
- `CHANGELOG.md` — commit hashes filled for M0 (`4eee9c1`), M1 (`ae7293d`), 05d (`b7d7535`), the 05e–i fan-out (`354437a`) and the env session (`d1d26c6`, `4bc3048`); the env session's Open item (no `LANE`, no `check_coverage`) closed.

**Decided** — no 🔒 change, no ADR. Conventions fixed in code comments: id numbering is a running integer per source in test-file order; the golden `content_hash` is BLAKE2b-256 over the five example files' bytes concatenated in the README's file order; `n/a` markers only for rules untestable by nature.

**Open** ⚠️
- **Shrinking property-test package (ADR 05i §5, Open 1)** — not adopted this slice; `forEachSeed` is the interim rule the ADR allows. Candidates to evaluate next slice: `glados` (shrinking, Flutter-free, maintenance to confirm) vs staying on seeded loops; recommendation: decide only once a generator actually needs shrinking.
- 257 🔒 lines still unmarked — by design, they are annotated as their milestone's tests land (03/05 at M2–M4, 04 at M3, 06 at M6, 07/13/design at M5+, 08/12 at M13). The checker stays warn-only until M4 exit.
- The skipped `A-02-45` (amend target missing → `held`) re-lands with the `held` state in the next M2 slice, as the skip reason says.
- `flutter_test` accepts `@Tags`; whether `flutter test` honours the root `dart_test.yaml` include is untested until F1 grows past one file.

**Commits** — `e5acd22` (together with the ledger-time-boundary + persistence slice).

---

## 2026-09-06 — env: Claude Code hooks + project skills

Owner asked whether to add plugins/skills for coding, testing and database work. Ruling: wire the existing `scripts/ci.sh` gate into the session via hooks, encode the CLAUDE.md workflow as project skills, defer stack plugins (Supabase MCP until the M4 server milestone and then against a local project only; TypeScript LSP once `server/functions` exists; no Dart/Flutter LSP exists in the official marketplace).

**Added**
- `.claude/settings.json` — three hooks. PostToolUse on Write|Edit runs `dart format` + `dart analyze --fatal-infos` (package-scoped; `flutter analyze` under `app/`) + `scripts/check_purity.sh`, failures returned to the model as a blocking reason. PreToolUse on Bash denies `git commit` / `git push` / `gh pr create` at command position (owner commits). Stop blocks once when the tree changed but `CHANGELOG.md` did not (`stop_hook_active` guard).
- `.claude/hooks/{dart_post_edit,block_git_commit,stop_changelog}.sh` — the hook scripts; pipe-tested on pass and fail paths (nine-case table for the commit block, incl. prose mentions that must be allowed and `git -C . commit` that must be denied); PreToolUse proven live in-session.
- `.claude/skills/` — `/slice M<n>` (orient on roadmap row + owning spec + ADRs + 09 ids, tests-first), `/gate [lane]` (run ci.sh, report by step/suite, mechanical fixes only), `/adr` (dated ADR scaffold with `⟦tests: …⟧` markers, spec cross-refs, changelog Decided line), `/changelog` (house-format entry), `/goldens` (suite A worked-example goldens with the engine-bug / spec-vs-reference / parser-drift triage).

**Changed**
- Plugins installed by the owner from `claude-plugins-official` (user-level, not in the repo): `hookify` (rule-based hooks from conversation analysis) and `context7` (live library docs via MCP — Drift, sodium_libs, Supabase, Deno).
- `.gitignore` — `.claude/settings.json`, `.claude/hooks/`, `.claude/skills/` now tracked alongside `.claude/commands/` so hooks and skills travel with the repo.

**Open** ⚠️
- `ci.sh` has no `LANE` switch and no `check_coverage.dart` yet, though CLAUDE.md § Commands describes both; they land at M2 per ADR 2026-09-05i. `/gate` passes `LANE` through and says so. → *closed 2026-09-06 (M2 test-contract slice).*

**Commits** — `d1d26c6`, `4bc3048`.

---

## 2026-09-05 — docs: seven-spec review fan-out → five ADRs (05e–05i) + M2 code follow-ups

Seven parallel review agents (02, 07, 08, 09, 12, 13, design system) produced one consolidated decision sheet of 40 items; owner ruled **"accept all recommendations"**. Five forked agents drafted one ADR each plus an edit script; scripts applied serially (e → g → h → i → f), shifted anchors re-anchored by hand, zero table breakage, `gen_tokens --check` green.

**Decided**
- `2026-09-05e-ledger-time-boundary.md` — 🔒 §9 balance formula restated (reversal + target both count); certified vector as-of `accounting_date`, balance-sheet accounts only, FY P&L from FY envelopes, Corpus a computed line (accounting-reference conflict owner-ruled; errata F-5/F-6/F-7 pending bookkeeper sign-off); late arrivals in live balance, out of certified month; close blocked on author gap / `held`; `period_lock`/`period_unlock` all-time objects; per-kind shape invariants; sealed-book pairs *unconfirmed*; loss distribution + FY-scoped period + ceiling; member removal / FY-start / archive structural (quorum), FY-start frozen after any close; peer reviewer in `book_config`; `held` = dangling ref only, tray state renamed `inTray`; registry + `period_unlock`, `structural_approval`, `business_setting`.
- `2026-09-05f-ux-design-catch-up.md` — 🔒 tab bar = four tabs + docked centre (+) in 13/07/design-system/DESIGN-PACK; the seventeen ADR states given screens (S1.4, S10.5, S11.9, S11.10, S15.4, S19.5, variants), 13 §6 gains Device and App-lock models, Sync aligned to 05 §9; 07 §5 contradictions resolved (later rulings win); Inbox card taxonomy; notification→destination map (13 §3.4); nine screens 07 did not own + Opening-balances door; copy honesty fixes; design system: status colour family (icons/borders/words, never amounts), four grounds audited, `focus-on-primary`, type scale + Indic line-height floor, canvas palette generated from tokens, skeletons/loader drawn, paise none in-app / two decimals in statements, `check_contrast.dart` in ci.sh; pending/locked/sunk/scrim approved with the sunk caveat; PIN lockout = ADR behaviour + canvas tone.
- `2026-09-05g-subscription-entitlement.md` — 🔒 entitlement token under the **one** server signing key (pinned beside SPKI pins); hard caps server-side, watermark soft and reports-only; quota table (10k/100k/250k/1M envelopes per book · 250 MB/2/5/15 GB · attachments 100 MB/2/5/20 GB · 10 MB/file · devices 5/5/8/15 = max across tenants · 600/min, 5k/h, 50 MB/day) closes 05b §7 ⚠️; dunning grace ≠ offline grace, clock floor; seats count invited+pending+active; `payer_user_id`; IAP option 1 + web GST checkout + single INR price; `billing_events`, `subscriptions.updated_at` etc.; GST in paise half-up; refunds scoped to gateway, one per user lifetime; trial once per user; 24-month lapsed → cold storage, never deletion.
- `2026-09-05h-admin-console-staff.md` — 🔒 freeze exists narrowly (fraud/legal/abuse, four-eyes, ≤30 d, member notified; `rejected:tenant_frozen` pushes only) and is in 06 §8; support revocation pending-window + no re-revoke after cancel; support deletion = request to user devices; admin role has no KMS decrypt, phone lookup by HMAC, own column allowlist; break-glass doctrine (12 §3.1) for backup/maintenance/KMS incl. Phase-0 SQL; staff lookup quotas; hash-chained off-box staff log ≥3 y separate from 03 §6; staff roles + SSO + quarterly review; four-eyes by irreversibility; config canary/rollback; DPDP & legal (12 §7); transparency event Phase 1; ≥2 staff accounts.
- `2026-09-05i-test-contract.md` — 🔒 test ids + `⟦tests: …⟧` marker on every 🔒 line, `check_coverage.dart` warn→block at M4; four CI lanes; golden governance (provisional until bookkeeper sign-off, README front-matter approval + hash, blocks M14 exit; README header corrected 5/8/185); supersession `@Skip` rule; shrinking property tests / seed corpus; perf gate SE 3 p95/20 nightly, Android at M12; `/testing/harness`; hygiene grep + flaky policy; suite F → F1/F2/F3; E server runner; 13 previously untested 🔒 rulings given ids.

**Added (code, M2 follow-ups)** — `packages/core_ledger`: `EffectiveStatus.held` → `inTray`; orphan-amendment test split, the superseded half `@Skip`ped with the ADR pointer. `dart analyze` clean; 134 passed, 1 skipped.

**Changed** — 02, 03, 04, 05, 06, 07 (+ new §§20–28), 09, 10, 11, 13, CLAUDE.md, design-system.md, DESIGN-PACK.md, tokens.json (`_proposed_2026-09-05f` note only), reference errata + worked-examples README + one Corpus sentence + one interest figure (pending sign-off).

**Open** ⚠️ — per-ADR Open sections; notably exact hex for the darker light `credit` (05f), shrinking-generator package (05i), SAC code (05g), canvas-mirror versioning (05f), 07 §19 renumber pass.

**Commits** — `354437a`.

---

## 2026-09-05 — docs: auth & devices vs the hostile relative (ADR 2026-09-05d)

Fourth review of the day, of 06. The strongest spec of the four; its gaps were flows that let a hostile human — or two colluding guardians — act faster than the owner can notice.

**Decided** — `docs/decisions/2026-09-05d-auth-devices-human-attackers.md`
- 🔒 Guardian recovery and guardian phone-change **wait 24 h with one-tap Cancel** on every existing device when the user still has an active device; immediate only when none exists.
- 🔒 **Uncertified devices see nothing but themselves** — server verifies the cert under the UMK public key, RLS requires `certified` for every tenant table.
- 🔒 **Support revocation delayed 24 h, cancellable**, lands unsigned → target suspends, never wipes.
- 🔒 Keystore bound to the **current biometric set**; enrolment change → MPIN. 🔒 **MPIN attempt policy** (5 free, escalating, 10 → OTP+biometric), HMAC under a hardware-backed key, counter survives app-data clearance.
- 🔒 **New-device notice on every path** (incl. silent platform key sync) + `device_added` signed record; verification events are signed records.
- Threat model names Apple/Google-account + number compromise; invites phone-bound; 15-min revocation lag stated; challenge/registration rate limits.

**Changed** — 06 §3, §4.4, §5, §6, §7, §8, §9.3 (placement fix), §9.4, §10, §11 · 04 §1.2, §7.3 · 03 §2.5 · 07 §5.6 · 09 suite C · 10 M6.

**Open** ⚠️ — rate-limit numbers; per-tenant 24 h window; Android keystore invalidation across OEMs.

**Commits** — `b7d7535`.

---

## 2026-09-05 — docs: storage durability & integrity (ADR 2026-09-05c)

Third review of the day, of the data model (03). Spine stands (envelopes are truth, projections disposable, integer paise, one plaintext boundary, append-only by grant). Gaps were at the edges 03 had not looked at.

**Decided** — `docs/decisions/2026-09-05c-storage-durability-integrity.md`
- 🔒 **India residency** for DB, object storage, backups, logs; PITR + snapshot policy (numbers ⚠️); quarterly restore drill; every restore bumps `store_epoch`.
- 🔒 **`blob_hash`** plaintext column — corruption is re-fetched and counted, never quarantined; only an intact blob with a bad signature is tampering.
- 🔒 **`projectorVersion`** recorded in every lock/close envelope; older readers show *update to verify*, never a false mismatch; result-changing projector changes bump min-client-version and force Recompute.
- 🔒 **Phone numbers encrypted at rest** (`phone_ct` + `phone_hmac`, server KMS); **invitees' numbers never stored** (HMAC only).
- Shape checks enumerated (`rejected:shape`); local corruption path (`quick_check`, drop+Recompute / re-bootstrap; `integrity_ok` gates Home); RLS with our own claims via `SET LOCAL`; platform backups excluded; private bucket + orphan sweep; audit retention 24 mo.

**Changed** — 03 §1/§2.1/§2.3/§2.5/§3.1/§5/§6/§7/§8 · 02 §8 step 4 · 04 §4 · 05 §3, §8 · 06 §7, §9.3 · 09 suite E · 10 M2/M4.

**Open** ⚠️ — PITR/snapshot/RTO-RPO numbers vs hosting plan; KMS/Vault choice + rotation; whether projector bumps share the crypto/sync min-version route group.

**Commits** — `460eb53`.

---

## 2026-09-05 — docs: sync trust boundaries (ADR 2026-09-05b)

Same review as the client blueprint, applied to 05. Core of 05 stands (seq cursors, idempotency, key-sync-before-drain, content-blind server, cross-client close hashes). Every gap was one shape: the server was still trusted for things it should only relay.

**Decided** — `docs/decisions/2026-09-05b-sync-trust-boundaries.md`
- 🔒 Structural facts (membership, roles, limits, revocation, removal, rotation) are **signed records** from certified devices; server rows are their projection; clients verify the record, not the row.
- 🔒 **No wipe on the server's word** — unsigned revocation → *suspended*, data kept; wipe only on a verified signed record.
- 🔒 **Per-author sequence inside the ciphertext** — withholding becomes a visible gap; provisional projection; month/year-close blocked while gaps exist.
- 🔒 **Dangling refs are `held`**, not counted (fixes the M1 orphan-amendment double-count when the original arrives late).
- 🔒 **Revocation cut-off = server `seq`**, never HLC (a stolen phone cannot backdate its receipt).
- 🔒 **Store epoch** on every response + outbox `observed` state (read-your-writes; `write_lost` event) — survives a server restore.
- Rate limits + per-plan quotas (numbers ⚠️ 08), plaintext padding to size buckets, signed-URL lifetimes, content-free server metrics, separate `maintenance` deletion role.

**Changed** — 05 §1/§3/§4/§5/§9/§10/§11 · 03 §2.5, §3.1 (schema) · 04 §1.2, §9.2 · 02 §5 · 06 §7 · 09 §2 suite D · 10 M2/M3/M4 rows.

**Open** ⚠️ — quota/rate numbers per plan (08); guardian k-of-n revocation as multi-sig vs k records (M3); one `bigserial` for records + envelopes (with 05 §11.1 test). Owner raised **whether to drop zero-knowledge** for a server-readable tier; **ruled 5 Sep 2026: keep zero-knowledge for now.** The opt-in company-assisted-recovery tier is parked in 10 § Phase 2 (not scheduled, not 🔒). Owner also asked why libsodium rather than Flutter/Dart built-ins — answered in session (Dart has no AEAD/signature/KX primitives; libsodium is native C over FFI, audited, one implementation for both platforms); rule 7 stands.

**Commits** — `217818a` (ADR + cross-refs); zero-knowledge ruling + parking-lot row follow in the next commit.

---

## 2026-09-05 — docs: client hardening (ADR 2026-09-05)

Owner brought a generic Flutter fintech security blueprint (MASVS / PCI framed) and asked what we adopt. Assessed against 04/05/06/07/13; about two thirds already decided or compatible.

**Decided** — `docs/decisions/2026-09-05-client-hardening.md`
- **Rejected 🔒:** "server is the sole authority for financial calculations" — contradicts zero-knowledge; the ADR tabulates our equivalents (signed envelopes, deterministic projector + cross-client hash, flag-for-review limits, signed quorum approvals) so the idea does not return.
- **Adopted 🔒:** SPKI public-key pinning with backup pins, hard-fail in staging too (05 §1) · OS transport configs, `FLAG_SECURE`, tap-jacking flag (M0 shell) · obfuscated release builds with symbols kept as CI artefacts · **screenshots/recording blocked** — owner-ruled, because PDF/WhatsApp share already exists (07 §5.6) · root/jailbreak/debugger **detect-warn-log, never block** (06 §4; 04 §1.2) · foreground inactivity lock 5 min beside the 2 min background lock (06 §4) · key material only in `Uint8List`/`SecureKey`, FFI-only, never a `MethodChannel` · CI: secret scan, dependency audit, no bare `print(` · temp exports purged after share (readable Drive export untouched) · MASVS L2+R as the M14 checklist; PCI out of scope, DPDP not GDPR.

**Changed**
- 04 §1.2, 05 §1, 06 §4 + §11, 07 §5.6, 09 §4 (client-hardening gates), 10 (M14 row + hardening-by-milestone note).

**Open** ⚠️
- SPKI pin set for hosted Supabase (intermediate CA + backup) and rotation runbook — verify at M4.
- `FLAG_SECURE` on the *Show my code* ceremony screen (consistent; confirm camera path unaffected).
- Detection library: prefer a small native check we own over a third-party package in the trust path.
- Code items (manifest flags, ci.sh steps, purity grep) land with their owning milestone — none written this session.

**Commits** — `2b89db7`.

---

## 2026-09-04 — M1: ledger core (pure Dart)

Exit gate (10 M1): **suite A incl. property tests, green** — `./scripts/ci.sh` passes end to end; `core_ledger` carries 134 tests, among them the golden replay of all five worked examples (8 books, 185 vouchers: every ledger row, every closing c/f, every trial-balance row and total, and the three Due to/from pairs whose both sides are in the package).

**Added** (`packages/core_ledger/lib/src/`, ~2,900 lines + ~2,300 lines of tests)
- `money.dart` — `Paise` extension type over `int`: integer arithmetic only, no path to a float (rule 1); `Side`; `floorDiv`, `roundHalfUp`.
- `local_date.dart`, `hlc.dart` — `LocalDate` / `YearMonth` / `FinancialYear` (per-book start month, default April) with no clock anywhere; `Hlc` = 48-bit ms + 16-bit counter (03 §1), `tick()` takes the physical reading as an argument; `(hlc, id)` event order.
- `accounts.dart` — `BookType`, the seven `AccountClass`es, `MoneySubtype` (incl. `cashCollection`), `SystemRole` for the equity_system wizards, `Account`, `Chart`.
- `entry.dart` — `Entry` / `Line` / `EntryRefs` per 02 §1.3 wire names; `fromJson` rejects non-integer money; unknown fields ride along at entry, refs and line level and are written back byte-stable (03 §3.3.4); `amendWith` / `reversal` builders (02 §5).
- `invariants.dart` — universal invariants 02 §1.4 + reader re-checks (`review_required` vs carried limit, `pending` only for an advance request shape); authoring-only future-date rule kept out of the projector.
- `verbs.dart` — the six verbs, the adjustment wizards (opening, cash-count difference, write-off), advance request/spend/return, partner paid-cost/drawing, and one-entry `profitDistribution` (interest first, then remainder by ratio). Wrong-class slots throw; a gollak is never a spending source and empties only into Cash or a bank account (02 §8.2).
- `ratio.dart` — `splitByRatio` 🔒 rule: floors, remainder to the largest ratio, ties to earliest; property-tested.
- `projection.dart` — `project(events, chart, {opening, heldInTray})`: sorts by `(hlc, id)`, quarantines violators as security events, folds approval decisions (last wins; self-approval quarantined — 02 §7.2 item 1), amend chains (head only, kind fixed), reversals (exact mirror, once), the advance queue vs the review queue, period lock rule (02 §8), year close with reader-side vector re-verification and certificate voiding on re-open (02 §8.1); `BalanceVector.canonical()` as the close-hash input; `trialBalance`, `statement` (running balance + side per row), `netProfit`, `yearClosePreconditions`.
- `partners.dart` — `interestOnCapital` (average daily balance, inclusive days, half-up to the paisa; debit balances charged unless told otherwise), `settlementCapacity`, `partnerDrift` (02 §7.1).
- `advances.dart` — `openAdvances` with FIFO ageing (02 §7). `interbook.dart` — `InterBook.transfer` / `pocketExpense` pairs sharing `transfer_group`, `isInTransit`, `reconcile` (02 §6). `cash_count.dart` — `DenominationSheet`, `CashCount` memo event, `countPolicy` / `validateCount`, `resolveCount` → verified / adjustment / recognition (02 §8.2).
- Tests: `test/golden_worked_examples_test.dart` parses the worked-example markdown directly (chart, daybook, ledger rows, TB) so the fixtures stay in `docs/reference/` as the single source; unit/property suites per module.

**Decided** (interpretations, all conservative, marked `⚠️ SPEC` in code — no 🔒 change, no ADR)
- `review_limit_paise` is nullable in the engine: `null` = no limit applies (own personal book, single-member book). 02 §1.3 types it as a plain int; the "never flagged" cases needed a representation.
- Advance movements map onto the six kinds as request = `money_out` + `pending`, spend = `money_out`, return = `money_in`. 02 fixes the postings, not the kind; balances never depend on kind.
- Re-dating a late arrival is the one amendment accepted against a locked period: lines identical, only the date moves, into a period open at the amendment's HLC. Everything else in a locked period must go through reversal. The tray itself (arrival order) is client-local and is passed to `project` as `heldInTray`.
- Verified interest illustration in paise: Amrit ₹4,295.89 · Sukhdev ₹2,311.23 · Harjit ₹1,354.52 (8 %, 1 Apr–31 Jul, day of posting counts).

**Open**
- ⚠️ 02 §7.1 shows Harjit's interest as ₹1,354 and the remainder as ₹5,86,039; `joint-business-partnership.md` §5 shows ₹1,355 / ₹5,86,038. Both are whole-rupee displays of ₹1,354.52 — no engine conflict, but the two documents should agree. Suggest both print paise.
- ⚠️ `joint-business-partnership.md` §5 "equal share of costs" splits ₹3,35,000 in rupees (1,11,668 / 1,11,666 / 1,11,666). The 🔒 rule divides in paise: 1,11,666.68 / 1,11,666.66 / 1,11,666.66. Presentation column only; flag for the bookkeeper pass.
- ⚠️ `trust-singh-sabha-gurudwara.md` predates the 2–3 Sep gollak ADRs: its "Gollak Cash A/c" is spent from directly (T-003, T-018…), so the fixture treats it as plain `cash`. On sign-off, consider splitting it into a `cash_collection` Gollak plus the seeded Cash A/c with Transfer vouchers between them.
- ⚠️ Owner to confirm the three interpretations under *Decided* (nullable limit, advance kinds, re-date rule) or point at the section that settles them.
- Not in M1 by design: envelope signing/encryption around these payloads (M2, 04), Drift persistence + the running-balance cache (M3, 03 §3.2), HLC generation from a real clock (M4 sync), FY-scoped P&L views and statement presentation strings (M5+).

**Commits**
- `ae7293d`

---

## 2026-09-04 — M0: scaffold

Exit gate: **CI green on hello-world tests** — `./scripts/ci.sh` passes end to end (pub get · generators current · format · purity · strings · analyze · 4 package suites · 3 app widget tests).

**Added**
- Pub workspace root (`pubspec.yaml`, one `pubspec.lock`) over `packages/core_ledger`, `core_crypto`, `data`, `sync_engine` and `app`; strict analysis options at root, per package and in the app.
- Four pure-Dart packages, each with a `packageName` hello export and one test; doc comments name the spec they own (02/04/03/05).
- `app/`: Flutter, iOS + Android targets (`com.rukkafolio.*`), Material 3 theme built from tokens only, light + dark, brand fonts (Mukta 400/500/600, Mukta Mahee 400/500/600, Noto Sans variable; OFL licences beside them), `flutter_localizations`, hello screen showing `app.name` + `splash.opening`; widget test renders EN / PA / HI.
- `scripts/ci.sh` — the gate, also run by `.github/workflows/ci.yml` (Flutter 3.47.0 stable, ubuntu).
- `scripts/gen_tokens.dart` — the only writer of `tokens.css`, `design/tokens/tokens.dart` and `app/lib/shared/tokens.dart`; `--check` fails CI on drift (design-system.md §status). Regenerated outputs verified value-identical to the hand-synced files; new: `RkIcon`, `RkMarkLight/Dark`, `RkMotion.markUnlockTotal`, `RkSpace.cardPadding`, `--row-min-h`.
- `scripts/check_strings.dart` — EN/PA/HI key parity, ICU placeholder parity (01 §1 rule 7), forbidden-jargon scan with the rule-4 whitelist (`app.name`, `app.name.short`, `about.*`), dotted key shape.
- `scripts/check_purity.sh` — no Flutter in `packages/`; no `dart:io`/`dart:math`/`DateTime.now()`/`Random()` in `core_*`; no hex colour literals in `app/lib` outside the generated tokens file.
- `scripts/gen_l10n_arb.dart` — see Decided.

**Changed**
- `design/tokens/tokens.json`: `space` gains structured `gutter` / `cardPadding` / `rowMinHeight` (values already present in its note); `$meta.note` now names the generator. No token value changed.
- `design/tokens/tokens.css`, `tokens.dart`: now generator output (headers say so).
- `design/design-system.md`: generator landed; M0 checklist ticked. `CLAUDE.md`: scripts listed in Layout; workspace / tokens / strings commands.
- `.gitignore`: Dart/Flutter/iOS/Android artefacts, `app/lib/l10n/gen/`, `.env*`.

**Decided** (build-time bridge, not a spec change — no ADR)
- 01 §1 rule 9 🔒 keeps ARB keys dotted (`screen.element.state`); Flutter gen_l10n only accepts Dart identifiers. Canonical ARBs stay dotted in `app/lib/l10n/`; `gen_l10n_arb.dart` derives identifier-keyed copies into the git-ignored `app/lib/l10n/gen/` (`app.name` → `appName`). Collisions fail the build.
- Product name stays Latin in PA/HI ARBs (01 §1 rule 8: a name the user matches, not a word inside a sentence; lockup shows it that way, 11 §4.2).

**Open**
- ⚠️ `splash.opening` PA/HI (ਤੁਹਾਡੇ ਵਹੀ-ਖਾਤੇ ਖੋਲ੍ਹ ਰਹੇ ਹਾਂ। / आपके बही-खाते खोल रहे हैं।) drafted from the 01 §2 term table; native review at the M12 gate.
- ⚠️ Bundle id `com.rukkafolio.*` is a placeholder until the domain / store-name check in README § Name.
- Not in M0 by design: `server/supabase` (M4, needs Docker), `testing/` harness (M4), Drift/SQLCipher/libsodium deps (M2/M3), `tokens.dart` consumers beyond the hello theme (M5).

**Commits**
- `4eee9c1`

---

## 2026-09-04 — env: development toolchain

**Added**
- Flutter 3.47.0 stable (Dart 3.13.0) via Homebrew cask; `flutter doctor` clean in every category.
- CocoaPods 1.17.0, Deno 2.9.5, GitHub CLI 2.97.0, Supabase CLI 2.116.0.
- Android SDK via `android-commandlinetools` cask: platforms 35 + 36, build-tools 35.0.0 + 36.0.0, platform-tools 37.0.1, emulator 37.1.11; all licenses accepted.
- OpenJDK 17.0.20.1 (Homebrew formula, no sudo) — Flutter configured with `--jdk-dir`.
- `~/.zprofile`: `ANDROID_HOME`, `JAVA_HOME`, `platform-tools` on PATH.
- This file, and the changelog rule in `CLAUDE.md` § Workflow.

**Open**
- ⚠️ Docker Desktop not installed — cask needs a sudo password. Required from M4 for `supabase db reset` and local RLS tests. Owner runs `brew install --cask docker-desktop`.
- No Android emulator image yet; not needed before M12 (iOS ships first, 10 🔒).

**Commits**
- `a08ec51`

---

## 2026-09-03 → 2026-09-04 — docs: design fold, brand v1.4, loading states

**Changed**
- Dark-theme credit/debit tokens → `#4FA37A` / `#CB6F6F` (debit lifted one step for AA on surface).
- 11 §4.5 — how the app waits: loader rule, ruled skeletons, splash branches; canvases 1/11 lockup, spinner removed.
- 11 §4.2 → v1.4: brand v1.2 mark canonical, icon package + animation reference, canvas 3 sealed mark.
- Verb pill: *Move money* is the fifth position; one door per adjustment wizard.
- Menu gains *Close the month*; Import lives in the entry header (S2), not a Menu row; Legal row on the Menu (07 §1).
- Roadmap: Phase 2 parking lot (non-normative).
- Gollak: deposits flexible (Cash A/c or bank, whole or in parts); empties only into the Cash A/c. Trust Cash A/c gets its own verify-mode count (C3c).
- Canvas 7 split into 7 / 15 / 16; canonical bottom-nav icon set; `/design-pull` pins canonical canvas display names.

**Decided**
- `docs/decisions/2026-09-03-gollak-deposit-flexibility.md`
- `docs/decisions/2026-09-03-menu-close-row-and-import-in-entry.md`
- `docs/decisions/2026-09-03b-entry-doors-move-money-and-wizards.md`
- `docs/decisions/2026-09-03c-brand-v1.2-mark-canonical.md`
- `docs/decisions/2026-09-03d-loading-and-splash.md`

**Commits**
- `9125a8f` `6f02926` `b2c6e08` `2655410` `098a8cf` `6d8a1f7` `ddcfede` `a761ea0` `2c1a42c` `d66ca49` `93d7dac` `4a00f50`

---

## 2026-09-01 → 2026-09-02 — docs: design slices 2–4, rulings A1–A4, Option B

**Changed**
- Slice 2: 13's screen inventory reconciled with the drawn canvases.
- Slice 3: danger-surface verdict; `sunk` + `scrim` tokens added as PROPOSED.
- Slice 4: S6.1 drawn, S17.1 folded, S18.x are documents, Narration carve-out, branch order ruled.
- A1+A2: one PIN everywhere; S7.2 = import balance check. A3: drawings (S2.5) + donation receipt (S4.2) ratified, D6 removed. A4: head displays as *President*; S7.4 import preview added.
- Option B ruled: designations are labels, permissions admin-granted; designation vocabulary tables (trust/org + business) saved.
- Trial Balance transliterates — ਟ੍ਰਾਇਲ ਬੈਲੇਂਸ / ट्रायल बैलेंस 🔒.
- 1 Sep design fold landed: MPIN, role labels, onboarding branches, vocabulary.

**Added**
- `/design-pull` command + byte-exact extractor `scripts/design_mirror_extract.py` (envelopes ordered chronologically).

**Decided**
- `docs/decisions/2026-09-01-pin-model-and-import-ids.md`
- `docs/decisions/2026-09-02-ratifications.md`

**Commits**
- `ab96d83` `6992bcc` `6bf4e99` `db8df45` `6493ece` `30b04b5` `b8c6843` `2fbaac6` `07f1980` `cc42990` `a6e0a5e` `31661b4` `ab1c7f1`

---

## 2026-08-30 → 2026-08-31 — docs: specification set v1.0

**Added**
- Specs 00–13, `requirements-architecture.md` (non-normative), `design/` system + tokens, `CLAUDE.md`, `README.md`.
- Screens: account · subscription · support · legal · system states; entry detail, invite, profile, plans, help, legal, update/maintenance, permissions, viewer, search, Group-by flow; backup setup, recovery flow, devices and backup settings.

**Changed**
- Phone recovery flow; language keyword corrections.

**Decided**
- `docs/decisions/2026-08-30-audit-remediation.md`

**Commits**
- `6d030a6` `774c421` `0efff54` `caa2499` `c3c66ce`
