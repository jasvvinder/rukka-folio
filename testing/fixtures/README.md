# testing/fixtures — synthetic sync and UI fixtures only

Created at M2 (CLAUDE.md § Layout; ADR 2026-09-05i §7).

- **Synthetic data only.** Never a real entry, phone number, name or amount from anyone's books
  (CLAUDE.md rule 4). Phone numbers use the reserved `+91 99999 xxxxx` range; people are the fictional
  Sharma / Kaur / Verma families already used by the worked examples. `scripts/check_purity.sh` greps
  this tree for real-looking mobile, Aadhaar and PAN strings.
- **Accounting goldens do not live here.** The five reference books stay in `docs/accounting/reference-books/`
  and are parsed in place by the suite-A engine test — one source (ADR 2026-10-20; that test re-lands at M14).
- Fixtures land with the milestone that needs them: hostile envelopes (M3/M4, `--dart-define=HOSTILE_ENVELOPES=true`),
  two-client sync scripts (M4, suite D), screen fixtures (M5, suite F1).
