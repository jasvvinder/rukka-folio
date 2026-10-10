// ADR 2026-10-07b 🔒 — an account created inside an entry asks for its opening
// balance afterwards, on the account: never during the entry (07 §1 rule 1,
// the 8-second entry) and never on the *Saved* toast.
//
// Three pieces, all drawn by c7 (*A/C statement · opening balance not set*,
// *· add the opening balance*, *Ledger index · opening balance not set*):
//
// - [OpeningPromptCard] — the card at the top of S4: *Opening balance not set*
//   with **Add opening balance** and **Not needed** (ruling 1).
// - [OpeningMarker] — the quiet line under the A/C's name in S3 (ruling 1).
// - [OpeningBalanceSheet] — the answer: S3.1's class-worded question, posted
//   through the same `LocalLedger.openingBalances` path S3.1 uses, as **one**
//   adjustment against Opening Balance dated at the book's start — or, when
//   that month is locked, in the earliest open month (ADR 2026-09-09d §4,
//   `LocalLedger.openingDateOf`) — behind the read-only gate (ADR 2026-09-24b
//   §13) — ruling 2.
//
// Which accounts carry the prompt is the data layer's answer
// (`LocalLedger.watchOpeningUnanswered`), derived only from data that syncs;
// these widgets decide nothing about it.
//
// ⚠️ SPEC (ADR 2026-10-07b Open ⚠️, PLAN desk 177): **Not needed** records that
// the opening is zero and posts nothing — so it needs somewhere to record that
// which reaches every device, and no synced field can carry it today (the
// `account` payload, 03 §2.3, has none). A phone-only answer would ask again on
// the next device, which the ruling forbids. Until the owner rules on the field
// proposed in the lane report, *Not needed* is drawn disabled with its reason
// in words beside it ([OpeningNotNeeded] is the seam it will be wired through).
//
// The marker is drawn in the frame's ink (`colorScheme.primary`, the c7 S3 and
// S4 frames' info line), not amber, with an info icon and the words — the words
// carry the state, never the colour alone (07 §1 rule 3 🔒). ⚠️ SPEC: ruling 1
// says *the accent colour*; the token named `accent` is bahi red, which on S3
// is the Cr figure's colour and would read as an amount owed. The approved
// frames draw it in ink, so this follows them — owner to confirm.
import 'package:core_ledger/core_ledger.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/format/date_format.dart';
import '../../../shared/format/money_format.dart';
import '../../../shared/ledger/ledger_scope.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';
import '../../../shared/widgets/rk_fit_text.dart';
import '../../entry/entry_restriction.dart';
import '../screens/s3_1_quick_add_sheet.dart' show parseRupeesToPaise;
import 'text_metrics.dart';

/// Records *Not needed* for [accountId] of [bookId] (ADR 2026-10-07b §2 🔒).
/// Null — every build until the synced field exists — draws the action
/// disabled with its reason.
typedef OpeningNotNeeded = Future<void> Function(
  String bookId,
  String accountId,
);

/// Keys the tests and the design captures find these widgets by.
abstract final class OpeningPromptKeys {
  static const card = Key('opening-prompt-card');
  static const add = Key('opening-prompt-add');
  static const notNeeded = Key('opening-prompt-not-needed');
  static const notNeededReason = Key('opening-prompt-not-needed-reason');
  static const marker = Key('opening-marker');
  static const sheet = Key('opening-sheet');
  static const theyOwe = Key('opening-sheet-they-owe');
  static const youOwe = Key('opening-sheet-you-owe');
  static const amount = Key('opening-sheet-amount');
  static const save = Key('opening-sheet-save');
  static const total = Key('opening-sheet-total');
  static const dated = Key('opening-sheet-dated');
  static const cancel = Key('opening-sheet-cancel');
}

/// The S4 card (c7 *A/C statement · opening balance not set*).
class OpeningPromptCard extends StatelessWidget {
  const OpeningPromptCard({
    super.key,
    required this.account,
    required this.onAdd,
    this.onNotNeeded,
  });

  final Account account;
  final VoidCallback onAdd;

