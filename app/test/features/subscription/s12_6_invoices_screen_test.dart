// F1 widget tests for S12.6 Invoices (13 §3.2 row S12.6, 07 §20 🔒,
// DESIGN-PACK §11 S12.6 🔒, 08 §3.1 🔒 — email AND WhatsApp, ADR 2026-09-05g
// §10 🔒 — 18 % inclusive, half-up to the paisa, round_off line, per-FY serial,
// credit note on refund).
@Tags(['F1'])
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/subscription/entitlement_source.dart';
import 'package:rukka_folio/features/subscription/invoice_source.dart';
import 'package:rukka_folio/features/subscription/screens/s12_6_invoices_screen.dart';
import 'package:rukka_folio/features/subscription/tier_catalogue.dart';
import 'package:rukka_folio/l10n/gen/app_localizations.dart';
import 'package:rukka_folio/shared/widgets/rk_states.dart';

import '../../shared/test_app.dart';

/// 08 §2 🔒 — the Family annual price, integer paise, GST-inclusive.
final _familyAnnual = rkTierFor(RkPlan.family).annualPaise;

final _invoices = [
  RkInvoice(
    serial: 'RF/2026-27/0001',
    issuedOn: DateTime(2026, 4, 2),
    totalPaise: _familyAnnual,
    kind: RkInvoiceKind.invoice,
  ),
  RkInvoice(
    serial: 'RF/2026-27/0002',
    issuedOn: DateTime(2026, 9, 12),
    totalPaise: 59900,
    kind: RkInvoiceKind.creditNote,
  ),
];

/// A source that never resolves until it is told to — the only way to see the
/// loading state, which a resolved future skips past.
class _HeldSource implements InvoiceSource {
  final _gate = Completer<List<RkInvoice>>();

  void give(List<RkInvoice> invoices) => _gate.complete(invoices);

  @override
  Future<List<RkInvoice>> read() => _gate.future;
}

/// A fresh key per pump: Flutter reuses a [State] whenever type and position
/// match, and these tests pump more than one screen each.
int _pumps = 0;

Future<void> _pump(
  WidgetTester tester, {
  required InvoiceSource source,
  Locale? locale,
  Size viewport = rkTallViewport,
  double textScale = 1,
}) => pumpRk(
  tester,
  InvoicesScreen(key: ValueKey(_pumps++), source: source),
  locale: locale,
  viewport: viewport,
  textScale: textScale,
);

