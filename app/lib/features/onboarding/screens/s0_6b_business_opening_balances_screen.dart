// S0.6b The business's opening balances (13 §3.2 row S0.6b, ADR 2026-09-09c
// §3–§4, ADR 2026-09-09d §1 and §4).
//
// **One grouped screen, not a three-step wizard.** The accounts already exist
// — `createBook` seeded them from the S0.6a / S0.6a1 answers — so this screen
// is review-and-fill: three groups in the consumer vocabulary (02 §10 🔒 —
// *What you have · Who owes you · Who you owe*, never Assets/Liabilities),
// plus *What each owner put in* on a shared business. A row left empty is
// still created; the S0.7 checklist brings the user back to any row skipped.
//
// **No bank is seeded** (ADR 2026-09-09d §1): the *What you have* group offers
// *Add a bank account* instead, so the bank is named properly the first time
// and asks for its balance in the same breath (02 §4 🔒).
//
// **The opening entry must balance and the screen says how** (ADR 2026-09-09c
// §4): the difference between what the owners put in and the net opening
// position lands in `Opening Balance / Capital A/c`, and the screen shows the
// figure and names the account — never a silent plug.
//
// **Nothing is dated before the book's start date** (ADR 2026-09-09d §4): the
// screen states the date every row will carry; it offers no date picker, so
// nothing earlier can be typed.
//
// Money is integer paise throughout — rupees typed by the user are parsed
// digit by digit ([parseRupeesToPaise]); no double ever touches an amount.
import 'package:core_ledger/core_ledger.dart' show LocalDate;
import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/format/date_format.dart';
import '../../../shared/format/money_format.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';

/// The groups of ADR 2026-09-09c §3, in screen order.
enum OpeningGroup {
  /// Money accounts — cash, and any bank the user adds here.
  have,

  /// Parties with a debit opening — they will pay you.
  owedToYou,

  /// Parties with a credit opening — you will pay them.
  youOwe,

  /// Shared business only: one row per owner's Partner Current A/c.
  ownerContributions,
}

/// One seeded account on S0.6b: what it is called and which group it sits in.
@immutable
final class OpeningRow {
  /// Creates a row.
  const OpeningRow({
    required this.accountId,
    required this.name,
    required this.group,
    this.initialPaise = 0,
    this.suggested = false,
  });

  /// The engine account id this row's opening balance posts against.
  final String accountId;

  /// The seeded (editable) account name.
  final String name;

  /// Which group the row is rendered under.
  final OpeningGroup group;

  /// Pre-filled amount in paise, unsigned — the group supplies the sign.
  final int initialPaise;

  /// True when [initialPaise] is a *suggestion* derived from the share
  /// weights. ADR 2026-09-09c §4: a contribution is asked, never derived, so
  /// the suggestion is labelled as one and stays editable.
  final bool suggested;
}

/// Parses a rupee amount the user typed into integer paise. Digits only, an
/// optional decimal point and at most two decimals; anything else yields 0.
/// Deliberately string arithmetic — CLAUDE.md rule 1.
int parseRupeesToPaise(String input) {
  final cleaned = input.replaceAll(',', '').replaceAll(' ', '').trim();
  if (cleaned.isEmpty) return 0;
  final parts = cleaned.split('.');
  if (parts.length > 2) return 0;
  final rupees = parts[0].isEmpty ? '0' : parts[0];
  final paise = parts.length == 2 ? parts[1].padRight(2, '0') : '00';
  if (!RegExp(r'^\d+$').hasMatch(rupees)) return 0;
  if (paise.length > 2 || !RegExp(r'^\d{2}$').hasMatch(paise)) return 0;
  return (int.tryParse(rupees) ?? 0) * 100 + (int.tryParse(paise) ?? 0);
}

/// The sign a group's typed amount carries in the engine (02 §4): money and
/// *who owes you* are debit-positive; *who you owe* and an owner's Partner
/// Current A/c are credit, so negative.
int signOf(OpeningGroup group) => switch (group) {
  OpeningGroup.have || OpeningGroup.owedToYou => 1,
  OpeningGroup.youOwe || OpeningGroup.ownerContributions => -1,
};

/// S0.6b — the grouped opening-balances screen.
class BusinessOpeningBalancesScreen extends StatefulWidget {
  /// Creates the screen.
  const BusinessOpeningBalancesScreen({
    super.key,
    required this.rows,
    required this.startDate,
    this.onSave,
    this.onSkip,
    this.onAddAccount,
  });

  /// The seeded accounts, already grouped by [OpeningRow.group].
  final List<OpeningRow> rows;

  /// The book's start date (ADR 2026-09-09d §4) — every row is dated here.
  final LocalDate startDate;

  /// Called with account id → **signed** paise, ready for
  /// `LocalLedger.openingBalances`. Zero rows are included; the engine skips
  /// them, and the account exists either way (ADR 2026-09-09c §3).
  final void Function(Map<String, int> balances)? onSave;

  /// *Skip for now* — the S0.7 checklist brings the user back.
  final VoidCallback? onSkip;

  /// Opens the *Add an account* type grid (S3.1) for a group — how a bank
  /// arrives, since no book seeds one (ADR 2026-09-09d §1).
  final void Function(OpeningGroup group)? onAddAccount;

  @override
  State<BusinessOpeningBalancesScreen> createState() =>
      _BusinessOpeningBalancesScreenState();
}

