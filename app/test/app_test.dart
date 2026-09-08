@Tags(['F1'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/main.dart';
import 'package:rukka_folio/shared/seams/auth_client.dart';
import 'package:rukka_folio/shared/seams/sync_client.dart';
import 'package:rukka_folio/shared/widgets/rk_tab_bar.dart';

import 'shared/test_app.dart';

void main() {
  // The shell boots on Home, strings resolve in all three languages, the four
  // tab labels render, nothing overflows at the default scale.
  const expected = {
    'en': ('Your position and today’s entries will appear here.', 'Ledger'),
    'pa': ('ਤੁਹਾਡੀ ਸਥਿਤੀ ਅਤੇ ਅੱਜ ਦੀਆਂ ਐਂਟਰੀਆਂ ਇੱਥੇ ਦਿਖਣਗੀਆਂ।', 'ਖਾਤੇ'),
    'hi': ('आपकी स्थिति और आज की एंट्रियाँ यहाँ दिखेंगी।', 'खाते'),
  };

  for (final entry in expected.entries) {
    testWidgets('F1-10-1 app boots in ${entry.key}', (tester) async {
      final db = await openTestDb();
      await tester.pumpWidget(
        RukkaFolioApp(
          db: db,
          sync: FakeSyncClient(),
          auth: FakeAuthClient(),
          now: testNow,
          locale: Locale(entry.key),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Rukka Folio'), findsOneWidget);
      expect(find.text(entry.value.$1), findsOneWidget);
      expect(find.text(entry.value.$2), findsOneWidget);
      expect(find.byType(RkTabItem), findsNWidgets(4));
      expect(find.byType(RkCentreAction), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
