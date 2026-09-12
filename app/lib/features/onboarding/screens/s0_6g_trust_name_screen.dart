// S0.6g Name the trust and its type (13 §3.2 row S0.6g, 07 §3.1.1 branch
// O6g) — a name and which of the four illustrative types it is: gurudwara,
// temple, society, registered trust (07 §3.1 step 3: "the list is examples,
// not an exhaustive set; the underlying tenant type is the generic
// `organization`").
//
// Unlike S0.6a there is no ownership question (a trust is not a
// partnership — no owner-contributions group, the same reading U1d took for
// the family pool, ADR 2026-09-09c §2) and no financial-year choice (07
// §3.1.1's trust row asks for none, same as the family branch).
//
// As with S0.6a/S0.6d, the screen only *states* the book's start date and the
// floor it sets (ADR 2026-09-09d §4) — `createBook` stamps it, and nothing
// here ever offers a picker.
//
// ⚠️ SPEC: the chosen [TrustType] has nowhere to persist — `BookConfig`
// (packages/data) carries no organization-subtype field, the same gap ADR
// 2026-09-09 §1 left open for S0.6a1's share weights. It is held on
// [OnboardingFlow] for this build and named in the lane report; giving it a
// home is a `packages/data` change, not one for this lane's directories.
import 'package:core_ledger/core_ledger.dart' show LocalDate;
import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/format/date_format.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';

/// Which of the four illustrative types (07 §3.1 step 3) the trust is. The
/// list is examples, not exhaustive — every value maps to the same
/// `tenant.type = organization`.
enum TrustType {
  /// ਗੁਰਦੁਆਰਾ.
  gurudwara,

  /// A temple / मंदिर.
  temple,

  /// A registered society.
  society,

  /// A registered trust.
  registeredTrust,
}

/// The two answers S0.6g collects, handed to the caller that calls
/// `createBook`. Money is not touched here; opening balances are S0.6i's job.
@immutable
final class TrustDraft {
  /// Creates a draft.
  const TrustDraft({required this.name, required this.type});

  /// The trust's name, trimmed.
  final String name;

  /// The illustrative type chosen (07 §3.1 step 3) — display only; see the
  /// ⚠️ SPEC note above.
  final TrustType type;
}

/// S0.6g — name the trust and say which of the four illustrative types it
/// is.
class TrustNameScreen extends StatefulWidget {
  /// Creates the screen.
  const TrustNameScreen({
    super.key,
    required this.startDate,
    this.onSubmit,
    this.initial,
  });

  /// The day this book's books begin (ADR 2026-09-09d §4) — stated, never
  /// edited.
  final LocalDate startDate;

  /// Called with the answers when Continue is pressed.
  final void Function(TrustDraft draft)? onSubmit;

  /// Pre-fills the screen when the step is resumed (07 §3.1.1).
  final TrustDraft? initial;

  @override
  State<TrustNameScreen> createState() => _TrustNameScreenState();
}

class _TrustNameScreenState extends State<TrustNameScreen> {
  late final _name = TextEditingController(text: widget.initial?.name ?? '');
  late var _type = widget.initial?.type ?? TrustType.gurudwara;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    widget.onSubmit?.call(TrustDraft(name: name, type: _type));
  }

  String _typeLabel(AppLocalizations l10n, TrustType t) => switch (t) {
    TrustType.gurudwara => l10n.onboardingTrustTypeGurudwara,
    TrustType.temple => l10n.onboardingTrustTypeTemple,
    TrustType.society => l10n.onboardingTrustTypeSociety,
    TrustType.registeredTrust => l10n.onboardingTrustTypeRegisteredTrust,
  };

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
                        l10n.onboardingTrustTitle,
                        style: text.headlineMedium,
                      ),
                      const SizedBox(height: RkSpace.s2),
                      Text(l10n.onboardingTrustSubtitle, style: text.bodyLarge),
                      const SizedBox(height: RkSpace.s6),
                      TextField(
                        controller: _name,
                        autofocus: true,
                        textCapitalization: TextCapitalization.words,
                        decoration: InputDecoration(
                          labelText: l10n.onboardingTrustNameLabel,
                          hintText: l10n.onboardingTrustNameHint,
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: RkSpace.s6),
                      Text(
                        l10n.onboardingTrustTypeQuestion,
                        style: text.titleMedium,
                      ),
                      const SizedBox(height: RkSpace.s2),
                      for (final t in TrustType.values) ...[
                        _TrustTypeOption(
                          label: _typeLabel(l10n, t),
                          selected: _type == t,
                          onTap: () => setState(() => _type = t),
                        ),
                        const SizedBox(height: RkSpace.s2),
                      ],
                      const SizedBox(height: RkSpace.s4),
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
                              l10n.onboardingTrustStartNote(
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
                    l10n.onboardingTrustNameError,
                    style: text.bodySmall?.copyWith(color: status.muted),
                  ),
                ),
              FilledButton(
                onPressed: empty ? null : _submit,
                child: Text(l10n.onboardingTrustContinueLabel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One trust-type choice: a tappable card whose selected state carries a
/// tick *and* the label weight — colour never alone (07 §1 rule 3). Mirrors
/// S0.6a's `_OwnershipOption`.
class _TrustTypeOption extends StatelessWidget {
  const _TrustTypeOption({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
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
          padding: const EdgeInsets.all(RkSpace.s3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(RkRadius.lg),
            border: Border.all(
              color: selected ? scheme.primary : status.hairline,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected ? Icons.check_circle : Icons.radio_button_unchecked,
                size: RkIcon.grid,
                color: selected ? scheme.primary : status.muted,
              ),
              const SizedBox(width: RkSpace.s3),
              Expanded(
                child: Text(
                  label,
                  style: text.titleMedium?.copyWith(
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
