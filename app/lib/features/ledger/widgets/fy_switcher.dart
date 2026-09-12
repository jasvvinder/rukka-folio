// The financial-year switcher (ADR 2026-09-09 §4 🔒) — one control that S4
// wears today and S8.2 / S10.4 will wear on the same terms:
//
//   • the year renders as a **chip**, and tapping it opens a bottom sheet
//     listing the years;
//   • a closed year shows the **b/f it hands to the next year** and the badge
//     copy *Certified* — copy, not a state (13 §6) — with the word beside the
//     tick, never colour alone (07 §1);
//   • **before the first year close there is no switcher**: one year exists,
//     so the year stays plain text. A control that opens a list of one is a
//     lie, so this file draws plain text whenever no year has closed.
//
// There is no year-close source until S10.4 lands (M9), so the closed years
// arrive through the [ClosedYearsSource] seam, which defaults to *none* — the
// same shape as `features/home`'s `RebuildProgressSource`. Shipped behaviour
// today is therefore plain text, and the chip is exercised from a fake.
import 'package:core_ledger/core_ledger.dart';
import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/format/money_format.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';

/// A financial year that has been closed and certified (02 §8.1).
@immutable
final class ClosedYear {
  /// Creates the record.
  const ClosedYear({required this.year, required this.carriedForwardPaise});

  /// The year itself.
  final FinancialYear year;

  /// The **b/f it hands to the next year** for the account being shown,
  /// signed paise (+ = Dr) — the certified closing balance of 02 §8.1.
  final int carriedForwardPaise;

  @override
  bool operator ==(Object other) =>
      other is ClosedYear &&
      other.year == year &&
      other.carriedForwardPaise == carriedForwardPaise;

  @override
  int get hashCode => Object.hash(year, carriedForwardPaise);
}

/// The seam S4 consumes: the certified years of [bookId], for [accountId],
/// oldest first. Empty until the first year close — which is every build
/// before M9, so [noClosedYears] is what the app ships.
typedef ClosedYearsSource = Future<List<ClosedYear>> Function(
  String bookId,
  String accountId,
);

/// The shipped source: no year has closed, so there is no switcher.
Future<List<ClosedYear>> noClosedYears(String bookId, String accountId) async =>
    const <ClosedYear>[];

/// The year on a statement header: plain text until a year has closed, a chip
/// after it (ADR 2026-09-09 §4).
class FySwitcher extends StatelessWidget {
  /// Creates the switcher.
  const FySwitcher({
    super.key,
    required this.selected,
    required this.closedYears,
    required this.openYear,
    required this.onSelected,
  });

  /// The year the statement is showing.
  final FinancialYear selected;

  /// Certified years, oldest first. Empty ⇒ plain text, no control.
  final List<ClosedYear> closedYears;

  /// The year still running — always offered, never certified.
  final FinancialYear openYear;

  /// Called with the year the reader picked.
  final ValueChanged<FinancialYear> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final status = RkStatusColors.of(context);
    final label = l10n.ledgerStatementFy(selected.label);

    if (closedYears.isEmpty) {
      // One year exists. Plain muted text — the control would be a lie.
      return Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: RkSpace.gutter,
          vertical: RkSpace.s1,
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelLarge
              ?.copyWith(color: status.muted),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: RkSpace.gutter,
        vertical: RkSpace.s1,
      ),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: ActionChip(
          avatar: const Icon(Icons.expand_more),
          label: Text(label),
          tooltip: l10n.ledgerStatementFyChange,
          onPressed: () => _open(context),
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context) async {
    final picked = await showModalBottomSheet<FinancialYear>(
      context: context,
      showDragHandle: true,
      builder: (context) => _YearSheet(
        selected: selected,
        closedYears: closedYears,
        openYear: openYear,
      ),
    );
    if (picked != null) onSelected(picked);
  }
}

class _YearSheet extends StatelessWidget {
  const _YearSheet({
    required this.selected,
    required this.closedYears,
    required this.openYear,
  });

  final FinancialYear selected;
  final List<ClosedYear> closedYears;
  final FinancialYear openYear;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final status = RkStatusColors.of(context);
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: RkSpace.s4),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              RkSpace.gutter,
              RkSpace.s1,
              RkSpace.gutter,
              RkSpace.s2,
            ),
            child: Text(
              l10n.ledgerStatementFyChange,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          for (final closed in closedYears)
            _YearRow(
              year: closed.year,
              selected: closed.year == selected,
              // A closed year carries its badge and the figure it hands on.
              badge: _CertifiedBadge(text: l10n.ledgerStatementFyCertified),
              detail: _Carried(paise: closed.carriedForwardPaise),
            ),
          _YearRow(
            year: openYear,
            selected: openYear == selected,
            badge: Text(
              l10n.ledgerStatementFyOpen,
              style: Theme.of(context).textTheme.labelMedium
                  ?.copyWith(color: status.muted),
            ),
          ),
        ],
      ),
    );
  }
}

class _YearRow extends StatelessWidget {
  const _YearRow({
    required this.year,
    required this.selected,
    required this.badge,
    this.detail,
  });

  final FinancialYear year;
  final bool selected;
  final Widget badge;
  final Widget? detail;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final title = Text(l10n.ledgerStatementFy(year.label));
    // Past 1.3x a ListTile cannot hold a title and a worded badge on one line
    // at 360 px, so the badge drops under the year (07 §1 rule 11).
    final stacked = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    return ListTile(
      minTileHeight: RkSpace.rowMinHeight,
      // Selection is never colour alone (07 §1): the tick says it too.
      leading: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
      ),
      selected: selected,
      title: stacked
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                title,
                const SizedBox(height: RkSpace.s1),
                badge,
              ],
            )
          : title,
      subtitle: detail,
      trailing: stacked ? null : badge,
      onTap: () => Navigator.of(context).pop(year),
    );
  }
}

/// *Carried forward to next year* and the figure it hands on. The label and
/// the amount stack rather than share a line: side by side they overflow a
/// sheet row before 200% is even reached (07 §1 rule 11).
class _Carried extends StatelessWidget {
  const _Carried({required this.paise});

  final int paise;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final status = RkStatusColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          l10n.ledgerStatementFyCarried,
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: status.muted),
        ),
        const SizedBox(height: RkSpace.s1),
        MoneyText(
          paise,
          vocabulary: Vocabulary.professional,
          showDirection: true,
          favour: paise == 0
              ? null
              : paise > 0
              ? Favour.favourable
              : Favour.unfavourable,
        ),
      ],
    );
  }
}

/// *Certified* — badge copy, not a state (02 §8.1, 13 §6). The word rides
/// beside the tick so the meaning never depends on the colour (07 §1).
class _CertifiedBadge extends StatelessWidget {
  const _CertifiedBadge({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final status = RkStatusColors.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.verified_outlined, size: RkSpace.s4, color: status.success),
        const SizedBox(width: RkSpace.s1),
        Text(
          text,
          style: Theme.of(context).textTheme.labelMedium
              ?.copyWith(color: status.success),
        ),
      ],
    );
  }
}
