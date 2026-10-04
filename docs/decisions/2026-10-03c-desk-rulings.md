# ADR 2026-10-03c — Desk rulings: test rewrites, invite status, guardian choice, support email

**Status:** accepted (owner-ruled, 3 Oct 2026, in one sitting, clearing PLAN desk 36, 37, 38, 40, 43, 44, 53,
65 and 96, and the *same shape as desk 40/96* note on desk 105).
**Amends:** ADR 2026-09-05i §4 (an in-place rewrite is allowed when the new behaviour lands in the same
commit, §1 below) · ADR 2026-09-25b §2 (the GET rows carry `status`, §2 below) · ADR 2026-09-25 §4 (the
email card gains the warning the AI chat already carries, §7 below). **Confirms as built:** ADR
2026-09-24b §1 (§5 below) · ADR 2026-09-25 §4's bare `mailto:` (§6 below) · ADR 2026-09-25 §5 for
untokened builds (§8 below). Everything else in those documents stands.

## Context

Each item was flagged by a lane, as a `⚠️ SPEC` in the file that holds it or as a desk note, because no
doc settled it. The owner chose the recommended reading for each. §1, §2, §5, §6 and §8 change no code
behaviour: they write down what is built and retire the `⚠️ SPEC` comments that asked. §3, §4 and §7
change behaviour and go to build lanes. Their test ids are reserved here (`@M13`).

## Rulings 🔒 ⟦tests: n/a — container heading; each ruling below carries its own marker⟧

### 1. A test may be rewritten in place when the new behaviour lands in the same commit (desk 40, 96, 105) ⟦tests: n/a — process rule, not behaviour⟧
ADR 2026-09-05i §4 exists so that **no test stays green against a superseded rule**. `@Skip` is its tool
for the case where the new behaviour re-lands later. When the ruling and the code that implements it
land in the **same commit**, the lane may rewrite the test in place under its existing id instead. No
stale green test exists at any commit. The commit's CHANGELOG entry names the id and the ruling that
moved it. `@Skip` plus a re-land milestone stays mandatory whenever the new behaviour is **not** in the
same commit. This accepts, as built: `E-06-32` (ADR 2026-09-25b §2), `E-06-89` and `E-03b-7` (ADR
2026-10-03b §2, §6).

### 2. `GET /sync-meta/invites` rows carry `status` (desk 36) ⟦tests: E-25b-1⟧
Each row carries the invite's own `status`, either `sent` (a live offer) or `accepted` (the caller's
own, spent: a nonce for S9.2, never an offer). Rows at `sent` come first. The column was already granted
in `0006`, and nothing new is exposed. The `⚠️ SPEC` at `sync-meta/index.ts` (M11-INV1 repair) is
retired. Desk 41's option (b) can now read it.

### 3. A revoked device cannot read or accept its user's invites (desk 37) ⟦tests: E-03c-1 @M13, E-03c-2 @M13⟧
`rf.my_invites` and `rf.accept_invite` refuse a caller whose device is not live (`rf.device_live_for`).
Today they key on the user claim alone, so an unexpired access token on a revoked phone can still read
offers and their nonces, and accept one. The nonce is not secret (04 §6.1), but a revoked device must
not act for its user. The refusal is the same named refusal the other device-gated routes give. A
`lane-server` slice builds it: E-03c-1 covers the read, E-03c-2 the accept.

### 4. S11.1 never offers an unverified member as a guardian (desk 53) ⟦tests: F1-03c-1 @M13, F1-03c-3 @M13, F1-03c-4 @M13⟧
A member whose ceremony stands at `invited`, `expired` or `blocked` cannot be **chosen** on S11.1. The
checkbox is disabled with the same reason *Meet them* already shows (13 §4.3), consistent with 04 §7.3's
verified-key rule. `save` still refuses to seal to an unverified key, as defence in depth.
`TrustedMemberCandidate.inviteId` (`app/lib/shared/seams/guardians.dart`) is retired, because S11.1 reads
nothing from it since *Meet them* opens S9.3 by member id (`F1-07-545`).

### 5. The recovery candidate is zeroised after any reconstruct, and is not biometric-bound (desk 38) ⟦tests: F1-24b-1⟧
(a) ADR 2026-09-24b §1's *"zeroised after `reconstructVerified`"* means after **any** reconstruct,
successful or not. A failed reconstruct (a share that does not open, a mismatch, too few shares) costs a
fresh attempt rather than leaving a key that shares have been tried against. The build already does this
(`recovery_candidate.dart`). (b) The candidate key-store item stays this-device-only and never synced,
but is **not** biometric-bound. The person who reaches recovery may have lost the biometric enrolment the
device keys depend on, and binding the candidate could lock them out mid-attempt.

### 6. S17.4's report is not pre-filled into the support email (desk 43) ⟦tests: F1-07-404⟧
ADR 2026-09-25 §4's `mailto:` to the one support address carries **no subject and no body**. S17.4 keeps
*Copy the report*. The person pastes it into their own email app and sees exactly what leaves the phone.
`DiagnosticsSender` keeps no production producer, and the `⚠️ SPEC` comments in `diagnostics_seams.dart`
and `s17_4_diagnostics_screen.dart` are retired.

### 7. The email card warns not to share amounts or account numbers (desk 44) ⟦tests: F1-03c-2 @M13⟧
S17.3's email card carries the warning ADR 2026-09-25 §4 requires of the AI chat: *do not send amounts or
account numbers*. The copy is new, under one ARB key in EN, PA and HI. This extends CLAUDE.md rule 4 to the
one channel where the person writes the text. The 06 §8 statement of what support cannot do stays word
for word.

### 8. Untokened builds stay Free: no pilot exception (desk 65) ⟦tests: F1-25-13, F1-25-14⟧
ADR 2026-09-25 §5 🔒 applies as built: with no token, PDF export and statement import are shut. Pilot
users get a real token by starting a trial once billing runs on `rukka-folio-dev`. There is no build
flag and no special-case code.

## Consequences
- **Build, `lane-server`:** §3, through `0028`, MemStore and the RLS suite.
- **Build, `lane-ui`:** §4 (`features/devices` S11.1 plus `shared/seams/guardians.dart`, its doubles) and §7
  (`features/help` S17.3 plus an ARB part). Desk 47's WhatsApp-wording cleanup can ride with §7.
- **Doc edits made with this ADR:** cross-reference lines in ADR 2026-09-05i §4, ADR 2026-09-25b §2, ADR
  2026-09-24b §1 and ADR 2026-09-25 §4. `⚠️ SPEC` comments retired in `sync-meta/index.ts`,
  `recovery_candidate.dart`, `diagnostics_seams.dart` and `s17_4_diagnostics_screen.dart`.

## Open ⚠️
None from these rulings. Desk 41 (the accepted invite forgotten on restart) and desk 42 (the ceremony
session's tenant) stay open. §2 makes desk 41's option (b) possible, but does not choose it.