  /// Null draws *Not needed* disabled, with the reason in words.
  final VoidCallback? onNotNeeded;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final muted = RkStatusColors.of(context).muted;
    final body = account.accountClass == AccountClass.party
        ? l10n.ledgerOpeningPromptBodyParty(account.name)
        : l10n.ledgerOpeningPromptBodyMoney(account.name);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        RkSpace.gutter,
        RkSpace.s2,
        RkSpace.gutter,
        RkSpace.s2,
      ),
      child: DecoratedBox(
        key: OpeningPromptKeys.card,
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(RkRadius.lg),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.all(RkSpace.cardPadding),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, color: scheme.primary),
              const SizedBox(width: RkSpace.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        l10n.ledgerOpeningPromptTitle,
                        style: text.titleMedium,
                      ),
                    ),
                    const SizedBox(height: RkSpace.s1),
                    Text(body, style: text.bodyMedium?.copyWith(color: muted)),
                    const SizedBox(height: RkSpace.s3),
                    // A Wrap, not a Row: at 200 % on a 360 px phone the two
                    // actions take a line each rather than overflowing
                    // (07 §1 rule 9).
                    Wrap(
                      spacing: RkSpace.s2,
                      runSpacing: RkSpace.s2,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        FilledButton(
                          key: OpeningPromptKeys.add,
                          // The theme's button is full-bleed
                          // (`Size.fromHeight`); inside a Wrap it sizes to
                          // its words, as the frame draws it.
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(0, RkSpace.s12),
                            // The frame's button hugs its words, so both
                            // actions share one line at default size.
                            padding: const EdgeInsets.symmetric(
                              horizontal: RkSpace.s4,
                            ),
                          ),
                          onPressed: onAdd,
                          // `RkFitText`: at 200 % one Gurmukhi word of this
                          // label is wider than the card leaves a button on a
                          // 360 px phone; it steps down only as far as that
                          // word needs (the S3.1 tile pattern).
                          child: RkFitText(l10n.ledgerOpeningPromptAdd),
                        ),
                        TextButton(
                          key: OpeningPromptKeys.notNeeded,
                          onPressed: onNotNeeded,
                          child: RkFitText(l10n.ledgerOpeningPromptNotNeeded),
                        ),
                      ],
                    ),
                    if (onNotNeeded == null) ...[
                      const SizedBox(height: RkSpace.s2),
                      Text(
                        l10n.ledgerOpeningPromptNotNeededUnavailable,
                        key: OpeningPromptKeys.notNeededReason,
                        style: text.bodySmall?.copyWith(color: muted),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The S3 line under the A/C's name (c7 *Ledger index · opening balance not
/// set*): info icon and words, in ink.
class OpeningMarker extends StatelessWidget {
  const OpeningMarker({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final ink = Theme.of(context).colorScheme.primary;
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(color: ink);
    final size =
        (style?.fontSize ?? RkSpace.s4) *
        MediaQuery.textScalerOf(context).scale(1);
    return Row(
      key: OpeningPromptKeys.marker,
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: RkSpace.s1 / 2),
          child: Icon(Icons.info_outline, size: size, color: ink),
        ),
        const SizedBox(width: RkSpace.s1),
        Flexible(child: Text(l10n.ledgerOpeningPromptTitle, style: style)),
      ],
    );
  }
}

/// Raises [OpeningBalanceSheet] over [context]. Resolves true when the opening
/// was posted.
Future<bool?> showOpeningBalanceSheet(
  BuildContext context, {
  required String bookId,
  required Account account,
}) => showModalBottomSheet<bool>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (_) => OpeningBalanceSheet(bookId: bookId, account: account),
);

/// The answer to the prompt (c7 *A/C statement · add the opening balance*).
///
/// The question is S3.1's, worded by class (02 §4): for a person *they owe
/// you / you owe them* and the amount; for a money A/C the balance, negative
/// allowed for an overdraft. The figure is parsed by S3.1's own
/// [parseRupeesToPaise] — integer paise, no float ever touches it.
class OpeningBalanceSheet extends StatefulWidget {
  const OpeningBalanceSheet({
    super.key,
    required this.bookId,
    required this.account,
  });

  final String bookId;
  final Account account;

  @override
  State<OpeningBalanceSheet> createState() => _OpeningBalanceSheetState();
}

class _OpeningBalanceSheetState extends State<OpeningBalanceSheet> {
  /// What a segment or a button keeps around its words: its horizontal
  /// padding, a segment's icon and gap, and the hairline border.
  static const _chrome = RkSpace.s12 + RkSpace.s4;

  final _amount = TextEditingController();

  /// +1 *they owe you* (Dr), −1 *you owe them* (Cr) — 02 §4, the same sign
  /// S3.1's debtor / creditor tiles apply.
  int _side = 1;
  bool _amountError = false;
  bool _saving = false;
  bool _saveError = false;

  /// The day the opening will be dated at, and whether that is the book's
  /// start (else the start month is locked and it lands in the earliest open
  /// month — ADR 2026-09-09d §4).
  Future<(LocalDate, bool)>? _dated;

  /// What the A/C reads now, all time, signed as the engine signs it (+ = Dr,
  /// *you will get* for a person) — read from the ledger, never from the year
  /// the statement behind the sheet happens to show. Null until it has loaded;
  /// the *in all* line waits for it rather than show a wrong figure.
  int? _current;

