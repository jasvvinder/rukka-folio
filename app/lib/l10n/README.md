# app/lib/l10n — strings (01 §1 rule 9 🔒, CLAUDE.md rule 8)

- **Edit `parts/<feature>_{en,pa,hi}.arb`.** One feature folder, one trio of part
  files; every key ships in all three languages or `gen_l10n_arb.dart` fails.
- `app_en.arb`, `app_pa.arb`, `app_hi.arb` are **generated** (`@@x-generated`)
  by `dart run scripts/gen_l10n_arb.dart` — the merge of every part. Never edit
  them; the next run overwrites your change.
- `gen/` (git-ignored) holds the identifier-keyed copies gen_l10n reads.
- Keys stay dotted `screen.element.state`; `scripts/check_strings.dart` gates
  parity, ICU placeholders and the forbidden-jargon list (01 §1 rule 4).
