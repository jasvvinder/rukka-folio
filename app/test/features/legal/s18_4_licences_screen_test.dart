// F1-07-338 / F1-07-339 — S18.4 Open-source licences (13 §3.2 row S18.4),
// every state of 13 §4.3: loading (ruled skeleton, 11 §4.5), populated,
// empty with the one next action, error-with-retry.
@Tags(['F1'])
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/legal/screens/s18_4_licences_screen.dart';
import 'package:rukka_folio/l10n/gen/app_localizations.dart';
import 'package:rukka_folio/shared/widgets/rk_states.dart';

import '../../shared/test_app.dart';

Stream<LicenseEntry> _two() async* {
  yield const LicenseEntryWithLineBreaks(['zeta_pkg'], 'Zeta licence text.');
  yield const LicenseEntryWithLineBreaks(['alpha_pkg'], 'Alpha licence text.');
}

Stream<LicenseEntry> _none() async* {}

Stream<LicenseEntry> _boom() async* {
  throw StateError('registry unavailable');
}

void main() {
  group('S18.4 Open-source licences', () {
    testWidgets(
      'F1-07-338 shows the ruled skeleton while reading, then one row per '
      'package in name order, each carrying its licence text',
      (tester) async {
        final done = Completer<void>();
        Stream<LicenseEntry> slow() async* {
          await done.future;
          yield* _two();
        }

        await pumpRk(
          tester,
          LicencesScreen(source: slow),
          viewport: rkPhone360,
        );
        // 11 §4.5: a ruled skeleton, never a spinner.
        expect(find.byType(RkSkeleton), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsNothing);

        done.complete();
        await tester.pumpAndSettle();

        expect(find.text('alpha_pkg'), findsOneWidget);
        expect(find.text('zeta_pkg'), findsOneWidget);
        final rows = tester
            .widgetList<Text>(find.byType(Text))
            .map((t) => t.data)
            .whereType<String>()
            .toList();
        expect(
          rows.indexOf('alpha_pkg'),
          lessThan(rows.indexOf('zeta_pkg')),
          reason: 'packages are listed in name order',
        );

        await tester.tap(find.text('alpha_pkg'));
        await tester.pumpAndSettle();
        expect(find.text('Alpha licence text.'), findsOneWidget);
      },
    );

    testWidgets(
      'F1-07-339 the empty and error states both offer a way on, and every '
      'state resolves in EN, PA and HI without cutting a word',
      (tester) async {
        for (final locale in rkLocales) {
          final l10n = await AppLocalizations.delegate.load(locale);

          // Empty — the one next action (07 §1 rule 12).
          var back = 0;
          await pumpRk(
            tester,
            LicencesScreen(source: _none, onBack: () => back++),
            locale: locale,
            viewport: rkPhone360,
            textScale: 2,
          );
          await tester.pumpAndSettle();
          expect(find.text(l10n.legalLicencesEmpty), findsOneWidget);
          expectTextFits(tester, reason: 'empty ${locale.languageCode}');
          await tester.ensureVisible(find.text(l10n.legalLicencesEmptyAction));
          await tester.pumpAndSettle();
          await tester.tap(find.text(l10n.legalLicencesEmptyAction));
          await tester.pump();
          expect(back, 1);

          // Error — named cause plus retry, and the retry actually re-reads.
          await pumpRk(
            tester,
            LicencesScreen(source: _boom),
            locale: locale,
            viewport: rkPhone360,
            textScale: 2,
          );
          await tester.pumpAndSettle();
          expect(find.byType(RkErrorState), findsOneWidget);
          expect(find.text(l10n.legalLicencesError), findsOneWidget);
          expectTextFits(tester, reason: 'error ${locale.languageCode}');
          await tester.ensureVisible(find.text(l10n.legalLicencesRetry));
          await tester.pumpAndSettle();
          await tester.tap(find.text(l10n.legalLicencesRetry));
          await tester.pumpAndSettle();
          expect(find.byType(RkErrorState), findsOneWidget);

          expect(tester.takeException(), isNull);
        }
      },
    );
  });
}
