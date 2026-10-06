// S0.6 Opening balances · first run — "What do you have?" (13 §3.2 row S0.6,
// 13 §5 F1 "→ S0.6 own opening balances (skippable) → S1 with setup
// checklist", 07 §3.1 step 7, canvas 1 frame S0.6 in the row *All five paths
// converge here*; desk 172, owner-ruled 6 Oct: follow the design).
//
// The **person's own** book — the personal book made at S0.4
// (`personal_book.dart`) — reviewed and filled on one grouped screen (ADR
// 2026-09-09c §3): *What you have · Who owes you · Who you owe*, in the
// consumer vocabulary (02 §10 🔒, never Assets/Liabilities). The seeded Cash
// A/c is the one row a personal book certainly has (ADR 2026-09-09c §1); a
// bank, a person or a category arrives through *Add an account* (S3.1 —
// ADR 2026-09-09d §1: no book type seeds a bank).
//
// The date is plain read-only text, not a control: 02 §4 🔒 asks a money
// account for its *balance today*, and the book begins today (ADR 2026-09-09d
// §4), so there is nothing to pick.
//
// *Finish* and *Skip for now* both lead on to Home (desk 172); the host
// decides what each records. A row left at ₹0 posts nothing (02 §4) — the
// account is still made, as the footer says.
//
// A row whose account already carries an **opening** (an account added
// through *Add an account*, which asks its balance in the same breath, or a
// resumed step) shows that opening read-only: one opening per account, never
// two. The host passes the opening, never the running balance — an account
// that entries have moved but that has no opening still takes one (P1A
// review, finding 2).
//
// The field groups the figure as it is typed, ₹ set tight against the digits
// (`₹14,500`, canvas 11 O6a; 07 §1 rule 4 🔒 — ₹ + Indian grouping).
//
// Money is integer paise throughout; rupees are parsed digit by digit
// ([parseRupeesToPaise]) and never touch a double (CLAUDE.md rule 1).
import 'package:core_ledger/core_ledger.dart' show LocalDate;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/format/date_format.dart';
import '../../../shared/format/money_format.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';
import '../../../shared/widgets/rk_fit_text.dart';
import 's0_6b_business_opening_balances_screen.dart'
    show OpeningGroup, parseRupeesToPaise, signOf;

/// One account on S0.6.
@immutable
final class FirstRunRow {
  /// Creates a row.
  const FirstRunRow({
    required this.accountId,
    required this.name,
    required this.group,
    this.isCash = false,
    this.postedPaise = 0,
  });

  /// The engine account the opening posts against.
  final String accountId;

  /// The account's (editable) name.
  final String name;

  /// [OpeningGroup.have], [OpeningGroup.owedToYou] or [OpeningGroup.youOwe].
  final OpeningGroup group;

  /// A cash account — drawn with *money in hand* beneath its name (canvas 1).
  final bool isCash;

  /// The account's opening already in the book, signed paise (+ = Dr) — the
  /// opening, never the running balance. Non-zero makes the row read-only.
  final int postedPaise;

  /// True when the row still takes a figure.
  bool get editable => postedPaise == 0 && group == OpeningGroup.have;
}

/// S0.6 — "What do you have?".
class OpeningBalancesScreen extends StatefulWidget {
  /// Creates the screen.
  const OpeningBalancesScreen({
    super.key,
    required this.rows,
    required this.asOn,
    this.onFinish,
    this.onSkip,
    this.onAddAccount,
    this.onBack,
    this.busy = false,
    this.saveFailed = false,
    this.debugTyped = const {},
  });

  /// The personal book's accounts, grouped.
  final List<FirstRunRow> rows;

  /// The day every opening is dated (the book's start date, ADR 2026-09-09d
  /// §4) — drawn as plain text.
  final LocalDate asOn;

  /// *Finish*: account id → **signed** paise for every editable row (zero
  /// rows included; the engine skips them).
  final void Function(Map<String, int> balances)? onFinish;

  /// *Skip for now* — the S0.7 checklist row stays open as the way back.
  final VoidCallback? onSkip;

  /// *Add an account* (S3.1).
  final VoidCallback? onAddAccount;

  /// The back chevron; null draws none.
  final VoidCallback? onBack;

  /// A save is in flight — *Finish* and *Skip* hold.
  final bool busy;

  /// The last *Finish* failed — the cause is named and *Finish* tries again
  /// (07 §1 rule 12). Nothing was posted.
  final bool saveFailed;

  /// Rupee figures to type into rows before the first frame — design
  /// captures only.
  @visibleForTesting
  final Map<String, String> debugTyped;

  @override
  State<OpeningBalancesScreen> createState() => _OpeningBalancesScreenState();
}