  bool get _isParty => widget.account.accountClass == AccountClass.party;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Plain futures, read once (an InheritedWidget is not reachable from
    // initState): the date the opening is dated at, and the A/C's balance now.
    if (_dated != null) return;
    final ledger = LedgerScope.of(context);
    _dated = () async {
      final when = await ledger.openingDateOf(widget.bookId);
      final start = await ledger.startDateOf(widget.bookId);
      return (when, start == null || when == start);
    }();
    ledger.balanceOf(widget.bookId, widget.account.id).then((paise) {
      if (mounted) setState(() => _current = paise);
    }, onError: (Object _) {});
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  /// The signed opening in paise, or null when nothing postable is typed.
  int? get _signed {
    final typed = parseRupeesToPaise(_amount.text);
    if (typed == null || typed == 0) return null;
    return _isParty ? typed.abs() * _side : typed;
  }

  Future<void> _save() async {
    final signed = _signed;
    if (signed == null) {
      setState(() => _amountError = true);
      return;
    }
    // S12.5 (ADR 2026-09-24b §13): read-only refuses an opening balance here
    // exactly as it does from S3.1. Both seams and the ledger are read before
    // the first await; the figure stays under the sheet.
    final sources = entryRestrictionSourcesOf(context);
    final ledger = LedgerScope.of(context);
    setState(() {
      _saving = true;
      _saveError = false;
    });
    final refused = await refuseIfEntryRestricted(context, sources, [
      widget.bookId,
    ], onBlocked: () => setState(() => _saving = false));
    if (refused || !mounted) return;
    try {
      // One adjustment against Opening Balance, dated at the book's start or,
      // when that month is locked, in the earliest open month (ADR
      // 2026-09-09d §4) — the path S3.1 and setup post through.
      await ledger.openingBalances(
        widget.bookId,
        balances: {widget.account.id: signed},
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveError = true;
      });
    }
  }

  /// The *in all* line (c7 *A/C statement · add the opening balance*): the
  /// sentence in muted body text with its figure emphasised — semibold, in
  /// the money-in colour when they will owe you (or the A/C is in credit for
  /// money), money-out when you will owe them. The words *get* / *give* and
  /// the sign carry the side; the colour never does alone (07 §1 rule 3 🔒).
  Widget? _total(AppLocalizations l10n, Locale locale, TextStyle? base) {
    final signed = _signed;
    final current = _current;
    if (signed == null || current == null) return null;
    final total = current + signed;
    final String sentence;
    final String amount;
    if (!_isParty) {
      amount = formatPaise(total, locale: locale);
      sentence = l10n.ledgerOpeningSheetTotalMoney(widget.account.name, _slot);
    } else if (total == 0) {
      return Text(l10n.ledgerOpeningSheetTotalSettled, style: base);
    } else {
      amount = formatPaise(total.abs(), locale: locale);
      sentence = total > 0
          ? l10n.ledgerOpeningSheetTotalGet(_slot)
          : l10n.ledgerOpeningSheetTotalGive(_slot);
    }
    final status = RkStatusColors.of(context);
    final figure = base?.copyWith(
      color: total < 0 ? status.debit : status.credit,
      fontWeight: FontWeight.w600,
    );
    // The figure's place comes from the translation itself (a placeholder
    // filled with [_slot]), so PA and HI put it where their grammar does.
    final at = sentence.indexOf(_slot);
    return Text.rich(
      key: OpeningPromptKeys.total,
      TextSpan(
        style: base,
        children: [
          TextSpan(text: sentence.substring(0, at)),
          TextSpan(text: amount, style: figure),
          TextSpan(text: sentence.substring(at + _slot.length)),
        ],
      ),
    );
  }

