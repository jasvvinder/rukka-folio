// S0.6c Add another business? (13 §3.2 row S0.6c — "loop control,
// multi-business branch"; 07 §3.1.1 branch O6c; design canvas 1 *Onboarding*,
// screen **S0.6c**).
//
// The only screen in onboarding whose job is a *branch*, not an answer: the
// **My businesses** row of 07 §3.1.1 reads O6a → O6b → **O6c** looping back to
// O6a → O6 your own → checklist. The **My shop** row does not pass through
// here at all — the canvas caption says it exactly: "My shop arrives with one
// book made and leaves; My businesses loops here until the person says that is
// all" — so reaching this screen is decided by the purpose card, not by the
// fact that a business exists (`afterBusinessOpening`, onboarding_routes.dart).
//
// Nothing is created here and nothing is posted: each business became its own
// book at its own committing step (ADR 2026-09-09c §3), so this screen only
// recaps what is already real and asks which way to go.
//
// The canvas ranks the two ways on, and it is the opposite of the obvious
// guess: the loop is a **list row** under the businesses already made, and the
// filled primary is **No, that's all**. Nobody is pushed round the loop a
// second time; the way out is the biggest thing on the screen, with the
// generic *Skip for now* of every branch step beneath it (07 §3.1.1).
import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/format/date_format.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';

/// One business already set up, as S0.6c recaps it: the name from S0.6a and
/// the financial year it keeps.
///
/// ⚠️ SPEC: the canvas row reads `shop · FY from 1 April · ₹1,50,500`. The
/// opening total is a balance read against that book, which this step does not
/// hold — S0.6b posts and moves on — so the row states only what onboarding
/// itself knows rather than showing an amount it would have to guess. The gap
/// is in the lane report (canvas 1, screen S0.6c).
@immutable
final class AddedBusiness {
  /// Creates a recap row.
  const AddedBusiness({required this.name, this.fyStartMonth});

  /// The business name, as S0.6a took it.
  final String name;

  /// Financial-year start month, 1–12 (02 §8.1); omitted when unknown.
  final int? fyStartMonth;
}

/// S0.6c — recap the businesses set up so far, then loop or move on.
class AddAnotherBusinessScreen extends StatelessWidget {
  /// Creates the screen.
  const AddAnotherBusinessScreen({
    super.key,
    required this.businesses,
    this.onAddAnother,
    this.onDone,
    this.onSkip,
  });

  /// The businesses set up so far, in the order they were named. Empty is
  /// drawn too: the recap simply disappears and every way on remains.
  final List<AddedBusiness> businesses;

  /// *Add another business* — back to S0.6a for the next one (07 §3.1.1).
  final VoidCallback? onAddAnother;

  /// *No, that's all* — on to the user's own opening balances and the S0.7
  /// checklist (07 §3.1.1, 07 §3.1 step 7).
  final VoidCallback? onDone;

  /// *Skip for now* — every branch step is skippable (07 §3.1.1); the S0.7
  /// checklist is what brings the rest of setup back.
  final VoidCallback? onSkip;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final status = RkStatusColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(top: RkSpace.s6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: RkSpace.s5,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.onboardingBusinessAnotherTitle,
                            style: text.headlineMedium,
                          ),
                          const SizedBox(height: RkSpace.s2),
                          Text(
                            l10n.onboardingBusinessAnotherSubtitle,
                            style: text.bodyMedium?.copyWith(
                              color: status.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: RkSpace.s5),
                    // Hairline-ruled rows, not cards — this is a paper product
                    // (design-system §4.1, canvas 1 S0.6c).
                    Divider(
                      height: 1,
                      thickness: 1,
                      color: scheme.outlineVariant,
                    ),
                    for (final business in businesses)
                      _BusinessRow(business: business),
                    _AddAnotherRow(onTap: onAddAnother),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                RkSpace.s5,
                RkSpace.s4,
                RkSpace.s5,
                RkSpace.s3,
              ),
              child: Text(
                l10n.onboardingBusinessAnotherBooksNote,
                style: text.bodySmall?.copyWith(color: status.muted),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: RkSpace.s4),
              child: FilledButton(
                onPressed: onDone,
                child: Text(l10n.onboardingBusinessAnotherDone),
              ),
            ),
            TextButton(
              onPressed: onSkip,
              child: Text(l10n.onboardingBusinessAnotherSkip),
            ),
          ],
        ),
      ),
    );
  }
}

/// One recap row: the business's name, the financial year it keeps, and a tick
/// saying its book is already made. The tick is an icon, not a bare colour
/// (07 §1 rule 3), and it carries the word for a screen reader.
class _BusinessRow extends StatelessWidget {
  const _BusinessRow({required this.business});

  final AddedBusiness business;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final status = RkStatusColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final month = business.fyStartMonth;
    return Container(
      constraints: const BoxConstraints(minHeight: RkSpace.rowMinHeight),
      padding: const EdgeInsets.symmetric(
        vertical: RkSpace.s2,
        horizontal: RkSpace.s4,
      ),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(business.name, style: text.bodyLarge),
                if (month != null)
                  Text(
                    l10n.onboardingBusinessAnotherRowMeta(
                      monthName(l10n, month),
                    ),
                    style: text.bodySmall?.copyWith(color: status.muted),
                  ),
              ],
            ),
          ),
          const SizedBox(width: RkSpace.s3),
          Icon(
            Icons.check,
            size: RkIcon.grid,
            color: status.credit,
            semanticLabel: l10n.onboardingBusinessAnotherReadyTag,
          ),
        ],
      ),
    );
  }
}

/// The loop itself — the last row of the list, never the page's primary
/// (canvas 1, screen S0.6c).
class _AddAnotherRow extends StatelessWidget {
  const _AddAnotherRow({this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: RkSpace.rowMinHeight),
        padding: const EdgeInsets.symmetric(
          vertical: RkSpace.s2,
          horizontal: RkSpace.s4,
        ),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
        ),
        child: Row(
          children: [
            Icon(Icons.add, size: RkIcon.grid, color: scheme.primary),
            const SizedBox(width: RkSpace.s3),
            Expanded(
              child: Text(
                l10n.onboardingBusinessAnotherAdd,
                style: text.titleMedium?.copyWith(color: scheme.primary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
