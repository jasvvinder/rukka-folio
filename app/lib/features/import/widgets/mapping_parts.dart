// S7.0b — the column-mapping rows and the sample line they produce.
//
// The bank's own header cells are shown as **data** (they are quoted from the
// file, never translated, and never live in ARB — `check_strings` carves them
// out by name). Everything the app says about them is in the user's words:
// *Money in* / *Money out*, never Dr/Cr (02 §10 🔒).
import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/format/date_format.dart';
import '../../../shared/format/money_format.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';
import '../../../shared/widgets/rk_fit_text.dart';
import '../parse/column_mapping.dart';
import '../parse/parsed_statement.dart';

/// The user's word for one column role. Never the bank's Dr/Cr.
String columnRoleLabel(AppLocalizations l, StatementColumn role) =>
    switch (role) {
      StatementColumn.date => l.importMapColDate,
      StatementColumn.description => l.importMapColText,
      StatementColumn.moneyOut => l.importMapColMoneyOut,
      StatementColumn.moneyIn => l.importMapColMoneyIn,
      StatementColumn.amount => l.importMapColAmount,
      StatementColumn.direction => l.importMapColDirection,
      StatementColumn.balance => l.importMapColBalance,
    };

/// One role and the column it was read from, correctable.
///
/// Laid out as label-above-control rather than side by side: at 200 % a
/// Gurmukhi label and a long bank header cannot share a 360 px row, and the
/// control must stay reachable (07 §1 rule 9, 13 §8).
class MappingRow extends StatelessWidget {
  /// Creates the row.
  const MappingRow({
    super.key,
    required this.role,
    required this.headers,
    required this.value,
    required this.onChanged,
    this.required = false,
  });

  /// Which role this row sets.
  final StatementColumn role;

  /// The file's own header cells, in column order.
  final List<String> headers;

  /// The column currently playing [role], or null for *not in this file*.
  final int? value;

  /// A correction.
  final ValueChanged<int?> onChanged;

  /// Whether *not in this file* is offered. The date column is not optional.
  final bool required;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final status = RkStatusColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: RkSpace.gutter,
        vertical: RkSpace.s2,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RkFitText(
            columnRoleLabel(l, role),
            style: theme.textTheme.labelLarge,
          ),
          const SizedBox(height: RkSpace.s1),
          DropdownButtonFormField<int?>(
            // A correction to one role can move another's column, so the
            // field is re-keyed on its value: a FormField keeps its own state
            // and would otherwise show the column it opened with.
            key: ValueKey('${role.name}:$value'),
            initialValue: value,
            isExpanded: true,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: RkSpace.s3,
                vertical: RkSpace.s2,
              ),
              labelStyle: TextStyle(color: status.muted),
            ),
            items: [
              if (!required)
                DropdownMenuItem<int?>(
                  child: Text(
                    l.importMapColNone,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              for (var i = 0; i < headers.length; i++)
                DropdownMenuItem<int?>(
                  value: i,
                  // The bank's own header, verbatim, as data. Ellipsis is the
                  // design here: a 60-character header is the bank's doing.
                  child: Text(
                    headers[i].trim().isEmpty ? '#${i + 1}' : headers[i],
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

/// The sample row: one line of the file, read the way the mapping says.
///
/// This is what the user confirms. Date, the bank's own words in muted
/// monospace (02 §10 🔒 — never mistaken for the user's words, truncated to
/// one line with a tail ellipsis), and the amount with its direction in
/// consumer words.
class SampleLineCard extends StatelessWidget {
  /// Creates the card.
  const SampleLineCard({super.key, required this.line});

  /// The line to show, or null when the mapping reads nothing.
  final ParsedLine? line;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final status = RkStatusColors.of(context);
    final line = this.line;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        RkSpace.gutter,
        RkSpace.s4,
        RkSpace.gutter,
        RkSpace.s2,
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(RkSpace.cardPadding),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(RkRadius.lg),
          border: Border.all(color: status.hairline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RkFitText(
              line == null ? l.importMapSampleNone : l.importMapSample,
              style: theme.textTheme.bodySmall?.copyWith(color: status.muted),
            ),
            if (line != null) ...[
              const SizedBox(height: RkSpace.s2),
              RkFitText(
                formatLedgerDate(line.date, strings: l),
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: RkSpace.s1),
              // `bank_text`, muted monospace, one line with a tail ellipsis;
              // the stored value is always complete (02 §10 🔒).
              Text(
                line.bankText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: status.muted,
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(height: RkSpace.s2),
              MoneyText(
                line.direction == BankDirection.moneyIn
                    ? line.paise
                    : -line.paise,
                showDirection: true,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
