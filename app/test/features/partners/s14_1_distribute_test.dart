// F1-07-150…159: S14.1 the profit-distribution wizard (02 §7.1 🔒, 02 §7.2.1
// 🔒, ADR 2026-09-05e §8, ADR 2026-09-14b; 13 §3.2 row S14.1, 13 §4.3 states,
// 07 §1 rules).
//
// The screen is pumped over [FakeDistributionPort], never over `LocalLedger`:
// S14.1 reads the ledger through the port and the arithmetic is pinned
// separately, on the real facade, by F1-02-52…59. The figures here are the
// same Kaur Family year, so a UI assertion and an engine assertion speak about
// one book.
@Tags(['F1'])
library;

import 'package:core_ledger/core_ledger.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/partners/partners_port.dart';
import 'package:rukka_folio/features/partners/partners_routes.dart';
import 'package:rukka_folio/features/partners/screens/s14_1_distribute_screen.dart';
import 'package:rukka_folio/l10n/gen/app_localizations.dart';
import 'package:rukka_folio/shared/widgets/rk_connection_notice.dart';

import '../../shared/test_app.dart';
import 'fake_partners_port.dart';

const _book = 'kaur-farm';

Future<void> pumpS14_1(
  WidgetTester tester,
  FakeDistributionPort port, {
  Locale? locale,
  double textScale = 1,
  Size viewport = rkTallViewport,
}) async {
  // A clean tree every time. Pumping a second `MaterialApp` into the same slot
  // reuses the first one's `ScaffoldMessenger`, so a toast raised by the last
  // pump would still be covering this one's footer — which is exactly the kind
  // of ghost that makes a tap land on nothing.
  await tester.pumpWidget(const SizedBox.shrink());
  await pumpRk(
    tester,
    DistributeProfitScreen(bookId: _book, port: port),
    locale: locale,
    textScale: textScale,
    viewport: viewport,
  );
}

AppLocalizations stringsFor(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(Scaffold)));

/// Steps the wizard on [times] times through the footer's forward button.
Future<void> tapNext(WidgetTester tester, {int times = 1}) async {
  for (var i = 0; i < times; i++) {
    await tester.tap(find.byKey(DistributeKeys.next));
    await tester.pumpAndSettle();
  }
}

