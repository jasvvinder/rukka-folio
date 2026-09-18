// F1-07-190…196, F1-07-198, F1-07-199: S10.4 the Year Close ceremony
// (02 §8.1 🔒, 07 §13 last bullet 🔒, 13 §3.2 row S10.4, 13 §6 🔒,
// ADR 2026-09-05c §3 🔒, ADR 2026-09-05e §2, ADR 2026-09-09 §4 🔒).
//
// The screen is pumped over the feature-local [FakeYearCloseSource], which
// refuses a close **exactly when the checklist holds a blocker** —
// `yearClosePreconditions`' contract stated once (02 §8.1 🔒, ADR 2026-09-05e
// §4). A blocker carries `core_ledger`'s own [CloseBlocker], so what "blocks"
// means here is the engine's word and not a stub's.
//
// This is a state-machine screen (13 §4.3), so the rules that are easy to
// break silently are asserted **structurally** rather than by copy:
//
//   * the blocks-versus-warns split (F1-07-190) asserts that no blocking item
//     is ever drawn inside the warning list or the other way about;
//   * *unverified-by-you* (F1-07-193) asserts the **absence** of every
//     mismatch word, because ADR 2026-09-05c §3 🔒's whole point is that the
//     third outcome is never dressed as the second;
//   * resumability (F1-07-195) re-pumps a **new** [State] and reads the
//     ceremony back out of the ledger, because S10.4 holds nothing;
//   * the switcher (F1-07-192) is asserted absent before the first close and
//     present after it, which is ADR 2026-09-09 §4 🔒's *no switcher at all
//     until the first year close*.
//
// Every amount is synthetic (CLAUDE.md rule 4) and integer paise (rule 1).
@Tags(['F1'])
library;

import 'package:core_ledger/core_ledger.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:rukka_folio/features/close/close_routes.dart';
import 'package:rukka_folio/features/close/widgets/close_blocked_panel.dart';
import 'package:rukka_folio/features/close/widgets/close_parts.dart';
import 'package:rukka_folio/features/ledger/widgets/fy_switcher.dart';
import 'package:rukka_folio/features/partners/partners_paths.dart';
import 'package:rukka_folio/l10n/gen/app_localizations.dart';
import 'package:rukka_folio/l10n/l10n.dart';
import 'package:rukka_folio/shared/format/date_format.dart';
import 'package:rukka_folio/shared/theme.dart';
import 'package:rukka_folio/shared/widgets/rk_banner.dart';
import 'package:rukka_folio/shared/widgets/rk_states.dart';

import '../../shared/test_app.dart';

// ---- fixtures ---------------------------------------------------------------

/// FY 2026-27, the April-start year of 02 §8.1's own example.
final fy2627 = FinancialYear(2026);

/// The same book on a calendar year — a trust. 02 §8.1 speaks of 31 March
/// because that is the common case, not the only one.
final fy2026Calendar = FinancialYear(2026, startMonth: 1);

/// A balanced closing vector: money and equity carried, the year's result as
/// the one net line ADR 2026-09-05e §2 requires in place of category accounts.
YearCloseVector balancedVector() => YearCloseVector(
  vector: BalanceVector({
    'galla': const Paise(250000),
    'sbi': const Paise(11460000),
    'capital': const Paise(-1000000),
    netResultKey(fy2627): const Paise(-10710000),
  }),
  names: const {
    'galla': 'Galla',
    'sbi': 'SBI Saving',
    'capital': 'Opening Balance / Capital A/c',
  },
);

/// The same vector with the result line missing — it no longer adds up, so it
/// is not certifiable (02 §8).
YearCloseVector unbalancedVector() => YearCloseVector(
  vector: BalanceVector({
    'galla': const Paise(250000),
    'capital': const Paise(-1000000),
  }),
  names: const {'galla': 'Galla', 'capital': 'Opening Balance / Capital A/c'},
);

/// Nothing to carry forward — the honest empty card, never blank white.
YearCloseVector emptyVector() =>
    YearCloseVector(vector: BalanceVector(const {}));

YearCloseBlocker monthOpen([String ref = '2027-03']) =>
    YearCloseBlocker.of(CloseBlocker.monthOpen, ref);

YearCloseBlocker reviewFlag() => YearCloseBlocker.of(
  CloseBlocker.reviewFlagOpen,
  'entry-1',
  label: 'Diesel · 24 Aug',
);

YearCloseBlocker advancePending() =>
    YearCloseBlocker.of(CloseBlocker.advancePending, 'adv-2', label: 'Sunita');

