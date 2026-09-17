// F1-07-27 + F1-07-129…135: S10 the month-close wizard and S10.5 the blocked
// state (02 §8 🔒, 07 §13 🔒, 07 §28 🔒, 13 §3.2 rows S10 and S10.5).
//
// The screen is pumped over the feature-local [FakeCloseSource], which refuses
// a lock exactly when the tray holds a blocker — `monthLockPreconditions`'
// contract (02 §8 step 3 🔒, ADR 2026-09-05b §3–4, ADR 2026-09-05e §4). A
// blocking item carries `core_ledger`'s own [CloseBlocker], so what "blocks"
// means here is the engine's word and not a stub's.
//
// This is a state-machine screen (13 §4.3), so the two rules that are easy to
// break silently are asserted **structurally**, not by copy: the resume path
// (F1-07-133) reads back what the seam was told, and the blocks-versus-warns
// split (F1-07-131) asserts that no blocking item is ever drawn inside the
// warning list or the other way about.
//
// Every amount is synthetic (CLAUDE.md rule 4) and integer paise (rule 1).
@Tags(['F1'])
library;

import 'package:core_ledger/core_ledger.dart';
import 'package:flutter/material.dart';
import 'package:rukka_folio/shared/widgets/rk_states.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/cash_count/cash_count_paths.dart';
import 'package:rukka_folio/features/close/close_routes.dart';
import 'package:rukka_folio/features/close/widgets/close_blocked_panel.dart';
import 'package:rukka_folio/features/close/widgets/close_parts.dart';
import 'package:rukka_folio/l10n/gen/app_localizations.dart';
import 'package:rukka_folio/shared/format/date_format.dart';

import '../../shared/test_app.dart';

// ---- fixtures ---------------------------------------------------------------

final august = YearMonth(2026, 8);

CloseCashAccount galla({bool counted = true}) => CloseCashAccount(
  accountId: 'galla',
  name: 'Galla',
  bookBalance: const Paise(250000),
  lastCountDate: counted ? LocalDate(2026, 8, 31) : null,
  countedInPeriod: counted,
);

const sbi = CloseBankAccount(
  accountId: 'sbi',
  name: 'SBI Saving',
  bookBalance: Paise(11460000),
);

const pnb = CloseBankAccount(
  accountId: 'pnb',
  name: 'PNB Current',
  bookBalance: Paise(3200000),
);

/// A blocker of the kind the closer can settle here — an open review flag.
const reviewFlag = CloseBlockingItem(
  kind: CloseBlocker.reviewFlagOpen,
  ref: 'entry-1',
  label: 'Diesel · 24 Aug',
);

/// The two gap blockers that raise S10.5.
const gapFromPankaj = CloseBlockingItem(
  kind: CloseBlocker.authorGapOpen,
  ref: 'device-2',
  deviceName: 'Pankaj’s phone',
);

const heldFromPankaj = CloseBlockingItem(
  kind: CloseBlocker.heldEnvelope,
  ref: 'env-9',
  deviceName: 'Pankaj’s phone',
);

const agedAdvance = CloseWarningItem(
  kind: CloseWarning.agedAdvance,
  ref: 'adv-1',
  label: 'Sunita',
);

const unverifiedCount = CloseWarningItem(
  kind: CloseWarning.unverifiedCount,
  ref: 'galla',
  label: 'Galla',
);

CloseView view({
  List<CloseCashAccount>? cash,
  List<CloseBankAccount>? banks,
  CloseTray tray = const CloseTray(),
  CloseProgress progress = const CloseProgress(),
  bool readOnly = false,
}) => CloseView(
  bookId: 'book-1',
  bookName: 'Kirana',
  period: august,
  cashAccounts: cash ?? [galla()],
  bankAccounts: banks ?? const [sbi],
  tray: tray,
  progress: progress,
  readOnly: readOnly,
);

/// Distinguishes one pump from the next, so re-pumping builds a **new**
/// [State] rather than reusing the one already on screen — which is what
/// *leaving and coming back* means, and the only way F1-07-133 can prove the
/// resume path at all.
int _pumpSeq = 0;

/// Pumps the wizard over [source], recording every path it asks to open.
Future<List<String>> pumpClose(
  WidgetTester tester,
  FakeCloseSource source, {
  Locale? locale,
  double textScale = 1,
  Size viewport = rkTallViewport,
  bool offline = false,
}) async {
  final opened = <String>[];
  await pumpRk(
    tester,
    MonthCloseScreen(
      key: ValueKey('close-pump-${_pumpSeq++}'),
      bookId: 'book-1',
      period: august,
      source: source,
      offline: offline,
      onOpenCount: opened.add,
    ),
    locale: locale,
    textScale: textScale,
    viewport: viewport,
  );
  return opened;
}

