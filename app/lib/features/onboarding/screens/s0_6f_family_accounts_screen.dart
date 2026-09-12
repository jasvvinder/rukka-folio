// S0.6f The family's shared accounts (13 §3.2 row S0.6f, 07 §3.1.1 branch
// O6f "pool bank and cash").
//
// Reuses the S0.6b grouped opening-balance pattern (ADR 2026-09-09c §3): the
// pool book's accounts already exist by the time this screen shows —
// [FamilyOpeningHost] creates it — so this is review-and-fill, not creation.
// It reuses [OpeningRow], [OpeningGroup.have], [parseRupeesToPaise] and
// [signOf] from S0.6b's screen file rather than redefining them.
//
// Unlike S0.6b there is only ever one group: the pool has no parties seeded
// (ADR 2026-09-09c §1: no party accounts are ever seeded) and it is not a
// partnership, so there is no *What each owner put in* section. **No bank is
// seeded** (ADR 2026-09-09d §1) — the group offers *Add a bank account*
// instead, named properly the first time and asking for its balance in the
// same breath (02 §4 🔒).
//
// Money is integer paise throughout; rupees typed by the user are parsed
// digit by digit, never through a double (CLAUDE.md rule 1).
import 'package:core_ledger/core_ledger.dart' show LocalDate;
import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/format/date_format.dart';
import '../../../shared/format/money_format.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';
import 's0_6b_business_opening_balances_screen.dart'
    show OpeningGroup, OpeningRow, parseRupeesToPaise, signOf;

/// S0.6f — the pool's seeded money accounts, review-and-fill.
class FamilySharedAccountsScreen extends StatefulWidget {
  /// Creates the screen.
  const FamilySharedAccountsScreen({
    super.key,
    required this.rows,
    required this.startDate,
    this.onSave,
    this.onSkip,
    this.onAddAccount,
  });

  /// The seeded money accounts (always [OpeningGroup.have]).
  final List<OpeningRow> rows;

  /// The book's start date (ADR 2026-09-09d §4) — every row is dated here.
  final LocalDate startDate;

  /// Called with account id → signed paise, ready for
  /// `LocalLedger.openingBalances`. Zero rows are included; the engine skips
  /// them, and the account exists either way.
  final void Function(Map<String, int> balances)? onSave;

  /// *Skip for now* — the S0.7 checklist brings the user back.
  final VoidCallback? onSkip;

  /// Opens *Add an account* (S3.1) for the pool — how a bank arrives, since
  /// no book seeds one (ADR 2026-09-09d §1).
  final void Function(OpeningGroup group)? onAddAccount;

  @override
  State<FamilySharedAccountsScreen> createState() =>
      _FamilySharedAccountsScreenState();
}

class _FamilySharedAccountsScreenState
    extends State<FamilySharedAccountsScreen> {
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

  /// What `Opening Balance / Capital A/c` absorbs — the counterpart of every
  /// row typed, so the entry balances (ADR 2026-09-09c §4).
  int get _balancingPaise => -_signed.values.fold<int>(0, (sum, p) => sum + p);

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
                      l10n.onboardingFamilyAccountsTitle,
                      style: text.headlineMedium,
                    ),
                    const SizedBox(height: RkSpace.s2),
                    Text(
                      l10n.onboardingFamilyAccountsSubtitle,
                      style: text.bodyLarge,
                    ),
                    const SizedBox(height: RkSpace.s4),
                    _Note(
                      icon: Icons.event_outlined,
                      text: l10n.onboardingFamilyAccountsDatedNote(
                        formatLedgerDate(widget.startDate, strings: l10n),
                      ),
                    ),
                    const SizedBox(height: RkSpace.s6),
                    Text(
                      l10n.onboardingFamilyAccountsGroupHave,
                      style: text.titleMedium,
                    ),
                    const SizedBox(height: RkSpace.s2),
                    for (final row in widget.rows) ...[
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
                            : () => widget.onAddAccount!(OpeningGroup.have),
                        icon: const Icon(Icons.add),
                        // No book seeds a bank (ADR 2026-09-09d §1).
                        label: Text(l10n.onboardingFamilyAccountsAddBank),
                      ),
                    ),
                    const SizedBox(height: RkSpace.s6),
                    Text(
                      l10n.onboardingFamilyAccountsZeroNote,
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
                            l10n.onboardingFamilyAccountsBalancingLabel,
                            style: text.titleSmall,
                          ),
                          const SizedBox(height: RkSpace.s1),
                          Text(
                            balancing == 0
                                ? l10n.onboardingFamilyAccountsBalancingZero
                                : l10n.onboardingFamilyAccountsBalancingNote(
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
                child: Text(l10n.onboardingFamilyAccountsSave),
              ),
              const SizedBox(height: RkSpace.s2),
              TextButton(
                onPressed: widget.onSkip,
                child: Text(l10n.onboardingFamilyAccountsSkip),
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
            label: '${row.name} · ${l10n.onboardingFamilyAccountsBalanceLabel}',
            child: TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: l10n.onboardingFamilyAccountsBalanceLabel,
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
