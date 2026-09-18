// S10.2 — the month summary card 🔒 (07 §13, adopted 30 Aug 2026; 13 §3.2 row
// S10.2).
//
// "The screen shown immediately after a book locks is a **reward, not a
// receipt**" — *"August · in ₹1,75,000 · out ₹1,38,200 · saved ₹36,800"* with
// the three largest expenses and, in a joint family, each sub-family's total.
// So this card states three figures large and plainly, and it does not restate
// the close: no vector hash, no declared-balance table, no blocker list. Those
// belong to step 4, which the closer has just finished.
//
// **Consumer vocabulary throughout** — *Money in / Money out*, never Dr/Cr
// (02 §10 🔒, CLAUDE.md rule 9). Every figure arrives as positive integer
// paise from the seam; the engine's signs are read there and never shown here.
//
// **The share door.** 07 §13 🔒 wants this *"shareable to WhatsApp as an
// image"*. The app's one share sink is `shareReportFile(ReportFile)`
// (`features/reports/export/file_report_sink.dart`), and `ReportFile` carries
// a **closed** `ReportFormat` — `pdf | csv | xlsx` — not an arbitrary media
// type, so no PNG can pass through it and forking the sink would put a second
// share path in the app. The door therefore renders **disabled with its
// reason** and points at where the figures *are* (13 §4.3, 07 §1 rule 6); the
// change wanted on `ReportFile` is recorded as an open item. Nothing here
// imports the sink, because nothing here can use it yet.
//
// Tokens only — a hex literal here is review-blocking (CLAUDE.md,
// design-system).
import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/format/money_format.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';
import '../../../shared/widgets/rk_fit_text.dart';
import '../../../shared/widgets/rk_ruled_card.dart';
import '../close_source.dart';
import 'close_parts.dart';

/// Keys S10.2's parts answer to.
abstract final class MonthSummaryKeys {
  /// The whole card.
  static const card = Key('close.summary');

  /// The three figures: in, out, saved.
  static const figures = Key('close.summary.figures');

  /// The three-largest-expenses list.
  static const top = Key('close.summary.top');

  /// The per-sub-family list, in a joint family.
  static const families = Key('close.summary.families');

  /// The disabled *Share as a picture* door.
  static const share = Key('close.summary.share');

  /// The way off the card.
  static const done = Key('close.summary.done');
}

/// S10.2 — the reward shown the moment a book's month locks.
class MonthSummaryCard extends StatelessWidget {
  /// Creates the card.
  const MonthSummaryCard({
    super.key,
    required this.summary,
    required this.monthLabel,
    this.onDone,
  });

  /// The month, already added up by the seam.
  final MonthSummary summary;

  /// The month in the reader's own words, pre-formatted by the caller so this
  /// card and the wizard's title can never disagree (07 §1 rule 5 🔒).
  final String monthLabel;

  /// Leaves the card. Null renders no action — a caller that has nowhere to
  /// go (the wizard's own inline use) relies on its own chrome.
  final VoidCallback? onDone;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final status = RkStatusColors.of(context);
    final locale = Localizations.localeOf(context);
    final saved = summary.saved;

