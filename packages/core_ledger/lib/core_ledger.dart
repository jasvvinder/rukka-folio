/// Ledger engine: entries, verbs to postings, invariants, amend/reverse,
/// periods, advances, inter-book pairs, partners, cash counts, balances (02). M1.
///
/// Spec owner: `docs/02-ledger-rules.md`; behavioural reference:
/// `docs/reference/financial-accounting-standards.md` + `worked-examples/`.
/// Pure Dart — no Flutter, no I/O, no `DateTime.now()`, no `Random()`
/// (CLAUDE.md rule 3; CI-enforced by `scripts/check_purity.sh`). Clock and RNG
/// are always injected: dates arrive as `LocalDate`, order as `Hlc`.
///
/// Two vocabularies, one engine (02 §10): everything here is signed paise with
/// + = debit and − = credit. Consumer surfaces translate to Money in / Money out;
/// professional surfaces show absolute value + side. The posting logic never
/// bends to the display language.
library;

export 'src/accounts.dart';
export 'src/advances.dart';
export 'src/balances.dart';
export 'src/cash_count.dart';
export 'src/entry.dart';
export 'src/events.dart';
export 'src/hlc.dart';
export 'src/interbook.dart';
export 'src/invariants.dart';
export 'src/local_date.dart';
export 'src/money.dart';
export 'src/partners.dart';
export 'src/projection.dart';
export 'src/ratio.dart';
export 'src/verbs.dart';

/// Package identity used by the M0 hello-world gate.
const String packageName = 'core_ledger';
