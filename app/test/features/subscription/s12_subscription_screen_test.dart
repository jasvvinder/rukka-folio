// F1 widget tests for S12 Subscription (13 §3.2 row S12, 07 §20 🔒, 08 §1 🔒
// *lapsed ≠ locked*, ADR 2026-09-05g §4 🔒 two graces / two copies).
@Tags(['F1'])
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/subscription/entitlement_source.dart';
import 'package:rukka_folio/features/subscription/screens/s12_subscription_screen.dart';
import 'package:rukka_folio/features/subscription/tier_catalogue.dart';
import 'package:rukka_folio/l10n/gen/app_localizations.dart';
import 'package:rukka_folio/shared/widgets/rk_states.dart';

import '../../shared/test_app.dart';

Entitlement _reading({
  required EntitlementGraceKind grace,
  required EntitlementSourceKind source,
  RkPlan plan = RkPlan.family,
  int activeMembers = 3,
  DateTime? periodEnd,
}) => Entitlement(
  tenantId: 't1',
  plan: plan,
  limits: rkTierFor(plan).limits,
  periodEnd: periodEnd ?? DateTime(2026, 10, 1),
  graceKind: grace,
  source: source,
  activeMembers: activeMembers,
);

/// A source that never resolves until it is told to — the only way to see the
/// loading state, which a resolved future skips past.
class _HeldSource implements EntitlementSource {
  final _gate = Completer<Entitlement>();

  void give(Entitlement e) => _gate.complete(e);

  @override
  Future<Entitlement> read() => _gate.future;
}

/// Every string drawn in the tree, whatever widget drew it.
List<String> _texts(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.data)
    .whereType<String>()
    .toList();

