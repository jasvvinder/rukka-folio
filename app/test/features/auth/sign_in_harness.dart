// Drives the S0.2 family through its in-app keypad (canvas 1b L2–L4), the way
// a person does: digits on the keypad, then *Send code*; six digits verify by
// themselves. Shared by the S0.2 screen and route tests.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/lock/widgets/pin_pad.dart';

/// Taps [digits] on the keypad, one key at a time.
Future<void> tapKeys(WidgetTester tester, String digits) async {
  for (final d in digits.split('')) {
    final key = find.descendant(
      of: find.byType(PinKeypad),
      matching: find.text(d),
    );
    // At 200 % the keypad can sit below the fold of the scrolling page.
    await tester.ensureVisible(key);
    await tester.tap(key);
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

/// Number → *Send code*.
Future<void> enterNumberAndSend(WidgetTester tester, String national) async {
  await tapKeys(tester, national);
  // The one filled action on the number step, in any language.
  final send = find.byType(FilledButton);
  await tester.ensureVisible(send);
  await tester.tap(send);
  await tester.pumpAndSettle();
}
