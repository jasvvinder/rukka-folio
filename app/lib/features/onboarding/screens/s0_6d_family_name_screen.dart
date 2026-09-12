// S0.6d Name the family (13 §3.2 row S0.6d, 07 §3.1.1 branch O6d) — the
// simplest branch step: just a name. Unlike S0.6a there is no ownership
// question (a family pool is one book, never several, ADR 2026-09-09c §2)
// and no financial-year choice (07 §3.1.1's family row asks for none).
//
// As with S0.6a, the screen only *states* the book's start date and the
// floor it sets (ADR 2026-09-09d §4) — `createBook` stamps it, and nothing
// here ever offers a picker.
import 'package:core_ledger/core_ledger.dart' show LocalDate;
import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/format/date_format.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';

/// The one answer S0.6d collects, handed to `createBook` at the committing
/// step (S0.6f, [FamilyOpeningHost]).
@immutable
final class FamilyDraft {
  /// Creates a draft.
  const FamilyDraft({required this.name});

  /// The family name, trimmed.
  final String name;
}

/// S0.6d — name the family.
class FamilyNameScreen extends StatefulWidget {
  /// Creates the screen.
  const FamilyNameScreen({
    super.key,
    required this.startDate,
    this.onSubmit,
    this.initial,
  });

  /// The day this book's books begin (ADR 2026-09-09d §4) — stated, never
  /// edited.
  final LocalDate startDate;

  /// Called with the answer when Continue is pressed.
  final void Function(FamilyDraft draft)? onSubmit;

  /// Pre-fills the screen when the step is resumed (07 §3.1.1).
  final FamilyDraft? initial;

  @override
  State<FamilyNameScreen> createState() => _FamilyNameScreenState();
}

class _FamilyNameScreenState extends State<FamilyNameScreen> {
  late final _name = TextEditingController(text: widget.initial?.name ?? '');

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    widget.onSubmit?.call(FamilyDraft(name: name));
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
                        l10n.onboardingFamilyTitle,
                        style: text.headlineMedium,
                      ),
                      const SizedBox(height: RkSpace.s2),
                      Text(
                        l10n.onboardingFamilySubtitle,
                        style: text.bodyLarge,
                      ),
                      const SizedBox(height: RkSpace.s6),
                      TextField(
                        controller: _name,
                        autofocus: true,
                        textCapitalization: TextCapitalization.words,
                        decoration: InputDecoration(
                          labelText: l10n.onboardingFamilyNameLabel,
                          hintText: l10n.onboardingFamilyNameHint,
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: RkSpace.s6),
                      // ADR 2026-09-09d §4 stated, not asked.
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
                              l10n.onboardingFamilyStartNote(
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
                    l10n.onboardingFamilyNameError,
                    style: text.bodySmall?.copyWith(color: status.muted),
                  ),
                ),
              FilledButton(
                onPressed: empty ? null : _submit,
                child: Text(l10n.onboardingFamilyContinueLabel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
