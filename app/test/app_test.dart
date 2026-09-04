import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/main.dart';

void main() {
  // M0 hello-world gate: the shell boots, strings resolve in all three languages,
  // nothing overflows at the default scale. Suite F proper lands with M5.
  const expected = {
    'en': 'Opening your books.',
    'pa': 'ਤੁਹਾਡੇ ਵਹੀ-ਖਾਤੇ ਖੋਲ੍ਹ ਰਹੇ ਹਾਂ।',
    'hi': 'आपके बही-खाते खोल रहे हैं।',
  };

  for (final entry in expected.entries) {
    testWidgets('renders in ${entry.key}', (tester) async {
      await tester.pumpWidget(RukkaFolioApp(locale: Locale(entry.key)));
      await tester.pumpAndSettle();
      expect(find.text('Rukka Folio'), findsOneWidget);
      expect(find.text(entry.value), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
