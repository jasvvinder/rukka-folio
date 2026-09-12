# ADR 2026-09-09b — Drawings is a real account; Capital already exists

**Re-cut 9 Sep 2026** after the owner reopened the first draft. The first version ruled that
`SystemRole.openingBalance` should stop being Capital and a separate `capital` role be added. That was
**wrong**, and checking `docs/reference/worked-examples/` — the behavioural reference, CLAUDE.md
§ Accounting authority — is what caught it. Both business examples name a **single** account
`Opening Balance / Capital A/c` (Equity): `business-sharma-textile.md` row 14, ₹2,18,000 Cr, and
`joint-business-partnership.md` row 12. Splitting them would break those trial balances the moment they
become golden fixtures. `02 §7.1`'s "a single Capital/Drawings pair" therefore reads as
**{`Drawings A/c`, `Opening Balance / Capital A/c`}** — and the engine already agreed with the reference.

What is genuinely missing is **Drawings**. `SystemRole.drawings` is declared at
`packages/core_ledger/lib/src/accounts.dart:99` and referenced **nowhere**: nothing seeds it, no verb
posts to it, and `S2.5` (design B5) — the sheet shown when an owner takes money out of a business, saying
*"not a business expense"* — had nothing to post to.

Owner ruled 9 Sep 2026: the pair is real and created at business setup.

## Rulings 🔒 ⟦tests: n/a — container heading; each ruling below carries its own marker⟧

### 1. Capital is Opening Balance, and stays that way ⟦tests: A-09b-1⟧
- `SystemRole.openingBalance` **is** the Capital account. Its doc comment
  (*"Opening Balance / Capital — counterpart of every opening (02 §4)"*) is correct and must not be
  changed. No `capital` role is added. ⟦tests: A-09b-1⟧
- Consequence for the goldens: an account named `Opening Balance / Capital A/c` must appear exactly once
  per book, and reproduce the reference's opening figures. ⟦tests: A-09b-1⟧

### 2. `Drawings A/c` is seeded for a *Just me* business book ⟦tests: A-09b-2⟧
- `createBook` seeds `Drawings A/c` — `AccountClass.equitySystem`, `SystemRole.drawings` — when
  `type == BookType.business` **and** ownership is *Just me*. ⟦tests: A-09b-2⟧
- **A shared business gets no Drawings account.** `02 §7.1` gives it one `Partner Current A/c` per owner
  and calls that *"the single place that relationship lives"*; the partnership example confirms it —
  voucher G-007, a partner's withdrawal, posts `Dr {partner} — Partner Current · Cr SBI Agri Current`
  with no Drawings account involved. ⟦tests: A-09b-3⟧
- Personal, family, joint and organization books get no Drawings account: they have no
  owner-versus-business boundary to record. ⟦tests: A-09b-3⟧

### 3. Owner takeout posts to Drawings, and is never an expense ⟦tests: A-09b-4⟧
- `Dr Drawings A/c · Cr {business money a/c}` — matching `business-sharma-textile.md` B-022
  (`Cr Business Cash`, ₹25,000) and B-031 (`Cr Indian Bank`, ₹30,000). ⟦tests: A-09b-4⟧
- Drawings is `equitySystem`, so it cannot reach the P&L and `02 §1.2`'s no-closing-entries rule is
  untouched. An owner takeout landing in an expense category is a defect, not a preference.
  ⟦tests: A-09b-4⟧
- The `S2.5` sheet says so in words. ⟦tests: F1-07-47 @M5⟧

## Consequences
- **`packages/core_ledger`:** a drawings verb with the `_role` guard the other system verbs use
  (`verbs.dart:375`). No enum change, no projection change — `equitySystem` already sits outside the P&L,
  which `A-09b-4` asserts rather than assumes.
- **`app/`:** `LocalLedger.createBook` (`app/lib/shared/ledger/local_ledger.dart:625`) seeds `Drawings A/c`
  per ruling 2; see ADR 2026-09-09c for the rest of the seed. `S2.5` becomes buildable (lane U2).
- **Docs:** cross-reference at `02 §7.1`. No 🔒 line is contradicted — this implements one never built — so
  **no test needs `@Skip`**.
- **Milestone:** M5. The seeding is ordinary app work; the verb is `core_ledger`.

## Open ⚠️
- **Tier and budget.** The verb is `core_ledger` behaviour against a 🔒 line, which CLAUDE.md puts on
  `lane-core` (fable), and fable is at **5 runs against a 2-run budget** this week. The seeding (ruling 2)
  is ordinary app work and needs no escalation; only ruling 3's verb does.
- **The 8th quick-add tile.** `07 §6` bullet 3 lists Capital among the S3.1 tiles; S3.1 ships seven. Capital
  is a system account created with the book, so a *user-created* Capital account still makes no sense.
  The tile most plausibly means **record capital introduced** — an entry, not an account. Recommendation:
  it opens the entry flow with the Capital account preselected, and `07 §6` bullet 3 is amended to say so.
  ⚠️ SPEC comment stands in `s3_1_quick_add_sheet.dart` until ruled.
