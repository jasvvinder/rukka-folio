// F1 widget tests for S12.1 Plans (13 §3.2 row S12.1, 08 §2 🔒 quotas,
// 08 §3.1 🔒 upgrade flow, 08 §3.2 / ADR 2026-09-05g §8 🔒 channels, ADR
// 2026-09-05g §14 🔒 organisations above 15, DESIGN-PACK §11 S12.1 🔒).
@Tags(['F1'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/subscription/entitlement_source.dart';
import 'package:rukka_folio/features/subscription/screens/s12_1_plans_screen.dart';
import 'package:rukka_folio/features/subscription/tier_catalogue.dart';
import 'package:rukka_folio/l10n/gen/app_localizations.dart';

import '../../shared/test_app.dart';

/// Tall enough that every card is built — a sliver below the fold has no
/// element, so `find` cannot see it.
const _tall = Size(420, 6000);

Entitlement _reading({RkPlan plan = RkPlan.family, int activeMembers = 3}) =>
    Entitlement(
      tenantId: 't1',
      plan: plan,
      limits: rkTierFor(plan).limits,
      periodEnd: DateTime(2026, 10, 1),
      graceKind: EntitlementGraceKind.none,
      source: EntitlementSourceKind.fresh,
      activeMembers: activeMembers,
    );

Future<void> _pump(
  WidgetTester tester, {
  Entitlement? entitlement,
  RkCheckoutChannel channel = RkCheckoutChannel.gateway,
  List<RkTier> tiers = rkTiers,
  Locale? locale,
  Size viewport = _tall,
  double textScale = 1,
}) => pumpRk(
  tester,
  PlansScreen(
    source: FakeEntitlementSource(entitlement: entitlement ?? _reading()),
    channel: channel,
    tiers: tiers,
  ),
  locale: locale,
  viewport: viewport,
  textScale: textScale,
);

void main() {
  group('S12.1 Plans', () {
    testWidgets(
      'F1-07-459 every 08 §2 tier is a card, with its quotas in plain words',
      (tester) async {
        final l10n = await AppLocalizations.delegate.load(const Locale('en'));
        await _pump(tester);

        expect(find.text(l10n.plansTitle), findsOneWidget);
        for (final name in [
          l10n.subscriptionPlanFree,
          l10n.subscriptionPlanPersonal,
          l10n.subscriptionPlanFamily,
          l10n.subscriptionPlanFamilyPlus,
        ]) {
          expect(find.text(name), findsOneWidget, reason: 'card $name');
        }

        // 08 §2 🔒 bands, as the cards say them.
        expect(find.text(l10n.plansLimitMembers(5)), findsOneWidget);
        expect(find.text(l10n.plansLimitMembers(15)), findsOneWidget);
        expect(find.text(l10n.plansLimitBooks(3)), findsOneWidget);
        // Unlimited is words, never a large number (Personal and Family+).
        expect(find.text(l10n.plansLimitBooksUnlimited), findsNWidgets(2));
        expect(find.text(l10n.plansLimitDevices(8)), findsOneWidget);
        expect(find.text(l10n.plansLimitStorageGb(15)), findsOneWidget);
        expect(find.text(l10n.plansLimitStorageMb(250)), findsOneWidget);
        // The watermark line follows the FORMAT (08 §1 🔒 as made precise by
        // ADR 2026-09-05g §5 and ADR 2026-09-12 §2), on the Free card only.
        expect(find.text(l10n.plansLimitExportsWatermarked), findsOneWidget);
        expect(find.text(l10n.plansLimitExportsClean), findsNWidgets(3));

        // DESIGN-PACK §11 (S12.1) 🔒 closes the screen with this sentence.
        expect(find.text(l10n.plansNeverLocked), findsOneWidget);
      },
    );

    testWidgets(
      'F1-07-460 the current plan is marked and the popular badge sits on one '
      'tier only (08 §3.1 🔒)',
      (tester) async {
        final l10n = await AppLocalizations.delegate.load(const Locale('en'));
        await _pump(tester, entitlement: _reading(plan: RkPlan.personal));
        expect(find.text(l10n.plansCurrent), findsOneWidget);
        expect(find.text(l10n.plansPopular), findsOneWidget);

        // …and it is on the tenant's own card: with only the Personal card
        // pumped the mark is there, with only Family's it is not.
        await _pump(
          tester,
          entitlement: _reading(plan: RkPlan.personal),
          tiers: [rkTierFor(RkPlan.personal)],
        );
        expect(find.text(l10n.subscriptionPlanPersonal), findsOneWidget);
        expect(find.text(l10n.plansCurrent), findsOneWidget);
        expect(find.text(l10n.plansPopular), findsNothing);

        await _pump(
          tester,
          entitlement: _reading(plan: RkPlan.personal),
          tiers: [rkTierFor(RkPlan.family)],
        );
        expect(find.text(l10n.plansCurrent), findsNothing);
        expect(find.text(l10n.plansPopular), findsOneWidget);
      },
    );

    testWidgets(
      'F1-07-461 the Monthly/Annual toggle shows the saving and swaps the '
      'prices, all from integer paise (08 §3.1 🔒, CLAUDE.md rule 1)',
      (tester) async {
        final l10n = await AppLocalizations.delegate.load(const Locale('en'));
        await _pump(tester, tiers: [rkTierFor(RkPlan.family)]);

        // Annual is the default (08 §2 principle 2: monthly is the fallback).
        expect(find.text(l10n.plansCycleSaving(20)), findsOneWidget);
        expect(find.text(l10n.plansPriceYear('₹1,999')), findsOneWidget);
        expect(find.text(l10n.plansPriceMonth('₹209')), findsNothing);

        await tester.tap(find.text(l10n.plansCycleMonthly));
        await tester.pumpAndSettle();
        expect(find.text(l10n.plansPriceMonth('₹209')), findsOneWidget);
        expect(find.text(l10n.plansPriceYear('₹1,999')), findsNothing);
        // The saving stays on screen on both sides of the toggle.
        expect(find.text(l10n.plansCycleSaving(20)), findsOneWidget);

        // Free is free on either side, and never a price of ₹0.
        await _pump(tester, tiers: [rkTierFor(RkPlan.free)]);
        expect(find.text(l10n.plansPriceFree), findsOneWidget);
      },
    );

    testWidgets(
      'F1-07-462 checkout and add-on seats are shut with a reason, never a '
      'silent tap (07 §1 rule 6; S12.2 needs the IAP package)',
      (tester) async {
        final l10n = await AppLocalizations.delegate.load(const Locale('en'));
        await _pump(tester, tiers: [rkTierFor(RkPlan.family)]);

        expect(find.text(l10n.plansChoose), findsOneWidget);
        expect(find.text(l10n.plansChooseReason), findsOneWidget);
        expect(
          tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
          isNull,
        );
        expect(find.text(l10n.plansAddonSeatsTitle), findsOneWidget);
        expect(find.text(l10n.plansAddonSeatsReason), findsOneWidget);
      },
    );

    testWidgets(
      'F1-07-463 an organisation above 15 members is told, not refused '
      '(08 §2, ADR 2026-09-05g §14 🔒)',
      (tester) async {
        final l10n = await AppLocalizations.delegate.load(const Locale('en'));
        await _pump(
          tester,
          entitlement: _reading(plan: RkPlan.familyPlus, activeMembers: 40),
        );
        expect(find.text(l10n.plansLargeOrg), findsOneWidget);
        // Told, not refused: every plan is still on screen and the closing
        // promise is still made.
        expect(find.text(l10n.subscriptionPlanFamilyPlus), findsOneWidget);
        expect(find.text(l10n.plansNeverLocked), findsOneWidget);

        await _pump(
          tester,
          entitlement: _reading(plan: RkPlan.familyPlus, activeMembers: 15),
        );
        expect(find.text(l10n.plansLargeOrg), findsNothing);
      },
    );

    testWidgets(
      'F1-07-464 on iOS the GST buyer is sent to web checkout and there is no '
      'coupon field anywhere (08 §3.2 🔒, ADR 2026-09-05g §8 🔒)',
      (tester) async {
        final l10n = await AppLocalizations.delegate.load(const Locale('en'));
        await _pump(tester, channel: RkCheckoutChannel.inAppPurchase);

        expect(find.text(l10n.plansGstIos), findsOneWidget);
        expect(l10n.plansGstIos, contains('rukka.in'));
        expect(find.text(l10n.plansGstGateway), findsNothing);
        // No coupon field, and nothing else to type into either: Apple is
        // merchant of record on this platform.
        expect(find.byType(TextField), findsNothing);
        expect(find.byType(TextFormField), findsNothing);
        expect(find.byType(EditableText), findsNothing);

        // Off iOS the coupon/GSTIN line names the checkout that carries them.
        await _pump(tester, channel: RkCheckoutChannel.gateway);
        expect(find.text(l10n.plansGstGateway), findsOneWidget);
        expect(find.text(l10n.plansGstIos), findsNothing);
      },
    );

    testWidgets(
      'F1-07-465 S12.1 resolves in EN, PA and HI with nothing cut at 130 % or '
      '200 % on either phone',
      (tester) async {
        for (final locale in rkLocales) {
          final l10n = await AppLocalizations.delegate.load(locale);
          for (final viewport in rkPhones) {
            for (final scale in rkTextScales) {
              await _pump(
                tester,
                entitlement: _reading(
                  plan: RkPlan.familyPlus,
                  activeMembers: 40,
                ),
                locale: locale,
                viewport: viewport,
                textScale: scale,
              );
              expect(
                find.text(l10n.plansTitle),
                findsWidgets,
                reason: '${locale.languageCode} title missing',
              );
              expectTextFits(
                tester,
                reason:
                    '${locale.languageCode} @$scale on $viewport, '
                    'above the fold',
              );
              await tester.scrollUntilVisible(
                find.text(l10n.plansNeverLocked),
                400,
                scrollable: find.byType(Scrollable).first,
              );
              await tester.pumpAndSettle();
              expectTextFits(
                tester,
                reason:
                    '${locale.languageCode} @$scale on $viewport, '
                    'scrolled to the closing sentence',
              );
              expect(tester.takeException(), isNull);
            }
          }
        }
      },
    );
  });
}
