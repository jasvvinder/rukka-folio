// The pieces S7.1 and S7.3 are built from (13 §4.1: one component, one
// definition). Tokens only — a hex literal here is review-blocking.
//
// **Bank vocabulary throughout 🔒** (02 §10, CLAUDE.md rule 9): every row
// reads *Money in* / *Money out* with the amount. Nothing in this file names
// a side, and nothing in it says Dr or Cr.
//
// Each row asks **one question** — *Where did it come from?* / *Where did it
// go?* — because a statement line already states direction and amount
// (02 §10 🔒). The user never chooses a side.
//
// ⚠️ SPEC: 02 §10 🔒 asks for the bank's text in *muted monospace*, and
// `design/tokens/tokens.json` carries no monospace family (11 §4.4 bundles
// one superfamily). `design/` is not this lane's directory, so the
// conservative reading is taken: the evidence line is muted **and italic**,
// which is the same intent — visibly the bank's words, never the user's —
// and the token is asked for in the lane report.
import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/format/date_format.dart';
import '../../../shared/format/money_format.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';
import '../../../shared/widgets/rk_fit_text.dart';
import '../import_lines.dart';

/// Widget keys S7.1's tests drive the inbox by.
abstract final class ImportInboxKeys {
  /// The primary action.
  static const submit = Key('import.inbox.submit');

  /// The header action onto S7.2.
  static const balance = Key('import.inbox.balance');

  /// The *Keep for later* path out of a blocked submit.
  static const keep = Key('import.inbox.keep');

  /// One row.
  static Key row(String id) => Key('import.inbox.row.$id');

  /// Its state chip.
  static Key chip(String id) => Key('import.inbox.chip.$id');

  /// `Matched ✓` → unlink.
  static Key unlink(String id) => Key('import.inbox.unlink.$id');

  /// `Suggested` → the one-tap Approve.
  static Key approve(String id) => Key('import.inbox.approve.$id');

  /// `New` → open the A/C picker.
  static Key choose(String id) => Key('import.inbox.choose.$id');

  /// One candidate inside the picker.
  static Key pick(String id, String accountId) =>
      Key('import.inbox.pick.$id.$accountId');

  /// The picker's search field.
  static Key search(String id) => Key('import.inbox.search.$id');

  /// `Suspense` → record now, explain later.
  static Key suspense(String id) => Key('import.inbox.suspense.$id');

  /// S7.3 → yes, one movement.
  static Key transferYes(String id) => Key('import.inbox.transfer.yes.$id');

  /// S7.3 → no, two different things.
  static Key transferNo(String id) => Key('import.inbox.transfer.no.$id');

  /// `+ note`.
  static Key note(String id) => Key('import.inbox.note.$id');

  /// The inline note field.
  static Key noteField(String id) => Key('import.inbox.note_field.$id');

  /// The bank's own words — tap to see the whole line.
  static Key bankText(String id) => Key('import.inbox.bank_text.$id');
}

/// The word a chip says. A **word**, never a tint alone (07 §1 rule 3).
String chipLabel(AppLocalizations l, ImportLine line) => switch (line.state) {
  ImportLineState.matched => l.importInboxChipMatched,
  ImportLineState.suggested => l.importInboxChipSuggested,
  ImportLineState.needsAnswer => l.importInboxChipNew,
  ImportLineState.transfer => l.importInboxChipTransfer,
  ImportLineState.suspense => l.importInboxChipSuspense,
  ImportLineState.answered => l.importInboxChipAnswered,
};

/// The one question this line asks (02 §10 🔒).
String oneQuestion(AppLocalizations l, ImportLine line) =>
    line.isMoneyIn ? l.importInboxQuestionIn : l.importInboxQuestionOut;

/// The state chip: an icon and a word, tinted only to reinforce them.
class ImportStateChip extends StatelessWidget {
  /// Creates the chip.
  const ImportStateChip({super.key, required this.line});

