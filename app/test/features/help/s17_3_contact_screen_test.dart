// F1-07-396 … F1-07-398, F1-07-409, F1-25-4 — S17.3 Contact support
// (13 §3.2 row S17.3 "email primary for the pilot … states what support
// cannot do"; 07 §22 🔒, which makes the four limits of 06 §8 🔒 normative on
// this screen; ADR 2026-09-25 §4, which makes *Email support* the primary
// action and amends ADR 2026-09-19 ruling 2 by the one `mailto:` target).
//
// Test honesty: every launch assertion is made against what the seam
// *received* — the fake counts calls, and the production mailer is driven
// with a recording launcher so the exact URI it hands `url_launcher` is
// pinned. A mailer that did nothing would turn each of these red.
@Tags(['F1'])
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/help/faq_catalog.dart';
import 'package:rukka_folio/features/help/screens/s17_3_contact_screen.dart';
import 'package:rukka_folio/features/help/support_mailer.dart';
import 'package:rukka_folio/l10n/gen/app_localizations.dart';

import '../../shared/test_app.dart';

/// A mailer that records each call and answers what it is told to.
final class _FakeMailer implements SupportMailer {
  _FakeMailer({this.opens = true, this.throws = false});

  final bool opens;
  final bool throws;
  int calls = 0;

  @override
  Future<bool> openSupportEmail() async {
    calls++;
    if (throws) throw StateError('no activity');
    return opens;
  }
}

/// Captures what reaches the platform clipboard.
List<MethodCall> _captureClipboard(WidgetTester tester) {
  final clipboard = <MethodCall>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'Clipboard.setData') clipboard.add(call);
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  return clipboard;
}