  /// Stands in for the figure while the sentence is formatted, then marks
  /// where the styled figure goes. Never drawn.
  static const _slot = '\u0000';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context);
    final text = Theme.of(context).textTheme;
    final muted = RkStatusColors.of(context).muted;
    final total = _total(l10n, locale, text.bodyMedium?.copyWith(color: muted));
    // Side by side, or one above the other — measured, never a text-scale
    // threshold (07 §1 rule 9; `text_metrics.dart`): a word is never cut,
    // and a label is never shrunk to fit. [_chrome] is what a segment or a
    // button keeps around its words (padding, icon, gap, border).
    final line = MediaQuery.sizeOf(context).width - RkSpace.gutter * 2;
    final label = text.labelLarge;
    double word(String s) => longestWordWidth(context, s, label) + _chrome;
    final sidesInRow =
        word(l10n.ledgerOpeningSheetTheyOwe) <= line / 2 &&
        word(l10n.ledgerOpeningSheetYouOwe) <= line / 2;
    final third = (line - RkSpace.s3) / 3;
    final actionsInRow =
        word(l10n.ledgerOpeningSheetCancel) <= third &&
        word(l10n.ledgerOpeningSheetSave) <= third * 2;
    final cancel = OutlinedButton(
      key: OpeningPromptKeys.cancel,
      onPressed: _saving ? null : () => Navigator.of(context).pop(false),
      child: Text(l10n.ledgerOpeningSheetCancel),
    );
    final save = FilledButton(
      key: OpeningPromptKeys.save,
      onPressed: _saving ? null : _save,
      child: Text(l10n.ledgerOpeningSheetSave),
    );
    return Padding(
      key: OpeningPromptKeys.sheet,
      padding: EdgeInsets.only(
        left: RkSpace.gutter,
        right: RkSpace.gutter,
        bottom: MediaQuery.of(context).viewInsets.bottom + RkSpace.s6,
      ),
      // Height-capped sheet; at 200 % the body scrolls rather than overflow
      // (07 §1 rule 9), as S3.1's does.
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text(
                l10n.ledgerOpeningSheetTitle(widget.account.name),
                style: text.titleLarge,
              ),
            ),
            const SizedBox(height: RkSpace.s2),
            Text(
              _isParty
                  ? l10n.ledgerOpeningSheetSubtitleParty
                  : l10n.ledgerOpeningSheetSubtitleMoney,
              style: text.bodyMedium?.copyWith(color: muted),
            ),
            const SizedBox(height: RkSpace.s4),
            if (_isParty) ...[
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<int>(
                  direction: sidesInRow ? Axis.horizontal : Axis.vertical,
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(
                      value: 1,
                      icon: const Icon(Icons.arrow_downward),
                      label: Text(
                        l10n.ledgerOpeningSheetTheyOwe,
                        key: OpeningPromptKeys.theyOwe,
                      ),
                    ),
                    ButtonSegment(
                      value: -1,
                      icon: const Icon(Icons.arrow_upward),
                      label: Text(
                        l10n.ledgerOpeningSheetYouOwe,
                        key: OpeningPromptKeys.youOwe,
                      ),
                    ),
                  ],
                  selected: {_side},
                  onSelectionChanged: (s) => setState(() => _side = s.single),
                ),
              ),
              const SizedBox(height: RkSpace.s4),
            ],
            TextField(
              key: OpeningPromptKeys.amount,
              controller: _amount,
              autofocus: true,
              keyboardType: TextInputType.numberWithOptions(
                decimal: true,
                signed: !_isParty,
              ),
              inputFormatters: [
                // A person's side is the segmented choice, so the figure is a
                // magnitude; a money A/C may go below zero (overdraft, 02 §4).
                FilteringTextInputFormatter.allow(
                  _isParty ? RegExp(r'[0-9.]') : RegExp(r'[0-9.\-]'),
                ),
              ],
              decoration: InputDecoration(
                prefixText: '$rupeeSign ',
                labelText: _isParty
                    ? l10n.ledgerOpeningSheetAmount
                    : l10n.ledgerQuickAddOpeningLabelMoney,
                hintText: l10n.ledgerQuickAddOpeningHint,
                errorText: _amountError
                    ? l10n.ledgerOpeningSheetAmountError
                    : null,
              ),
              onChanged: (_) => setState(() => _amountError = false),
            ),
            const SizedBox(height: RkSpace.s3),
            if (total != null) total,
            FutureBuilder<(LocalDate, bool)>(
              future: _dated,
              builder: (context, snap) {
                final dated = snap.data;
                if (dated == null) return const SizedBox.shrink();
                final (postedOn, atStart) = dated;
                final day = formatLedgerDate(postedOn, strings: l10n);
                return Text(
                  key: OpeningPromptKeys.dated,
                  atStart
                      ? l10n.ledgerOpeningSheetDated(day)
                      : l10n.ledgerOpeningSheetDatedLocked(day),
                  style: text.bodyMedium?.copyWith(color: muted),
                );
              },
            ),
            if (_saveError) ...[
              const SizedBox(height: RkSpace.s2),
              Text(
                l10n.ledgerOpeningSheetSaveError,
                style: text.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ],
            const SizedBox(height: RkSpace.s4),
            if (actionsInRow)
              Row(
                children: [
                  Expanded(child: cancel),
                  const SizedBox(width: RkSpace.s3),
                  Expanded(flex: 2, child: save),
                ],
              )
            else ...[
              // Stacked, the primary first — the S3.1 pattern at 200 %.
              save,
              const SizedBox(height: RkSpace.s2),
              cancel,
            ],
          ],
        ),
      ),
    );
  }
}