AppLocalizations stringsOf(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(MonthCloseScreen)));

Future<void> tapNext(WidgetTester tester) async {
  await tester.tap(find.byKey(CloseKeys.next));
  await tester.pumpAndSettle();
}

/// True when the widget at [key] is an enabled button.
bool enabled(WidgetTester tester, Key key) =>
    tester.widget<ButtonStyleButton>(find.byKey(key)).onPressed != null;

void main() {
  // ── F1-07-27 · the four steps, 02 §8's own words, one screen each ──────────

  testWidgets(
    'F1-07-27 S10 is 02 §8\'s four steps, one screen each, in order',
    (tester) async {
      final source = FakeCloseSource(view: view());
      await pumpClose(tester, source);
      final l = stringsOf(tester);
      final titles = [
        l.closeStep1Title,
        l.closeStep2Title,
        l.closeStep3Title,
        l.closeStep4Title,
      ];

      for (var i = 0; i < titles.length; i++) {
        // Exactly one step is on screen — the wizard is never a long form.
        for (var j = 0; j < titles.length; j++) {
          expect(
            find.text(titles[j]),
            j == i ? findsOneWidget : findsNothing,
            reason:
                'at step ${i + 1}, ${titles[j]} should '
                '${j == i ? 'show' : 'not show'}',
          );
        }
        expect(find.text(l.closeStepOf(i + 1, 4)), findsOneWidget);
        if (i < titles.length - 1) await tapNext(tester);
      }

      // And back down again — no dead ends (07 §1 rule 6).
      await tester.tap(find.byKey(CloseKeys.back));
      await tester.pumpAndSettle();
      expect(find.text(l.closeStep3Title), findsOneWidget);
      // The last step has no Next, the first no Back.
      expect(find.byKey(CloseKeys.next), findsOneWidget);
    },
  );

  // ── F1-07-129 · step 1, Count your cash ───────────────────────────────────

  testWidgets(
    'F1-07-129 step 1 is a door per cash A/C to S5.5, and an uncounted A/C '
    'warns without blocking',
    (tester) async {
      final source = FakeCloseSource(
        view: view(
          cash: [
            galla(counted: true),
            const CloseCashAccount(
              accountId: 'vault',
              name: 'Vault',
              bookBalance: Paise(5000000),
            ),
          ],
          // Not counted is a *warning* (02 §8 🔒, 07 §13 🔒): it reaches the
          // tray's warn list and never its block list.
          tray: const CloseTray(warns: [unverifiedCount]),
        ),
      );
      final opened = await pumpClose(tester, source);
      final l = stringsOf(tester);

      expect(find.text('Galla'), findsOneWidget);
      expect(find.text('Vault'), findsOneWidget);
      expect(find.text(l.closeCashCounted), findsOneWidget);
      expect(find.text(l.closeCashNotCounted), findsOneWidget);
      expect(find.text(l.closeCashNeverCounted), findsOneWidget);

      // The row is the existing S5.5 sheet's door, at its own path constant.
      await tester.tap(
        find.ancestor(of: find.text('Vault'), matching: find.byType(InkWell)),
      );
      await tester.pumpAndSettle();
      expect(opened, [CashCountPaths.forAccount('vault')]);

      // An unverified count never stops the lock.
      await tapNext(tester);
      await tapNext(tester);
      expect(find.byKey(CloseKeys.blocks), findsNothing);
      expect(find.byKey(CloseKeys.warns), findsOneWidget);
      await tapNext(tester);
      expect(enabled(tester, CloseKeys.lock), isTrue);
    },
  );

  // ── F1-07-130 · step 2, Confirm each bank balance ─────────────────────────

  testWidgets(
    'F1-07-130 step 2 offers Matches / Doesn’t match per bank A/C, and the '
    'reconcile door is disabled with its reason',
    (tester) async {
      final source = FakeCloseSource(view: view(banks: const [sbi, pnb]));
      await pumpClose(tester, source);
      final l = stringsOf(tester);
      await tapNext(tester);

      expect(find.text('SBI Saving'), findsOneWidget);
      expect(find.text('PNB Current'), findsOneWidget);
      expect(find.text(l.closeBankMatches), findsNWidgets(2));
      expect(find.text(l.closeBankMismatch), findsNWidgets(2));
      expect(find.text(l.closeBankConfirmed(0, 2)), findsOneWidget);

      // Confirming one is counted, and stated.
      await tester.tap(
        find
            .descendant(
              of: find.ancestor(
                of: find.text('SBI Saving'),
                matching: find.byType(CloseCard),
              ),
              matching: find.text(l.closeBankMatches),
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(find.text(l.closeBankConfirmed(1, 2)), findsOneWidget);

      // A difference wants S7.2, which lands at M10 — so the door is off and
      // says why, and the close still goes on (13 §4.3, 07 §1 rule 6).
      expect(find.byType(CloseDisabledAction), findsNothing);
      await tester.tap(
        find
            .descendant(
              of: find.ancestor(
                of: find.text('PNB Current'),
                matching: find.byType(CloseCard),
              ),
              matching: find.text(l.closeBankMismatch),
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(find.text(l.closeBankReconcile), findsOneWidget);
      expect(find.text(l.closeBankReconcileUnavailable), findsOneWidget);
      final reconcile = tester.widget<CloseDisabledAction>(
        find.byType(CloseDisabledAction),
      );
      expect(reconcile.label, l.closeBankReconcile);
      expect(
        tester
            .widgetList<FilledButton>(find.byType(FilledButton))
            .where((b) => b.onPressed == null),
        isNotEmpty,
        reason: 'Reconcile is drawn disabled, not hidden',
      );
    },
  );

  // ── F1-07-131 · step 3, blocks and warns are two lists ────────────────────

  testWidgets(
    'F1-07-131 step 3 states blocks and warns as two lists, never one',
    (tester) async {
      final source = FakeCloseSource(
        view: view(
          tray: const CloseTray(
            blocks: [reviewFlag],
            warns: [agedAdvance, unverifiedCount],
          ),
        ),
      );
      await pumpClose(tester, source);
      final l = stringsOf(tester);
      await tapNext(tester);
      await tapNext(tester);

      // Two lists, each under its own heading.
      expect(find.byKey(CloseKeys.blocks), findsOneWidget);
      expect(find.byKey(CloseKeys.warns), findsOneWidget);
      expect(find.text(l.closeTrayBlocksTitle), findsOneWidget);
      expect(find.text(l.closeTrayWarnsTitle), findsOneWidget);

      // Structural, not merely a matter of copy: nothing that blocks is drawn
      // inside the warning list, and nothing that warns inside the blocking
      // one (07 §13 🔒).
      expect(
        find.descendant(
          of: find.byKey(CloseKeys.blocks),
          matching: find.text(l.closeBlockerReviewFlag),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(CloseKeys.warns),
          matching: find.text(l.closeBlockerReviewFlag),
        ),
        findsNothing,
      );
      for (final warning in [
        l.closeWarningAgedAdvance,
        l.closeWarningUnverifiedCount,
      ]) {
        expect(
          find.descendant(
            of: find.byKey(CloseKeys.warns),
            matching: find.text(warning),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(CloseKeys.blocks),
            matching: find.text(warning),
          ),
          findsNothing,
        );
      }

      // With nothing at all, the step says so rather than showing two empty
      // headings (13 §4.3).
      source.view = view();
      await pumpClose(tester, source);
      await tapNext(tester);
      await tapNext(tester);
      expect(find.text(l.closeTrayEmpty), findsOneWidget);
      expect(find.byKey(CloseKeys.blocks), findsNothing);
      expect(find.byKey(CloseKeys.warns), findsNothing);
    },
  );

  // ── F1-07-132 · step 4, Confirm & lock ────────────────────────────────────

  testWidgets(
    'F1-07-132 step 4 declares every money balance in integer paise and the '
    'lock reaches the engine with them',
    (tester) async {
      final source = FakeCloseSource(
        view: view(cash: [galla()], banks: const [sbi, pnb]),
      );
      await pumpClose(tester, source);
      final l = stringsOf(tester);
      for (var i = 0; i < 3; i++) {
        await tapNext(tester);
      }

      expect(find.byKey(CloseKeys.declared), findsOneWidget);
      expect(find.text(l.closeLockDeclared), findsOneWidget);
      for (final name in ['Galla', 'SBI Saving', 'PNB Current']) {
        expect(
          find.descendant(
            of: find.byKey(CloseKeys.declared),
            matching: find.text(name),
          ),
          findsOneWidget,
        );
      }

      expect(enabled(tester, CloseKeys.lock), isTrue);
      await tester.tap(find.byKey(CloseKeys.lock));
      await tester.pumpAndSettle();

      // Integer paise, every money A/C, exactly what was on screen.
      expect(source.lockedWith, hasLength(1));
      expect(source.lockedWith.single, {
        'galla': const Paise(250000),
        'sbi': const Paise(11460000),
        'pnb': const Paise(3200000),
      });
      // *Aug 2026*, not *August* — 07 §1 rule 5 🔒 abbreviates in EN, and the
      // screen mints no month vocabulary of its own (see `_month`).
      expect(
        find.text(l.closeLockDone('${monthName(l, 8)} 2026')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'F1-07-132 a blocking tray leaves the lock disabled with its reason and '
    'the way back to the tray',
    (tester) async {
      final source = FakeCloseSource(
        view: view(
          tray: const CloseTray(
            blocks: [
              reviewFlag,
              CloseBlockingItem(
                kind: CloseBlocker.suspenseNonZero,
                ref: 'suspense',
              ),
            ],
          ),
          progress: const CloseProgress(step: CloseStep.confirmAndLock),
        ),
      );
      await pumpClose(tester, source);
      final l = stringsOf(tester);

      expect(find.byKey(CloseKeys.lock), findsNothing);
      expect(find.text(l.closeLockBlocked(2)), findsOneWidget);
      expect(find.byType(CloseDisabledAction), findsOneWidget);
      expect(source.lockedWith, isEmpty);

      // The reason carries the path out (07 §1 rule 6).
      await tester.tap(find.text(l.closeLockBlockedAction));
      await tester.pumpAndSettle();
      expect(find.text(l.closeStep3Title), findsOneWidget);
      expect(find.byKey(CloseKeys.blocks), findsOneWidget);
    },
  );

  // ── F1-07-133 · Resumable 🔒 ──────────────────────────────────────────────

  testWidgets(
    'F1-07-133 the step reached is saved at every step and restored on return',
    (tester) async {
      final source = FakeCloseSource(view: view(banks: const [sbi, pnb]));
      await pumpClose(tester, source);
      final l = stringsOf(tester);

      // Nothing is saved before the closer moves, and every move is saved.
      expect(source.savedProgress, isEmpty);
      await tapNext(tester);
      await tapNext(tester);
      expect(source.savedProgress.map((p) => p.step), [
        CloseStep.confirmBanks,
        CloseStep.clearTray,
      ]);

      // Confirming a bank is progress too — a phone call should not cost the
      // closer eight bank confirmations.
      await tester.tap(find.byKey(CloseKeys.back));
      await tester.pumpAndSettle();
      await tester.tap(
        find
            .descendant(
              of: find.ancestor(
                of: find.text('PNB Current'),
                matching: find.byType(CloseCard),
              ),
              matching: find.text(l.closeBankMatches),
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(source.savedProgress.last.confirmedBankIds, {'pnb'});

      // Leave, come back: a **fresh** screen over the same seam opens where
      // the closer stopped, with the confirmations intact (07 §13 🔒).
      await pumpClose(tester, source);
      expect(find.text(l.closeStep2Title), findsOneWidget);
      expect(find.text(l.closeResumed), findsOneWidget);
      expect(find.text(l.closeBankConfirmed(1, 2)), findsOneWidget);
      expect(find.text(l.closeStepOf(2, 4)), findsOneWidget);
    },
  );

  // ── F1-07-134 · S10.5, waiting on a device ────────────────────────────────

  for (final (label, gap) in [
    ('an author gap', gapFromPankaj),
    ('a held envelope', heldFromPankaj),
  ]) {
    testWidgets(
      'F1-07-134 S10.5 replaces step 4\'s action for $label: it names the '
      'phone, Remind is disabled with its reason, the lock stays off',
      (tester) async {
        final source = FakeCloseSource(
          view: view(
            tray: CloseTray(blocks: [gap]),
            progress: const CloseProgress(step: CloseStep.confirmAndLock),
          ),
        );
        await pumpClose(tester, source);
        final l = stringsOf(tester);

        expect(find.byKey(CloseKeys.blocked), findsOneWidget);
        expect(find.byType(CloseBlockedPanel), findsOneWidget);
        expect(find.byKey(CloseKeys.lock), findsNothing);
        expect(find.text(l.closeBlockedTitle), findsOneWidget);
        expect(find.text(l.closeBlockedBody('Pankaj’s phone')), findsOneWidget);
        expect(find.text(l.closeBlockedLockOff), findsOneWidget);

        // *Remind {name}* — named, drawn, and off with its reason: 07 §17 has
        // no reminder source on this device yet.
        expect(
          find.text(l.closeBlockedRemind('Pankaj’s phone')),
          findsOneWidget,
        );
        expect(find.text(l.closeBlockedRemindUnavailable), findsOneWidget);
        for (final b in tester.widgetList<FilledButton>(
          find.byType(FilledButton),
        )) {
          expect(b.onPressed, isNull, reason: 'nothing is actionable here');
        }
        expect(source.lockedWith, isEmpty);
      },
    );
  }

  testWidgets(
    'F1-07-134 S10.5 says “another phone” rather than a device id when the '
    'device has no name',
    (tester) async {
      final source = FakeCloseSource(
        view: view(
          tray: const CloseTray(
            blocks: [
              CloseBlockingItem(
                kind: CloseBlocker.authorGapOpen,
                ref: 'd41d8cd98f00b204e9800998ecf8427e',
              ),
            ],
          ),
          progress: const CloseProgress(step: CloseStep.confirmAndLock),
        ),
      );
      await pumpClose(tester, source);
      final l = stringsOf(tester);
      expect(
        find.text(l.closeBlockedBody(l.closeBlockedUnknownDevice)),
        findsOneWidget,
      );
      expect(find.textContaining('d41d8cd9'), findsNothing);
    },
  );

  // ── F1-07-135 · every state, every language, every scale ──────────────────

  testWidgets('F1-07-135 S10 ships loading, error-with-retry, offline, '
      'read-only and empty states', (tester) async {
    // Loading: the ruled skeleton, never a spinner (11 §4.5). The load is held
    // open rather than merely slowed — a pending future schedules no frame, so
    // the harness settles *on* the loading state instead of racing past it.
    final slow = FakeCloseSource(view: view())..holdLoad = true;
    await pumpClose(tester, slow);
    expect(find.byType(RkSkeleton), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(
      tester.getSemantics(find.byType(RkSkeleton)).label,
      stringsOf(tester).closeSkeleton,
      reason: 'the skeleton announces what is coming (11 §4.5)',
    );

    // Error, with the retry that reloads.
    final broken = FakeCloseSource(view: view(), failLoad: true);
    await pumpClose(tester, broken);
    final strings = stringsOf(tester);
    expect(find.text(strings.closeError), findsOneWidget);
    expect(find.byType(RkErrorState), findsOneWidget);
    broken.failLoad = false;
    await tester.tap(find.text(strings.closeRetry));
    await tester.pumpAndSettle();
    expect(find.text(strings.closeStep1Title), findsOneWidget);

    // Offline is a chip, never a blocking banner (07 §1 rule 7 🔒).
    final ok = FakeCloseSource(view: view());
    await pumpClose(tester, ok, offline: true);
    expect(find.byType(CloseQuietChip), findsOneWidget);
    expect(find.text(strings.closeStep1Title), findsOneWidget);

    // Read-only: legible, and the lock says why it is off (13 §2.3.1).
    final readOnly = FakeCloseSource(
      view: view(
        readOnly: true,
        progress: const CloseProgress(step: CloseStep.confirmAndLock),
      ),
    );
    await pumpClose(tester, readOnly);
    expect(find.byType(CloseBanner), findsOneWidget);
    expect(find.text(strings.closeReadonly), findsWidgets);
    expect(find.byKey(CloseKeys.lock), findsNothing);
    expect(find.byKey(CloseKeys.declared), findsOneWidget);

    // Empty lists name the next action rather than showing blank white.
    final bare = FakeCloseSource(
      view: view(cash: const [], banks: const []),
    );
    await pumpClose(tester, bare);
    expect(find.text(strings.closeCashEmpty), findsOneWidget);
    await tapNext(tester);
    expect(find.text(strings.closeBankEmpty), findsOneWidget);
  });

  for (final locale in rkLocales) {
    for (final scale in rkTextScales) {
      testWidgets('F1-07-135 S10 holds at ${(scale * 100).round()} % in '
          '${locale.languageCode} on 360×800', (tester) async {
        final source = FakeCloseSource(
          view: view(
            cash: [galla(counted: false)],
            banks: const [sbi, pnb],
            tray: const CloseTray(
              blocks: [reviewFlag, gapFromPankaj],
              warns: [agedAdvance, unverifiedCount],
            ),
          ),
        );
        await pumpClose(
          tester,
          source,
          locale: locale,
          textScale: scale,
          viewport: rkPhone360,
        );
        for (var step = 0; step < 4; step++) {
          expect(tester.takeException(), isNull);
          expectTextFits(
            tester,
            reason: 'S10 step ${step + 1}, ${locale.languageCode} at $scale',
          );
          if (step < 3) await tapNext(tester);
        }
        // Step 4 is S10.5 here — the hardest line on the screen is its body.
        expect(find.byType(CloseBlockedPanel), findsOneWidget);
      });
    }
  }
}
