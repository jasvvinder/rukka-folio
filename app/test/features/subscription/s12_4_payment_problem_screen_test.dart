// F1 widget tests for S12.4 Payment problem (13 §3.2 row S12.4, 07 §20 🔒,
// 08 §3 🔒 — the dunning grace is 7 days from period_end, DESIGN-PACK §11
// S12.4 🔒, ADR 2026-09-05g §4 🔒 — two graces, two copies).
@Tags(['F1'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/subscription/entitlement_source.dart';
import 'package:rukka_folio/features/subscription/screens/s12_4_payment_problem_screen.dart';
import 'package:rukka_folio/features/subscription/subscription_commands.dart';
import 'package:rukka_folio/features/subscription/subscription_copy.dart';
import 'package:rukka_folio/features/subscription/tier_catalogue.dart';
import 'package:rukka_folio/l10n/gen/app_localizations.dart';

import '../../shared/test_app.dart';

/// `period_end`, and the clock the screen is handed. 08 §3 🔒 gives 7 days of
/// grace, so this pair is three days in.
final _periodEnd = DateTime(2026, 9, 1, 10);
final _threeDaysLeft = DateTime(2026, 9, 5, 10);

Entitlement _reading({
  EntitlementGraceKind grace = EntitlementGraceKind.dunning,
  EntitlementSourceKind source = EntitlementSourceKind.fresh,
  DateTime? periodEnd,
}) => Entitlement(
  tenantId: 't1',
  plan: RkPlan.family,
  limits: rkTierFor(RkPlan.family).limits,
  periodEnd: periodEnd ?? _periodEnd,
  graceKind: grace,
  source: source,
  activeMembers: 3,
);

/// A fresh key per pump: Flutter reuses a [State] whenever type and position
/// match, and these tests pump more than one screen each.
int _pumps = 0;

Future<void> _pump(
  WidgetTester tester, {
  required SubscriptionCommands commands,
  Entitlement? entitlement,
  DateTime? now,
  Locale? locale,
  Size viewport = rkTallViewport,
  double textScale = 1,
}) => pumpRk(
  tester,
  PaymentProblemScreen(
    key: ValueKey(_pumps++),
    source: FakeEntitlementSource(entitlement: entitlement ?? _reading()),
    commands: commands,
    // 🔒 The clock is supplied, never read: no widget and no pure function in
    // this feature calls DateTime.now().
    now: () => now ?? _threeDaysLeft,
    onOpenPlans: () {},
  ),
  locale: locale,
  viewport: viewport,
  textScale: textScale,
);

/// Every string drawn in the tree, whatever widget drew it.
List<String> _texts(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.data)
    .whereType<String>()
    .toList();

void main() {
  group('S12.4 Payment problem', () {
    testWidgets(
      'F1-07-478 the countdown is whole days from the injected clock, 7 days '
      'from period_end (08 §3 🔒)',
      (tester) async {
        final l10n = await AppLocalizations.delegate.load(const Locale('en'));
        await _pump(tester, commands: FakeSubscriptionCommands());

        expect(find.text(l10n.paymentTitle), findsOneWidget);
        expect(find.text(l10n.paymentHeadline), findsOneWidget);
        expect(find.text(l10n.paymentDaysLeft(3)), findsOneWidget);
        // The day the grace ends, written out: 01 Sep + 7 days.
        expect(find.text('08 Sep 2026'), findsOneWidget);

        // Move the clock, and only the count moves.
        await _pump(
          tester,
          commands: FakeSubscriptionCommands(),
          now: DateTime(2026, 9, 7, 23),
        );
        expect(find.text(l10n.paymentDaysLeft(0)), findsOneWidget);
        expect(find.text(l10n.paymentDaysLeft(3)), findsNothing);
      },
    );

    testWidgets(
      'F1-07-479 it says what changes when the time is up — entry stops, '
      'reading, exporting and closing carry on (08 §1 🔒)',
      (tester) async {
        final l10n = await AppLocalizations.delegate.load(const Locale('en'));
        await _pump(tester, commands: FakeSubscriptionCommands());

        expect(find.text(l10n.paymentEndsLabel), findsOneWidget);
        expect(find.text(l10n.paymentEndsBody), findsOneWidget);
        expect(l10n.paymentEndsBody, contains('Reading, exporting'));
      },
    );

    testWidgets(
      'F1-07-480 Retry goes through the seam; a failure is an inline error '
      'with the same button, an unwired channel shuts it with the reason, and '
      'Change payment method is always disabled-with-reason (PLAN-11)',
      (tester) async {
        final l10n = await AppLocalizations.delegate.load(const Locale('en'));
        final commands = FakeSubscriptionCommands();
        await _pump(tester, commands: commands);

        // Change payment method: shut, and the reason is on screen with it.
        expect(find.text(l10n.paymentChangeMethodReason), findsOneWidget);
        final method = tester.widget<OutlinedButton>(
          find.widgetWithText(OutlinedButton, l10n.paymentChangeMethod),
        );
        expect(method.onPressed, isNull);

        await tester.tap(find.text(l10n.paymentRetry));
        await tester.pumpAndSettle();
        expect(commands.retries, 1);
        expect(find.text(l10n.paymentRetryDone), findsOneWidget);

        // A failure says so and leaves the button live.
        final failing = FakeSubscriptionCommands(
          retry: const RkCommandFailed(),
        );
        await _pump(tester, commands: failing);
        await tester.tap(find.text(l10n.paymentRetry));
        await tester.pumpAndSettle();
        expect(find.text(l10n.paymentRetryFailed), findsOneWidget);
        await tester.tap(find.text(l10n.paymentRetry));
        await tester.pumpAndSettle();
        expect(failing.retries, 2);

        // The shipped, unwired commands: shut, with the reason written.
        await _pump(tester, commands: const UnwiredSubscriptionCommands());
        await tester.tap(find.text(l10n.paymentRetry));
        await tester.pumpAndSettle();
        expect(find.text(l10n.paymentRetryUnavailable), findsOneWidget);
        expect(find.text(l10n.paymentRetryDone), findsNothing);
        final shut = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, l10n.paymentRetry),
        );
        expect(shut.onPressed, isNull);
      },
    );

    testWidgets(
      'F1-07-481 only the dunning state gets the countdown; every other state '
      'says there is nothing to fix and shows no days',
      (tester) async {
        final l10n = await AppLocalizations.delegate.load(const Locale('en'));
        for (final reading in [
          _reading(grace: EntitlementGraceKind.none),
          _reading(grace: EntitlementGraceKind.trial),
          _reading(grace: EntitlementGraceKind.lapsed),
          _reading(
            grace: EntitlementGraceKind.dunning,
            source: EntitlementSourceKind.stale,
          ),
          Entitlement.untokened(),
        ]) {
          await _pump(
            tester,
            commands: FakeSubscriptionCommands(),
            entitlement: reading,
          );
          expect(
            find.text(l10n.paymentNoneTitle),
            findsOneWidget,
            reason: 'state ${reading.state}',
          );
          expect(
            find.text(l10n.paymentDaysLeft(3)),
            findsNothing,
            reason: 'countdown leaked into ${reading.state}',
          );
          expect(
            find.text(l10n.paymentHeadline),
            findsNothing,
            reason: 'dunning headline leaked into ${reading.state}',
          );
          // The state is still said in words beside its icon (07 §1 rule 3).
          expect(find.text(reading.state.label(l10n)), findsOneWidget);
        }
      },
    );

    testWidgets(
      'F1-07-482 offline grace never meets the lapse words — a stale reading '
      'reads "Connect once to keep entering" (ADR 2026-09-05g §4 🔒)',
      (tester) async {
        final l10n = await AppLocalizations.delegate.load(const Locale('en'));
        await _pump(
          tester,
          commands: FakeSubscriptionCommands(),
          entitlement: _reading(
            grace: EntitlementGraceKind.lapsed,
            source: EntitlementSourceKind.stale,
          ),
        );

        expect(
          find.text(l10n.subscriptionBannerOfflineGraceTitle),
          findsOneWidget,
        );
        for (final drawn in _texts(tester)) {
          expect(
            drawn.toLowerCase(),
            isNot(contains('lapsed')),
            reason: 'offline grace must never say lapsed: "$drawn"',
          );
          expect(
            drawn.toLowerCase(),
            isNot(contains('plan has ended')),
            reason: 'offline grace must never say ended: "$drawn"',
          );
        }
      },
    );

    testWidgets(
      'F1-07-483 S12.4 resolves in EN, PA and HI with nothing cut at 130 % or '
      '200 % on either phone',
      (tester) async {
        for (final locale in rkLocales) {
          final l10n = await AppLocalizations.delegate.load(locale);
          for (final viewport in rkPhones) {
            for (final scale in rkTextScales) {
              await _pump(
                tester,
                commands: FakeSubscriptionCommands(),
                locale: locale,
                viewport: viewport,
                textScale: scale,
              );
              expect(
                find.text(l10n.paymentTitle),
                findsWidgets,
                reason: '${locale.languageCode} title missing',
              );
              expectTextFits(
                tester,
                reason:
                    '${locale.languageCode} @$scale on $viewport, '
                    'above the fold',
              );
              // The two actions sit below the fold at 200 %, and a paragraph
              // only overflows once it has been laid out.
              await tester.scrollUntilVisible(
                find.text(l10n.paymentChangeMethodReason),
                300,
                scrollable: find.byType(Scrollable).first,
              );
              await tester.pumpAndSettle();
              expectTextFits(
                tester,
                reason:
                    '${locale.languageCode} @$scale on $viewport, '
                    'below the fold',
              );
            }
          }
        }
      },
    );
  });
}