  /// The row it belongs to.
  final ImportLine line;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final status = RkStatusColors.of(context);
    final theme = Theme.of(context);
    final (icon, tint) = switch (line.state) {
      ImportLineState.matched => (Icons.link, status.success),
      ImportLineState.suggested => (Icons.lightbulb_outline, status.success),
      ImportLineState.needsAnswer => (Icons.help_outline, status.muted),
      ImportLineState.transfer => (Icons.swap_horiz, status.info),
      ImportLineState.suspense => (Icons.schedule, status.warning),
      ImportLineState.answered => (Icons.check_circle_outline, status.success),
    };
    return Container(
      key: ImportInboxKeys.chip(line.id),
      padding: const EdgeInsets.symmetric(
        horizontal: RkSpace.s2,
        vertical: RkSpace.s1,
      ),
      decoration: BoxDecoration(
        color: status.sunk,
        borderRadius: BorderRadius.circular(RkRadius.sm),
        border: Border.all(color: status.hairline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: RkIcon.grid, color: tint),
          const SizedBox(width: RkSpace.s1),
          Flexible(
            child: RkFitText(
              chipLabel(l, line),
              style: theme.textTheme.bodySmall?.copyWith(color: tint),
            ),
          ),
        ],
      ),
    );
  }
}

/// The bank's own line — **immutable evidence** (02 §10 🔒).
///
/// One truncated line with a tail ellipsis, the whole string on tap. The
/// stored value is always complete; truncation is display-only.
class BankTextLine extends StatelessWidget {
  /// Creates the line.
  const BankTextLine({
    super.key,
    required this.line,
    required this.expanded,
    required this.onToggle,
  });

  /// The row.
  final ImportLine line;

  /// Whether the whole string is showing.
  final bool expanded;

  /// Expands or collapses it.
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final status = RkStatusColors.of(context);
    return Semantics(
      label: l.importInboxBanktextLabel,
      button: true,
      child: InkWell(
        key: ImportInboxKeys.bankText(line.id),
        onTap: onToggle,
        child: Text(
          line.parsed.bankText,
          maxLines: expanded ? null : 1,
          overflow: expanded ? TextOverflow.clip : TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            color: status.muted,
            fontStyle: FontStyle.italic,
          ),
        ),
      ),
    );
  }
}

/// The amount with its direction — colour in the numerals, always beside the
/// word and the sign (07 §1 rule 3, 02 §10 🔒).
class ImportAmount extends StatelessWidget {
  /// Creates the amount.
  const ImportAmount({super.key, required this.line, this.alignEnd = true});

  /// The row.
  final ImportLine line;

  /// Whether the figure hangs off the right edge of the row (the ledger
  /// column) or sits under the date (the stacked form at large text scales).
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final status = RkStatusColors.of(context);
    final inward = line.isMoneyIn;
    final tint = inward ? status.credit : status.debit;
    final text = formatPaise(
      inward ? line.parsed.paise : -line.parsed.paise,
      locale: Localizations.localeOf(context),
      showPaise: line.parsed.paise % 100 != 0,
      signed: true,
    );
    final word = inward ? l.importInboxMoneyIn : l.importInboxMoneyOut;
    return Semantics(
      label: '$word $text',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: alignEnd
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          // `+₹1,23,456.78` has no break opportunity in it at all, so at
          // 200 % it is simply wider than the card however the row is
          // arranged. It scales down to fit rather than losing its last
          // digits — the same treatment S2 gives its hero amount, and the
          // only one that keeps every figure readable (07 §1 rules 4 and 11).
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: alignEnd
                ? AlignmentDirectional.centerEnd
                : AlignmentDirectional.centerStart,
            child: Text(
              text,
              maxLines: 1,
              style: RkType.amountRow.copyWith(color: tint),
            ),
          ),
          RkFitText(
            word,
            style: theme.textTheme.bodySmall?.copyWith(color: tint),
            maxLines: 1,
            textAlign: alignEnd ? TextAlign.end : TextAlign.start,
          ),
        ],
      ),
    );
  }
}

/// The inline A/C picker: search, pick, or create without leaving the row
/// (07 §11 item 2 🔒 — *full picker*, *inline-create*).
class ImportCounterpartPicker extends StatefulWidget {
  /// Creates the picker.
  const ImportCounterpartPicker({
    super.key,
    required this.lineId,
    required this.counterparts,
    required this.onPick,
    required this.onCreate,
  });

  /// The row it answers.
  final String lineId;

  /// What the book offers.
  final List<ImportCounterpart> counterparts;