void main() {
  group('S12 Subscription', () {
    testWidgets('F1-07-31 S12 renders the plan, the state and the renewal '
        'date (07 §20)', (tester) async {
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      await pumpRk(
        tester,
        SubscriptionScreen(
          source: FakeEntitlementSource(
            entitlement: _reading(
              grace: EntitlementGraceKind.none,
              source: EntitlementSourceKind.fresh,
            ),
          ),
        ),
        viewport: rkTallViewport,
      );

      expect(find.text(l10n.subscriptionTitle), findsOneWidget);
      expect(find.text(l10n.subscriptionPlanFamily), findsOneWidget);
      expect(find.text(l10n.subscriptionStateActive), findsOneWidget);
      expect(find.text(l10n.subscriptionRenewalLabel), findsOneWidget);
      expect(find.text('01 Oct 2026'), findsOneWidget);
      expect(find.text(l10n.subscriptionMembersValue(3, 5)), findsOneWidget);
    });

    testWidgets(
      'F1-07-454 loading draws the ruled skeleton and a failed read says the '
      'PLAN COULD NOT BE READ, never that it ended; retry reads again',
      (tester) async {
        final l10n = await AppLocalizations.delegate.load(const Locale('en'));
        final held = _HeldSource();
        await pumpRk(
          tester,
          SubscriptionScreen(source: held),
          viewport: rkTallViewport,
        );
        // Ruled rows and a spoken label — never a spinner (11 §4.5).
        expect(find.byType(RkSkeleton), findsOneWidget);
        expect(find.bySemanticsLabel(l10n.subscriptionLoading), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        held.give(Entitlement.untokened());
        await tester.pumpAndSettle();
        expect(find.byType(RkSkeleton), findsNothing);

        final failing = FakeEntitlementSource(failure: StateError('no store'));
        await pumpRk(
          tester,
          SubscriptionScreen(source: failing),
          viewport: rkTallViewport,
        );
        expect(find.text(l10n.subscriptionError), findsOneWidget);
        // A failed read is not a lapse.
        expect(find.text(l10n.subscriptionBannerReadOnlyTitle), findsNothing);
        expect(failing.reads, 1);
        failing.failure = null;
        failing.entitlement = Entitlement.untokened();
        await tester.tap(find.text(l10n.subscriptionActionRetry));
        await tester.pumpAndSettle();
        expect(failing.reads, 2);
        expect(find.text(l10n.subscriptionPlanFree), findsOneWidget);
      },
    );

    testWidgets(
      'F1-07-455 offline grace reads "Connect once to keep entering" and the '
      'lapse words never appear (07 §20 🔒, ADR 2026-09-05g §4 🔒)',
      (tester) async {
        final l10n = await AppLocalizations.delegate.load(const Locale('en'));
        // Even a token that SAID lapsed: a stale reading is offline grace.
        final fake = FakeEntitlementSource(
          entitlement: _reading(
            grace: EntitlementGraceKind.lapsed,
            source: EntitlementSourceKind.stale,
          ),
        );
        await pumpRk(
          tester,
          SubscriptionScreen(source: fake, onOpenPlans: () {}),
          viewport: rkTallViewport,
        );

        expect(
          find.text(l10n.subscriptionBannerOfflineGraceTitle),
          findsOneWidget,
        );
        expect(
          l10n.subscriptionBannerOfflineGraceTitle,
          'Connect once to keep entering',
        );
        expect(find.text(l10n.subscriptionBannerReadOnlyTitle), findsNothing);
        expect(find.text(l10n.subscriptionStateOfflineGrace), findsOneWidget);
        for (final drawn in _texts(tester)) {
          expect(
            drawn.toLowerCase(),
            isNot(contains('laps')),
            reason: 'offline grace must never say the plan lapsed: "$drawn"',
          );
          expect(
            drawn.toLowerCase(),
            isNot(contains('has ended')),
            reason: 'offline grace must not say the plan ended: "$drawn"',
          );
        }

        // Its one action is another try at the server, never an upgrade.
        expect(find.text(l10n.subscriptionActionRetry), findsOneWidget);
        expect(find.text(l10n.subscriptionActionRenew), findsNothing);
        await tester.tap(find.text(l10n.subscriptionActionRetry));
        await tester.pumpAndSettle();
        expect(fake.reads, 2);
      },
    );

    testWidgets(
      'F1-07-456 read-only names what still works and hides no figure '
      '(08 §1 🔒 lapsed ≠ locked)',
      (tester) async {
        final l10n = await AppLocalizations.delegate.load(const Locale('en'));
        var plans = 0;
        await pumpRk(
          tester,
          SubscriptionScreen(
            source: FakeEntitlementSource(
              entitlement: _reading(
                grace: EntitlementGraceKind.lapsed,
                source: EntitlementSourceKind.fresh,
              ),
            ),
            onOpenPlans: () => plans++,
          ),
          viewport: rkTallViewport,
        );

        expect(find.text(l10n.subscriptionBannerReadOnlyTitle), findsOneWidget);
        // What still works, said out loud.
        expect(find.text(l10n.subscriptionBannerReadOnlyBody), findsOneWidget);
        // …and every figure still on screen.
        expect(find.text(l10n.subscriptionPlanFamily), findsOneWidget);
        expect(find.text('01 Oct 2026'), findsOneWidget);
        expect(find.text(l10n.subscriptionMembersValue(3, 5)), findsOneWidget);

        await tester.tap(find.text(l10n.subscriptionActionRenew));
        await tester.pumpAndSettle();
        expect(plans, 1);
      },
    );

    testWidgets(
      'F1-07-457 the four screen doors are live — S12.1 Plans, S12.3 Manage, '
      'S12.4 Payment problem and S12.6 Invoices (13 §3.2)',
      (tester) async {
        final l10n = await AppLocalizations.delegate.load(const Locale('en'));
        var plans = 0;
        var manage = 0;
        var payment = 0;
        var invoices = 0;
        await pumpRk(
          tester,
          SubscriptionScreen(
            source: FakeEntitlementSource(
              entitlement: _reading(
                grace: EntitlementGraceKind.trial,
                source: EntitlementSourceKind.fresh,
              ),
            ),
            onOpenPlans: () => plans++,
            onOpenManage: () => manage++,
            onOpenPayment: () => payment++,
            onOpenInvoices: () => invoices++,
          ),
          viewport: rkTallViewport,
        );

        for (final door in [
          (l10n.subscriptionRowPlansTitle, () => plans),
          (l10n.subscriptionRowManageTitle, () => manage),
          (l10n.subscriptionRowPaymentTitle, () => payment),
          (l10n.subscriptionRowInvoicesTitle, () => invoices),
        ]) {
          await tester.tap(find.text(door.$1));
          await tester.pumpAndSettle();
          expect(door.$2(), 1, reason: 'door ${door.$1} did not open');
        }
        // Each live row carries its subtitle, so the door says where it goes.
        for (final subtitle in [
          l10n.subscriptionRowPlansSubtitle,
          l10n.subscriptionRowManageSubtitle,
          l10n.subscriptionRowPaymentSubtitle,
          l10n.subscriptionRowInvoicesSubtitle,
        ]) {
          expect(find.text(subtitle), findsOneWidget);
        }

        // Trial says what it is without a price nag.
        expect(find.text(l10n.subscriptionStateTrial), findsOneWidget);
        expect(find.text(l10n.subscriptionStateTrialBody), findsOneWidget);
      },
    );

    testWidgets(
      'F1-07-490 S12.5 stays a row, disabled-with-reason: it is the global '
      'banner and blocked-entry sheet, not a page to push (13 §3.2, '
      '07 §1 rule 6)',
      (tester) async {
        final l10n = await AppLocalizations.delegate.load(const Locale('en'));
        await pumpRk(
          tester,
          SubscriptionScreen(
            source: FakeEntitlementSource(
              entitlement: _reading(
                grace: EntitlementGraceKind.none,
                source: EntitlementSourceKind.fresh,
              ),
            ),
            onOpenPlans: () {},
            onOpenManage: () {},
            onOpenPayment: () {},
            onOpenInvoices: () {},
          ),
          viewport: rkTallViewport,
        );

        expect(find.text(l10n.subscriptionRowReadOnlyTitle), findsOneWidget);
        expect(find.text(l10n.subscriptionRowReadOnlyReason), findsOneWidget);
        // The promise is said even where the door is shut (08 §1 🔒).
        expect(l10n.subscriptionRowReadOnlyReason, contains('never blocked'));
      },
    );

    testWidgets(
      'F1-07-458 S12 resolves in EN, PA and HI with nothing cut at 130 % or '
      '200 % on either phone',
      (tester) async {
        for (final locale in rkLocales) {
          final l10n = await AppLocalizations.delegate.load(locale);
          for (final viewport in rkPhones) {
            for (final scale in rkTextScales) {
              await pumpRk(
                tester,
                SubscriptionScreen(
                  source: FakeEntitlementSource(
                    entitlement: _reading(
                      grace: EntitlementGraceKind.lapsed,
                      source: EntitlementSourceKind.fresh,
                    ),
                  ),
                  onOpenPlans: () {},
                ),
                locale: locale,
                viewport: viewport,
                textScale: scale,
              );
              expect(
                find.text(l10n.subscriptionTitle),
                findsWidgets,
                reason: '${locale.languageCode} title missing',
              );
              expectTextFits(
                tester,
                reason:
                    '${locale.languageCode} @$scale on $viewport, '
                    'above the fold',
              );
              // The later doors sit below the fold at 200 %, and a paragraph
              // only overflows once it has been laid out.
              await tester.scrollUntilVisible(
                find.text(l10n.subscriptionRowInvoicesTitle),
                300,
                scrollable: find.byType(Scrollable).first,
              );
              await tester.pumpAndSettle();
              expectTextFits(
                tester,
                reason:
                    '${locale.languageCode} @$scale on $viewport, '
                    'scrolled to the doors',
              );
              expect(tester.takeException(), isNull);
            }
          }
        }
      },
    );
  });
}