void main() {
  group('S12.6 Invoices', () {
    testWidgets(
      'F1-07-484 lists newest first with the per-FY serial, the date and the '
      'amount (13 §3.2, ADR 2026-09-05g §10 🔒)',
      (tester) async {
        final l10n = await AppLocalizations.delegate.load(const Locale('en'));
        // Handed in oldest-first: the screen sorts, the source does not.
        await _pump(tester, source: FakeInvoiceSource(invoices: _invoices));

        expect(find.text(l10n.invoicesTitle), findsOneWidget);
        expect(
          find.text(l10n.invoicesSerial('RF/2026-27/0001')),
          findsOneWidget,
        );
        expect(
          find.text(l10n.invoicesSerial('RF/2026-27/0002')),
          findsOneWidget,
        );
        expect(find.text('02 Apr 2026'), findsOneWidget);
        expect(find.text('12 Sep 2026'), findsOneWidget);
        // ₹1,999.00 — integer paise formatted, never a float.
        expect(find.text('₹1,999.00'), findsOneWidget);
        expect(find.text('₹599.00'), findsOneWidget);

        // Newest first: the September credit note is drawn above the April
        // invoice.
        final newest = tester.getTopLeft(
          find.text(l10n.invoicesSerial('RF/2026-27/0002')),
        );
        final oldest = tester.getTopLeft(
          find.text(l10n.invoicesSerial('RF/2026-27/0001')),
        );
        expect(newest.dy, lessThan(oldest.dy));
      },
    );

    testWidgets(
      'F1-07-485 the GST split is drawn to the paisa from the pure function — '
      '18 % inclusive, half-up (ADR 2026-09-05g §10 🔒)',
      (tester) async {
        final l10n = await AppLocalizations.delegate.load(const Locale('en'));
        await _pump(
          tester,
          source: FakeInvoiceSource(invoices: [_invoices.first]),
        );

        final split = rkGstSplit(_familyAnnual);
        expect(split.taxablePaise, 169407);
        expect(split.taxPaise, 30493);
        expect(find.text(l10n.invoicesTaxable), findsOneWidget);
        expect(find.text('₹1,694.07'), findsOneWidget);
        expect(find.text(l10n.invoicesGst), findsOneWidget);
        expect(find.text('₹304.93'), findsOneWidget);
        expect(find.text(l10n.invoicesTotal), findsOneWidget);
        // A whole-rupee price has no round_off, so the line is not drawn.
        expect(find.text(l10n.invoicesRoundOff), findsNothing);
      },
    );

    testWidgets(
      'F1-07-486 round_off is shown as its own line when there is one '
      '(ADR 2026-09-05g §10 🔒), and a refund is a credit note in words',
      (tester) async {
        final l10n = await AppLocalizations.delegate.load(const Locale('en'));
        await _pump(
          tester,
          source: FakeInvoiceSource(
            invoices: [
              RkInvoice(
                serial: 'RF/2026-27/0007',
                issuedOn: DateTime(2026, 8, 1),
                // Not a whole rupee: 49 paise round down and the line says so.
                totalPaise: 199949,
                kind: RkInvoiceKind.creditNote,
              ),
            ],
          ),
        );

        expect(find.text(l10n.invoicesRoundOff), findsOneWidget);
        expect(find.text('−₹0.49'), findsOneWidget);
        // 🔒 Shown as a credit note in words, never as a negative invoice.
        expect(find.text(l10n.invoicesKindCreditNote), findsOneWidget);
        expect(find.text(l10n.invoicesKindCreditNoteBody), findsOneWidget);
        expect(find.text(l10n.invoicesKindInvoice), findsNothing);
      },
    );

    testWidgets(
      'F1-07-487 loading draws the ruled skeleton, an empty list draws the '
      'designed empty state, and a failed read says the READ failed',
      (tester) async {
        final l10n = await AppLocalizations.delegate.load(const Locale('en'));
        final held = _HeldSource();
        await _pump(tester, source: held);
        expect(find.byType(RkSkeleton), findsOneWidget);
        expect(find.bySemanticsLabel(l10n.invoicesLoading), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        held.give(const []);
        await tester.pumpAndSettle();

        // 🔒 Empty says where the document already is: email AND WhatsApp.
        expect(find.text(l10n.invoicesEmptyTitle), findsOneWidget);
        expect(find.text(l10n.invoicesEmptyBody), findsOneWidget);
        expect(l10n.invoicesEmptyBody, contains('WhatsApp'));

        // The shipped source is the same, honest, empty reading.
        await _pump(tester, source: const UnwiredInvoiceSource());
        expect(find.text(l10n.invoicesEmptyTitle), findsOneWidget);

        final failing = FakeInvoiceSource(failure: StateError('no store'));
        await _pump(tester, source: failing);
        expect(find.text(l10n.invoicesError), findsOneWidget);
        // Never "you have none" out of an error.
        expect(find.text(l10n.invoicesEmptyTitle), findsNothing);
        await tester.tap(find.text(l10n.subscriptionActionRetry));
        await tester.pumpAndSettle();
        expect(failing.reads, 2);
      },
    );

    testWidgets(
      'F1-07-488 every PDF door is disabled-with-reason and names email and '
      'WhatsApp (08 §3.1 🔒, 07 §1 rule 6)',
      (tester) async {
        final l10n = await AppLocalizations.delegate.load(const Locale('en'));
        await _pump(tester, source: FakeInvoiceSource(invoices: _invoices));

        final doors = find.widgetWithText(OutlinedButton, l10n.invoicesPdf);
        expect(doors, findsNWidgets(_invoices.length));
        for (final button in tester.widgetList<OutlinedButton>(doors)) {
          expect(button.onPressed, isNull, reason: 'no PDF producer exists');
        }
        expect(
          find.text(l10n.invoicesPdfReason),
          findsNWidgets(_invoices.length),
        );
        expect(l10n.invoicesPdfReason, contains('email'));
        expect(l10n.invoicesPdfReason, contains('WhatsApp'));
      },
    );

    testWidgets(
      'F1-07-489 S12.6 resolves in EN, PA and HI with nothing cut at 130 % or '
      '200 % on either phone, list and empty state alike',
      (tester) async {
        for (final locale in rkLocales) {
          final l10n = await AppLocalizations.delegate.load(locale);
          for (final viewport in rkPhones) {
            for (final scale in rkTextScales) {
              await _pump(
                tester,
                source: FakeInvoiceSource(invoices: _invoices),
                locale: locale,
                viewport: viewport,
                textScale: scale,
              );
              expect(
                find.text(l10n.invoicesTitle),
                findsWidgets,
                reason: '${locale.languageCode} title missing',
              );
              expectTextFits(
                tester,
                reason:
                    '${locale.languageCode} @$scale on $viewport, '
                    'invoice list',
              );
              // The PDF reason is the longest sentence, and it sits below the
              // fold at 200 %.
              await tester.scrollUntilVisible(
                find.text(l10n.invoicesPdfReason).first,
                300,
                scrollable: find.byType(Scrollable).first,
              );
              await tester.pumpAndSettle();
              expectTextFits(
                tester,
                reason:
                    '${locale.languageCode} @$scale on $viewport, '
                    'below the fold',
              );

              await _pump(
                tester,
                source: const UnwiredInvoiceSource(),
                locale: locale,
                viewport: viewport,
                textScale: scale,
              );
              expectTextFits(
                tester,
                reason:
                    '${locale.languageCode} @$scale on $viewport, empty state',
              );
            }
          }
        }
      },
    );
  });
}
