// F1 widget tests for S12.3 Manage subscription (13 §3.2 row S12.3, 07 §20 🔒,
// DESIGN-PACK §11 S12.3 🔒, 08 §1 principle 4 🔒, ADR 2026-09-05g §8 🔒).
@Tags(['F1'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/subscription/entitlement_source.dart';
import 'package:rukka_folio/features/subscription/screens/s12_3_manage_screen.dart';
import 'package:rukka_folio/features/subscription/subscription_commands.dart';
import 'package:rukka_folio/features/subscription/tier_catalogue.dart';
import 'package:rukka_folio/l10n/gen/app_localizations.dart';

import '../../shared/test_app.dart';

Entitlement _reading({
  RkPlan plan = RkPlan.family,
  EntitlementGraceKind grace = EntitlementGraceKind.none,
  EntitlementSourceKind source = EntitlementSourceKind.fresh,
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

/// Every pump gets a fresh key. Flutter reuses a [State] whenever type and
/// position match, so without this a second pump in one test would inherit the
/// first screen's open confirmation.
int _pumps = 0;

Future<void> _pump(
  WidgetTester tester, {
  required SubscriptionCommands commands,
  RkCheckoutChannel channel = RkCheckoutChannel.gateway,
  Entitlement? entitlement,
  VoidCallback? onOpenPlans,
  Locale? locale,
  Size viewport = rkTallViewport,
  double textScale = 1,
}) => pumpRk(
  tester,
  ManageSubscriptionScreen(
    key: ValueKey(_pumps++),
    source: FakeEntitlementSource(entitlement: entitlement ?? _reading()),
    commands: commands,
    channel: channel,
    onOpenPlans: onOpenPlans,
  ),
  locale: locale,
  viewport: viewport,
  textScale: textScale,
);

void main() {
  group('S12.3 Manage subscription', () {
    testWidgets(
      'F1-07-472 shows the plan, the renewal date and what is included '
      '(DESIGN-PACK §11 S12.3 🔒)',
      (tester) async {
        final l10n = await AppLocalizations.delegate.load(const Locale('en'));
        await _pump(tester, commands: FakeSubscriptionCommands());

        expect(find.text(l10n.manageTitle), findsOneWidget);
        expect(find.text(l10n.subscriptionPlanFamily), findsOneWidget);
        expect(find.text(l10n.subscriptionRenewalLabel), findsOneWidget);
        expect(find.text('01 Oct 2026'), findsOneWidget);
        expect(find.text(l10n.subscriptionMembersValue(3, 5)), findsOneWidget);

        // "What is included" — the tier catalogue's quota lines, not numbers
        // typed into the screen.
        final family = rkTierFor(RkPlan.family);
        expect(find.text(l10n.manageIncludedLabel), findsOneWidget);
        expect(
          find.text(l10n.plansLimitMembers(family.limits.members!)),
          findsOneWidget,
        );
        expect(
          find.text(l10n.plansLimitBooks(family.limits.businessBooks!)),
          findsOneWidget,
        );
        expect(find.text(l10n.plansLimitExportsClean), findsOneWidget);
      },
    );

    testWidgets('F1-07-473 Change plan opens S12.1 Plans', (tester) async {
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      var plans = 0;
      await _pump(
        tester,
        commands: FakeSubscriptionCommands(),
        onOpenPlans: () => plans++,
      );

      await tester.tap(find.text(l10n.manageChangePlan));
      await tester.pumpAndSettle();
      expect(plans, 1);
    });

    testWidgets(
      'F1-07-474 Cancel states what continues to work afterwards, issues '
      'cancelAtPeriodEnd through the seam off Apple platforms, and the '
      'scheduled date hides no figure (08 §1 🔒)',
      (tester) async {
        final l10n = await AppLocalizations.delegate.load(const Locale('en'));
        final commands = FakeSubscriptionCommands(
          cancel: RkCommandDone(effectiveOn: DateTime(2026, 10, 1)),
        );
        await _pump(tester, commands: commands);

        // 🔒 The 08 §1 sentence is on screen BEFORE anything is confirmed.
        expect(find.text(l10n.manageCancelWhatContinues), findsOneWidget);
        expect(commands.cancels, 0);

        await tester.tap(find.text(l10n.manageCancel));
        await tester.pumpAndSettle();
        expect(find.text(l10n.manageCancelConfirmTitle), findsOneWidget);
        expect(find.text(l10n.manageCancelConfirmBody), findsOneWidget);
        // A way back out of the confirmation (07 §1 rule 6).
        expect(find.text(l10n.manageCancelConfirmKeep), findsOneWidget);

        await tester.tap(find.text(l10n.manageCancelConfirmAction));
        await tester.pumpAndSettle();
        expect(commands.cancels, 1);

        // The screen reflects cancel_at_period_end …
        expect(
          find.text(l10n.manageCancelledTitle('01 Oct 2026')),
          findsOneWidget,
        );
        expect(find.text(l10n.manageCancelledBody), findsOneWidget);
        // … without hiding a figure: plan, renewal date and members stay.
        expect(find.text(l10n.subscriptionPlanFamily), findsOneWidget);
        expect(find.text('01 Oct 2026'), findsWidgets);
        expect(find.text(l10n.subscriptionMembersValue(3, 5)), findsOneWidget);
      },
    );

    testWidgets(
      'F1-07-475 on iOS the confirm is disabled-with-reason naming Apple’s '
      'subscription settings and the seam is never asked (ADR 2026-09-05g §8 🔒)',
      (tester) async {
        final l10n = await AppLocalizations.delegate.load(const Locale('en'));
        final commands = FakeSubscriptionCommands();
        await _pump(
          tester,
          commands: commands,
          channel: RkCheckoutChannel.inAppPurchase,
        );

        await tester.tap(find.text(l10n.manageCancel));
        await tester.pumpAndSettle();

        // The reason names the place — there is no URL launcher (PLAN-11).
        expect(find.text(l10n.manageCancelIosReason), findsOneWidget);
        expect(l10n.manageCancelIosReason, contains('Subscriptions'));

        final confirm = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, l10n.manageCancelConfirmAction),
        );
        expect(confirm.onPressed, isNull, reason: 'iOS confirm must be shut');

        await tester.tap(
          find.text(l10n.manageCancelConfirmAction),
          warnIfMissed: false,
        );
        await tester.pumpAndSettle();
        expect(commands.cancels, 0, reason: 'iOS must never cancel for Apple');
      },
    );

    testWidgets(
      'F1-07-476 a failed cancel is an inline error with the same button to '
      'press again, and an unwired channel shuts it with the reason '
      '(08 §3.1 🔒 — never a dead end)',
      (tester) async {
        final l10n = await AppLocalizations.delegate.load(const Locale('en'));
        final failing = FakeSubscriptionCommands(
          cancel: const RkCommandFailed(),
        );
        await _pump(tester, commands: failing);
        await tester.tap(find.text(l10n.manageCancel));
        await tester.pumpAndSettle();
        await tester.tap(find.text(l10n.manageCancelConfirmAction));
        await tester.pumpAndSettle();

        expect(failing.cancels, 1);
        expect(find.text(l10n.manageCancelFailed), findsOneWidget);
        // Nothing claims a cancellation happened.
        expect(find.text(l10n.manageCancelledBody), findsNothing);
        // The same button is live for another try.
        final again = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, l10n.manageCancelConfirmAction),
        );
        expect(again.onPressed, isNotNull);
        await tester.tap(find.text(l10n.manageCancelConfirmAction));
        await tester.pumpAndSettle();
        expect(failing.cancels, 2);

        // The shipped, unwired commands: shut, with the reason written.
        await _pump(tester, commands: const UnwiredSubscriptionCommands());
        await tester.tap(find.text(l10n.manageCancel));
        await tester.pumpAndSettle();
        await tester.tap(find.text(l10n.manageCancelConfirmAction));
        await tester.pumpAndSettle();
        expect(find.text(l10n.manageCancelUnavailable), findsOneWidget);
        expect(find.text(l10n.manageCancelledBody), findsNothing);
        final shut = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, l10n.manageCancelConfirmAction),
        );
        expect(shut.onPressed, isNull);
      },
    );

    testWidgets(
      'F1-07-477 S12.3 resolves in EN, PA and HI with nothing cut at 130 % or '
      '200 % on either phone',
      (tester) async {
        for (final locale in rkLocales) {
          final l10n = await AppLocalizations.delegate.load(locale);
          for (final viewport in rkPhones) {
            for (final scale in rkTextScales) {
              await _pump(
                tester,
                commands: FakeSubscriptionCommands(),
                channel: RkCheckoutChannel.inAppPurchase,
                locale: locale,
                viewport: viewport,
                textScale: scale,
                onOpenPlans: () {},
              );
              expect(
                find.text(l10n.manageTitle),
                findsWidgets,
                reason: '${locale.languageCode} title missing',
              );
              expectTextFits(
                tester,
                reason: '${locale.languageCode} @$scale on $viewport',
              );
              // The confirmation — the longest block on the screen — must fit
              // too, and the iOS reason is the longest sentence in it.
              await tester.scrollUntilVisible(
                find.text(l10n.manageCancel),
                300,
                scrollable: find.byType(Scrollable).first,
              );
              await tester.pumpAndSettle();
              await tester.tap(find.text(l10n.manageCancel));
              await tester.pumpAndSettle();
              expectTextFits(
                tester,
                reason:
                    '${locale.languageCode} @$scale on $viewport, '
                    'cancel confirmation',
              );
            }
          }
        }
      },
    );
  });
}
