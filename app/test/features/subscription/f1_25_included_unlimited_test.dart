// F1-25-11 — "what is included" says unlimited as unlimited (ADR 2026-09-24b
// §7 (b) 🔒: unlimited is `-1` on the wire; 0018 allows it on members,
// devices and tenant_bytes as well as business_books). A null count must
// never be read as a small number ("1 member", "Up to 0 phones",
// "0 MB of space").
@Tags(['F1'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/subscription/entitlement_source.dart';
import 'package:rukka_folio/features/subscription/screens/s12_3_manage_screen.dart';
import 'package:rukka_folio/features/subscription/subscription_commands.dart';
import 'package:rukka_folio/features/subscription/subscription_copy.dart';
import 'package:rukka_folio/features/subscription/tier_catalogue.dart';
import 'package:rukka_folio/l10n/gen/app_localizations.dart';

import '../../shared/test_app.dart';

/// Every count unlimited, as the wire carries it.
final _unlimited = EntitlementLimits.fromWire(const {
  'members': -1,
  'business_books': -1,
  'devices': -1,
  'envelopes_per_book': -1,
  'tenant_bytes': -1,
  'attachment_bytes': -1,
});

void main() {
  group('F1-25-11 unlimited is said as unlimited (ADR 2026-09-24b §7 🔒)', () {
    for (final locale in rkLocales) {
      test('F1-25-11 rkIncludedLines over -1 limits in '
          '${locale.languageCode}: members, books, phones and space each '
          'read unlimited, none as a count', () async {
        final l = await AppLocalizations.delegate.load(locale);
        final lines = rkIncludedLines(l, _unlimited, const []);
        expect(lines.take(4).toList(), [
          l.plansLimitMembersUnlimited,
          l.plansLimitBooksUnlimited,
          l.plansLimitDevicesUnlimited,
          l.plansLimitStorageUnlimited,
        ]);
        for (final wrong in [
          l.plansLimitMembers(0),
          l.plansLimitMembers(1),
          l.plansLimitDevices(0),
          l.plansLimitDevices(1),
          l.plansLimitStorageMb(0),
          l.plansLimitStorageGb(0),
        ]) {
          expect(lines, isNot(contains(wrong)));
        }
      });
    }

    test('F1-25-11 a counted limit still reads as its count', () async {
      final l = await AppLocalizations.delegate.load(const Locale('en'));
      final counted = EntitlementLimits.fromWire(const {
        'members': 4,
        'business_books': 2,
        'devices': 3,
        'envelopes_per_book': 100,
        'tenant_bytes': 1073741824,
        'attachment_bytes': 0,
      });
      final lines = rkIncludedLines(l, counted, const []);
      expect(lines.take(4).toList(), [
        l.plansLimitMembers(4),
        l.plansLimitBooks(2),
        l.plansLimitDevices(3),
        l.plansLimitStorageGb(1),
      ]);
    });

    testWidgets('F1-25-11 S12.3 over an all-unlimited token shows the '
        'unlimited lines', (tester) async {
      final l = await AppLocalizations.delegate.load(const Locale('en'));
      await pumpRk(
        tester,
        ManageSubscriptionScreen(
          source: FakeEntitlementSource(
            entitlement: Entitlement(
              tenantId: 't-synthetic',
              plan: RkPlan.family,
              limits: _unlimited,
              periodEnd: null,
              graceKind: EntitlementGraceKind.none,
              source: EntitlementSourceKind.fresh,
              activeMembers: 1,
              features: const [],
            ),
          ),
          commands: FakeSubscriptionCommands(),
          channel: RkCheckoutChannel.gateway,
        ),
        viewport: rkTallViewport,
      );
      expect(find.text(l.plansLimitMembersUnlimited), findsOneWidget);
      expect(find.text(l.plansLimitDevicesUnlimited), findsOneWidget);
      expect(find.text(l.plansLimitStorageUnlimited), findsOneWidget);
      expect(find.text(l.plansLimitMembers(1)), findsNothing);
      expect(find.text(l.plansLimitDevices(0)), findsNothing);
      expect(find.text(l.plansLimitStorageMb(0)), findsNothing);
    });
  });
}