    return Column(
      key: MonthSummaryKeys.card,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            RkSpace.gutter,
            RkSpace.s4,
            RkSpace.gutter,
            RkSpace.s2,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RkFitText(
                l.closeSummaryTitle(monthLabel),
                style: text.titleLarge,
              ),
              if (summary.bookName.isNotEmpty)
                RkFitText(
                  l.closeBook(summary.bookName),
                  style: text.bodySmall?.copyWith(color: status.muted),
                ),
            ],
          ),
        ),

        // The three figures 07 §13 🔒 names, in its order.
        CloseCard(
          key: MonthSummaryKeys.figures,
          rule: status.success,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Figure(label: l.closeSummaryIn, paise: summary.moneyIn.raw),
              _Figure(label: l.closeSummaryOut, paise: summary.moneyOut.raw),
              _Figure(
                label: l.closeSummarySaved,
                paise: saved.raw,
                strong: true,
              ),
              // A negative *Saved* is stated in words as well as in the sign:
              // colour and a minus are never the only carriers (07 §1 rule 3).
              if (saved.raw < 0)
                Padding(
                  padding: const EdgeInsets.only(top: RkSpace.s1),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: RkSpace.s4,
                        color: status.warning,
                      ),
                      const SizedBox(width: RkSpace.s2),
                      Expanded(
                        child: RkFitText(
                          l.closeSummaryOverspent,
                          style: text.bodySmall?.copyWith(color: status.muted),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),

        // The three largest expenses (07 §13 🔒).
        CloseCard(
          key: MonthSummaryKeys.top,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RkFitText(l.closeSummaryTop, style: text.titleMedium),
              const SizedBox(height: RkSpace.s2),
              if (summary.topExpenses.isEmpty)
                RkFitText(
                  l.closeSummaryTopEmpty,
                  style: text.bodyMedium?.copyWith(color: status.muted),
                )
              else
                for (final e in summary.topExpenses)
                  _Line(
                    name: e.name,
                    amount: formatPaise(e.amount.raw, locale: locale),
                  ),
            ],
          ),
        ),

        // Each sub-family's month, in a joint family (07 §13 🔒). Empty
        // everywhere else, and then the heading is not drawn at all.
        if (summary.subFamilies.isNotEmpty)
          CloseCard(
            key: MonthSummaryKeys.families,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RkFitText(l.closeSummaryFamilies, style: text.titleMedium),
                const SizedBox(height: RkSpace.s2),
                for (final f in summary.subFamilies) ...[
                  RkFitText(f.name, style: text.bodyLarge),
                  _Line(
                    name: l.closeSummaryIn,
                    amount: formatPaise(f.moneyIn.raw, locale: locale),
                  ),
                  _Line(
                    name: l.closeSummaryOut,
                    amount: formatPaise(f.moneyOut.raw, locale: locale),
                  ),
                  const SizedBox(height: RkSpace.s2),
                ],
              ],
            ),
          ),

        // Disabled with its reason — see the file header.
        CloseCard(
          key: MonthSummaryKeys.share,
          child: CloseDisabledAction(
            label: l.closeSummaryShare,
            reason: l.closeSummaryShareUnavailable,
            icon: Icons.image_outlined,
          ),
        ),

        if (onDone != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              RkSpace.gutter,
              RkSpace.s2,
              RkSpace.gutter,
              RkSpace.s4,
            ),
            child: FilledButton(
              key: MonthSummaryKeys.done,
              onPressed: onDone,
              child: RkFitText(l.closeSummaryDone),
            ),
          ),
      ],
    );
  }
}

/// One of the three headline figures: the word, then the amount.
///
/// [RkLabelAmountRow] is the house row for `label … amount` and the only one
/// that drops the figure to its own line **as measured** rather than at a
/// text-scale threshold — which is what keeps `₹1,75,000` whole beside a
/// Gurmukhi label at 200 % on a 360 px phone (07 §1 rule 11).
class _Figure extends StatelessWidget {
  const _Figure({
    required this.label,
    required this.paise,
    this.strong = false,
  });

  final String label;
  final int paise;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: RkSpace.s1),
      child: RkLabelAmountRow(
        label: RkFitText(
          label,
          style: strong ? text.titleMedium : text.bodyLarge,
        ),
        amount: RkFitText(
          formatPaise(paise, locale: Localizations.localeOf(context)),
          style: strong ? RkType.amountHero : RkType.amountRow,
          textAlign: TextAlign.end,
        ),
      ),
    );
  }
}

/// A name-and-amount row inside one of the lists.
class _Line extends StatelessWidget {
  const _Line({required this.name, required this.amount});

  final String name;
  final String amount;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: RkSpace.s1),
      child: RkLabelAmountRow(
        label: RkFitText(name),
        amount: RkFitText(
          amount,
          style: RkType.amountRow,
          textAlign: TextAlign.end,
        ),
      ),
    );
  }
}