class _OpeningBalancesScreenState extends State<OpeningBalancesScreen> {
  final _fields = <String, TextEditingController>{};

  TextEditingController _field(String accountId) => _fields.putIfAbsent(
    accountId,
    () => TextEditingController(
      text: IndianGroupingFormatter.withSign(
        widget.debugTyped[accountId] ?? '',
      ),
    ),
  );

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, int> get _signed => {
    for (final row in widget.rows)
      if (row.editable)
        row.accountId:
            signOf(row.group) *
            parseRupeesToPaise(
              (_fields[row.accountId]?.text ?? '').replaceAll(rupeeSign, ''),
            ),
  };

  List<FirstRunRow> _group(OpeningGroup g) => [
    for (final r in widget.rows)
      if (r.group == g) r,
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final status = RkStatusColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    final date = formatLedgerDate(widget.asOn, strings: l10n);
    final asOn = l10n.onboardingOpeningAsOn(date);
    final at = asOn.indexOf(date);

    Widget band(String label) => Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: status.sunk,
        border: Border(
          top: BorderSide(color: status.hairline),
          bottom: BorderSide(color: status.hairline),
        ),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: RkSpace.gutter,
        vertical: RkSpace.s2,
      ),
      child: Semantics(
        header: true,
        child: Text(
          label.toUpperCase(),
          style: text.bodySmall?.copyWith(
            color: status.muted,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
          ),
        ),
      ),
    );

    Widget empty(String line) => Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: RkSpace.gutter,
        vertical: RkSpace.s5,
      ),
      child: Text(line, style: text.bodyMedium?.copyWith(color: status.muted)),
    );

    List<Widget> group(OpeningGroup g, String label, String emptyLine) {
      final rows = _group(g);
      return [
        band(label),
        if (rows.isEmpty)
          empty(emptyLine)
        else
          for (final (i, row) in rows.indexed) ...[
            if (i > 0) Divider(height: 1, color: status.hairline),
            _AccountRow(
              row: row,
              controller: row.editable ? _field(row.accountId) : null,
              enabled: !widget.busy,
            ),
          ],
      ];
    }

    // At large text the note and the two actions scroll with the rows
    // instead of being pinned: pinned, they would leave the rows no room on
    // a 667-high phone (07 §1 rule 11).
    final pinned = MediaQuery.textScalerOf(context).scale(1) <= 1.5;
    final footer = <Widget>[
      Container(
        width: double.infinity,
        color: status.sunk,
        padding: const EdgeInsets.symmetric(
          horizontal: RkSpace.gutter,
          vertical: RkSpace.s4,
        ),
        child: widget.saveFailed
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Colour never alone (07 §1): the icon and the words.
                  Icon(
                    Icons.error_outline,
                    size: RkIcon.grid - RkSpace.s1,
                    color: scheme.error,
                  ),
                  const SizedBox(width: RkSpace.s2),
                  Expanded(
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        l10n.onboardingOpeningSaveError,
                        style: text.bodyMedium?.copyWith(color: scheme.error),
                      ),
                    ),
                  ),
                ],
              )
            : Text(
                l10n.onboardingOpeningNote,
                style: text.bodyMedium?.copyWith(color: status.muted),
              ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(
          RkSpace.gutter,
          RkSpace.s3,
          RkSpace.gutter,
          RkSpace.s1,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton(
              onPressed: widget.busy || widget.onFinish == null
                  ? null
                  : () => widget.onFinish!(_signed),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(RkSpace.s12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(RkRadius.lg),
                ),
              ),
              child: Text(l10n.onboardingOpeningFinish),
            ),
            const SizedBox(height: RkSpace.s1),
            TextButton(
              onPressed: widget.busy ? null : widget.onSkip,
              style: TextButton.styleFrom(foregroundColor: status.muted),
              child: Text(l10n.onboardingOpeningSkip),
            ),
          ],
        ),
      ),
    ];

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _TopBar(onBack: widget.onBack),
            Expanded(
              child: ListView(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      RkSpace.s5,
                      RkSpace.s3,
                      RkSpace.s5,
                      RkSpace.s5,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        RkFitText(
                          l10n.onboardingOpeningTitle,
                          style: text.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: RkSpace.s2),
                        // One ICU string; only the date inside it is bold
                        // (no concatenation, 13 §8).
                        Text.rich(
                          TextSpan(
                            style: text.bodyMedium?.copyWith(
                              color: status.muted,
                            ),
                            children: at < 0
                                ? [TextSpan(text: asOn)]
                                : [
                                    TextSpan(text: asOn.substring(0, at)),
                                    TextSpan(
                                      text: date,
                                      style: TextStyle(
                                        color: scheme.onSurface,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    TextSpan(
                                      text: asOn.substring(at + date.length),
                                    ),
                                  ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  ...group(
                    OpeningGroup.have,
                    l10n.onboardingBusinessOpeningGroupHave,
                    l10n.onboardingOpeningHaveEmpty,
                  ),
                  ...group(
                    OpeningGroup.owedToYou,
                    l10n.onboardingBusinessOpeningGroupOwedToYou,
                    l10n.onboardingOpeningOwedEmpty,
                  ),
                  ...group(
                    OpeningGroup.youOwe,
                    l10n.onboardingBusinessOpeningGroupYouOwe,
                    l10n.onboardingOpeningOweEmpty,
                  ),
                  Divider(height: 1, color: status.hairline),
                  _AddAccountRow(
                    onTap: widget.busy ? null : widget.onAddAccount,
                  ),
                  Divider(height: 1, color: status.hairline),
                  if (!pinned) ...[
                    const SizedBox(height: RkSpace.s6),
                    ...footer,
                  ],
                ],
              ),
            ),
            if (pinned) ...footer,
          ],
        ),
      ),
    );
  }
}