  /// Picked an existing A/C.
  final ValueChanged<ImportCounterpart> onPick;

  /// Created a new one by name.
  final ValueChanged<String> onCreate;

  @override
  State<ImportCounterpartPicker> createState() =>
      _ImportCounterpartPickerState();
}

class _ImportCounterpartPickerState extends State<ImportCounterpartPicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final q = _query.trim().toLowerCase();
    final shown = [
      for (final c in widget.counterparts)
        if (q.isEmpty || c.name.toLowerCase().contains(q)) c,
    ];
    final exact = widget.counterparts.any(
      (c) => c.name.toLowerCase() == q && q.isNotEmpty,
    );
    // The card draws its own surface, so the tiles need a Material of their
    // own for their ink — otherwise the splash paints behind the card's
    // decoration and the tap has no feedback at all.
    return Material(
      type: MaterialType.transparency,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            key: ImportInboxKeys.search(widget.lineId),
            decoration: InputDecoration(labelText: l.importInboxSearch),
            onChanged: (v) => setState(() => _query = v),
          ),
          for (final c in shown)
            ListTile(
              key: ImportInboxKeys.pick(widget.lineId, c.id),
              minTileHeight: RkSpace.rowMinHeight,
              title: RkFitText(c.name),
              subtitle: c.subtitle == null ? null : RkFitText(c.subtitle!),
              onTap: () => widget.onPick(c),
            ),
          if (q.isNotEmpty && !exact)
            ListTile(
              minTileHeight: RkSpace.rowMinHeight,
              leading: const Icon(Icons.add),
              title: RkFitText(l.importInboxCreate(_query.trim())),
              onTap: () => widget.onCreate(_query.trim()),
            ),
        ],
      ),
    );
  }
}

/// S7.3 — the transfer-pair card (ADR 2026-09-01 §2: a **row-level card**
/// inside S7.1, not a screen).
///
/// *Is this the same money moving between your accounts?* One tap records a
/// single Transfer instead of two entries (02 §10 🔒) — the un-paired case is
/// the classic notebook error of counting the same rupees twice.
class ImportTransferCard extends StatelessWidget {
  /// Creates the card.
  const ImportTransferCard({
    super.key,
    required this.line,
    required this.paired,
    required this.onYes,
    required this.onNo,
  });

  /// The row asking.
  final ImportLine line;

  /// The opposite line it matched, when the inbox holds it.
  final ImportLine? paired;

  /// Yes — one movement.
  final VoidCallback onYes;

