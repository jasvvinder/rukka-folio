// F1-24b-5 — the client half of ADR 2026-09-24b §6 🔒: the entitlement token
// carries `grace_until` (null unless `grace_kind = dunning`), and the client
// reads the server's date and **never derives `period_end + 7 d`**.
//
// Test-honesty: (a) is built so the +7 d derivation it replaces gives a
// different answer — `grace_until` is `period_end + 3 d`, so the old code
// would say 6 days and 08 Sep where the server declared 2 days and 04 Sep.
@Tags(['F1'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/subscription/dunning_grace.dart';
import 'package:rukka_folio/features/subscription/entitlement_source.dart';
import 'package:rukka_folio/features/subscription/screens/s12_3_manage_screen.dart';
import 'package:rukka_folio/features/subscription/screens/s12_4_payment_problem_screen.dart';
import 'package:rukka_folio/features/subscription/screens/s12_subscription_screen.dart';
import 'package:rukka_folio/features/subscription/subscription_commands.dart';
import 'package:rukka_folio/features/subscription/tier_catalogue.dart';
import 'package:rukka_folio/l10n/gen/app_localizations.dart';

import '../../shared/test_app.dart';

final _periodEnd = DateTime(2026, 9, 1, 10);

/// The server's date — deliberately **not** `period_end + 7 d`.
final _graceUntil = DateTime(2026, 9, 4, 10);

/// One day into the grace: the server's date leaves 2 days, +7 d would say 6.
final _oneDayIn = DateTime(2026, 9, 2, 10);

Entitlement _reading({
  EntitlementGraceKind grace = EntitlementGraceKind.dunning,
  EntitlementSourceKind source = EntitlementSourceKind.fresh,
  DateTime? graceUntil,
  bool noGraceUntil = false,
}) => Entitlement(
  tenantId: 't1',
  plan: RkPlan.family,
  limits: rkTierFor(RkPlan.family).limits,
  periodEnd: _periodEnd,
  graceKind: grace,
  graceUntil: noGraceUntil ? null : (graceUntil ?? _graceUntil),
  source: source,
  activeMembers: 3,
);

int _pumps = 0;

Future<void> _pump(WidgetTester tester, Entitlement entitlement) => pumpRk(
  tester,
  PaymentProblemScreen(
    key: ValueKey(_pumps++),
    source: FakeEntitlementSource(entitlement: entitlement),
    commands: FakeSubscriptionCommands(),
    now: () => _oneDayIn,
    onOpenPlans: () {},
  ),
  viewport: rkTallViewport,
);

/// Every string drawn in the tree, and every semantics label, whatever drew
/// it — "anywhere on S12.4" includes what a screen reader hears.
List<String> _everything(WidgetTester tester) => [
  ...tester
      .widgetList<Text>(find.byType(Text))
      .map((t) => t.data)
      .whereType<String>(),
  ...tester
      .widgetList<Semantics>(find.byType(Semantics))
      .map((s) => s.properties.label)
      .whereType<String>(),
];

/// Any decimal digit in any script — a day count or a date needs one.
final _digit = RegExp(r'\p{Nd}', unicode: true);

/// A token payload as the server mints it (`_shared/sodium.ts`), including
/// M11-CAT1's `features` after `limits` and a field no client knows yet.
Map<String, Object?> _payload({
  bool withGraceUntil = true,
  Object? graceUntil,
}) => {
  'tenant_id': 't1',
  'plan': 'family',
  'limits': {'members': 5, 'business_books': 3},
  'features': ['statement_import'],
  'period_end': _periodEnd.toUtc().millisecondsSinceEpoch,
  'grace_kind': 'dunning',
  if (withGraceUntil) 'grace_until': graceUntil,
  'iat': 1790000000000,
  'exp': 1790086400000,
  'a_field_from_the_future': {'nested': true},
};

/// A `period_end` instant whose UTC calendar day is **not** this machine's
/// local day — 23:45Z east of UTC, 00:15Z west of it (every real offset is at
/// least 30 min). In a UTC zone the two days coincide and (f) cannot tell the
/// fix from the bug; it is run under `TZ=Asia/Kolkata` and
/// `TZ=America/New_York` to discriminate.
DateTime _nearMidnightUtc() {
  final offset = DateTime.utc(2026, 9, 30, 12).toLocal().timeZoneOffset;
  return offset.isNegative
      ? DateTime.utc(2026, 9, 30, 0, 15)
      : DateTime.utc(2026, 9, 30, 23, 45);
}

/// `dd Mon yyyy` in English for a September/October [day] — computed here,
/// not by the production formatter.
String _enDate(DateTime day) =>
    '${day.day.toString().padLeft(2, '0')} '
    '${day.month == 10 ? 'Oct' : 'Sep'} ${day.year}';

/// The producer's path: wire payload -> [EntitlementTokenTimes] ->
/// [Entitlement.fromToken].
Entitlement _fromWire(
  Map<String, Object?> payload, {
  EntitlementGraceKind grace = EntitlementGraceKind.dunning,
  EntitlementSourceKind source = EntitlementSourceKind.fresh,
}) => Entitlement.fromToken(
  tenantId: 't1',
  plan: RkPlan.family,
  limits: rkTierFor(RkPlan.family).limits,
  graceKind: grace,
  times: EntitlementTokenTimes.fromPayload(payload),
  source: source,
  activeMembers: 3,
);

void main() {
  group(
    'F1-24b-5 the dunning date is the server\'s (ADR 2026-09-24b §6 🔒)',
    () {
      testWidgets(
        'F1-24b-5 (a) the countdown and the end date come from grace_until, '
        'not period_end + 7 d',
        (tester) async {
          final l10n = await AppLocalizations.delegate.load(const Locale('en'));
          await _pump(tester, _reading());

          expect(find.text(l10n.paymentDaysLeft(2)), findsOneWidget);
          expect(find.text('04 Sep 2026'), findsOneWidget);
          // The derivation ADR 24b §6 forbids would have drawn these.
          expect(find.text(l10n.paymentDaysLeft(6)), findsNothing);
          expect(find.text('08 Sep 2026'), findsNothing);
        },
      );

      test('F1-24b-5 (a) the pure helper counts to the date it is handed', () {
        expect(rkDunningDaysLeft(graceUntil: _graceUntil, now: _oneDayIn), 2);
        expect(rkDunningDaysLeft(graceUntil: _graceUntil, now: _periodEnd), 3);
      });

      testWidgets(
        'F1-24b-5 (b) dunning with a null grace_until shows no number and no '
        'date anywhere, and still offers the fix path (desk 46)',
        (tester) async {
          final l10n = await AppLocalizations.delegate.load(const Locale('en'));
          final reading = _reading(noGraceUntil: true);
          expect(reading.state, EntitlementState.dunningGrace);
          await _pump(tester, reading);

          for (final drawn in _everything(tester)) {
            expect(
              drawn,
              isNot(contains(_digit)),
              reason: 'a number or a date was invented: "$drawn"',
            );
          }
          for (var days = 0; days <= 10; days++) {
            expect(find.text(l10n.paymentDaysLeft(days)), findsNothing);
          }

          // The payment problem and its fix path are still there.
          expect(find.text(l10n.paymentHeadline), findsOneWidget);
          expect(find.text(l10n.paymentEndsBody), findsOneWidget);
          final retry = tester.widget<FilledButton>(
            find.widgetWithText(FilledButton, l10n.paymentRetry),
          );
          expect(retry.onPressed, isNotNull);
          expect(find.text(l10n.paymentChangeMethod), findsOneWidget);
          expect(find.text(l10n.paymentChangeMethodReason), findsOneWidget);
          expect(find.text(l10n.paymentNoneTitle), findsNothing);
        },
      );

      test('F1-24b-5 (c) an absent grace_until parses to null and does not '
          'throw; unknown fields are tolerated', () {
        late EntitlementTokenTimes absent;
        expect(
          () => absent = EntitlementTokenTimes.fromPayload(
            _payload(withGraceUntil: false),
          ),
          returnsNormally,
        );
        expect(absent.graceUntil, isNull);
        expect(absent.periodEnd, _periodEnd.toUtc());

        expect(
          EntitlementTokenTimes.fromPayload(_payload()).graceUntil,
          isNull,
        );

        final present = EntitlementTokenTimes.fromPayload(
          _payload(graceUntil: _graceUntil.toUtc().millisecondsSinceEpoch),
        );
        expect(present.graceUntil, _graceUntil.toUtc());
        expect(present.graceUntil!.isUtc, isTrue);

        // A wrong type is a malformed token, not a missing date.
        expect(
          () => EntitlementTokenTimes.fromPayload(
            _payload(graceUntil: '2026-09-04'),
          ),
          throwsFormatException,
        );
      });

      testWidgets(
        'F1-24b-5 (d) outside dunning grace_until is ignored — no countdown, '
        'no date',
        (tester) async {
          final l10n = await AppLocalizations.delegate.load(const Locale('en'));
          for (final reading in [
            _reading(grace: EntitlementGraceKind.none),
            _reading(grace: EntitlementGraceKind.trial),
            _reading(grace: EntitlementGraceKind.lapsed),
            // Stale is offline grace whatever the token said (ADR 05g §4 🔒).
            _reading(source: EntitlementSourceKind.stale),
          ]) {
            expect(
              reading.dunningGraceUntil,
              isNull,
              reason: '${reading.graceKind}/${reading.source}',
            );
            await _pump(tester, reading);
            expect(find.text(l10n.paymentNoneTitle), findsOneWidget);
            expect(find.text('04 Sep 2026'), findsNothing);
            for (var days = 0; days <= 10; days++) {
              expect(find.text(l10n.paymentDaysLeft(days)), findsNothing);
            }
          }
          expect(_reading().dunningGraceUntil, _graceUntil);
        },
      );
      testWidgets(
        'F1-24b-5 (e) wire to screen: the parsed grace_until reaches the '
        'reading and S12.4 draws the server\'s date',
        (tester) async {
          final l10n = await AppLocalizations.delegate.load(const Locale('en'));
          final reading = _fromWire(
            _payload(graceUntil: _graceUntil.toUtc().millisecondsSinceEpoch),
          );
          expect(reading.periodEnd, _periodEnd.toUtc());
          expect(reading.graceUntil, _graceUntil.toUtc());
          expect(reading.dunningGraceUntil, _graceUntil.toUtc());

          await _pump(tester, reading);
          expect(find.text(l10n.paymentDaysLeft(2)), findsOneWidget);
          expect(find.text(_enDate(_graceUntil)), findsOneWidget);
          expect(find.text('08 Sep 2026'), findsNothing);

          // An absent grace_until on the wire is desk 46's no-date case.
          final noDate = _fromWire(_payload(withGraceUntil: false));
          expect(noDate.state, EntitlementState.dunningGrace);
          expect(noDate.dunningGraceUntil, isNull);

          // A token reading is fresh or stale; absent is untokened.
          expect(
            () => _fromWire(_payload(), source: EntitlementSourceKind.absent),
            throwsArgumentError,
          );
        },
      );

      testWidgets(
        'F1-24b-5 (f) S12 and S12.3 show the token\'s UTC period_end on the '
        'device-local day',
        (tester) async {
          final instant = _nearMidnightUtc();
          final local = instant.toLocal();
          final reading = _fromWire(
            _payload()..['period_end'] = instant.millisecondsSinceEpoch,
            grace: EntitlementGraceKind.none,
          );
          expect(reading.periodEnd, instant);
          expect(reading.periodEnd!.isUtc, isTrue);
          final zoned = local.timeZoneOffset != Duration.zero;

          for (final screen in <Widget>[
            SubscriptionScreen(
              key: ValueKey(_pumps++),
              source: FakeEntitlementSource(entitlement: reading),
            ),
            ManageSubscriptionScreen(
              key: ValueKey(_pumps++),
              source: FakeEntitlementSource(entitlement: reading),
              commands: FakeSubscriptionCommands(),
              channel: RkCheckoutChannel.gateway,
            ),
          ]) {
            await pumpRk(tester, screen, viewport: rkTallViewport);
            expect(
              find.text(_enDate(local)),
              findsOneWidget,
              reason: '${screen.runtimeType}',
            );
            if (zoned) {
              expect(
                find.text(_enDate(instant)),
                findsNothing,
                reason: '${screen.runtimeType} drew the UTC day',
              );
            }
          }
        },
      );
    },
  );
}
