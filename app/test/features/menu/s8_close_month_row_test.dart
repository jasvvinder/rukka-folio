// F1-07-260 … F1-07-264 — the S8 *Close the month* row, live (ADR 2026-09-03
// ruling 1 🔒: a Menu row in *The books* group directly after Reports, with a
// **live subtitle** such as *August open · 3 items waiting*, opening S10).
//
// CL7 left this row as a `MenuDisabledRow` reading *The month close wizard has
// not been built yet* although S10 shipped at M9 — a built screen behind a *not
// built yet* sentence, which 07 §1 rule 6 does not allow. What is pinned here:
//
//  · **the door** — `ClosePaths.forBook(bookId, period)` for the book's **first
//    open month**, never the month asked for: months lock in order (02 §8.1 🔒)
//    and `closeStatuses` already reports the earlier one;
//  · **the subtitle** — the month (abbreviated in EN, 07 §1 rule 5: *Aug 2026*)
//    and the waiting count **in words**: nothing waiting reads as *ready to
//    close*, never as *0 items waiting*;
//  · **no dead end** — with nothing closable the row stays, disabled, saying
//    which case it is in one sentence; loading and error say so too, and the
//    error row is tappable rather than inert (07 §1 rule 6).
@Tags(['F1'])
library;

import 'package:core_ledger/core_ledger.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/close/close_paths.dart';
import 'package:rukka_folio/features/close/close_source.dart';
import 'package:rukka_folio/features/menu/close_month_books.dart';
import 'package:rukka_folio/features/menu/screens/s8_menu_screen.dart';

import '../../shared/test_app.dart';

/// A [CloseSource] that answers per book — [FakeCloseSource] holds one view, and
/// this row is about several books at once.
final class _MultiBookClose implements CloseSource {
  _MultiBookClose({required this.statusList, required this.views});

  final List<BookCloseStatus> statusList;
  final Map<String, CloseView> views;

  /// Makes both reads throw — the error state.
  bool fail = false;

  /// Every `(bookId, period)` [loadClose] was asked for, in order.
  final List<String> loaded = [];

  @override
  Future<List<BookCloseStatus>> closeStatuses(YearMonth upTo) async {
    if (fail) throw StateError('cannot read the close');
    return statusList;
  }

  @override
  Future<CloseView> loadClose(String bookId, YearMonth period) async {
    loaded.add('$bookId/$period');
    if (fail) throw StateError('cannot read the close');
    return views['$bookId/$period']!;
  }

  @override
  Future<void> saveProgress(
    String bookId,
    YearMonth period,
    CloseProgress progress,
  ) async {}

  @override
  Future<CloseLockResult> lock({
    required String bookId,
    required YearMonth period,
    required Map<String, Paise> declaredBalances,
  }) async => throw UnimplementedError();

  @override
  Future<MonthSummary> monthSummary(String bookId, YearMonth period) async =>
      throw UnimplementedError();
}

CloseView _view(
  String bookId,
  String bookName,
  YearMonth period, {
  CloseTray tray = const CloseTray(),
}) => CloseView(
  bookId: bookId,
  bookName: bookName,
  period: period,
  cashAccounts: const [],
  bankAccounts: const [],
  tray: tray,
);

CloseTray _tray({int blocks = 0, int warns = 0}) => CloseTray(
  blocks: [
    for (var i = 0; i < blocks; i++)
      CloseBlockingItem(kind: CloseBlocker.reviewFlagOpen, ref: 'e$i'),
  ],
  warns: [
    for (var i = 0; i < warns; i++)
      CloseWarningItem(kind: CloseWarning.agedAdvance, ref: 'a$i'),
  ],
);

/// The row's default state, for the test helper's default argument.
const _loadingDefault = MenuCloseMonthLoad(MenuCloseMonthState.loading);

