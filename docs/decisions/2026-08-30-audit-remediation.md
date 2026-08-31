# ADR 2026-08-30 — Specification audit remediation

Every finding from the audit is addressed below. 12 files changed, 1 added, 1 deleted.
All four verifiers re-run clean against the patched package.

| Check | Before | After |
|---|---|---|
| Worked-example arithmetic | 175/175 clean | **175/175 clean** (unchanged — confirms the M3 edit was label-only) |
| Cross-book pairs (02 §6) | 3/3 net zero | **3/3 net zero** |
| Dangling references | 2 | **0** |
| Token / contrast issues | 1 | **0** |

---

## H1 + H2 — the superseded requirements document

**Changed:** `docs/requirements-architecture.md`, `CLAUDE.md`, `README.md`

The root cause was structural: CLAUDE.md's conflict rule covered *code vs docs* but there was no rule for **doc vs doc**, so nothing said which document wins. Three edits:

1. **A supersession banner** at the top of `requirements-architecture.md` with an 8-row table naming each superseded section, what it wrongly says, and which locked spec replaces it. Plus inline ⛔ markers at Flow 3, Flow 4, §6.2 and §6.3 so a reader landing mid-document still sees it.
2. **A precedence ladder in CLAUDE.md** (new section): `docs/decisions/` ADRs → numbered specs 00–12 (*topic owner wins* — 02 owns ledger semantics, 03 storage, 04 crypto, and a passing mention elsewhere never overrides the owner) → `docs/reference/` → `requirements-architecture.md`, explicitly non-normative. Same-level conflicts stop and ask.
3. **README reading order** relabelled so the document is no longer presented as current product context.

The banner also catches two things the audit flagged only in passing: the phantom **"Query"** approver action, and the **daily cash limit** for operators (06 §1.1 has a per-entry threshold, not a daily aggregate).

## M1 — post-then-review never reached doc 03

**Changed:** `docs/02-ledger-rules.md` §1.3, §8.1, §9, §11 · `docs/03-data-model.md` §3.2, §3.3

The fix separates two things the docs had collapsed into one word:

- **`status`** stays `pending | posted | void`, but §1.3 now states that **`pending` means only "advance request awaiting approval"** — the single case (02 §7) where approval itself moves the money.
- **`review_state`** (`none | open | approved | rejected`) is new and independent. An over-limit ordinary entry is `posted` + `review_state='open'` and counts in balances from the first moment.

`entries_p` gains `review_state`, `review_approver`, `review_decided_hlc`, `review_reason`. The Inbox index is re-keyed to `(book_id, review_approver) where review_state='open'`, with a second, much smaller index for the advance queue. §8.1's FY-close precondition now names **both** queues explicitly.

**§9's balance definition** is rewritten: pending advance requests are excluded (the money genuinely hasn't moved); `review_state` never affects a balance, and a rejection removes its effect through the mirror reversal rather than by excluding the original.

### One thing worth knowing about this fix

The obvious implementation — *"projector looks up the member's limit and flags anything over it"* — **would have broken the close-hash.** `auto_post_limit_paise` lives in `book_roles`, which is plaintext server metadata, not an envelope; 03 §3.3.2 forbids the projector from reading it. Two devices with differently-cached role metadata would compute different flags and therefore different balance-vector hashes, silently failing month close (02 §8 step 4) with no obvious cause.

So the **authoring** client evaluates the limit at save time and writes `review_required` (plus `review_limit_paise`, for reader-side verification) into the entry payload. The projector only folds `approval_decision` envelopes over that boolean. New rule **03 §3.3.5** states this and says why.

## M2 — key rotation vs the offline window ⚠️ **needs your sign-off**

**Changed:** `docs/04-crypto.md` §5.3 · `docs/05-sync-protocol.md` §3, §5, §10

This was the only finding that needed a decision rather than an edit. Three options were on the table:

| Option | Verdict |
|---|---|
| Make the 48 h grace relative to each device's last-seen rotation notice | **Rejected** — the server can't verify that claim, and a hostile client would just assert it had never seen the notice |
| Accept rotation-window loss, document it in 04 §1.2 | **Rejected** — contradicts the at-least-once guarantee, and silently losing a shopkeeper's month of entries is the worst possible failure for this product |
| **Client re-seals queued envelopes under the new key before pushing** | **Adopted** |

Re-seal works because everything needed is already on the device: the outbox stores the full envelope blob (03 §3.1) and `key_cache` retains **all** key versions (03 §3.1), so the client can decrypt under `BK(v)` and re-encrypt under `BK(v+1)`.

