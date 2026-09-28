# ADR 2026-09-27 — a report or statement is exported only when nothing in it awaits approval

**Status:** accepted (owner-ruled, 27 Sep 2026, on the Canvas 17 design pull)
**Amends:** 07 §14 (export) · 13 §3.2 (adds S8.4). **Stands unchanged:** 02 §3 post-then-review, 06 §9.2
and 08 §4 (full export forever), ADR 2026-09-25 §7 (receipts next phase).

## Context

Canvas 17 *Reports and statements* (design project, drawn 25 Sep; `design/canvas-mirror/CHANGES.md`, 27 Sep)
draws every export as A4 pages. Its edge case **6a** and the PDF options sheet print an entry that is waiting
for approval but leave it out of the balance and totals, with the option *Show, not counted / Leave out*.
The canvas's example is an ordinary *Counter cash sales* entry (`reports-data.js:564`). That contradicts 02 §3 🔒 ⟦tests: n/a — citation, not behaviour⟧,
under which every entry counts the moment it is saved. A printed page that silently differs from the book is
the failure 13 §10 #5–#6 exist to prevent. The owner ruled on 27 Sep 2026 that a statement or report is not
generated or exported until the entries in it are approved. On the same day the owner chose the scope (the
report's own books and period), exempted the full backup, followed ADR 2026-09-25 §7 for the receipt, and
chose S8.4 for the new screen.

## Rulings 🔒 ⟦tests: n/a — container heading; each ruling below carries its own marker⟧

### 1. Export waits for approval ⟦tests: F1-27-1 @M12, F1-27-2 @M12, F1-27-3 @M12, F1-27-4 @M12⟧
- A report or statement (S4 A/C statement and S8.2 report viewer, as **PDF, CSV or XLSX**, and print through
  the share sheet) **cannot be generated or exported** while any entry **awaiting approval** falls within **that
  report's own book(s) and period**.
- *Awaiting approval* means an entry carrying an open **needs-review flag** (02 §3), or either half of an
  **inter-book transfer still in transit** (02 §6). An advance *request* is not an entry and does not block.
- Entries outside the report's books or period never block. A September flag does not stop an August statement.
- The export row shows **disabled-with-reason**, naming the count (*"2 entries are waiting for approval in this
  period"*). It has a door to the Inbox (S6) filtered to them, so the screen is never a dead end (07 §1).
- **Live balances are unchanged.** 02 §3 stands: the entry counts on every screen from the moment it is saved.
  Only the file waits.

### 2. The full backup is exempt ⟦tests: F1-27-5 @M12⟧
- **Export everything** (06 §9.2) is never gated by approvals. 08 §4 🔒 ⟦tests: n/a — citation, not behaviour⟧ (*data is never held hostage*) stands,
  including when a plan has lapsed or when an approver is absent.

### 3. Nothing prints with a pending entry left out ⟦tests: F1-27-3 @M12⟧
- Canvas 17's *Entries waiting for approval: Show, not counted / Leave out* option and edge case **6a** are
  **withdrawn**. Given §1, no exported page can contain an entry that awaits approval.

### 4. The donation receipt stays in the next phase ⟦tests: n/a — deferral, ADR 2026-09-25 §7⟧
- Canvas 17 row 5a is marked *next phase, Income Tax format*. Nothing is built from it now.

### 5. S8.4 PDF preview and options ⟦tests: F1-27-6 @M12⟧
- **S8.4** is the PDF preview shown before anything leaves the phone, and its options sheet. The sheet offers
  language and period. The page size is stated, not chosen, because orientation is set by the report. Share
  opens the system sheet.
- **S8.3 stays Family reconciliation** as built (`F1-07-24`, `F1-07-100…104`). Canvas 17's S8.3 label is renamed.

## Consequences
- **Code:** `app/lib/features/reports` gains an export gate over the live review queue
  (`LedgerReviewQueue`) and the in-transit reads, restricted to the report's books and period. The gate goes
  in front of the S4 and S8.2 export rows and the S8.4 screen. *Export everything* does not call it. No green
  test is flipped; `test/features/reports` has no test of export with a flag open.
- **Docs:** cross-reference lines at 07 §14 and 13 §3.2 (S8.4 row).
- **Design:** Canvas 17 needs 6a and the pending option removed, S8.3 relabelled S8.4, and 5a marked deferred.
  That is a push to the design project, done on the owner's request.
- **Milestone:** M12 reports lane (PLAN).

## Open ⚠️
- **The on-screen report is read as not gated.** S4 and S8.2 in the app are the live book, and they show the
  amber flags. §1 gates the files and print only. Owner to confirm.
- ~~Late arrivals~~ **Settled by ADR 2026-09-27b §3:** an unresolved late arrival blocks exports of its period.