YearCloseBlocker suspense() =>
    YearCloseBlocker.of(CloseBlocker.suspenseNonZero, 'suspense');

YearCloseBlocker gapFromPankaj() => YearCloseBlocker.of(
  CloseBlocker.authorGapOpen,
  'device-2',
  deviceName: 'Pankaj’s phone',
);

const agedAdvance = CloseWarningItem(
  kind: CloseWarning.agedAdvance,
  ref: 'adv-1',
  label: 'Sunita',
);

/// A [YearCloseView] over the fixtures above. [vector] defaults to the
/// balanced one; pass `noVector: true` for a book with no figures at all.
YearCloseView yview({
  YearStatus status = YearStatus.open,
  List<YearCloseBlocker> blockers = const [],
  List<CloseWarningItem> warnings = const [],
  YearCloseVector? vector,
  bool noVector = false,
  bool isBusiness = false,
  bool distributionPending = false,
  YearCloseVector? certifiedVector,
  CloseVerification? verification,
  YearMonth? voidedBy,
  bool readOnly = false,
  FinancialYear? financialYear,
}) => YearCloseView(
  bookId: 'book-1',
  bookName: 'Kirana',
  financialYear: financialYear ?? fy2627,
  status: status,
  blockers: blockers,
  warnings: warnings,
  vector: noVector ? null : (vector ?? balancedVector()),
  isBusiness: isBusiness,
  distributionPending: distributionPending,
  certifiedVector: certifiedVector,
  verification: verification,
  voidedBy: voidedBy,
  readOnly: readOnly,
);

/// Distinguishes one pump from the next, so re-pumping builds a **new**
/// [State] rather than reusing the one on screen — which is what *leaving and
/// coming back* means, and the only way F1-07-195 can prove resumability.
int _pumpSeq = 0;

/// Pumps S10.4 over [source], recording every path it asks to open.
Future<List<String>> pumpYear(
  WidgetTester tester,
  YearCloseSource? source, {
  Locale? locale,
  double textScale = 1,
  Size viewport = rkTallViewport,
  bool offline = false,
  FinancialYear? financialYear,
  bool withDone = true,
}) async {
  final opened = <String>[];
  await pumpRk(
    tester,
    YearCloseScreen(
      key: ValueKey('year-pump-${_pumpSeq++}'),
      bookId: 'book-1',
      financialYear: financialYear ?? fy2627,
      source: source,
      offline: offline,
      onOpen: opened.add,
      onDone: withDone ? () {} : null,
    ),
    locale: locale,
    textScale: textScale,
    viewport: viewport,
  );
  return opened;
}

AppLocalizations stringsOf(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(YearCloseScreen)));

/// *Mar 2027* — the locale's own month words, never a name this test minted
/// (07 §1 rule 5 🔒).
String monthLabel(AppLocalizations l, YearMonth m) =>
    '${monthName(l, m.month)} ${m.year}';

Finder inBlocks(Finder f) =>
    find.descendant(of: find.byKey(YearCloseKeys.blocks), matching: f);

Finder inWarns(Finder f) =>
    find.descendant(of: find.byKey(YearCloseKeys.warns), matching: f);