/// The back chevron and the three filled progress dashes of canvas 1.
class _TopBar extends StatelessWidget {
  const _TopBar({this.onBack});

  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final status = RkStatusColors.of(context);
    return SizedBox(
      height: RkSpace.rowMinHeight,
      child: Row(
        children: [
          const SizedBox(width: RkSpace.s1),
          if (onBack != null)
            IconButton(
              tooltip: MaterialLocalizations.of(context).backButtonTooltip,
              onPressed: onBack,
              icon: Icon(Icons.chevron_left, color: status.muted),
            ),
          const Spacer(),
          // The setup's last stage: every dash filled. Decoration only — the
          // title says where the person is.
          ExcludeSemantics(
            child: Row(
              children: [
                for (var i = 0; i < 3; i++) ...[
                  if (i > 0) const SizedBox(width: RkSpace.s1),
                  Container(
                    width: RkSpace.s5 + RkSpace.s1 / 2,
                    height: RkSpace.s1 - 0.5,
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      borderRadius: BorderRadius.circular(RkRadius.sm),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: RkSpace.gutter),
        ],
      ),
    );
  }
}

/// One account: its name (with *money in hand* under a cash account) and its
/// figure — a field while it takes one, the posted figure once it has one.
class _AccountRow extends StatelessWidget {
  const _AccountRow({
    required this.row,
    required this.controller,
    required this.enabled,
  });

  final FirstRunRow row;
  final TextEditingController? controller;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final status = RkStatusColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    final locale = Localizations.localeOf(context);

    final name = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(row.name, style: text.bodyLarge),
        if (row.isCash)
          Text(
            l10n.onboardingOpeningCashHint,
            style: text.bodyMedium?.copyWith(color: status.muted),
          ),
      ],
    );

    final Widget figure;
    final c = controller;
    if (c == null) {
      // Already in the book: shown, not asked again. A party's group names
      // its direction in words, so its figure is the magnitude (02 §9 *you
      // will get / you will give*); a money account's opening can be below
      // nil (an overdraft, 02 §4), and then the figure carries its − so
      // *What you have* never shows a debt as a holding (07 §1 rules 3–4).
      final overdrawn = row.group == OpeningGroup.have && row.postedPaise < 0;
      figure = Text(
        formatPaise(
          overdrawn ? row.postedPaise : row.postedPaise.abs(),
          locale: locale,
        ),
        textAlign: TextAlign.end,
        style: text.labelLarge,
      );
    } else {
      figure = Semantics(
        label: l10n.onboardingOpeningAmountLabel(row.name),
        child: TextField(
          controller: c,
          enabled: enabled,
          textAlign: TextAlign.end,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: const [IndianGroupingFormatter()],
          style: text.labelLarge,
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: scheme.surface,
            hintText: '$rupeeSign 0',
            hintStyle: text.labelLarge?.copyWith(color: status.muted),
            // No prefix: a prefix sits at the field's start while the figure
            // is end-aligned, leaving `₹      12,400`. The formatter writes
            // ₹ into the text, tight against the digits, as canvas 11 O6a
            // sets `₹14,500` (07 §1 rule 4 🔒); the empty hint keeps canvas
            // 1's `₹ 0`.
            contentPadding: const EdgeInsets.symmetric(
              horizontal: RkSpace.s3,
              vertical: RkSpace.s2,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(RkRadius.sm),
              borderSide: BorderSide(color: status.hairline),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(RkRadius.sm),
              borderSide: BorderSide(color: status.hairline),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: RkSpace.gutter,
        vertical: RkSpace.s4,
      ),
      // Name and figure side by side; at 200 % on a 360-wide phone the
      // figure drops beneath the name instead of overflowing (07 §1 rule 11).
      child: LayoutBuilder(
        builder: (context, box) {
          final scale = MediaQuery.textScalerOf(context).scale(1);
          if (scale > 1.2 || box.maxWidth < 300) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                name,
                const SizedBox(height: RkSpace.s2),
                figure,
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: name),
              const SizedBox(width: RkSpace.s3),
              SizedBox(width: box.maxWidth * 0.34, child: figure),
            ],
          );
        },
      ),
    );
  }
}