void main() {
  group('S14.1 the wizard (13 §3.2 row S14.1)', () {
    testWidgets('F1-07-150 every state of 13 §4.3: loading skeleton · error '
        'with retry · the three steps', (tester) async {
      // Loading — a preview that has not answered yet.
      final loading = FakeDistributionPort();
      await pumpS14_1(tester, loading);
      final l10n = stringsFor(tester);
      expect(find.bySemanticsLabel(l10n.distributeSkeleton), findsOneWidget);

      // Error, with the retry that really asks again.
      final broken = FakeDistributionPort(previewFails: true);
      await pumpS14_1(tester, broken);
      await tester.pumpAndSettle();
      expect(find.text(l10n.distributeError), findsOneWidget);
      broken
        ..previewFails = false
        ..preview = kaurDistribution();
      await tester.tap(find.text(l10n.distributeRetry));
      await tester.pumpAndSettle();
      expect(broken.previews, hasLength(2));

      // Step 1 — the period, defaulted to the open FY to date.
      expect(find.text(l10n.distributeStep(1, 3)), findsOneWidget);
      expect(find.text(l10n.distributeStep1Title), findsOneWidget);
      expect(find.text(l10n.distributePeriodYear('2026-27')), findsOneWidget);
      expect(find.byKey(DistributeKeys.from), findsOneWidget);
      expect(find.byKey(DistributeKeys.to), findsOneWidget);

      // Step 2 — the preview.
      await tapNext(tester);
      expect(find.text(l10n.distributeStep(2, 3)), findsOneWidget);
      expect(find.text(l10n.distributeStep2Title), findsOneWidget);

      // Step 3 — confirm, and *Back* reaches the preview again: no dead ends
      // (07 §1 rule 6).
      await tapNext(tester);
      expect(find.text(l10n.distributeStep3Title), findsOneWidget);
      await tester.tap(find.byKey(DistributeKeys.back));
      await tester.pumpAndSettle();
      expect(find.text(l10n.distributeStep2Title), findsOneWidget);
    });

    testWidgets('F1-07-151 step 2 shows both lines per owner, the totals, and '
        'the whole entry adding up exactly (02 §7.1 🔒)', (tester) async {
      // 8 % over the season, as 02 §7.1's worked illustration does: interest
      // first, then the remainder splits. Figures are the engine's.
      final port = FakeDistributionPort(
        preview: kaurDistribution(
          interest: true,
          interestPaise: const [
            Paise(4_296_00),
            Paise(2_311_00),
            Paise(1_354_52),
          ],
          shares: const [
            Paise(1_95_346_16),
            Paise(1_95_346_16),
            Paise(1_95_346_16),
          ],
          netProfit: const Paise(5_94_000_00),
        ),
      );
      await pumpS14_1(tester, port);
      await tester.pumpAndSettle();
      await tapNext(tester);
      final l10n = stringsFor(tester);

      // Both lines, for every owner (02 §7.1 🔒 *both lines per partner*).
      expect(find.text(l10n.distributeOwnerInterest), findsNWidgets(3));
      expect(find.text(l10n.distributeOwnerShare), findsNWidgets(3));
      expect(
        find.text(l10n.distributeOwnerTotal('Amrit Kaur')),
        findsOneWidget,
      );
      expect(find.text('₹4,296.00'), findsOneWidget);
      expect(find.text('₹1,354.52'), findsOneWidget, reason: 'to the paisa');

      // The totals, and the entry total: the two add to the year's figure
      // exactly, so the remainder is inside the owners' own numbers.
      expect(find.text(l10n.distributeTotalsInterest), findsOneWidget);
      expect(find.text(l10n.distributeTotalsShare), findsOneWidget);
      expect(find.text(l10n.distributeTotalsEntry), findsOneWidget);
      expect(find.text('₹5,94,000.00'), findsWidgets);
      // The ratio is whole-number weights, never a percentage (02 §7.1 🔒).
      expect(find.text(l10n.distributeRatio(1, 3)), findsNWidgets(3));
      expect(find.textContaining('%'), findsNothing);
    });

    testWidgets('F1-07-152 interest off is said, not left as a missing line '
        '(02 §7.1 🔒 — optional, off by default)', (tester) async {
      final port = FakeDistributionPort(preview: kaurDistribution());
      await pumpS14_1(tester, port);
      await tester.pumpAndSettle();
      await tapNext(tester);
      final l10n = stringsFor(tester);
      expect(find.text(l10n.distributeInterestOff), findsOneWidget);
      expect(find.text(l10n.distributeOwnerInterest), findsNothing);
      expect(find.text(l10n.distributeTotalsInterest), findsNothing);
      expect(find.text(l10n.distributeOwnerShare), findsNWidgets(3));
    });

    testWidgets('F1-07-153 a loss and interest-above-profit each get their '
        'plain sentence (ADR 2026-09-05e §8)', (tester) async {
      final loss = FakeDistributionPort(
        preview: kaurDistribution(
          netProfit: const Paise(-3_35_000_00),
          shares: const [
            Paise(-1_11_666_67),
            Paise(-1_11_666_67),
            Paise(-1_11_666_66),
          ],
        ),
      );
      await pumpS14_1(tester, loss);
      await tester.pumpAndSettle();
      await tapNext(tester);
      final l10n = stringsFor(tester);
      expect(find.text(l10n.distributeLoss('2026-27')), findsOneWidget);
      expect(find.text(l10n.distributeProfit('2026-27')), findsNothing);
      expect(find.text(l10n.distributeLossNote), findsOneWidget);

      // Interest above profit: still credited in full, the rest shared as a
      // loss, and the preview says so (02 §7.1 🔒).
      final above = FakeDistributionPort(
        preview: kaurDistribution(
          interest: true,
          netProfit: const Paise(5_000_00),
          interestPaise: const [
            Paise(4_000_00),
            Paise(3_000_00),
            Paise(1_000_00),
          ],
          shares: const [Paise(-1_000_00), Paise(-1_000_00), Paise(-1_000_00)],
        ),
      );
      await pumpS14_1(tester, above);
      await tester.pumpAndSettle();
      await tapNext(tester);
      expect(find.text(l10n.distributeInterestAbove), findsOneWidget);
    });

    testWidgets('F1-07-154 quorum of one distributes now; a shared book '
        'proposes and says it waits in the Inbox (02 §7.2.1 🔒)', (
      tester,
    ) async {
      final solo = FakeDistributionPort(
        preview: kaurDistribution(quorumOfOne: true),
      )..result = DistributionResult.posted;
      await pumpS14_1(tester, solo);
      await tester.pumpAndSettle();
      await tapNext(tester, times: 2);
      final l10n = stringsFor(tester);
      expect(find.text(l10n.distributeConfirmSolo), findsOneWidget);
      expect(find.text(l10n.distributeConfirmSoloNote), findsOneWidget);
      expect(find.text(l10n.distributeConfirmShared), findsNothing);
      await tester.tap(find.byKey(DistributeKeys.next));
      await tester.pumpAndSettle();
      expect(solo.distributions, hasLength(1));
      expect(solo.distributions.single.bookId, _book);
      expect(find.text(l10n.distributePosted), findsOneWidget);

      final shared = FakeDistributionPort(preview: kaurDistribution())
        ..result = DistributionResult.proposed;
      await pumpS14_1(tester, shared);
      await tester.pumpAndSettle();
      await tapNext(tester, times: 2);
      expect(find.text(l10n.distributeConfirmShared), findsOneWidget);
      expect(
        find.text(l10n.distributeConfirmSharedNote),
        findsOneWidget,
        reason:
            '02 §7.2.1 🔒 — nothing is applied early, and the screen '
            'says where it waits',
      );
      await tester.tap(find.byKey(DistributeKeys.next));
      await tester.pumpAndSettle();
      expect(find.text(l10n.distributeProposed), findsOneWidget);
    });

    testWidgets('F1-07-155 the ceiling refusal says by how much, and closes '
        'every way on (02 §7.1 🔒, ADR 2026-09-05e §8)', (tester) async {
      final port = FakeDistributionPort(
        preview: kaurDistribution(
          block: DistributionBlock.ceiling,
          excess: const Paise(2_00_000_00),
        ),
      );
      await pumpS14_1(tester, port);
      await tester.pumpAndSettle();
      final l10n = stringsFor(tester);
      expect(find.byKey(DistributeKeys.blocked), findsOneWidget);
      expect(
        find.text(l10n.distributeBlockCeiling('₹2,00,000.00')),
        findsOneWidget,
      );
      expect(find.text(l10n.distributeBlockCeilingHelp), findsOneWidget);
      // No forward action at all, and no stepper — but the app bar's back
      // button is still the way out (07 §1 rule 6).
      expect(find.byKey(DistributeKeys.next), findsNothing);
      expect(find.byType(AppBar), findsOneWidget);
    });

    testWidgets('F1-07-156 every other refusal of 13 §4.3 has its own words, '
        'and a single-owner business hears none of the three (ADR '
        '2026-09-09b 🔒)', (tester) async {
      Future<AppLocalizations> show(DistributionBlock block) async {
        await pumpS14_1(
          tester,
          FakeDistributionPort(preview: kaurDistribution(block: block)),
        );
        await tester.pumpAndSettle();
        return stringsFor(tester);
      }

      var l10n = await show(DistributionBlock.ratioNotRecorded);
      expect(find.text(l10n.distributeBlockRatioUnrecorded), findsOneWidget);
      // 02 §7.1 🔒: no number is shown and nothing is divided evenly.
      expect(find.text(l10n.distributeOwnerShare), findsNothing);

      l10n = await show(DistributionBlock.ratioIncomplete);
      expect(find.text(l10n.distributeBlockRatioIncomplete), findsOneWidget);

      l10n = await show(DistributionBlock.termsUnverified);
      expect(find.text(l10n.distributeBlockTerms), findsOneWidget);

      l10n = await show(DistributionBlock.nothingToDistribute);
      expect(find.text(l10n.distributeBlockNothing('2026-27')), findsOneWidget);

      l10n = await show(DistributionBlock.noPartners);
      expect(find.text(l10n.distributeBlockPartners), findsOneWidget);

      l10n = await show(DistributionBlock.noProfitDistributed);
      expect(find.text(l10n.distributeBlockAccount), findsOneWidget);

      // A *Just me* business: the app bar carries no title and the body says
      // none of *partner*, *share* or *distribute*.
      l10n = await show(DistributionBlock.notShared);
      expect(find.text(l10n.distributeBlockNotshared), findsOneWidget);
      expect(find.text(l10n.distributeTitle), findsNothing);
      expect(find.text(l10n.distributeOwnerShare), findsNothing);
    });

    testWidgets('F1-07-157 read-only keeps the figures and disables only the '
        'commit, with its reason; offline is a quiet notice (13 §5, 07 §1 '
        'rule 7)', (tester) async {
      final port = FakeDistributionPort(
        preview: kaurDistribution(readOnly: true, offline: true),
      );
      await pumpS14_1(tester, port);
      await tester.pumpAndSettle();
      final l10n = stringsFor(tester);
      expect(find.byType(RkConnectionNotice), findsOneWidget);
      await tapNext(tester, times: 2);
      expect(find.text(l10n.distributeReadonly), findsOneWidget);
      // The figures are still there; only writing stops.
      expect(find.text('Amrit Kaur'), findsOneWidget);
      final button = tester.widget<FilledButton>(
        find.byKey(DistributeKeys.next),
      );
      expect(button.onPressed, isNull);
      await tester.tap(find.byKey(DistributeKeys.next));
      await tester.pumpAndSettle();
      expect(port.distributions, isEmpty);
    });

    testWidgets('F1-07-158 a refused commit says the ledger is untouched and '
        're-reads rather than leaving stale figures (02 §5)', (tester) async {
      final port = FakeDistributionPort(preview: kaurDistribution())
        ..distributeThrows = const DistributionBlocked(
          DistributionBlock.ceiling,
          excess: Paise(1_00_00),
        );
      await pumpS14_1(tester, port);
      await tester.pumpAndSettle();
      await tapNext(tester, times: 2);
      final l10n = stringsFor(tester);
      await tester.tap(find.byKey(DistributeKeys.next));
      await tester.pumpAndSettle();
      expect(find.text(l10n.distributeFailed), findsOneWidget);
      expect(
        port.previews,
        hasLength(2),
        reason: 'the screen re-reads instead of trusting what it had',
      );
    });

    testWidgets('F1-07-159 every string resolves in EN, PA and HI, and the '
        'layout survives 200 % on a 360×800 phone (07 §1 rule 11)', (
      tester,
    ) async {
      for (final locale in const [Locale('en'), Locale('pa'), Locale('hi')]) {
        for (final step in [0, 1, 2]) {
          final port = FakeDistributionPort(
            preview: kaurDistribution(
              interest: true,
              interestPaise: const [
                Paise(4_296_00),
                Paise(2_311_00),
                Paise(1_354_52),
              ],
            ),
          );
          await pumpS14_1(
            tester,
            port,
            locale: locale,
            textScale: 2,
            viewport: rkPhone360,
          );
          await tester.pumpAndSettle();
          if (step > 0) await tapNext(tester, times: step);
          final l10n = stringsFor(tester);
          expect(
            l10n.distributeTitle.isNotEmpty,
            isTrue,
            reason: '${locale.languageCode}: the title resolves',
          );
          expect(tester.takeException(), isNull);
        }
      }
    });
  });
}