void main() {
  // ── F1-07-190 · the preconditions checklist (02 §8.1 🔒) ──────────────────

  testWidgets(
    'F1-07-190 S10.4 states what blocks and what only warns as two lists, and '
    'each blocker names its month or its queue',
    (tester) async {
      final source = FakeYearCloseSource(
        view: yview(
          blockers: [monthOpen(), reviewFlag(), advancePending(), suspense()],
          warnings: const [agedAdvance],
        ),
      );
      await pumpYear(tester, source);
      final l = stringsOf(tester);

      // Two lists, never one (07 §13 🔒) — and they say which is which.
      expect(find.byKey(YearCloseKeys.blocks), findsOneWidget);
      expect(find.byKey(YearCloseKeys.warns), findsOneWidget);
      expect(find.text(l.closeYearBlocksTitle), findsOneWidget);
      expect(find.text(l.closeYearWarnsTitle), findsOneWidget);
      expect(find.text(l.closeYearChecklistReady('2026-27')), findsNothing);

      // A month names *itself*: "Mar 2027 is still open" tells the closer
      // where to go, "a month is open" does not (07 §1 rule 6).
      expect(
        inBlocks(
          find.text(
            l.closeYearBlockerMonthOpen(monthLabel(l, YearMonth(2027, 3))),
          ),
        ),
        findsOneWidget,
      );
      expect(
        inBlocks(find.text(l.closeYearBlockerMonthOpenHelp)),
        findsOneWidget,
      );

      // The two queues 02 §8.1 🔒 keeps apart are named apart.
      expect(inBlocks(find.text(l.closeYearBlockerReviewFlag)), findsOneWidget);
      expect(
        inBlocks(
          find.text('${l.closeYearBlockerReviewFlagQueue} · Diesel · 24 Aug'),
        ),
        findsOneWidget,
      );
      expect(
        inBlocks(find.text(l.closeYearBlockerAdvancePending)),
        findsOneWidget,
      );
      expect(
        inBlocks(
          find.text('${l.closeYearBlockerAdvancePendingQueue} · Sunita'),
        ),
        findsOneWidget,
      );
      expect(inBlocks(find.text(l.closeYearBlockerSuspense)), findsOneWidget);

      // Structural: nothing that blocks is drawn in the warn list, and the
      // aged advance — warn-only at the year boundary — never in the block
      // list (02 §8.1 🔒).
      expect(inWarns(find.text(l.closeWarningAgedAdvance)), findsOneWidget);
      expect(inBlocks(find.text(l.closeWarningAgedAdvance)), findsNothing);
      for (final blocked in [
        l.closeYearBlockerSuspense,
        l.closeYearBlockerReviewFlag,
        l.closeYearBlockerAdvancePending,
      ]) {
        expect(inWarns(find.text(blocked)), findsNothing);
      }

      // The action is off, says how many things are in the way, and offers
      // the way back to the list — never a dead end (07 §1 rule 6).
      expect(find.byKey(YearCloseKeys.certify), findsNothing);
      expect(find.text(l.closeYearCertifyBlocked(4)), findsOneWidget);
      expect(find.text(l.closeYearCertifyBlockedAction), findsOneWidget);
      expect(source.closed, isEmpty);

      // Nothing in the way: one settled line, no empty headings, one action.
      final ready = FakeYearCloseSource(view: yview());
      await pumpYear(tester, ready);
      expect(find.text(l.closeYearChecklistReady('2026-27')), findsOneWidget);
      expect(find.byKey(YearCloseKeys.blocks), findsNothing);
      expect(find.byKey(YearCloseKeys.warns), findsNothing);
      expect(find.byKey(YearCloseKeys.certify), findsOneWidget);
    },
  );

  testWidgets(
    'F1-07-190 a missing-entries gap raises the S10.5 shape in place of the '
    'action and names the phone, not the device id',
    (tester) async {
      final source = FakeYearCloseSource(
        view: yview(blockers: [gapFromPankaj(), monthOpen()]),
      );
      await pumpYear(tester, source, viewport: rkPhone360, textScale: 2.0);
      final l = stringsOf(tester);

      expect(find.byKey(YearCloseKeys.blocked), findsOneWidget);
      expect(find.byType(CloseBlockedPanel), findsOneWidget);
      expect(find.byKey(YearCloseKeys.certify), findsNothing);
      expect(find.text(l.closeYearBlockedTitle), findsOneWidget);
      expect(
        find.text(l.closeYearBlockedBody('Pankaj’s phone')),
        findsOneWidget,
      );
      expect(find.text(l.closeYearBlockedOff), findsOneWidget);
      // A device id is never printed at a shopkeeper (07 §28 🔒).
      expect(find.textContaining('device-2'), findsNothing);
      // The hardest lines on the screen, at the hardest size.
      expect(tester.takeException(), isNull);
      expectTextFits(tester, reason: 'S10.5 shape on S10.4 at 200 % on 360');
    },
  );

  // ── F1-07-191 · the optional distribute door (02 §8.1 🔒, 02 §7.1 🔒) ──────

  testWidgets(
    'F1-07-191 a business with an undistributed surplus gets the door to '
    'S14.1; a settled business gets the settled line; a personal book gets '
    'neither, and never hears the word partner',
    (tester) async {
      final pending = FakeYearCloseSource(
        view: yview(isBusiness: true, distributionPending: true),
      );
      final opened = await pumpYear(tester, pending);
      final l = stringsOf(tester);

      expect(find.byKey(YearCloseKeys.distribute), findsOneWidget);
      expect(find.text(l.closeYearDistributeTitle), findsOneWidget);
      expect(find.text(l.closeYearDistributeBody), findsOneWidget);

      // A **door**, never a rebuilt wizard: S14.1 already owns distribution
      // (02 §7.2.1 — it is a structural action).
      await tester.tap(find.text(l.closeYearDistributeAction));
      await tester.pumpAndSettle();
      expect(opened, [PartnersPaths.distributeOf('book-1')]);

      // 02 §7.1 🔒: carry forward is preselected, and the word says so —
      // never the tint alone (07 §1 rule 3).
      expect(find.byKey(YearCloseKeys.settlement), findsOneWidget);
      expect(find.text(l.closeYearSettlementCarry), findsOneWidget);
      expect(find.text(l.closeYearSettlementOthers), findsOneWidget);
      await tester.tap(find.text(l.closeYearSettlementOpen));
      await tester.pumpAndSettle();
      expect(opened.last, PartnersPaths.of('book-1'));

      // Already shared: the state is stated, and the offer is gone.
      final settled = FakeYearCloseSource(view: yview(isBusiness: true));
      await pumpYear(tester, settled);
      expect(find.text(l.closeYearDistributeDone), findsOneWidget);
      expect(find.text(l.closeYearDistributeAction), findsNothing);
      expect(find.text(l.closeYearDistributeTitle), findsNothing);

      // A *Just me* book never mentions partners, ratios or profit
      // distribution anywhere in the app (02 §7.1 🔒).
      final personal = FakeYearCloseSource(
        view: yview(distributionPending: true),
      );
      await pumpYear(tester, personal);
      expect(find.byKey(YearCloseKeys.distribute), findsNothing);
      expect(find.byKey(YearCloseKeys.settlement), findsNothing);
      for (final word in [
        l.closeYearDistributeTitle,
        l.closeYearDistributeDone,
        l.closeYearSettlementTitle,
        l.closeYearSettlementOpen,
      ]) {
        expect(find.text(word), findsNothing);
      }
      // …and the ceremony itself is unaffected.
      expect(find.byKey(YearCloseKeys.certify), findsOneWidget);
    },
  );

  // ── F1-07-192 · certify, seal, and the switcher (ADR 2026-09-09 §4 🔒) ─────

  testWidgets(
    'F1-07-192 the closing vector is shown before anything is published, and '
    'certifying seals the year and brings the FY switcher with it',
    (tester) async {
      final source = FakeYearCloseSource(view: yview());
      final opened = await pumpYear(tester, source);
      final l = stringsOf(tester);

      // Shown **before** the action (02 §8.1 🔒), and nothing published yet.
      expect(find.byKey(YearCloseKeys.vector), findsOneWidget);
      expect(find.text(l.closeYearVectorTitle), findsOneWidget);
      expect(find.text(l.closeYearVectorHelp('2027-28')), findsOneWidget);
      for (final name in [
        'Galla',
        'SBI Saving',
        'Opening Balance / Capital A/c',
      ]) {
        expect(find.text(name), findsOneWidget);
      }
      // Category accounts are not carried; the year's result is one line
      // (ADR 2026-09-05e §2).
      expect(find.text(l.closeYearVectorNetResult), findsOneWidget);
      expect(find.text(l.closeYearVectorTotal), findsOneWidget);
      expect(source.closed, isEmpty);

      // No switcher at all until the first year close (ADR 2026-09-09 §4 🔒).
      expect(find.byKey(YearCloseKeys.switcher), findsNothing);
      expect(find.byType(FySwitcher), findsNothing);

      // The ledger will hand back one certified year the moment it has one.
      source.years = [
        CertifiedYear(
          year: fy2627,
          status: YearStatus.closed,
          carriedForward: const Paise(11710000),
        ),
      ];
      await tester.tap(find.byKey(YearCloseKeys.certify));
      await tester.pumpAndSettle();

      // The ceremony ran once, for this book and this year.
      expect(source.closed, ['book-1/2026-27']);
      expect(find.byKey(YearCloseKeys.sealed), findsOneWidget);
      expect(find.text(l.closeYearSealedBadge('2026-27')), findsOneWidget);
      expect(find.text(l.closeYearSealedBody('2027-28')), findsOneWidget);
      // The certified figure is the engine's integer paise, drawn on the
      // professional side of the house (02 §10 🔒).
      expect(
        find.textContaining(l.moneySideDr, findRichText: true),
        findsWidgets,
      );
      // A sealed year is not a dead end (07 §1 rule 6).
      expect(find.text(l.closeYearSealedDone), findsOneWidget);

      // …and the switcher appears the moment the year seals.
      expect(find.byKey(YearCloseKeys.switcher), findsOneWidget);
      await tester.tap(find.text(l.ledgerStatementFy('2026-27')).last);
      await tester.pumpAndSettle();
      expect(find.text(l.ledgerStatementFyCertified), findsOneWidget);
      // The new FY is offered, and picking one re-enters the ceremony at its
      // own path rather than swapping the year in place.
      await tester.tap(find.text(l.ledgerStatementFy('2027-28')));
      await tester.pumpAndSettle();
      expect(opened, [ClosePaths.forYear('book-1', '2027-04')]);
    },
  );

  testWidgets(
    'F1-07-192 the engine may still refuse, and an unbalanced vector or a '
    'failed publish never reads as a certified year',
    (tester) async {
      // The screen keeps the action off for every blocker it can see, so a
      // refusal is the backstop: the ledger moved under the closer.
      final source = FakeYearCloseSource(view: yview());
      await pumpYear(tester, source);
      final l = stringsOf(tester);
      source.view = yview(blockers: [monthOpen(), reviewFlag()]);
      await tester.tap(find.byKey(YearCloseKeys.certify));
      await tester.pumpAndSettle();

      expect(find.byKey(YearCloseKeys.sealed), findsNothing);
      expect(find.text(l.closeYearCertifyRefused(2)), findsOneWidget);
      expect(source.closed, isEmpty);
      // The way back is the checklist itself, now showing what the engine saw.
      await tester.tap(find.text(l.closeYearCertifyBlockedAction));
      await tester.pumpAndSettle();
      expect(find.byKey(YearCloseKeys.blocks), findsOneWidget);

      // A vector that does not add up is not certifiable (02 §8).
      final skewed = FakeYearCloseSource(
        view: yview(vector: unbalancedVector()),
      );
      await pumpYear(tester, skewed);
      expect(find.byKey(YearCloseKeys.certify), findsNothing);
      expect(find.text(l.closeYearVectorUnbalanced), findsWidgets);
      expect(skewed.closed, isEmpty);

      // A publish that failed is an error with a retry, not a sealed year.
      final broken = FakeYearCloseSource(view: yview())..failClose = true;
      await pumpYear(tester, broken);
      await tester.tap(find.byKey(YearCloseKeys.certify));
      await tester.pumpAndSettle();
      expect(find.text(l.closeYearCertifyError), findsOneWidget);
      expect(find.byKey(YearCloseKeys.sealed), findsNothing);
      broken.failClose = false;
      await tester.tap(find.text(l.closeRetry));
      await tester.pumpAndSettle();
      expect(find.byKey(YearCloseKeys.sealed), findsOneWidget);
      expect(broken.closed, ['book-1/2026-27']);
    },
  );

  // ── F1-07-193 · unverified-by-you (ADR 2026-09-05c §3 🔒) ──────────────────

  testWidgets(
    'F1-07-193 readerOutdated is *Update the app to verify this close* and is '
    'never drawn as a mismatch',
    (tester) async {
      final source = FakeYearCloseSource(
        view: yview(
          status: YearStatus.closed,
          certifiedVector: balancedVector(),
          verification: CloseVerification.readerOutdated,
        ),
      );
      await pumpYear(tester, source);
      final l = stringsOf(tester);

      expect(find.text(l.closeYearSealedUnverified), findsOneWidget);
      expect(find.text(l.closeYearSealedUnverifiedBody), findsOneWidget);
      // The year *is* certified; only this phone cannot check it.
      expect(find.text(l.closeYearSealedBadge('2026-27')), findsOneWidget);
      // Never a mismatch, and never the older-certifier words either.
      for (final wrong in [
        l.closeYearSealedMismatch,
        l.closeYearSealedMismatchBody,
        l.closeYearSealedStale,
        l.closeYearSealedStaleBody,
      ]) {
        expect(find.text(wrong), findsNothing);
      }

      // The real mismatch is a different card in different words — the two
      // outcomes are drawn apart.
      final mismatched = FakeYearCloseSource(
        view: yview(
          status: YearStatus.closed,
          certifiedVector: balancedVector(),
          verification: CloseVerification.mismatch,
        ),
      );
      await pumpYear(tester, mismatched);
      expect(find.text(l.closeYearSealedMismatch), findsOneWidget);
      expect(find.text(l.closeYearSealedUnverified), findsNothing);
      expect(find.text(l.closeYearSealedUnverifiedBody), findsNothing);

      // And the same three outcomes reach the closer who has just certified.
      final justClosed = FakeYearCloseSource(view: yview())
        ..verification = CloseVerification.readerOutdated;
      await pumpYear(tester, justClosed);
      await tester.tap(find.byKey(YearCloseKeys.certify));
      await tester.pumpAndSettle();
      expect(find.text(l.closeYearSealedUnverified), findsOneWidget);
      expect(find.text(l.closeYearSealedMismatch), findsNothing);
    },
  );

  // ── F1-07-194 · voided by re-open, loudly (02 §8.1 🔒, 13 §6 🔒) ───────────

  testWidgets(
    'F1-07-194 re-opening a month voids the year loudly, names the month, and '
    'says every later year is void too',
    (tester) async {
      final source = FakeYearCloseSource(
        view: yview(
          status: YearStatus.uncertified,
          voidedBy: YearMonth(2026, 9),
          blockers: [monthOpen('2026-09')],
        ),
      );
      await pumpYear(tester, source);
      final l = stringsOf(tester);

      expect(find.byKey(YearCloseKeys.voided), findsOneWidget);
      expect(find.text(l.closeYearVoidedTitle), findsOneWidget);
      expect(
        find.text(
          l.closeYearVoidedBody(monthLabel(l, YearMonth(2026, 9)), '2026-27'),
        ),
        findsOneWidget,
      );
      // Loud: the danger banner, with glyph and words carrying it without the
      // tint (13 §4.2, 07 §1 rule 3).
      final banner = tester.widget<RkBannerSurface>(
        find.byType(RkBannerSurface),
      );
      expect(banner.tone, RkBannerTone.danger);
      expect(find.byKey(YearCloseKeys.sealed), findsNothing);

      // It sits above the checklist: a void certificate is the most important
      // fact on the screen and must not sit under a list.
      final bannerY = tester.getTopLeft(find.byKey(YearCloseKeys.voided)).dy;
      final listY = tester.getTopLeft(find.byKey(YearCloseKeys.blocks)).dy;
      expect(bannerY, lessThan(listY));

      // Re-closing happens here, in order — never a dead end.
      expect(find.text(l.closeYearChecklistTitle), findsOneWidget);

      // When the month is not known, the year still says what happened.
      final vague = FakeYearCloseSource(
        view: yview(status: YearStatus.uncertified),
      );
      await pumpYear(tester, vague);
      expect(
        find.text(l.closeYearVoidedBodyUnknown('2026-27')),
        findsOneWidget,
      );
    },
  );

  // ── F1-07-195 · resumable, by derivation (07 §13 🔒) ───────────────────────

  testWidgets(
    'F1-07-195 leaving and coming back re-reads the ceremony from the ledger, '
    'and nothing is held on the screen to lose',
    (tester) async {
      final source = FakeYearCloseSource(
        view: yview(blockers: [monthOpen()], warnings: const [agedAdvance]),
      );
      await pumpYear(tester, source);
      final l = stringsOf(tester);
      expect(find.byKey(YearCloseKeys.blocks), findsOneWidget);
      expect(source.loaded, ['book-1/2026-27']);

      // The closer leaves, locks March from S10, and comes back: a **new**
      // State, and the ceremony is in the state the ledger is in — not the
      // state the screen remembered.
      source.view = yview(warnings: const [agedAdvance]);
      await pumpYear(tester, source);
      expect(source.loaded, ['book-1/2026-27', 'book-1/2026-27']);
      expect(find.byKey(YearCloseKeys.blocks), findsNothing);
      expect(find.byKey(YearCloseKeys.warns), findsOneWidget);
      expect(find.byKey(YearCloseKeys.certify), findsOneWidget);
      expect(find.text(l.closeYearChecklistReady('2026-27')), findsNothing);

      // Coming and going never publishes anything.
      expect(source.closed, isEmpty);
    },
  );

  // ── F1-07-196 · the two doors, and the route (07 §13 🔒) ───────────────────

  testWidgets(
    'F1-07-196 S10 prompts for the year close when the FY’s last month locks '
    '— March for an April book, December for a calendar-year trust',
    (tester) async {
      Future<List<String>> lockAndSee(
        YearMonth period,
        int fyStartMonth,
      ) async {
        final opened = <String>[];
        final source = FakeCloseSource(
          view: CloseView(
            bookId: 'book-1',
            bookName: 'Kirana',
            period: period,
            cashAccounts: const [],
            bankAccounts: const [],
            tray: const CloseTray(),
            fyStartMonth: fyStartMonth,
          ),
        );
        await pumpRk(
          tester,
          MonthCloseScreen(
            key: ValueKey('month-pump-${_pumpSeq++}'),
            bookId: 'book-1',
            period: period,
            source: source,
            onOpenYear: opened.add,
            onDone: () {},
          ),
          viewport: rkTallViewport,
        );
        for (var i = 0; i < 3; i++) {
          await tester.tap(find.byKey(CloseKeys.next));
          await tester.pumpAndSettle();
        }
        await tester.tap(find.byKey(CloseKeys.lock));
        await tester.pumpAndSettle();
        return opened;
      }

      // March 2027 locks: the prompt, under the reward and never over it.
      var opened = await lockAndSee(YearMonth(2027, 3), 4);
      final l = AppLocalizations.of(
        tester.element(find.byType(MonthCloseScreen)),
      );
      expect(find.byKey(CloseKeys.yearPrompt), findsOneWidget);
      expect(find.text(l.closeYearPromptTitle('2026-27')), findsOneWidget);
      // It is an offer, never a gate: *Done* is untouched.
      expect(find.text(l.closeSummaryDone), findsOneWidget);
      await tester.tap(find.text(l.closeYearPromptAction));
      await tester.pumpAndSettle();
      expect(opened, [ClosePaths.forYear('book-1', '2026-04')]);

      // An ordinary month locks: no prompt.
      opened = await lockAndSee(YearMonth(2026, 8), 4);
      expect(find.byKey(CloseKeys.yearPrompt), findsNothing);
      expect(opened, isEmpty);

      // A calendar-year trust is prompted in December, not in March.
      opened = await lockAndSee(YearMonth(2026, 12), 1);
      expect(find.byKey(CloseKeys.yearPrompt), findsOneWidget);
      expect(find.text(l.closeYearPromptTitle('2026')), findsOneWidget);
      await tester.tap(find.text(l.closeYearPromptAction));
      await tester.pumpAndSettle();
      expect(opened, [ClosePaths.forYear('book-1', '2026-01')]);

      opened = await lockAndSee(YearMonth(2027, 3), 1);
      expect(find.byKey(CloseKeys.yearPrompt), findsNothing);
      expect(opened, isEmpty);
    },
  );

  test('F1-07-196 the year route names the FY by its first month and guesses '
      'nothing', () {
    // A book's FY need not start in April, so a bare year cannot name the
    // period; the first month always can.
    expect(ClosePaths.fyStartOf(fy2627), '2026-04');
    expect(ClosePaths.fyStartOf(fy2026Calendar), '2026-01');
    expect(
      ClosePaths.forYear('book-1', ClosePaths.fyStartOf(fy2627)),
      '/close/book-1/year/2026-04',
    );
    expect(parseFinancialYear('2026-04'), fy2627);
    expect(parseFinancialYear('2026-01'), fy2026Calendar);
    // Malformed is null — never *the current year*, because certifying the
    // wrong year is the one mistake 02 §8.1 🔒 makes permanent.
    for (final bad in [null, '', '2026', 'nope', '2026-13', '2026-00']) {
      expect(parseFinancialYear(bad), isNull, reason: 'parsed "$bad"');
    }
  });

  testWidgets(
    'F1-07-196 closeRoutes builds S10.4 from the path alone, and a malformed '
    'year is a way back rather than a red screen',
    (tester) async {
      Future<GoRouter> pumpRoute(String location) async {
        final router = GoRouter(routes: closeRoutes, initialLocation: location);
        addTearDown(router.dispose);
        await tester.pumpWidget(
          YearCloseScope(
            source: FakeYearCloseSource(view: yview()),
            child: MaterialApp.router(
              routerConfig: router,
              supportedLocales: AppLocalizations.supportedLocales,
              localizationsDelegates: rkLocalizationsDelegates,
              theme: rkTheme(Brightness.light),
            ),
          ),
        );
        await tester.pumpAndSettle();
        return router;
      }

      await pumpRoute(ClosePaths.forYear('book-1', '2026-04'));
      final l = stringsOf(tester);
      // Built from the path, with no source passed in: the scope is the door
      // `closeRoutes` relies on.
      expect(find.byType(YearCloseScreen), findsOneWidget);
      expect(find.text(l.closeYearTitle), findsOneWidget);
      expect(find.byKey(YearCloseKeys.certify), findsOneWidget);

      await pumpRoute('/close/book-1/year/nope');
      expect(find.byType(YearCloseUnavailableScreen), findsOneWidget);
      expect(find.byType(YearCloseScreen), findsNothing);
      expect(find.text(l.closeYearError), findsOneWidget);
      expect(find.text(l.closeBack), findsOneWidget);
    },
  );

  // ── F1-07-198 · the 13 §4.3 state set ─────────────────────────────────────

  testWidgets('F1-07-198 S10.4 has loading, error, offline, read-only and '
      'empty states, and a missing source is never a red screen', (
    tester,
  ) async {
    // Loading: a ruled skeleton that announces what is coming (11 §4.5).
    final slow = FakeYearCloseSource(view: yview())..holdLoad = true;
    await pumpYear(tester, slow);
    final l = stringsOf(tester);
    expect(find.byType(RkSkeleton), findsOneWidget);
    expect(
      tester.getSemantics(find.byType(RkSkeleton)).label,
      l.closeYearSkeleton,
    );

    // Error, with the retry that reloads.
    final broken = FakeYearCloseSource(view: yview(), failLoad: true);
    await pumpYear(tester, broken);
    expect(find.byType(RkErrorState), findsOneWidget);
    expect(find.text(l.closeYearError), findsOneWidget);
    broken.failLoad = false;
    await tester.tap(find.text(l.closeRetry));
    await tester.pumpAndSettle();
    expect(find.byKey(YearCloseKeys.certify), findsOneWidget);

    // No source in scope at all: the error state, not a thrown red screen.
    await pumpYear(tester, null);
    expect(find.byType(RkErrorState), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Offline is a chip, never a blocking banner (07 §1 rule 7 🔒): a close is
    // computed locally.
    final ok = FakeYearCloseSource(view: yview());
    await pumpYear(tester, ok, offline: true);
    expect(find.byType(CloseQuietChip), findsOneWidget);
    expect(find.byKey(YearCloseKeys.certify), findsOneWidget);

    // Read-only: legible, and the action says why it is off (13 §2.3.1).
    final reader = FakeYearCloseSource(view: yview(readOnly: true));
    await pumpYear(tester, reader);
    expect(find.byType(CloseBanner), findsOneWidget);
    expect(find.text(l.closeYearReadonly), findsWidgets);
    expect(find.byKey(YearCloseKeys.certify), findsNothing);
    expect(reader.closed, isEmpty);

    // Nothing to carry forward is said in words, not left blank.
    final bare = FakeYearCloseSource(view: yview(vector: emptyVector()));
    await pumpYear(tester, bare);
    expect(find.text(l.closeYearVectorEmpty), findsOneWidget);

    // A years list that cannot be read costs the closer nothing.
    final noYears = FakeYearCloseSource(view: yview())..failYears = true;
    await pumpYear(tester, noYears);
    expect(find.byKey(YearCloseKeys.switcher), findsNothing);
    expect(find.byKey(YearCloseKeys.certify), findsOneWidget);
  });

  // ── F1-07-199 · the sweep (07 §1 rule 11) ─────────────────────────────────

  for (final viewport in rkPhones) {
    for (final locale in rkLocales) {
      for (final scale in rkTextScales) {
        testWidgets('F1-07-199 S10.4 holds at ${(scale * 100).round()} % in '
            '${locale.languageCode} on ${viewport.width.round()}×'
            '${viewport.height.round()}', (tester) async {
          // The heaviest open year there is: the loud banner, both lists,
          // both doors, the vector and the disabled action.
          final busy = FakeYearCloseSource(
            view: yview(
              status: YearStatus.uncertified,
              voidedBy: YearMonth(2026, 9),
              blockers: [
                monthOpen('2026-09'),
                reviewFlag(),
                advancePending(),
                suspense(),
              ],
              warnings: const [agedAdvance],
              isBusiness: true,
              distributionPending: true,
            ),
          );
          await pumpYear(
            tester,
            busy,
            locale: locale,
            textScale: scale,
            viewport: viewport,
          );
          expect(tester.takeException(), isNull);
          expectTextFits(
            tester,
            reason:
                'S10.4 open year, ${locale.languageCode} at $scale on '
                '${viewport.width}',
          );

          // And the sealed year, with the switcher chip and the longest of
          // the four verification bodies.
          final sealed =
              FakeYearCloseSource(
                  view: yview(
                    status: YearStatus.closed,
                    certifiedVector: balancedVector(),
                    verification: CloseVerification.readerOutdated,
                  ),
                )
                ..years = [
                  CertifiedYear(
                    year: fy2627,
                    status: YearStatus.closed,
                    carriedForward: const Paise(11710000),
                  ),
                ];
          await pumpYear(
            tester,
            sealed,
            locale: locale,
            textScale: scale,
            viewport: viewport,
          );
          expect(tester.takeException(), isNull);
          expectTextFits(
            tester,
            reason:
                'S10.4 sealed year, ${locale.languageCode} at $scale on '
                '${viewport.width}',
          );
        });
      }
    }
  }
}
