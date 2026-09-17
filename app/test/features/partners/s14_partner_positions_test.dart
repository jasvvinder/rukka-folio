// F1-07-110…114 + F1-07-37: S14 Partner positions and the S14.2 drift &
// settlement card (02 §7.1 🔒, 07 §27 🔒, 13 §3.2 rows S14 / S14.2).
//
// The screen is pumped over [FakePartnersPort], never over `LocalLedger`: S14
// reads the ledger through `PartnersPort` and the implementation lands next
// lane. The figures are the Kaur Family worked example the engine's own
// A-02-62…67 already pin, so the UI and the engine talk about one book.
@Tags(['F1'])
library;

import 'package:core_ledger/core_ledger.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/partners/partners_routes.dart';
import 'package:rukka_folio/features/partners/screens/s14_partner_positions_screen.dart';
import 'package:rukka_folio/features/partners/widgets/drift_settlement_card.dart';
import 'package:rukka_folio/l10n/gen/app_localizations.dart';
import 'package:rukka_folio/shared/widgets/rk_connection_notice.dart';

import '../../shared/test_app.dart';
import 'fake_partners_port.dart';

const _book = 'kaur-farm';

Future<void> pumpS14(
  WidgetTester tester,
  FakePartnersPort port, {
  Locale? locale,
  double textScale = 1,
  Size viewport = rkTallViewport,
}) => pumpRk(
  tester,
  PartnerPositionsScreen(bookId: _book, port: port),
  locale: locale,
  textScale: textScale,
  // Tall by default: S14 is a list of cards and a widget test's 800×600
  // window would leave the third owner unbuilt, so an assertion about "every
  // owner" would silently mean "the first one". The 200 % test overrides it
  // with the real 360×800 phone, which is where layout is judged.
  viewport: viewport,
);

AppLocalizations stringsFor(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(Scaffold)));