void main() {
  final aug = YearMonth(2026, 8);
  final jul = YearMonth(2026, 7);

  Widget menu({
    MenuCloseMonthLoad close = _loadingDefault,
    void Function(MenuCloseMonthBook book)? onOpenCloseMonth,
    VoidCallback? onRetryCloseMonth,
  }) => MenuScreen(
    onOpenReports: () {},
    onOpenBooks: () {},
    onOpenBackup: () {},
    onOpenDevices: () {},
    onOpenSettings: () {},
    onOpenHelp: () {},
    onOpenSubscription: () {},
    onOpenLegal: () {},
    closeMonth: close,
    onOpenCloseMonth: onOpenCloseMonth,
    onRetryCloseMonth: onRetryCloseMonth,
  );

  testWidgets(
    'F1-07-260 the row is enabled and the tap carries the book and the month '
    'the wizard opens at (ADR 2026-09-03 ruling 1 🔒)',
    (tester) async {
      final book = MenuCloseMonthBook(
        bookId: 'b1',
        bookName: 'Me',
        period: aug,
        waiting: 3,
      );
      final taken = <MenuCloseMonthBook>[];
      await pumpRk(
        tester,
        menu(
          close: MenuCloseMonthLoad(MenuCloseMonthState.ready, books: [book]),
          onOpenCloseMonth: taken.add,
        ),
      );

      expect(find.text('Close the month'), findsOneWidget);
      await tester.tap(find.text('Close the month'));
      await tester.pumpAndSettle();

      expect(taken.single.bookId, 'b1');
      expect(taken.single.period, aug);
      // The path is built by `ClosePaths`, never by hand.
      expect(
        ClosePaths.forBook(taken.single.bookId, taken.single.period.toString()),
        '/close/b1/2026-08',
      );
    },
  );

  test('F1-07-260 the row offers each book its FIRST OPEN month, not the month '
      'asked for — months lock in order (02 §8.1 🔒)', () async {
    final source = _MultiBookClose(
      statusList: [
        // August is over, but this book still has July open.
        BookCloseStatus(
          bookId: 'b1',
          bookName: 'Kirana',
          period: jul,
          state: BookCloseState.notStarted,
        ),
        BookCloseStatus(
          bookId: 'b2',
          bookName: 'Me',
          period: aug,
          state: BookCloseState.inProgress,
          step: CloseStep.clearTray,
        ),
      ],
      views: {
        'b1/2026-07': _view('b1', 'Kirana', jul, tray: _tray(blocks: 2)),
        'b2/2026-08': _view('b2', 'Me', aug, tray: _tray(warns: 1)),
      },
    );

    final load = await menuCloseMonthLoad(source, aug);
    expect(load.state, MenuCloseMonthState.ready);
    expect(load.books.map((b) => b.bookId), ['b1', 'b2']);
    expect(load.books.first.period, jul);
    expect(load.books.first.waiting, 2);
    expect(load.books.last.period, aug);
    // Blocks and warns alike are *items waiting* on this row — the tray
    // states which is which (07 §13 🔒); the Menu only says how many.
    expect(load.books.last.waiting, 1);
    expect(load.books.last.resumable, isTrue);
    expect(source.loaded, ['b1/2026-07', 'b2/2026-08']);
  });

  test(
    'F1-07-262 a book already locked through the month contributes no row, and '
    'a device where every book is locked reports *closed*',
    () async {
      final source = _MultiBookClose(
        statusList: [
          BookCloseStatus(
            bookId: 'b1',
            bookName: 'Kirana',
            period: aug,
            state: BookCloseState.closed,
          ),
        ],
        views: const {},
      );

      final load = await menuCloseMonthLoad(source, aug);
      expect(load.state, MenuCloseMonthState.closed);
      expect(load.books, isEmpty);
      expect(load.upTo, aug);
      // A locked book is never loaded — there is nothing to count.
      expect(source.loaded, isEmpty);
    },
  );

  test('F1-07-260 the month the row asks about is the one that has just ENDED, '
      'never the month in progress — the Home close card\'s own reading '
      '(07 §13 🔒)', () {
    expect(endedMonthAt(DateTime(2026, 9, 1, 6)), YearMonth(2026, 8));
    expect(endedMonthAt(DateTime(2026, 9, 30, 23)), YearMonth(2026, 8));
    // January reaches back across the year boundary.
    expect(endedMonthAt(DateTime(2027, 1, 3, 9)), YearMonth(2026, 12));
  });

  test('F1-07-262 a device holding no book at all reports *nothing*', () async {
    final source = _MultiBookClose(statusList: [], views: const {});
    final load = await menuCloseMonthLoad(source, aug);
    expect(load.state, MenuCloseMonthState.nothing);
    expect(load.books, isEmpty);
  });

  testWidgets(
    'F1-07-261 the subtitle names the month abbreviated (07 §1 rule 5) and the '
    'waiting count IN WORDS — 0 reads *ready to close*, never *0 items*',
    (tester) async {
      await pumpRk(
        tester,
        menu(
          close: MenuCloseMonthLoad(
            MenuCloseMonthState.ready,
            books: [
              MenuCloseMonthBook(
                bookId: 'b1',
                bookName: 'Me',
                period: aug,
                waiting: 3,
              ),
            ],
          ),
        ),
      );

      expect(find.text('Aug 2026 open · 3 items waiting'), findsOneWidget);
      expect(find.textContaining('0 items'), findsNothing);
    },
  );

  testWidgets('F1-07-261 one waiting item is singular, and none reads as a '
      'plain *ready to close*', (tester) async {
    await pumpRk(
      tester,
      menu(
        close: MenuCloseMonthLoad(
          MenuCloseMonthState.ready,
          books: [
            MenuCloseMonthBook(
              bookId: 'b1',
              bookName: 'Kirana',
              period: aug,
              waiting: 1,
            ),
            MenuCloseMonthBook(
              bookId: 'b2',
              bookName: 'Me',
              period: jul,
              waiting: 0,
            ),
          ],
        ),
      ),
    );

    // More than one book, so each row names its own book (07 §13 🔒).
    expect(
      find.text('Kirana · Aug 2026 open · 1 item waiting'),
      findsOneWidget,
    );
    expect(find.text('Me · Jul 2026 open · ready to close'), findsOneWidget);
    expect(find.text('Close the month'), findsNWidgets(2));
  });

  testWidgets(
    'F1-07-262 with nothing closable the row stays, disabled, saying which '
    'case it is in ONE sentence (07 §1 rule 6)',
    (tester) async {
      await pumpRk(
        tester,
        menu(close: MenuCloseMonthLoad(MenuCloseMonthState.closed, upTo: aug)),
      );
      expect(find.text('Close the month'), findsOneWidget);
      expect(find.text('Every book is closed up to Aug 2026.'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await pumpRk(
        tester,
        menu(close: MenuCloseMonthLoad(MenuCloseMonthState.nothing)),
      );
      expect(find.text('There is no month to close yet.'), findsOneWidget);
    },
  );

  testWidgets('F1-07-263 while the close is being read the row says so, and '
      'cannot be entered', (tester) async {
    await pumpRk(
      tester,
      menu(
        close: MenuCloseMonthLoad(MenuCloseMonthState.loading),
        onOpenCloseMonth: (_) => fail('a loading row must not be tappable'),
      ),
    );
    expect(find.text('Checking where each book stands…'), findsOneWidget);
    await tester.tap(find.text('Close the month'));
    await tester.pumpAndSettle();
  });

  testWidgets(
    'F1-07-263 a read that failed is a row that can be tried again, never an '
    'inert one (07 §1 rule 6)',
    (tester) async {
      var retried = 0;
      await pumpRk(
        tester,
        menu(
          close: MenuCloseMonthLoad(MenuCloseMonthState.failed),
          onRetryCloseMonth: () => retried++,
        ),
      );
      expect(
        find.text('Could not check the close · tap to try again'),
        findsOneWidget,
      );
      await tester.tap(find.text('Close the month'));
      await tester.pumpAndSettle();
      expect(retried, 1);
    },
  );

  test('F1-07-263 a source that throws is the *failed* state, not a crash and '
      'not a silently empty row', () async {
    final source = _MultiBookClose(statusList: [], views: const {})
      ..fail = true;
    final load = await menuCloseMonthLoad(source, aug);
    expect(load.state, MenuCloseMonthState.failed);
    expect(load.books, isEmpty);
  });

  for (final locale in rkLocales) {
    for (final vp in rkPhones) {
      for (final scale in rkTextScales) {
        testWidgets('F1-07-264 the live Close the month row fits in '
            '${locale.languageCode} at ${scale}x on ${vp.width.toInt()}x'
            '${vp.height.toInt()}', (tester) async {
          await pumpRk(
            tester,
            menu(
              close: MenuCloseMonthLoad(
                MenuCloseMonthState.ready,
                books: [
                  MenuCloseMonthBook(
                    bookId: 'b1',
                    bookName: 'Kirana',
                    period: aug,
                    waiting: 3,
                  ),
                  MenuCloseMonthBook(
                    bookId: 'b2',
                    bookName: 'Me',
                    period: jul,
                    waiting: 0,
                  ),
                ],
              ),
            ),
            locale: locale,
            textScale: scale,
            viewport: vp,
          );
          expect(tester.takeException(), isNull);
          expectTextFits(
            tester,
            reason: 'ready · ${locale.languageCode} @ $scale on $vp',
          );
        });

        testWidgets(
          'F1-07-264 the disabled, loading and error Close the month rows fit '
          'in ${locale.languageCode} at ${scale}x on ${vp.width.toInt()}x'
          '${vp.height.toInt()}',
          (tester) async {
            for (final state in [
              MenuCloseMonthLoad(MenuCloseMonthState.closed, upTo: aug),
              MenuCloseMonthLoad(MenuCloseMonthState.nothing),
              MenuCloseMonthLoad(MenuCloseMonthState.loading),
              MenuCloseMonthLoad(MenuCloseMonthState.failed),
            ]) {
              await pumpRk(
                tester,
                menu(close: state),
                locale: locale,
                textScale: scale,
                viewport: vp,
              );
              expect(tester.takeException(), isNull);
              expectTextFits(
                tester,
                reason:
                    '${state.state.name} · ${locale.languageCode} @ $scale '
                    'on $vp',
              );
            }
          },
        );
      }
    }
  }
}
