// S0.6a Name the business (13 §3.2 row S0.6a, 07 §5.7, 07 §3.1.1 branch O6a) —
// three answers and nothing else: name · who owns it · financial-year start.
//
// The ownership answer is what branches the flow: *Just me* goes straight to
// S0.6b, *Shared with others* goes to S0.6a1 first (ADR 2026-09-09 §1). The
// screen never asks for a start date: the book's start date is stamped when
// the book is created (ADR 2026-09-09d §4, `LocalLedger.createBook`), so this
// screen only *states* it, together with the floor it sets — nothing may ever
// be dated before it.
import 'package:core_ledger/core_ledger.dart' show LocalDate;
import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/format/date_format.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';

/// Who owns the business (07 §5.7); maps to `BookOwnership` when the book is
/// created. [shared] is the only value that reaches S0.6a1.
enum BusinessOwnershipChoice {
  /// One owner — gets `Drawings A/c` beside Opening Balance / Capital.
  justMe,

  /// Several owners — S0.6a1 collects them and their share weights.
  shared,
}

/// The three answers S0.6a collects, handed to the caller that calls
/// `createBook`. Money is not touched here; opening balances are S0.6b's job.
@immutable
final class BusinessDraft {
  /// Creates a draft.
  const BusinessDraft({
    required this.name,
    required this.ownership,
    required this.fyStartMonth,
  });

  /// The business name, trimmed.
  final String name;

  /// *Just me* or *Shared with others*.
  final BusinessOwnershipChoice ownership;

  /// Financial-year start month, 1–12 (02 §8.1); April by default.
  final int fyStartMonth;
}

/// S0.6a — name the business, say who owns it, pick the FY start.
class BusinessNameScreen extends StatefulWidget {
  /// Creates the screen.
  const BusinessNameScreen({
    super.key,
    required this.startDate,
    this.onSubmit,
    this.initial,
  });

  /// The day this book's books begin (ADR 2026-09-09d §4) — stated, never
  /// edited: `createBook` stamps it and it is immutable thereafter.
  final LocalDate startDate;

  /// Called with the answers when Continue is pressed.
  final void Function(BusinessDraft draft)? onSubmit;

  /// Pre-fills the screen when the user comes back to this step (07 §3.1.1:
  /// every branch step is resumable) — including the *Just me after all*
  /// return from S0.6a1 (ADR 2026-09-09 §3).
  final BusinessDraft? initial;

  @override
  State<BusinessNameScreen> createState() => _BusinessNameScreenState();
}

class _BusinessNameScreenState extends State<BusinessNameScreen> {
  late final _name = TextEditingController(text: widget.initial?.name ?? '');
  late var _ownership =
      widget.initial?.ownership ?? BusinessOwnershipChoice.justMe;
  late var _fyStartMonth = widget.initial?.fyStartMonth ?? 4;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    widget.onSubmit?.call(
      BusinessDraft(
        name: name,
        ownership: _ownership,
        fyStartMonth: _fyStartMonth,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final status = RkStatusColors.of(context);
    final text = Theme.of(context).textTheme;
    final empty = _name.text.trim().isEmpty;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(RkSpace.s6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        l10n.onboardingBusinessTitle,
                        style: text.headlineMedium,
                      ),
                      const SizedBox(height: RkSpace.s2),
                      Text(
                        l10n.onboardingBusinessSubtitle,
                        style: text.bodyLarge,
                      ),
                      const SizedBox(height: RkSpace.s6),
                      TextField(
                        controller: _name,
                        autofocus: true,
                        textCapitalization: TextCapitalization.words,
                        decoration: InputDecoration(
                          labelText: l10n.onboardingBusinessNameLabel,
                          hintText: l10n.onboardingBusinessNameHint,
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: RkSpace.s6),
                      Text(
                        l10n.onboardingBusinessOwnershipQuestion,
                        style: text.titleMedium,
                      ),
                      const SizedBox(height: RkSpace.s2),
                      _OwnershipOption(
                        label: l10n.onboardingBusinessOwnershipJustMe,
                        note: l10n.onboardingBusinessOwnershipJustMeNote,
                        selected: _ownership == BusinessOwnershipChoice.justMe,
                        onTap: () => setState(
                          () => _ownership = BusinessOwnershipChoice.justMe,
                        ),
                      ),
                      const SizedBox(height: RkSpace.s2),
                      _OwnershipOption(
                        label: l10n.onboardingBusinessOwnershipShared,
                        note: l10n.onboardingBusinessOwnershipSharedNote,
                        selected: _ownership == BusinessOwnershipChoice.shared,
                        onTap: () => setState(
                          () => _ownership = BusinessOwnershipChoice.shared,
                        ),
                      ),
                      const SizedBox(height: RkSpace.s6),
                      Text(
                        l10n.onboardingBusinessFyLabel,
                        style: text.titleMedium,
                      ),
                      const SizedBox(height: RkSpace.s2),
                      DropdownButtonFormField<int>(
                        initialValue: _fyStartMonth,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: l10n.onboardingBusinessFyLabel,
                          helperText: l10n.onboardingBusinessFyNote,
                          helperMaxLines: 3,
                        ),
                        items: [
                          for (var m = 1; m <= 12; m++)
                            DropdownMenuItem(
                              value: m,
                              child: Text(monthName(l10n, m)),
                            ),
                        ],
                        onChanged: (m) =>
                            setState(() => _fyStartMonth = m ?? _fyStartMonth),
                      ),
                      const SizedBox(height: RkSpace.s6),
                      // ADR 2026-09-09d §4 stated, not asked: the books begin
                      // the day the book is made and nothing may precede it.
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.event_outlined,
                            size: RkIcon.grid,
                            color: status.muted,
                          ),
                          const SizedBox(width: RkSpace.s2),
                          Expanded(
                            child: Text(
                              l10n.onboardingBusinessStartNote(
                                formatLedgerDate(
                                  widget.startDate,
                                  strings: l10n,
                                ),
                              ),
                              style: text.bodySmall?.copyWith(
                                color: status.muted,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              // Disabled-with-reason (13 §4.3).
              if (empty)
                Padding(
                  padding: const EdgeInsets.only(bottom: RkSpace.s2),
                  child: Text(
                    l10n.onboardingBusinessNameError,
                    style: text.bodySmall?.copyWith(color: status.muted),
                  ),
                ),
              FilledButton(
                onPressed: empty ? null : _submit,
                child: Text(l10n.onboardingBusinessContinueLabel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One ownership choice: a tappable card whose selected state carries a tick
/// *and* the label weight — colour never alone (07 §1 rule 3).
class _OwnershipOption extends StatelessWidget {
  const _OwnershipOption({
    required this.label,
    required this.note,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String note;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final status = RkStatusColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Semantics(
      selected: selected,
      button: true,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(RkRadius.lg),
        child: Container(
          padding: const EdgeInsets.all(RkSpace.s4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(RkRadius.lg),
            border: Border.all(
              color: selected ? scheme.primary : status.hairline,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                selected ? Icons.check_circle : Icons.radio_button_unchecked,
                size: RkIcon.grid,
                color: selected ? scheme.primary : status.muted,
              ),
              const SizedBox(width: RkSpace.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: text.titleMedium?.copyWith(
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                    const SizedBox(height: RkSpace.s1),
                    Text(
                      note,
                      style: text.bodySmall?.copyWith(color: status.muted),
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
