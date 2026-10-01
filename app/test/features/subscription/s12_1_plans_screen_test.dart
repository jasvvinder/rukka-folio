// F1 widget tests for S12.1 Plans (13 §3.2 row S12.1, 08 §3.1 🔒 upgrade
// flow, 08 §3.2 / ADR 2026-09-05g §8 🔒 channels, ADR 2026-09-05g §14 🔒
// organisations above 15, DESIGN-PACK §11 S12.1 🔒).
//
// Since ADR 2026-09-25 §5–§6 🔒 every number on this screen is the server's
// catalogue's (M13-CAT2). These tests pump a **synthetic** catalogue through
// the [PlanCatalogueSource] seam and assert the screen shows *its* numbers —
// no figure below is 08 §2's, and none is 0018's either.
@Tags(['F1'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/subscription/entitlement_source.dart';
import 'package:rukka_folio/features/subscription/plan_catalogue_source.dart';
import 'package:rukka_folio/features/subscription/screens/s12_1_plans_screen.dart';
import 'package:rukka_folio/features/subscription/tier_catalogue.dart';
import 'package:rukka_folio/l10n/gen/app_localizations.dart';

import '../../shared/test_app.dart';

/// Tall enough that every card is built — a sliver below the fold has no
/// element, so `find` cannot see it.
const _tall = Size(420, 6000);

Map<String, Object?> _row(
  String id,
  String entity,
  int sort, {
  required int members,
  required int books,
  required int devices,
  required int bytes,
  required int yearly,
  required int monthly,
  bool popular = false,
  List<String> features = const [],
}) => {
  'id': id,
  'entity_type': entity,
  'name': 'console-only $id',
  'sort_order': sort,
  'limits': {
    'members': members,
    'business_books': books,
    'devices': devices,
    'envelopes_per_book': 1000,
    'tenant_bytes': bytes,
    'attachment_bytes': bytes,
  },
  'features': features,
  'price_yearly_paise': yearly,
  'price_monthly_paise': monthly,
  'popular': popular,
  'placeholder': true,
};

/// A synthetic catalogue: two Individual plans and three Family plans, with
/// numbers no document uses, so a screen that still read a hard-coded table
/// would fail here.
final _catalogue = RkPlanCatalogue.fromJson({
  'plans': [
    _row(
      'free',
      'individual',
      1,
      members: 1,
      books: 0,
      devices: 2,
      bytes: 70 * 1024 * 1024,
      yearly: 0,
      monthly: 0,
    ),
    _row(
      'personal',
      'individual',
      2,
      members: 1,
      books: 2,
      devices: 3,
      bytes: 1 << 30,
      yearly: 77700,
      monthly: 7770,
      features: ['pdf_output', 'statement_import'],
    ),
    _row(
      'family_lite',
      'family',
      1,
      members: 3,
      books: 1,
      devices: 4,
      bytes: 3 << 30,
      yearly: 111100,
      monthly: 11110,
    ),
    _row(
      'family',
      'family',
      2,
      members: 9,
      books: 6,
      devices: 7,
      bytes: 6 << 30,
      yearly: 222200,
      monthly: 22220,
      popular: true,
      features: ['pdf_output', 'statement_import'],
    ),
    _row(
      'family_plus',
      'family',
      3,
      members: 25,
      books: -1,
      devices: 11,
      bytes: 11 << 30,
      yearly: 444400,
      monthly: 44440,
      features: ['pdf_output', 'statement_import'],
    ),
  ],
});

RkTier _t(RkPlan p) => _catalogue.tierFor(p)!;

Entitlement _reading({RkPlan plan = RkPlan.family, int activeMembers = 3}) =>
    Entitlement(
      tenantId: 't1',
      plan: plan,
      limits: rkTierFor(RkPlan.family).limits,
      periodEnd: DateTime(2026, 10, 1),
      graceKind: EntitlementGraceKind.none,
      source: EntitlementSourceKind.fresh,
      activeMembers: activeMembers,
    );

Future<void> _pump(
  WidgetTester tester, {
  Entitlement? entitlement,
  RkCheckoutChannel channel = RkCheckoutChannel.gateway,
  RkPlanCatalogue? catalogue,
  PlanCatalogueSource? source,
  Locale? locale,
  Size viewport = _tall,
  double textScale = 1,
}) => pumpRk(
  tester,
  PlansScreen(
    source: FakeEntitlementSource(entitlement: entitlement ?? _reading()),
    channel: channel,
    catalogue:
        source ?? FakePlanCatalogueSource(catalogue: catalogue ?? _catalogue),
  ),
  locale: locale,
  viewport: viewport,
  textScale: textScale,
);

/// A catalogue holding only [plans].
RkPlanCatalogue _only(List<RkPlan> plans) =>
    RkPlanCatalogue(plans: [for (final p in plans) _t(p)]);

void main() {
  group('S12.1 Plans', () {
    testWidgets(
      'F1-07-459 every catalogue plan of the tenant\'s entity type is a card, '
      'with the catalogue\'s quotas and extras in plain words (ADR 2026-09-25 '
      '§5–§6)',
      (tester) async {
        final l10n = await AppLocalizations.delegate.load(const Locale('en'));
        await _pump(tester);

        expect(find.text(l10n.plansTitle), findsOneWidget);
        // A Family tenant sees the three Family plans, and no Individual one
        // (⚠️ SPEC: entity type read off the current plan's row).
        for (final name in [
          l10n.subscriptionPlanFamilyLite,
          l10n.subscriptionPlanFamily,
          l10n.subscriptionPlanFamilyPlus,
        ]) {
          expect(find.text(name), findsOneWidget, reason: 'card $name');
        }
        expect(find.text(l10n.subscriptionPlanFree), findsNothing);
        expect(find.text(l10n.subscriptionPlanPersonal), findsNothing);
        // The catalogue's name column is never drawn (CLAUDE.md rule 8).
        expect(find.textContaining('console-only'), findsNothing);

        // Every card's quotas, as the catalogue gives them.
        for (final p in [RkPlan.familyLite, RkPlan.family]) {
          final l = _t(p).limits;
          expect(find.text(l10n.plansLimitMembers(l.members!)), findsOneWidget);
          expect(
            find.text(l10n.plansLimitBooks(l.businessBooks!)),
            findsOneWidget,
          );
          expect(find.text(l10n.plansLimitDevices(l.devices!)), findsOneWidget);
          final gb = rkStorageOf(l.tenantBytes!);
          expect(gb.gigabytes, isTrue);
          expect(
            find.text(l10n.plansLimitStorageGb(gb.amount)),
            findsOneWidget,
          );
        }
        // Unlimited (-1 on the wire) is words, never a large number.
        expect(find.text(l10n.plansLimitBooksUnlimited), findsOneWidget);
        // The two extras, said both ways: Lite holds neither.
        expect(find.text(l10n.plansFeaturePdfNone), findsOneWidget);
        expect(find.text(l10n.plansFeatureImportNone), findsOneWidget);
        expect(find.text(l10n.plansFeaturePdfIncluded), findsNWidgets(2));
        expect(find.text(l10n.plansFeatureImportIncluded), findsNWidgets(2));

        // DESIGN-PACK §11 (S12.1) 🔒 closes the screen with this sentence.
        expect(find.text(l10n.plansNeverLocked), findsOneWidget);
      },
    );

    testWidgets(
      'F1-07-460 the current plan is marked and the popular badge is the '
      'catalogue\'s flag (08 §3.1 🔒, ADR 2026-09-25 §5)',
      (tester) async {
        final l10n = await AppLocalizations.delegate.load(const Locale('en'));
        await _pump(tester, entitlement: _reading(plan: RkPlan.familyLite));
        expect(find.text(l10n.plansCurrent), findsOneWidget);
        expect(find.text(l10n.plansPopular), findsOneWidget);

        // Individual has no popular plan in this catalogue, so no badge.
        await _pump(tester, entitlement: _reading(plan: RkPlan.personal));
        expect(find.text(l10n.subscriptionPlanPersonal), findsOneWidget);
        expect(find.text(l10n.plansCurrent), findsOneWidget);
        expect(find.text(l10n.plansPopular), findsNothing);

        // The badge moves with the flag: the same card, flag off → no badge.
        final unflagged = RkPlanCatalogue.fromJson({
          'plans': [
            {..._t(RkPlan.family).toJson(), 'popular': false},
          ],
        });
        await _pump(tester, catalogue: unflagged);
        expect(find.text(l10n.plansCurrent), findsOneWidget);
        expect(find.text(l10n.plansPopular), findsNothing);
      },
    );

    testWidgets(
      'F1-07-461 the Monthly/Annual toggle shows the saving and swaps the '
      'prices, all from integer paise (08 §3.1 🔒, CLAUDE.md rule 1)',
      (tester) async {
        final l10n = await AppLocalizations.delegate.load(const Locale('en'));
        await _pump(tester, catalogue: _only([RkPlan.family]));
        final family = _t(RkPlan.family);
        // 12 × 22220 = 266640 against 222200 → 16.66…% → truncated to 16.
        expect(family.annualSavingPercent, 16);

        // Annual is the default (08 §2 principle 2: monthly is the fallback).
        expect(find.text(l10n.plansCycleSaving(16)), findsOneWidget);
        expect(find.text(l10n.plansPriceYear('₹2,222')), findsOneWidget);
        expect(find.text(l10n.plansPriceMonth('₹222.20')), findsNothing);

        await tester.tap(find.text(l10n.plansCycleMonthly));
        await tester.pumpAndSettle();
        // A price with paise shows them — dropping them would understate it.
        expect(find.text(l10n.plansPriceMonth('₹222.20')), findsOneWidget);
        expect(find.text(l10n.plansPriceYear('₹2,222')), findsNothing);
        // The saving stays on screen on both sides of the toggle.
        expect(find.text(l10n.plansCycleSaving(16)), findsOneWidget);

        // Free is free on either side, and never a price of ₹0.
        await _pump(
          tester,
          entitlement: _reading(plan: RkPlan.free),
          catalogue: _only([RkPlan.free]),
        );
        expect(find.text(l10n.plansPriceFree), findsOneWidget);
      },
    );

    testWidgets(
      'F1-07-462 checkout and add-on seats are shut with a reason, never a '
      'silent tap (07 §1 rule 6; S12.2 needs the IAP package)',
      (tester) async {
        final l10n = await AppLocalizations.delegate.load(const Locale('en'));
        await _pump(tester, catalogue: _only([RkPlan.family]));

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

    testWidgets(
      'F1-25-12 a catalogue that cannot be read is the error state with a '
      'retry that reads again — never a hard-coded table',
      (tester) async {
        final l10n = await AppLocalizations.delegate.load(const Locale('en'));
        final source = FakePlanCatalogueSource(
          catalogue: _catalogue,
          failure: const PlanCatalogueFailure(PlanCatalogueRefusal.offline),
        );
        await _pump(tester, source: source);
        expect(find.text(l10n.subscriptionError), findsOneWidget);
        expect(find.text(l10n.subscriptionPlanFamily), findsNothing);

        source.failure = null;
        await tester.tap(find.text(l10n.subscriptionActionRetry));
        await tester.pumpAndSettle();
        expect(source.reads, 2);
        expect(find.text(l10n.subscriptionPlanFamily), findsOneWidget);
      },
    );

    testWidgets(
      'F1-25-12 a plan id this build has no words for is drawn under generic '
      'words, and a tenant on it sees every plan (CLAUDE.md rule 6; ADR '
      '2026-09-25 §5 nothing is hidden)',
      (tester) async {
        final l10n = await AppLocalizations.delegate.load(const Locale('en'));
        final grown = RkPlanCatalogue.fromJson({
          'plans': [
            ..._catalogue.toJson()['plans']! as List,
            {
              ..._t(RkPlan.family).toJson(),
              'id': 'kirana_max',
              'entity_type': 'cooperative',
              'popular': false,
              'brand_new_field': {'x': 1},
            },
          ],
        });
        await _pump(
          tester,
          entitlement: _reading(plan: const RkPlan('kirana_max')),
          catalogue: grown,
        );
        expect(tester.takeException(), isNull);
        expect(find.text(l10n.subscriptionPlanOther), findsOneWidget);
        expect(find.text(l10n.plansCurrent), findsOneWidget);
        // Its type is the catalogue's own; this reading's plan has a row, so
        // only that type's plans are drawn.
        expect(find.text(l10n.subscriptionPlanFamily), findsNothing);

        // A reading whose plan is in no row at all sees every plan.
        await _pump(
          tester,
          entitlement: _reading(plan: const RkPlan('retired_plan')),
          catalogue: grown,
        );
        for (final name in [
          l10n.subscriptionPlanFree,
          l10n.subscriptionPlanPersonal,
          l10n.subscriptionPlanFamilyLite,
          l10n.subscriptionPlanFamily,
          l10n.subscriptionPlanFamilyPlus,
          l10n.subscriptionPlanOther,
        ]) {
          expect(find.text(name), findsOneWidget, reason: name);
        }
        expect(find.text(l10n.plansCurrent), findsNothing);
      },
    );
  });
}