void main() {
  ContactSupportScreen screen({
    Key? key,
    SupportMailer? mailer,
    VoidCallback? onOpenDiagnostics,
    void Function(String id)? onOpenArticle,
  }) => ContactSupportScreen(
    key: key,
    mailer: mailer ?? _FakeMailer(),
    onOpenDiagnostics: onOpenDiagnostics ?? () {},
    onOpenArticle: onOpenArticle ?? (_) {},
  );

  group('S17.3 Contact support', () {
    testWidgets(
      'F1-07-396 the page states all four things support cannot do, and that '
      'none of them exists in the app (06 §8 🔒, 07 §22 🔒)',
      (tester) async {
        final l10n = await AppLocalizations.delegate.load(const Locale('en'));
        await pumpRk(tester, screen(), viewport: rkTallViewport);

        expect(find.text(l10n.helpCannotTitle), findsOneWidget);
        for (final limit in [
          l10n.helpCannotRead,
          l10n.helpCannotKey,
          l10n.helpCannotMember,
          l10n.helpCannotCeremony,
        ]) {
          expect(find.text(limit), findsOneWidget, reason: 'missing: $limit');
        }
        // "None of these exist in the app, so nobody can be talked into one"
        // — the sentence that makes the list a defence and not a policy.
        expect(find.text(l10n.helpCannotFootnote), findsOneWidget);
        // Each limit is carried by an icon as well as by its words, so the
        // meaning survives grayscale (07 §1 rule 3).
        expect(find.byIcon(Icons.block), findsNWidgets(4));
      },
    );

    testWidgets(
      'F1-07-397 the email row: *Email support* is the primary action and '
      'reaches the mailer exactly once; the address is always shown, '
      'selectable, beside a copy action; the other ways on still work '
      '(ADR 2026-09-25 §4; 07 §1 rule 6 🔒)',
      (tester) async {
        final l10n = await AppLocalizations.delegate.load(const Locale('en'));
        final mailer = _FakeMailer();
        var diagnostics = 0;
        final articles = <String>[];
        await pumpRk(
          tester,
          screen(
            mailer: mailer,
            onOpenDiagnostics: () => diagnostics++,
            onOpenArticle: articles.add,
          ),
          viewport: rkTallViewport,
        );

        // The primary action is a filled button carrying a mail icon as well
        // as its words (07 §1 rule 3).
        final action = find.widgetWithText(
          FilledButton,
          l10n.helpContactEmailAction,
        );
        expect(action, findsOneWidget);
        expect(
          find.descendant(
            of: action,
            matching: find.byIcon(Icons.mail_outline),
          ),
          findsOneWidget,
        );

        // The address is on the page before anything is tapped, and it sits
        // in a selection area so it can be long-pressed and copied by hand.
        expect(find.text(supportEmailAddress), findsOneWidget);
        expect(
          find.ancestor(
            of: find.text(supportEmailAddress),
            matching: find.byType(SelectionArea),
          ),
          findsOneWidget,
        );
        expect(find.text(l10n.helpContactEmailCopy), findsOneWidget);

        // No failure line until a launch has failed.
        final failed = l10n.helpContactEmailFailed(supportEmailAddress);
        expect(find.text(failed), findsNothing);

        await tester.tap(action);
        await tester.pumpAndSettle();
        expect(mailer.calls, 1);
        // A launch that opened the mail app leaves nothing to explain.
        expect(find.text(failed), findsNothing);
        expect(tester.takeException(), isNull);

        // The ways on that are not email.
        await tester.tap(find.text(faqText(l10n, 'support_powers')!.question));
        await tester.tap(find.text(l10n.helpDiagnosticsTitle));
        await tester.pumpAndSettle();
        expect(articles, ['support_powers']);
        expect(diagnostics, 1);
        // Tapping the other doors never reached the mailer.
        expect(mailer.calls, 1);
      },
    );

    for (final (label, mailer) in [
      ('answers false', () => _FakeMailer(opens: false)),
      ('throws', () => _FakeMailer(throws: true)),
    ]) {
      testWidgets(
        'F1-07-409 a launch that fails ($label) names the address in words '
        'beside an icon and offers copy, and copy puts exactly the address on '
        'the clipboard (07 §1 rules 3, 6 🔒; ADR 2026-09-19 ruling 3 shape)',
        (tester) async {
          final l10n = await AppLocalizations.delegate.load(const Locale('en'));
          final fake = mailer();
          final clipboard = _captureClipboard(tester);
          await pumpRk(tester, screen(mailer: fake), viewport: rkTallViewport);

          await tester.tap(
            find.widgetWithText(FilledButton, l10n.helpContactEmailAction),
          );
          await tester.pumpAndSettle();
          expect(fake.calls, 1);
          expect(tester.takeException(), isNull);

          final failed = l10n.helpContactEmailFailed(supportEmailAddress);
          expect(failed, contains(supportEmailAddress));
          expect(find.text(failed), findsOneWidget);
          // The failure is carried by an icon as well as its words.
          expect(find.byIcon(Icons.error_outline), findsOneWidget);
          // The primary action stays live — trying again is allowed.
          expect(
            tester
                .widget<FilledButton>(
                  find.widgetWithText(
                    FilledButton,
                    l10n.helpContactEmailAction,
                  ),
                )
                .onPressed,
            isNotNull,
          );

          await tester.tap(find.text(l10n.helpContactEmailCopy));
          await tester.pumpAndSettle();
          expect(clipboard, hasLength(1));
          expect(
            (clipboard.single.arguments as Map)['text'],
            supportEmailAddress,
          );
          expect(find.text(l10n.helpContactEmailCopied), findsOneWidget);
        },
      );
    }

    testWidgets('F1-25-4 through the production mailer, *Email support* hands '
        'url_launcher exactly mailto:support@rukkafolio.com — one URI, one '
        'launch — and the page offers no WhatsApp and no chat door '
        '(ADR 2026-09-25 §4)', (tester) async {
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      final launched = <Uri>[];
      await pumpRk(
        tester,
        screen(
          mailer: UrlLauncherSupportMailer(
            launch: (uri) async {
              launched.add(uri);
              return true;
            },
          ),
        ),
        viewport: rkTallViewport,
      );

      await tester.tap(
        find.widgetWithText(FilledButton, l10n.helpContactEmailAction),
      );
      await tester.pumpAndSettle();
      expect(launched, hasLength(1));
      expect(launched.single.toString(), 'mailto:support@rukkafolio.com');
      expect(launched.single.scheme, 'mailto');
      expect(launched.single.path, supportEmailAddress);
      expect(launched.single.hasQuery, isFalse);

      // WhatsApp is gone (ADR 2026-09-25 §4: no handle) and in-app chat
      // needs its own ADR — neither may appear as a door.
      expect(find.textContaining('WhatsApp'), findsNothing);
      expect(find.byIcon(Icons.chat_outlined), findsNothing);
      expect(find.byIcon(Icons.chat), findsNothing);
    });

    testWidgets(
      'F1-07-398 strings resolve in EN, PA and HI and nothing is cut at '
      '130 % or 200 % on either phone, scrolled to the end — with the '
      'failure line showing',
      (tester) async {
        for (final locale in rkLocales) {
          final l10n = await AppLocalizations.delegate.load(locale);
          for (final viewport in rkPhones) {
            for (final scale in rkTextScales) {
              await pumpRk(
                tester,
                // A fresh key per pass: otherwise the previous pass's state
                // (scrolled to the end, failure showing) is kept.
                screen(
                  key: ValueKey('$locale $viewport $scale'),
                  mailer: _FakeMailer(opens: false),
                ),
                locale: locale,
                viewport: viewport,
                textScale: scale,
              );
              final where = '${locale.languageCode} @$scale on $viewport';
              expect(
                find.text(l10n.helpContactTitle),
                findsWidgets,
                reason: '$where title missing',
              );
              expectTextFits(tester, reason: '$where, above the fold');

              await tester.tap(
                find.widgetWithText(FilledButton, l10n.helpContactEmailAction),
              );
              await tester.pumpAndSettle();
              expect(
                find.text(l10n.helpContactEmailFailed(supportEmailAddress)),
                findsOneWidget,
                reason: '$where failure line missing',
              );
              expectTextFits(tester, reason: '$where, failure line');

              await tester.scrollUntilVisible(
                find.text(l10n.helpDiagnosticsTitle),
                300,
                scrollable: find.byType(Scrollable).first,
              );
              await tester.pumpAndSettle();
              expectTextFits(tester, reason: '$where, scrolled to the doors');
              expect(tester.takeException(), isNull);
            }
          }
        }
      },
    );
  });

  group('SupportMailer', () {
    test('F1-25-4 the production mailer opens only the one constant URI and '
        'answers the launcher\'s own result', () async {
      for (final answer in [true, false]) {
        final launched = <Uri>[];
        final mailer = UrlLauncherSupportMailer(
          launch: (uri) async {
            launched.add(uri);
            return answer;
          },
        );
        expect(await mailer.openSupportEmail(), answer);
        expect(launched, [Uri.parse('mailto:support@rukkafolio.com')]);
      }
      expect(supportEmailAddress, 'support@rukkafolio.com');
      expect(supportMailtoUri.toString(), 'mailto:support@rukkafolio.com');
    });

    test('F1-25-4 a launcher that throws is a failed launch (false), never an '
        'exception on the screen', () async {
      final mailer = UrlLauncherSupportMailer(
        launch: (_) async => throw PlatformException(code: 'ACTIVITY'),
      );
      expect(await mailer.openSupportEmail(), isFalse);
    });
  });
}