void main() {
  group('S14 partner positions (02 §7.1 🔒, 13 §3.2 row S14)', () {
    testWidgets(
      'F1-07-110 every state of 13 §4.3: loading skeleton · error with retry · '
      'empty · populated',
      (tester) async {
        // Loading — a stream that has not spoken yet.
        final loading = FakePartnersPort();
        await pumpS14(tester, loading);
        expect(find.byType(ListView), findsOneWidget);
        expect(find.byType(PartnerPositionsScreen), findsOneWidget);

        // Error, with the retry that actually re-subscribes.
        final broken = FakePartnersPort(error: true);
        await pumpS14(tester, broken);
        final l10n = stringsFor(tester);
        expect(find.text(l10n.partnersError), findsOneWidget);
        expect(find.text(l10n.partnersRetry), findsOneWidget);
        broken
          ..error = false
          ..view = kaurView();
        await tester.tap(find.text(l10n.partnersRetry));
        await tester.pumpAndSettle();
        expect(broken.watchCount, 2);
        expect(find.text('Amrit Kaur'), findsOneWidget);

        // Empty — a shared book whose partner accounts are not seeded yet.
        final empty = FakePartnersPort(
          view: const PartnersView(
            ownership: BookOwnership.shared,
            positions: [],
            canSettleAll: true,
            shortBy: Paise.zero,
            moneyTotal: Paise.zero,
            partnerCreditTotal: Paise.zero,
            drift: [],
            sources: [],
          ),
        );
        await pumpS14(tester, empty);
        expect(find.text(l10n.partnersEmptyTitle), findsOneWidget);
        expect(find.text(l10n.partnersEmptyBody), findsOneWidget);

        // Populated.
        await pumpS14(tester, FakePartnersPort(view: kaurView()));
        expect(find.text('Amrit Kaur'), findsOneWidget);
        expect(find.text('Sukhdev Singh'), findsOneWidget);
        expect(find.text('Harjit Kaur'), findsOneWidget);
        expect(find.byType(RkConnectionNotice), findsNothing);

        // Offline — 07 §1 rule 7: quiet and non-blocking, the figures stay.
        await pumpS14(tester, FakePartnersPort(view: kaurView(offline: true)));
        expect(find.byType(RkConnectionNotice), findsOneWidget);
        expect(find.text('Amrit Kaur'), findsOneWidget);
        expect(find.text(l10n.partnersCapacityCan), findsOneWidget);
      },
    );

    testWidgets(
      'F1-07-111 put in · took out · share · net per owner, in consumer words '
      'only — and a debit balance stated as plainly as a credit one',
      (tester) async {
        final port = FakePartnersPort(view: kaurView(harjitInDebit: true));
        await pumpS14(tester, port);
        final l10n = stringsFor(tester);

        expect(find.text(l10n.partnersPositionPutin), findsNWidgets(3));
        expect(find.text(l10n.partnersPositionTookout), findsNWidgets(3));
        expect(find.text(l10n.partnersPositionShare), findsNWidgets(3));

        // Amrit: put in ₹2,40,000, took out ₹1,10,000, share ₹1,98,000.
        expect(find.text('₹2,40,000'), findsOneWidget);
        expect(find.text('₹1,10,000'), findsOneWidget);
        expect(find.text('₹1,98,000'), findsNWidgets(3));

        // The credit case and the debit case, both in words (02 §7.1 🔒
        // *Debit balances are real and must be shown*).
        expect(
          find.text(l10n.partnersPositionNetOwed('Amrit Kaur')),
          findsOneWidget,
        );
        expect(
          find.text(l10n.partnersPositionNetOwes('Harjit Kaur')),
          findsOneWidget,
        );
        expect(find.text('₹1,42,000'), findsOneWidget);

        // 02 §10 🔒 / CLAUDE.md rule 9: this is a consumer surface. No Dr, no
        // Cr, anywhere on it — the posting underneath is unchanged.
        for (final w in tester.widgetList<Text>(find.byType(Text))) {
          final text = w.data ?? '';
          expect(
            RegExp(r'\b(Dr|Cr)\b').hasMatch(text),
            isFalse,
            reason: 'professional vocabulary leaked onto S14: "$text"',
          );
        }

        // 🔒 The payer never books an expense in their own book — said in the
        // user's own words on the screen that shows the claim.
        expect(find.text(l10n.partnersNotePayer), findsOneWidget);
      },
    );

    testWidgets(
      'F1-07-112 settlement capacity is stated in words, with the figures '
      'beneath — both branches (02 §7.1 🔒, A-02-65)',
      (tester) async {
        await pumpS14(tester, FakePartnersPort(view: kaurView()));
        final l10n = stringsFor(tester);
        expect(find.text(l10n.partnersCapacityCan), findsOneWidget);
        expect(
          find.text(l10n.partnersCapacityFigures('₹9,29,000', '₹8,79,000')),
          findsOneWidget,
        );

        final short = kaurView();
        final shortView = PartnersView(
          ownership: short.ownership,
          positions: short.positions,
          canSettleAll: false,
          shortBy: rs(50000),
          moneyTotal: rs(829000),
          partnerCreditTotal: rs(879000),
          drift: short.drift,
          sources: short.sources,
          driftMargin: short.driftMargin,
        );
        await pumpS14(tester, FakePartnersPort(view: shortView));
        expect(
          find.text(l10n.partnersCapacityShort('₹50,000')),
          findsOneWidget,
        );
        expect(
          find.text(l10n.partnersCapacityFigures('₹8,29,000', '₹8,79,000')),
          findsOneWidget,
        );
        expect(find.text(l10n.partnersCapacityCan), findsNothing);
      },
    );

    testWidgets('F1-07-113 EN, ਪੰਜਾਬੀ and हिन्दी all fit at 200 % on 360×800', (
      tester,
    ) async {
      for (final locale in const [Locale('en'), Locale('pa'), Locale('hi')]) {
        await pumpS14(
          tester,
          FakePartnersPort(view: kaurView()),
          locale: locale,
          textScale: 2,
          viewport: rkPhone360,
        );
        expectTextFits(
          tester,
          reason: 'S14 at 200 % in ${locale.languageCode}',
        );
        // The drift card and its three doors are on the same screen.
        expect(find.byType(DriftSettlementCard), findsOneWidget);
        expect(find.byType(OutlinedButton), findsNWidgets(3));
      }
    });

    testWidgets(
      'F1-07-114 a Just-me book is told nothing about partners, ratios or '
      'distribution (ADR 2026-09-09b 🔒); an absent ratio map says *not '
      'recorded*, never equal shares (02 §7.1 🔒)',
      (tester) async {
        await pumpS14(
          tester,
          FakePartnersPort(
            view: kaurView(ownership: BookOwnership.justMe, soleOwner: true),
          ),
        );
        final l10n = stringsFor(tester);
        expect(find.text(l10n.partnersSoloTitle), findsOneWidget);
        expect(find.text(l10n.partnersSoloBody), findsOneWidget);
        // Not one partner figure, not one door, not one ratio.
        expect(find.text('Amrit Kaur'), findsNothing);
        expect(find.byType(DriftSettlementCard), findsNothing);
        expect(find.text(l10n.partnersRatioLabel), findsNothing);
        expect(find.text(l10n.partnersPositionPutin), findsNothing);
        for (final w in tester.widgetList<Text>(find.byType(Text))) {
          final text = (w.data ?? '').toLowerCase();
          for (final word in const ['partner', 'ratio', 'share', 'profit']) {
            expect(
              text.contains(word),
              isFalse,
              reason:
                  'ADR 2026-09-09b 🔒: a Just-me business never mentions '
                  '"$word" — found in "$text"',
            );
          }
        }

        // Shared book, no `partner_shares` recorded: the screen says so and
        // divides nothing evenly.
        await pumpS14(tester, FakePartnersPort(view: kaurView(ratios: false)));
        expect(
          find.textContaining(l10n.partnersRatioUnrecorded),
          findsNWidgets(3),
        );
        expect(find.text(l10n.partnersRatioUnrecordedHelp), findsNWidgets(3));
        expect(
          find.textContaining(l10n.partnersRatioWeight(1, 3)),
          findsNothing,
        );

        // Recorded weights are whole numbers, never percentages.
        await pumpS14(tester, FakePartnersPort(view: kaurView()));
        expect(
          find.textContaining(l10n.partnersRatioWeight(1, 3)),
          findsNWidgets(3),
        );
      },
    );

    testWidgets('F1-07-110 the route carries the book id', (tester) async {
      expect(PartnersPaths.of(_book), '/books/$_book/partners');
      expect(partnersRoutes, hasLength(1));
    });
  });

  group('S14.2 drift & settlement card (07 §27 🔒, 02 §7.1 🔒)', () {
    testWidgets(
      'F1-07-37 quiet card above the margin, never a demand, with three doors '
      '— pay out and partner-to-partner post through the port in integer '
      'paise, carry forward is disabled with its reason',
      (tester) async {
        final port = FakePartnersPort(view: kaurView());
        await pumpS14(tester, port);
        final l10n = stringsFor(tester);

        // Informational, never a demand (02 §7.1 🔒 *Drift visibility*).
        expect(
          find.text(l10n.partnersDriftTitle('Amrit Kaur', '₹35,000')),
          findsOneWidget,
        );
        expect(find.text(l10n.partnersDriftBody), findsOneWidget);

        // Three doors, in 07 §27's order.
        expect(find.text(l10n.partnersDriftDoorPayout), findsOneWidget);
        expect(find.text(l10n.partnersDriftDoorP2p), findsOneWidget);
        expect(find.text(l10n.partnersDriftDoorCarry), findsOneWidget);

        // Carry forward is the default and the year-close ceremony performs
        // it: disabled-with-reason, not a dead tap (13 §4.3, 07 §1 rule 6).
        expect(find.text(l10n.partnersDriftDoorCarryDisabled), findsOneWidget);
        final carry = tester.widget<OutlinedButton>(
          find.ancestor(
            of: find.text(l10n.partnersDriftDoorCarry),
            matching: find.byType(OutlinedButton),
          ),
        );
        expect(carry.onPressed, isNull);

        // Door 1 posts `Dr Partner Current · Cr {money a/c}` — in this
        // feature's own sheet, never by routing into the entry flow.
        await tester.tap(find.text(l10n.partnersDriftDoorPayout));
        await tester.pumpAndSettle();
        // The door label and the sheet title are deliberately the same
        // words, so the sheet is identified by its own line.
        expect(
          find.text(l10n.partnersSheetPayoutBody('Amrit Kaur')),
          findsOneWidget,
        );
        await tester.enterText(find.byType(TextField), '35,000');
        await tester.tap(find.text(l10n.partnersSheetSave));
        await tester.pumpAndSettle();
        expect(port.payOuts, hasLength(1));
        expect(port.payOuts.single.bookId, _book);
        expect(port.payOuts.single.partnerAccountId, 'amrit');
        expect(port.payOuts.single.fromAccountId, 'bank');
        expect(port.payOuts.single.amount.raw, 3500000);
        expect(find.text(l10n.partnersSaved), findsOneWidget);

        // Door 2 posts `Dr {over-funded} · Cr {under-funded}`.
        await tester.tap(find.text(l10n.partnersDriftDoorP2p));
        await tester.pumpAndSettle();
        expect(
          find.text(l10n.partnersSheetP2pBody('Amrit Kaur')),
          findsOneWidget,
        );
        await tester.tap(find.text('Harjit Kaur').last);
        await tester.enterText(find.byType(TextField), '20000');
        await tester.tap(find.text(l10n.partnersSheetSave));
        await tester.pumpAndSettle();
        expect(port.settlements, hasLength(1));
        expect(port.settlements.single.fromPartnerAccountId, 'amrit');
        expect(port.settlements.single.toPartnerAccountId, 'harjit');
        expect(port.settlements.single.amount.raw, 2000000);
      },
    );

    testWidgets(
      'F1-07-37 no margin configured means no card at all — the app never '
      'invents a threshold (02 §7.1 ⚠️ the margin has no stated default)',
      (tester) async {
        await pumpS14(tester, FakePartnersPort(view: kaurView(drift: false)));
        expect(find.byType(DriftSettlementCard), findsNothing);
      },
    );

    testWidgets(
      'F1-07-37 every closed door says why: no cash, no second owner, '
      'read-only (13 §4.3, 07 §1 rule 6)',
      (tester) async {
        // No money account with anything in it → route 1 cannot run.
        await pumpS14(tester, FakePartnersPort(view: kaurView(cash: false)));
        final l10n = stringsFor(tester);
        expect(find.text(l10n.partnersDriftDoorPayoutDisabled), findsOneWidget);
        expect(
          tester
              .widget<OutlinedButton>(
                find.ancestor(
                  of: find.text(l10n.partnersDriftDoorPayout),
                  matching: find.byType(OutlinedButton),
                ),
              )
              .onPressed,
          isNull,
        );

        // Only one owner in the book → route 2 has nobody to settle with.
        await pumpS14(
          tester,
          FakePartnersPort(view: kaurView(soleOwner: true)),
        );
        expect(find.text(l10n.partnersDriftDoorP2pDisabled), findsOneWidget);

        // Read-only tenant (13 §5, S12.5): figures stay, posting stops.
        await pumpS14(tester, FakePartnersPort(view: kaurView(readOnly: true)));
        expect(find.text(l10n.partnersDoorsReadonly), findsNWidgets(2));
        expect(find.text(l10n.partnersCapacityCan), findsOneWidget);
      },
    );

    testWidgets(
      'F1-07-37 a refused posting says so and leaves the ledger untouched',
      (tester) async {
        final port = FakePartnersPort(view: kaurView(), throwOnPost: true);
        await pumpS14(tester, port);
        final l10n = stringsFor(tester);
        await tester.tap(find.text(l10n.partnersDriftDoorPayout));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), '1000');
        await tester.tap(find.text(l10n.partnersSheetSave));
        await tester.pumpAndSettle();
        expect(find.text(l10n.partnersSheetError), findsOneWidget);
        expect(port.payOuts, isEmpty);
        expect(find.text(l10n.partnersSaved), findsNothing);
      },
    );

    testWidgets('F1-07-37 a settlement may never exceed the claim it settles', (
      tester,
    ) async {
      final port = FakePartnersPort(view: kaurView());
      await pumpS14(tester, port);
      final l10n = stringsFor(tester);
      await tester.tap(find.text(l10n.partnersDriftDoorPayout));
      await tester.pumpAndSettle();
      // Amrit's claim is ₹3,28,000.
      await tester.enterText(find.byType(TextField), '400000');
      await tester.tap(find.text(l10n.partnersSheetSave));
      await tester.pumpAndSettle();
      expect(
        find.text(l10n.partnersSheetAmountMax('Amrit Kaur', '₹3,28,000')),
        findsOneWidget,
      );
      expect(port.payOuts, isEmpty);
    });
  });
}
