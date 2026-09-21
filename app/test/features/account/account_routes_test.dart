@Tags(['F1'])
library;

// The account feature's route table — specifically the row S16 drew as a
// closed door until M11/A2 (13 §3.2 row S16.2, 06 §9.4 🔒).
//
// F1-07-318 already holds both halves of the phone row *as a widget*: disabled
// with a reason when no destination is supplied, a live door when one is. What
// it cannot see is whether [accountRoutes] actually mounts the destination —
// a builder that forgets `onChangePhone`, or a route registered at a different
// spelling, passes that test and still leaves the user at a dimmed row. This
// file closes that gap by driving the real router.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/account/account_routes.dart';
import 'package:rukka_folio/main.dart';
import 'package:rukka_folio/shared/router.dart';
import 'package:rukka_folio/shared/seams/auth_client.dart';
import 'package:rukka_folio/shared/seams/sync_client.dart';

import '../../shared/test_app.dart';

Future<GoRouter> _pumpApp(WidgetTester tester) async {
  final db = await openTestDb();
  final router = buildRouter(featureRoutes: accountRoutes);
  await tester.pumpWidget(
    RukkaFolioApp(
      db: db,
      sync: FakeSyncClient(),
      auth: FakeAuthClient(),
      now: testNow,
      router: router,
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

void main() {
  group('Account routes (13 §3.2 rows S16, S16.2)', () {
    testWidgets(
      'F1-07-372 S16.2 is mounted at AccountPaths.changePhone and S16 opens '
      'it: the phone row is a door now, not a dimmed row with an apology',
      (tester) async {
        rkViewport(tester, rkPhone360);
        final router = await _pumpApp(tester);

        unawaited(router.push(AccountPaths.root));
        await tester.pumpAndSettle();
        expect(find.text('My account'), findsOneWidget);
        expect(
          find.text('Changing your number is not in this version yet.'),
          findsNothing,
          reason:
              'the route exists, so the row must be live rather than '
              'disabled-with-reason',
        );

        await tester.tap(find.byKey(const Key('account.row.phone')));
        await tester.pumpAndSettle();
        expect(find.text('Change phone number'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'F1-07-373 with no PhoneChangeScope installed — the shell before the '
      'adapter lands — S16.2 degrades to the named error of 13 §4.3 with a '
      'retry beside it, and never to a crash or a flow that pretends to work',
      (tester) async {
        rkViewport(tester, rkPhone360);
        final router = await _pumpApp(tester);

        unawaited(router.push(AccountPaths.changePhone));
        await tester.pumpAndSettle();

        expect(find.text('Change phone number'), findsOneWidget);
        expect(find.text('Couldn’t check this change.'), findsOneWidget);
        expect(find.text('Try again'), findsOneWidget);
        // Nothing offers to send a code it has nowhere to send.
        expect(find.byKey(const Key('account.change.otp')), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  });
}
