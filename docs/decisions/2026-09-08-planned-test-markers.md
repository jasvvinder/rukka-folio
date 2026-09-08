# ADR 2026-09-08 — Planned-test markers: a 🔒 line may name a test that has not landed yet

ADR 2026-09-05i §1 gave every 🔒 line two ways to satisfy traceability: name real test ids, or
declare itself deliberately untestable with `⟦tests: n/a — reason⟧`. Three days of annotation
showed the contract is missing the case that dominates the backlog. Of the 185 unmarked 🔒 lines
counted on 8 Sep 2026, roughly ninety describe **real, testable behaviour whose milestone is not
built** — `07-ui-flows` (61 lines: screens land M5 onward), `08-subscription` (11: M12),
`12-admin-console` (9: M13). Neither existing form fits them:

- naming the intended id fails check (b), "an id in a marker that no test declares";
- `n/a — reason` is false — the behaviour *is* testable — and worse, it is **terminal**: once a line
  reads `n/a`, nothing ever forces it to acquire a real id when the milestone lands. It buries the
  debt instead of scheduling it.

The gap is not hypothetical: ADR 2026-09-06 §7 already writes `⟦tests: B-04-63, F1-06a-1⟧` where its
own table labels `F1-06a-1 (M11, suite F1)`. The contract was being violated by the ADRs written
under it, because the honest annotation had no legal syntax. 05i §1 also anticipated this outcome
without providing for it, promising the backlog would be "annotated milestone by milestone as their
tests land" while `--strict` turns blocking at M4 exit. Owner ruling, 8 Sep 2026.

## Rulings 🔒 ⟦tests: n/a — container heading; each ruling below carries its own marker⟧

### 1. A third marker form: an id may carry an explicit milestone ⟦tests: n/a — marker syntax, exercised by check_coverage's own tests⟧
A marker id may be suffixed ` @M<n>`, meaning *this test is planned and lands at milestone n*:

```
**Some locked rule 🔒** … ⟦tests: F1-07-12 @M5⟧
**Mixed is legal 🔒** … ⟦tests: E-03-9, F1-08-3 @M12⟧
```

- The id must still be well-formed `<Suite>-<source>-<n>` (05i §1 is unchanged on id shape); `@M<n>`
  is a property of the *marker*, not part of the id.
- A planned id is **exempt from check (b)** — no test need declare it yet.
- A planned id is **not** an orphan-check participant: when the test lands, the ` @M<n>` suffix is
  deleted in the same commit and the line becomes an ordinary marker.

### 2. A planned marker expires — it fails once its milestone is reached ⟦tests: n/a — CI phasing; enforced by check_coverage --milestone⟧
`check_coverage --milestone M<n>` **fails** on any ` @M<k>` marker with `k ≤ n` whose test still does
not exist. This is the property `n/a` lacks: the annotation schedules its own removal, and a
milestone cannot be exited while it owes tests it promised. Reported as `overdue planned tests`,
alongside the existing overdue-supersession check of 05i §4, which it deliberately mirrors.

### 3. Planned lines are counted, never hidden ⟦tests: n/a — reporting format⟧
The summary line reports `planned` as its own figure beside `marked`, `n/a` and `unmarked`. A 🔒 line
carrying only planned ids is **not** "covered"; it is scheduled. Any statement of coverage — PLAN.md
§0, a milestone exit — quotes the planned count separately, so nobody reads a wall of `@M13` markers
as evidence of anything.

## Consequences
- `scripts/check_coverage.dart` accepts and counts the form, exempts planned ids from check (b), and
  gains the overdue-planned failure under `--milestone`.
- ADR 2026-09-06 §7's `F1-06a-1` becomes legal as `F1-06a-1 @M11` — the annotation the author meant.
- 05i §1 is amended, not superseded: forms (a) real ids and (b) `n/a — reason` are untouched, and
  every existing marker stays valid. No test asserts the two-form rule, so 05i §4 supersession does
  not apply and no test is skipped by this ADR.
