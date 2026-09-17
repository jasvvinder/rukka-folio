// The S4 statement header's cash-count block (02 §8.2 🔒 *Where it appears*):
//
//     Last counted 27 Aug · 20×500, 15×200, 25×100, ₹50 in coins
//     [ Count again ]
//
// It appears on the statement of a `cash` account and of a `cash_collection`
// account, and nowhere else — a bank, party or category A/C is not counted.
// The door's words change with the kind of count (02 §8.2 *Two kinds of
// count* 🔒): *Count again* verifies a balance the book already knows, *Open
// and count* is the gollak, where nobody knows what is inside until it is
// opened. The collection wording reuses S5.5's own `count.title.collect`, so
// the door and the sheet it opens can never drift apart.
//
// 07 §1 rule 6 — no dead doors, and no dead ends either. The last-count line
// is drawn only when there *is* one to draw: with no [CashCountScope] mounted,
// with a load that fails, or with an account never counted, the button stands
// alone and still opens the sheet. Nothing here throws, and nothing here is a
// tap that does nothing.
import 'package:core_ledger/core_ledger.dart';
import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/format/date_format.dart';
import '../../../shared/format/money_format.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';
import '../../cash_count/cash_count_source.dart';

/// The last-count line and the door to S5.5, for one countable A/C.
class CashCountHeader extends StatefulWidget {
  /// Creates the header block.
  const CashCountHeader({super.key, required this.account, this.onCount});

  /// The A/C the statement belongs to. Only `cash` and `cash_collection`
  /// draw anything (02 §8.2).
  final Account account;

  /// Opens S5.5 for this A/C. Null draws no button at all rather than an
  /// inert one — the header line, if there is one, still shows.
  final void Function(String accountId)? onCount;

  @override
  State<CashCountHeader> createState() => _CashCountHeaderState();
}

class _CashCountHeaderState extends State<CashCountHeader> {
  LastCashCount? _last;
  bool _started = false;

  bool get _countable {
    final subtype = widget.account.subtype;
    return subtype == MoneySubtype.cash ||
        subtype == MoneySubtype.cashCollection;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // An InheritedWidget may only be read from here on (the defect S3 and S4
    // both carried once): reading the scope in initState throws.
    if (_started || !_countable) return;
    _started = true;
    final source = CashCountScope.maybeOf(context);
    if (source == null) return; // The door alone — never an error state.
    _load(source);
  }

  Future<void> _load(CashCountSource source) async {
    try {
      final target = await source.loadTarget(widget.account.id);
      if (!mounted) return;
      setState(() => _last = target.lastCount);
    } catch (_) {
      // A statement is not the count sheet: a count we could not read is a
      // line we do not draw, not a screen that fails. S5.5 itself owns the
      // error-with-retry state for this read (13 §4.3).
    }
  }

  /// The sheet in 02 §8.2's own form — biggest note first, coins last.
  String? _breakdown(AppLocalizations l10n, Locale locale) {
    final sheet = _last?.sheet;
    if (sheet == null) return null;
    final values =
        sheet.notes.keys.where((v) => (sheet.notes[v] ?? 0) > 0).toList()
          ..sort((a, b) => b.compareTo(a));
    final parts = [
      for (final value in values)
        l10n.ledgerStatementCountNote('${sheet.notes[value]}', '$value'),
      if (sheet.coinsPaise.raw > 0)
        l10n.ledgerStatementCountCoins(
          formatPaise(sheet.coinsPaise.raw, locale: locale),
        ),
    ];
    return parts.isEmpty ? null : parts.join(', ');
  }

  @override
  Widget build(BuildContext context) {
    if (!_countable) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context);
    final status = RkStatusColors.of(context);
    final last = _last;
    final date = last == null
        ? null
        : formatLedgerDate(last.date, strings: l10n);
    final breakdown = _breakdown(l10n, locale);
    final line = date == null
        ? null
        : breakdown == null
        ? l10n.countLastCounted(date)
        : l10n.ledgerStatementCountLast(date, breakdown);
    final collection = widget.account.isCollection;
    final open = widget.onCount;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        RkSpace.gutter,
        RkSpace.s2,
        RkSpace.gutter,
        RkSpace.s2,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (line != null)
            Padding(
              padding: const EdgeInsets.only(bottom: RkSpace.s2),
              child: Text(
                line,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: status.muted),
              ),
            ),
          if (open != null)
            // A button, not a bare tappable line: the icon travels with the
            // words so *this opens something* never rides on colour alone
            // (07 §1 rule 3).
            OutlinedButton.icon(
              onPressed: () => open(widget.account.id),
              icon: Icon(
                collection ? Icons.savings_outlined : Icons.calculate_outlined,
              ),
              label: Text(
                collection
                    ? l10n.countTitleCollect
                    : l10n.ledgerStatementCountAgain,
              ),
            ),
        ],
      ),
    );
  }
}
