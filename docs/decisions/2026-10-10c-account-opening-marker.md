# ADR 2026-10-10c — The opening-balance marker travels on the account

ADR 2026-10-07b left open where an account's *opening answered* state lives, requiring only that it survive sync.
OPEN177 (10 Oct) built the prompt and derived *answered* from data that already syncs: an opening adjustment exists,
or a certified year-close vector names the account. That leaves two answers with no shared home: **Not needed**,
and a **zero** opening entered at S3.1 or S0.6/S0.6b (`openingBalances` posts nothing for zero). Such an account
keeps asking on every phone. The lane proposed a field on the account payload; the owner ruled **yes** on 10 Oct 2026
(PLAN desk 201). This resolves ADR 2026-10-07b *Open ⚠️*.

Where it shows: S2 *Add entry* (Canvas 2 → "S2 · State 2 · choosing, in the same space") → S2.1 inline create →
S4 *A/C statement* (Canvas 7 → "S4 · A/C statement · opening balance not set", "S4 · A/C statement · add the opening
balance") and S3 *Ledger index* (Canvas 7 → "S3 · Ledger index · opening balance not set").

## Rulings 🔒 ⟦tests: n/a — container heading; each ruling below carries its own marker⟧

### 1. The account payload carries `opening` 🔒 ⟦tests: E-1010c-1 @M13, E-1010c-2 @M13⟧
- The `account` object's payload gains an optional field `opening` with two values: `"pending"` and `"not_needed"`.
- **Absent means answered.** Every account written before this ADR, and every account created through S3.1, setup
  (S0.6/S0.6b) or book creation, carries no field and is never asked.
- `"pending"` is written only when an account is created inline from the entry picker (S2.1), per ADR 2026-10-07b §1.
- `"not_needed"` is written by **Not needed** as a new version of the account object that keeps every other field
  (03 §3.3 rule 4, unknown-field round-trip).
- The field is additive (03 §5 *additive fields freely*), so `payload_schema` and min_client_version do not change.
  A client that does not know the field preserves it.

### 2. When an account asks 🔒 ⟦tests: F1-1010c-1 @M13⟧
- An account asks (S4 card, S3 marker) when its projected `opening` is `"pending"` **and** no opening adjustment
  exists for it. Posting an opening adjustment answers it; `"not_needed"` answers it. Either answer is final for the
  prompt (ADR 2026-10-07b §2 unchanged).
- A zero opening entered inline is recorded as `"not_needed"` (nothing posts for zero).
- Money accounts follow the same rule once inline creation can make one (today it makes people accounts only).

### 3. Projection 🔒 ⟦tests: E-1010c-3 @M13⟧
- `accounts_p` gains `opening text null` (03 §3.2), filled by the projector from the account's current version.
- It is a projection change: bump the client Drift schema with a tested upgrade path, and force a full Recompute on
  first launch after upgrade (03 §5, ADR 2026-09-05c §3). Balances are unaffected.

## Consequences
- Code: `packages/data` (account payload codec, `accounts_p.opening`, Recompute, schema bump + migration test);
  `app/lib/shared/ledger` (`addAccount(openingPending:)`, *Not needed* writes the new account version,
  `watchOpeningUnanswered` reads the column instead of the derivation); `app/lib/features/entry` (S2 inline create
  passes `openingPending: true`); `app/lib/features/ledger` (enable **Not needed**; remove its disabled-with-reason
  seam and `⚠️ SPEC`). OPEN177's derived rule stays as the *no adjustment yet* half of ruling 2.
- Docs: 03 §3.2 (`accounts_p` line) and 03's account payload, 02 §4 cross-reference, 07 §6 inline-creation line.
- Milestone: M13, one slice (`lane-sync` for data + shared ledger, risk high: a projection and schema change).

## Open ⚠️
- The S3 marker colour: ADR 2026-10-07b §1 says *accent* (the bahi-red token, also S3's Cr colour); Canvas 7 draws
  ink. The build follows the canvas. Owner to confirm.