class _BusinessOpeningBalancesScreenState
    extends State<BusinessOpeningBalancesScreen> {
  final _fields = <String, TextEditingController>{};

  @override
  void initState() {
    super.initState();
    for (final row in widget.rows) {
      _fields[row.accountId] = TextEditingController(
        text: row.initialPaise == 0 ? '' : (row.initialPaise ~/ 100).toString(),
      );
    }
  }

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  int _paiseOf(OpeningRow row) =>
      parseRupeesToPaise(_fields[row.accountId]?.text ?? '');

  Map<String, int> get _signed => {
    for (final row in widget.rows)
      row.accountId: signOf(row.group) * _paiseOf(row),
  };

  /// What `Opening Balance / Capital A/c` absorbs: the counterpart of every
  /// other line, so the entry balances (ADR 2026-09-09c §4).
  int get _balancingPaise => -_signed.values.fold<int>(0, (sum, p) => sum + p);

  List<OpeningRow> _group(OpeningGroup g) => [
    for (final r in widget.rows)
      if (r.group == g) r,
  ];

  String _groupLabel(AppLocalizations l10n, OpeningGroup g) => switch (g) {
    OpeningGroup.have => l10n.onboardingBusinessOpeningGroupHave,
    OpeningGroup.owedToYou => l10n.onboardingBusinessOpeningGroupOwedToYou,
    OpeningGroup.youOwe => l10n.onboardingBusinessOpeningGroupYouOwe,
    OpeningGroup.ownerContributions =>
      l10n.onboardingBusinessOpeningGroupOwnerContributions,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final status = RkStatusColors.of(context);
    final text = Theme.of(context).textTheme;
    final locale = Localizations.localeOf(context);
    final balancing = _balancingPaise;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(RkSpace.s6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ListView(
                  children: [
                    Text(
                      l10n.onboardingBusinessOpeningTitle,
                      style: text.headlineMedium,
                    ),
                    const SizedBox(height: RkSpace.s2),
                    Text(
                      l10n.onboardingBusinessOpeningSubtitle,
                      style: text.bodyLarge,
                    ),
                    const SizedBox(height: RkSpace.s4),
                    _Note(
                      icon: Icons.event_outlined,
                      text: l10n.onboardingBusinessOpeningDatedNote(
                        formatLedgerDate(widget.startDate, strings: l10n),
                      ),
                    ),
                    for (final group in OpeningGroup.values) ...[
                      if (_group(group).isNotEmpty ||
                          group == OpeningGroup.have) ...[
                        const SizedBox(height: RkSpace.s6),
                        Text(_groupLabel(l10n, group), style: text.titleMedium),
                        if (group == OpeningGroup.ownerContributions) ...[
                          const SizedBox(height: RkSpace.s1),
                          Text(
                            l10n.onboardingBusinessOpeningSuggestionNote,
                            style: text.bodySmall?.copyWith(
                              color: status.muted,
                            ),
                          ),
                        ],
                        const SizedBox(height: RkSpace.s2),
                        for (final row in _group(group)) ...[
                          _AmountRow(
                            row: row,
                            controller: _fields[row.accountId]!,
                            onChanged: () => setState(() {}),
                          ),
                          const SizedBox(height: RkSpace.s2),
                        ],
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: TextButton.icon(
                            onPressed: widget.onAddAccount == null
                                ? null
                                : () => widget.onAddAccount!(group),
                            icon: const Icon(Icons.add),
                            label: Text(
                              group == OpeningGroup.have
                                  // No book seeds a bank (ADR 2026-09-09d §1).
                                  ? l10n.onboardingBusinessOpeningAddBank
                                  : l10n.onboardingBusinessOpeningAddAnother,
                            ),
                          ),
                        ),
                      ],
                    ],
                    const SizedBox(height: RkSpace.s6),
                    Text(
                      l10n.onboardingBusinessOpeningZeroNote,
                      style: text.bodySmall?.copyWith(color: status.muted),
                    ),
                    const SizedBox(height: RkSpace.s4),
                    // The balancing figure, named — never a silent plug.
                    Container(
                      padding: const EdgeInsets.all(RkSpace.s4),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(RkRadius.lg),
                        border: Border.all(color: status.hairline),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.onboardingBusinessOpeningBalancingLabel,
                            style: text.titleSmall,
                          ),
                          const SizedBox(height: RkSpace.s1),
                          Text(
                            balancing == 0
                                ? l10n.onboardingBusinessOpeningBalancingZero
                                : l10n.onboardingBusinessOpeningBalancingNote(
                                    formatPaise(
                                      balancing.abs(),
                                      locale: locale,
                                    ),
                                  ),
                            style: text.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              FilledButton(
                onPressed: () => widget.onSave?.call(_signed),
                child: Text(l10n.onboardingBusinessOpeningSave),
              ),
              const SizedBox(height: RkSpace.s2),
              TextButton(
                onPressed: widget.onSkip,
                child: Text(l10n.onboardingBusinessOpeningSkip),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AmountRow extends StatelessWidget {
  const _AmountRow({
    required this.row,
    required this.controller,
    required this.onChanged,
  });

  final OpeningRow row;
  final TextEditingController controller;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    // Wrap, not Row: at 200% text scale on a 360-wide screen the name and the
    // field stack instead of overflowing.
    return Wrap(
      runSpacing: RkSpace.s1,
      children: [
        SizedBox(
          width: double.infinity,
          child: Text(row.name, style: text.titleSmall),
        ),
        SizedBox(
          width: double.infinity,
          child: Semantics(
            label:
                '${row.name} · ${l10n.onboardingBusinessOpeningBalanceLabel}',
            child: TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: l10n.onboardingBusinessOpeningBalanceLabel,
                prefixText: rupeeSign,
              ),
              onChanged: (_) => onChanged(),
            ),
          ),
        ),
      ],
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final status = RkStatusColors.of(context);
    final style = Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: status.muted);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: RkIcon.grid, color: status.muted),
        const SizedBox(width: RkSpace.s2),
        Expanded(child: Text(text, style: style)),
      ],
    );
  }
}