The spec now says: **key sync precedes outbox drain on every reconnect** (previously stated only for bootstrap, §8 — that ordering is what makes the rest possible), then any queued envelope below the highest key version is decrypted, re-encrypted, re-AAD'd and re-signed, **preserving `envelope_id`, `object_id`, `hlc` and payload byte-for-byte**. Only `key_version`, `nonce`, `ciphertext` and `author_sig` change.

Three properties make this safe:
- Preserving `envelope_id` keeps idempotency — if the pre-rotation copy landed inside the grace window, the server dedupes and the re-sealed copy is a no-op.
- Preserving `hlc` keeps ordering and the Late Arrivals rule (02 §8) unchanged. **Re-sealing is a re-wrapping, not a re-authoring**, and must never alter what an entry means.
- It is not an append-only violation: an outbox envelope has never been stored, so nothing is mutated.

`rejected:key_version_stale` is added to the §3 push table as the missing result code, and is the **one non-terminal rejection** — exactly one re-seal-and-retry, so it cannot loop. 04 §5.3 is reframed: the 48 h grace now explicitly covers **the in-flight race only**, and is no longer pretending to be how offline devices are accommodated.

Two acceptance tests added (05 §10) covering the 30-day-offline-across-rotation case and the grace-window boundary.

> ⚠️ **Sign-off needed:** re-seal is a genuine addition to the crypto surface. It is small and uses no new primitive, but it means a client decrypts and re-encrypts data it has already authored. Worth putting in front of the external crypto review at M14 (10 M14) rather than shipping unreviewed.

## M3 — worked-example class vocabulary

**Changed:** `docs/reference/worked-examples/individual-rahul-sharma.md` · **added** `docs/reference/worked-examples/README.md`

Rather than rewriting all seven books' labels — a bookkeeper reviewing these *should* see "Creditor" — the fix makes the mapping explicit and binding:

- **New README** with the label ⇄ class table (Debtor and Creditor both → `party`), an explanation of why the split is presentation-only and would be wrong the moment a balance crossed zero, and a **do/don't list for the fixture harness**: assert postings, balances and TB rows; never assert the type label.
- **The credit card is retyped** to `money` subtype `CC` in both the chart of accounts and its ledger header. Its postings were already correct and are untouched — re-running the verifier confirms 175/175 still clean.

The README also records **four coverage gaps** the audit surfaced: two unpaired inter-book balances (Rahul ₹2,00,000, Geeta ₹2,60,000), and the absence of any period lock, year close, amendment, reversal or import line anywhere in the examples. None blocks sign-off on the arithmetic; all bound what the fixtures can prove.

## Low severity

| # | Fix |
|---|---|
| **L1** | `design-system.md` §2 `pending` light corrected `#A16C00` → `#8F5F00`, matching tokens.json. The stale value measured **3.96:1 and fails AA**; the correct one is 4.85:1. §3 already described the change. |
| **L2** | `07-ui-flows.md` §16: garbled `(09 §9.2 of doc 06 …)` → `06 §9.2`. `10-roadmap.md` M13: `08 §4.1` → `08 §3.2` (where the IAP content actually lives). Dangling refs now 0. |
| **L3** | Deleted the misfiled `rukka-folio-ux-architecture.pdf` from `worked-examples/` (byte-identical duplicate of the `design/` copy, md5 `7acd153a…`). The CA reviewing that folder no longer receives a UX document among the accounting exhibits. |
| **L4** | 01 §1.3 gains a carve-out: *folio* is forbidden **as a common noun only**; the product name is exempt, and `check_strings.dart` must whitelist `app.name` / `about.*` rather than flagging them. Prevents CI tripping on the app's own name. |
| **L5** | Recorded as gap #1 in the new worked-examples README (needs two more books generated, not a doc edit). |
| **L6** | README conventions block now documents the dual meaning of `NN §M` — real sub-heading *or* Mth numbered item — and adds ⛔ to the marker legend. |

---

## Still open — not fixable by editing

1. **M2 crypto sign-off** (above) — decision made and specified, but the re-seal path should go to external review at M14.
2. **Two more fixture books** — Rahul and Geeta sub-family books, to close the remaining 2 of 5 due-to/due-from pairs.
3. **Bookkeeper re-verification** — still pending on the corrected standards doc; the errata's own ⚠️ note.
4. **The two open items the audit flagged for promotion** — the Shamir library choice (04 §2, gates M3 and the flagship recovery rung) and the iOS IAP decision (08 §3.2, affects pricing arithmetic, not just plumbing).