  /// No — two different things.
  final VoidCallback onNo;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final status = RkStatusColors.of(context);
    final other = paired;
    return Container(
      margin: const EdgeInsets.only(top: RkSpace.s2),
      padding: const EdgeInsets.all(RkSpace.s3),
      decoration: BoxDecoration(
        color: status.sunk,
        borderRadius: BorderRadius.circular(RkRadius.md),
        border: Border.all(color: status.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RkFitText(
            l.importInboxTransferQuestion,
            style: theme.textTheme.titleSmall,
          ),
          if (other != null) ...[
            const SizedBox(height: RkSpace.s1),
            RkFitText(
              l.importInboxTransferOther(
                formatPaise(
                  other.parsed.paise,
                  locale: Localizations.localeOf(context),
                  showPaise: other.parsed.paise % 100 != 0,
                ),
                formatLedgerDate(other.parsed.date, strings: l),
                other.accountId,
              ),
              style: theme.textTheme.bodySmall?.copyWith(color: status.muted),
            ),
          ],
          const SizedBox(height: RkSpace.s1),
          RkFitText(
            l.importInboxTransferHelp,
            style: theme.textTheme.bodySmall?.copyWith(color: status.muted),
          ),
          const SizedBox(height: RkSpace.s2),
          Wrap(
            spacing: RkSpace.s2,
            runSpacing: RkSpace.s1,
            children: [
              FilledButton(
                key: ImportInboxKeys.transferYes(line.id),
                onPressed: onYes,
                child: RkFitText(l.importInboxTransferYes),
              ),
              TextButton(
                key: ImportInboxKeys.transferNo(line.id),
                onPressed: onNo,
                child: RkFitText(l.importInboxTransferNo),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One row of the import inbox: date · the bank's words · Money in/out
/// amount · one question, with its state chip (07 §11 item 2 🔒).
class ImportLineCard extends StatelessWidget {
  /// Creates the row.
  const ImportLineCard({
    super.key,
    required this.line,
    required this.paired,
    required this.counterparts,
    required this.picking,
    required this.noting,
    required this.expanded,
    required this.onToggleBankText,
    required this.onUnlink,
    required this.onApprove,
    required this.onOpenPicker,
    required this.onPick,
    required this.onCreate,
    required this.onSuspense,
    required this.onConfirmTransfer,
    required this.onRejectTransfer,
    required this.onToggleNote,
    required this.onNote,
  });

  /// The line.
  final ImportLine line;

  /// Its pair, on `Transfer?`.
  final ImportLine? paired;

  /// The A/Cs the picker offers.
  final List<ImportCounterpart> counterparts;

  /// Whether the picker is open on this row.
  final bool picking;

  /// Whether the note field is open on this row.
  final bool noting;

  /// Whether the bank's whole line is showing.
  final bool expanded;

  /// Expand or collapse the bank text.
  final VoidCallback onToggleBankText;

  /// Unlink a `Matched ✓` row.
  final VoidCallback onUnlink;

  /// Approve a `Suggested` row in one tap.
  final VoidCallback onApprove;

  /// Open the A/C picker.
  final VoidCallback onOpenPicker;

  /// Answer with an existing A/C.
  final ValueChanged<ImportCounterpart> onPick;

  /// Answer with a new one.
  final ValueChanged<String> onCreate;

  /// Record now, explain later.
  final VoidCallback onSuspense;

  /// Yes, one movement.
  final VoidCallback onConfirmTransfer;

  /// No, two different things.
  final VoidCallback onRejectTransfer;

  /// Open or close the inline note.
  final VoidCallback onToggleNote;

  /// Commit the note.
  final ValueChanged<String> onNote;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final status = RkStatusColors.of(context);
    // Past the user's default size the ledger column stops working: at 130 %
    // the amount alone wants 158 px of the 143 px half a 360 px card can give
    // it, and at 200 % the date's box collapses to nothing and is drawn over
    // itself — neither throws (07 §1 rule 11). Anywhere above 100 % the pair
    // stacks, date over amount, and both keep their full size.
    final stacked = MediaQuery.textScalerOf(context).scale(1) > 1.05;
    return Padding(
      key: ImportInboxKeys.row(line.id),
      padding: const EdgeInsets.symmetric(
        horizontal: RkSpace.gutter,
        vertical: RkSpace.s2,
      ),
      child: Container(
        padding: const EdgeInsets.all(RkSpace.cardPadding),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(RkRadius.lg),
          border: Border.all(color: status.hairline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // At 200 % the amount alone is wider than half a 360 px card, so
            // side by side the date is squeezed to nothing and drawn over
            // itself — a 0 px box that throws nothing (07 §1 rule 11). Past
            // 150 % the pair stacks instead, date over amount, and both keep
            // their full size. Below it, the ledger column: date left,
            // figure right.
            if (stacked) ...[
              RkFitText(
                formatLedgerDate(line.parsed.date, strings: l),
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: RkSpace.s1),
              ImportAmount(line: line, alignEnd: false),
            ] else
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: RkFitText(
                      formatLedgerDate(line.parsed.date, strings: l),
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                  const SizedBox(width: RkSpace.s2),
                  Flexible(child: ImportAmount(line: line)),
                ],
              ),
            const SizedBox(height: RkSpace.s1),
            BankTextLine(
              line: line,
              expanded: expanded,
              onToggle: onToggleBankText,
            ),
            const SizedBox(height: RkSpace.s2),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: ImportStateChip(line: line),
            ),
            const SizedBox(height: RkSpace.s2),
            ..._answerArea(context, l, theme, status),
            if (line.isClassified) ...[
              const SizedBox(height: RkSpace.s1),
              if (!noting)
                TextButton(
                  key: ImportInboxKeys.note(line.id),
                  onPressed: onToggleNote,
                  child: RkFitText(l.importInboxNoteAdd),
                )
              else
                _NoteField(lineId: line.id, note: line.note, onNote: onNote),
              if (line.note != null && !noting)
                RkFitText(line.note!, style: theme.textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _answerArea(
    BuildContext context,
    AppLocalizations l,
    ThemeData theme,
    RkStatusColors status,
  ) {
    switch (line.state) {
      case ImportLineState.matched:
        return [
          RkFitText(
            l.importInboxMatchedWhat(line.match?.entryLabel ?? ''),
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: RkSpace.s1),
          RkFitText(
            l.importInboxMatchedNothing,
            style: theme.textTheme.bodySmall?.copyWith(color: status.muted),
          ),
          TextButton(
            key: ImportInboxKeys.unlink(line.id),
            onPressed: onUnlink,
            child: RkFitText(l.importInboxMatchedUnlink),
          ),
        ];
      case ImportLineState.transfer:
        return [
          ImportTransferCard(
            line: line,
            paired: paired,
            onYes: onConfirmTransfer,
            onNo: onRejectTransfer,
          ),
        ];
      case ImportLineState.suspense:
        return [
          RkFitText(
            l.importInboxSuspenseWhat,
            style: theme.textTheme.bodyMedium,
          ),
          TextButton(
            key: ImportInboxKeys.choose(line.id),
            onPressed: onOpenPicker,
            child: RkFitText(l.importInboxChange),
          ),
          if (picking) ..._picker(l),
        ];
      case ImportLineState.answered:
        return [
          RkFitText(
            line.isMoneyIn
                ? l.importInboxAnswerIn(line.counterpartName ?? '')
                : l.importInboxAnswerOut(line.counterpartName ?? ''),
            style: theme.textTheme.bodyMedium,
          ),
          if (line.pairedLineId != null)
            RkFitText(
              l.importInboxTransferDone,
              style: theme.textTheme.bodySmall?.copyWith(color: status.muted),
            ),
          TextButton(
            key: ImportInboxKeys.choose(line.id),
            onPressed: onOpenPicker,
            child: RkFitText(l.importInboxChange),
          ),
          if (picking) ..._picker(l),
        ];
      case ImportLineState.suggested:
      case ImportLineState.needsAnswer:
        final suggestion = line.suggestion;
        return [
          RkFitText(oneQuestion(l, line), style: theme.textTheme.titleSmall),
          const SizedBox(height: RkSpace.s2),
          if (suggestion != null) ...[
            RkFitText(
              l.importInboxSuggestedChip(suggestion.accountName),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: status.success,
              ),
            ),
            const SizedBox(height: RkSpace.s1),
          ],
          Wrap(
            spacing: RkSpace.s2,
            runSpacing: RkSpace.s1,
            children: [
              if (suggestion != null)
                FilledButton(
                  key: ImportInboxKeys.approve(line.id),
                  onPressed: onApprove,
                  child: RkFitText(l.importInboxApprove),
                ),
              OutlinedButton(
                key: ImportInboxKeys.choose(line.id),
                onPressed: onOpenPicker,
                child: RkFitText(l.importInboxChoose),
              ),
              TextButton(
                key: ImportInboxKeys.suspense(line.id),
                onPressed: onSuspense,
                child: RkFitText(l.importInboxSuspenseAction),
              ),
            ],
          ),
          if (picking) ..._picker(l),
        ];
    }
  }

  List<Widget> _picker(AppLocalizations l) => [
    const SizedBox(height: RkSpace.s2),
    ImportCounterpartPicker(
      lineId: line.id,
      counterparts: counterparts,
      onPick: onPick,
      onCreate: onCreate,
    ),
  ];
}

class _NoteField extends StatefulWidget {
  const _NoteField({
    required this.lineId,
    required this.note,
    required this.onNote,
  });

  final String lineId;
  final String? note;
  final ValueChanged<String> onNote;

  @override
  State<_NoteField> createState() => _NoteFieldState();
}

class _NoteFieldState extends State<_NoteField> {
  late final _controller = TextEditingController(text: widget.note ?? '');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          key: ImportInboxKeys.noteField(widget.lineId),
          controller: _controller,
          decoration: InputDecoration(labelText: l.importInboxNoteHint),
        ),
        const SizedBox(height: RkSpace.s1),
        TextButton(
          onPressed: () => widget.onNote(_controller.text.trim()),
          child: RkFitText(l.importInboxNoteSave),
        ),
      ],
    );
  }
}