/// *Add an account* — the dashed tile of canvas 1, a primary title and the
/// examples beneath it.
class _AddAccountRow extends StatelessWidget {
  const _AddAccountRow({required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final status = RkStatusColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    final ink = onTap == null ? status.muted : scheme.primary;
    return Semantics(
      button: true,
      enabled: onTap != null,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: RkSpace.gutter,
            vertical: RkSpace.s4,
          ),
          child: Row(
            children: [
              CustomPaint(
                painter: _DashedSquare(color: ink),
                child: SizedBox.square(
                  dimension: RkSpace.s8 - RkSpace.s1 / 2,
                  child: Icon(Icons.add, size: RkSpace.s4, color: ink),
                ),
              ),
              const SizedBox(width: RkSpace.s5),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.onboardingOpeningAddAccount,
                      style: text.bodyLarge?.copyWith(
                        color: ink,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      l10n.onboardingOpeningAddAccountHint,
                      style: text.bodyMedium?.copyWith(color: status.muted),
                    ),
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

class _DashedSquare extends CustomPainter {
  const _DashedSquare({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    const dash = 3.0;
    const gap = 2.0;
    void line(Offset a, Offset b) {
      final length = (b - a).distance;
      final dir = (b - a) / length;
      for (var d = 0.0; d < length; d += dash + gap) {
        final end = d + dash > length ? length : d + dash;
        canvas.drawLine(a + dir * d, a + dir * end, paint);
      }
    }

    final r = Offset.zero & size;
    line(r.topLeft, r.topRight);
    line(r.topRight, r.bottomRight);
    line(r.bottomRight, r.bottomLeft);
    line(r.bottomLeft, r.topLeft);
  }

  @override
  bool shouldRepaint(_DashedSquare old) => old.color != color;
}

/// Groups a rupee figure as it is typed — `1500000` → `₹15,00,000` (07 §1
/// rule 4 🔒, ₹ + Indian grouping; [groupIndian] owns the rule). Digits and one `.`
/// with at most two paise digits; anything else is dropped. The text is a
/// string of digits throughout — [parseRupeesToPaise] reads it back to integer
/// paise and no double ever touches it (CLAUDE.md rule 1).
class IndianGroupingFormatter extends TextInputFormatter {
  /// Creates the formatter.
  const IndianGroupingFormatter();

  /// [raw] cleaned and grouped.
  static String group(String raw) {
    final buf = StringBuffer();
    var dot = false;
    var paise = 0;
    for (final ch in raw.split('')) {
      if (ch == '.') {
        if (dot) continue;
        dot = true;
        buf.write(ch);
      } else if (RegExp(r'\d').hasMatch(ch)) {
        if (dot) {
          if (paise == 2) continue;
          paise++;
        }
        buf.write(ch);
      }
    }
    final clean = buf.toString();
    if (clean.isEmpty) return '';
    final at = clean.indexOf('.');
    var rupees = at < 0 ? clean : clean.substring(0, at);
    final tail = at < 0 ? '' : clean.substring(at);
    // No leading zeros on the rupees, but a lone `0` before `.` stays.
    rupees = rupees.replaceFirst(RegExp(r'^0+(?=\d)'), '');
    final grouped = rupees.isEmpty ? '' : groupIndian(rupees);
    return '$grouped$tail';
  }

  /// [group] with ₹ set tight before it; empty stays empty, so the hint
  /// shows.
  static String withSign(String raw) {
    final grouped = group(raw);
    return grouped.isEmpty ? '' : '$rupeeSign$grouped';
  }

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = withSign(newValue.text);
    // Keep the caret after the same number of digits (and `.`) it followed.
    final end = newValue.selection.end.clamp(0, newValue.text.length);
    final before = newValue.text
        .substring(0, end)
        .replaceAll(RegExp(r'[^0-9.]'), '')
        .length;
    var seen = 0;
    // Past the ₹, then past as many digits (and `.`) as preceded the caret.
    var caret = text.startsWith(rupeeSign) ? rupeeSign.length : 0;
    while (caret < text.length && seen < before) {
      if (text[caret] != ',') seen++;
      caret++;
    }
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: caret),
    );
  }
}
