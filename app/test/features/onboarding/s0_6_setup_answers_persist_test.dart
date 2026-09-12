// F1 widget test for the onboarding handoff: the two answers the setup wizard
// collects that used to die with the screen — the S0.6a1 share weights (ADR
// 2026-09-09 §2, 02 §7.1 🔒 divides by them) and the S0.6g trust type (07
// §3.1.1 🔒) — now reach the `book_config` envelope the book is made from.
//
// The assertion is deliberately made against the *ledger*, not the flow
// object: a weight that only lives in `OnboardingFlow` is a weight that is
// gone the moment setup closes, which is exactly the gap this closes.
@Tags(['F1'])
library;

import 'package:core_ledger/core_ledger.dart';
import 'package:data/data.dart' show BookOwnership, OrganizationSubtype;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/onboarding/onboarding_flow.dart';
import 'package:rukka_folio/features/onboarding/screens/s0_6a1_business_owners_screen.dart';
import 'package:rukka_folio/features/onboarding/screens/s0_6a_business_name_screen.dart';
import 'package:rukka_folio/features/onboarding/screens/s0_6g_trust_name_screen.dart';
import 'package:rukka_folio/features/onboarding/widgets/business_opening_host.dart';
import 'package:rukka_folio/features/onboarding/widgets/trust_opening_host.dart';
import 'package:rukka_folio/shared/ledger/local_ledger.dart';

import '../../shared/test_app.dart';

final _start = LocalDate(2026, 9, 7);

Future<void> _pump(
  WidgetTester tester,
  LocalLedger ledger,
  Widget child,
) async {
  tester.view.physicalSize = const Size(420, 3200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await pumpRk(tester, child, ledger: ledger);
  await tester.pumpAndSettle();
}

void main() {
  group('setup answers reach the ledger (ADR 2026-09-09 §2, 07 §3.1.1)', () {
    testWidgets(
      'F1-07-86 the S0.6a1 share weights are written into book_config, keyed '
      'to each owner\'s Partner Current A/c id and in S0.6a1 order',
      (tester) async {
        final ledger = await openTestLedger();
        await ledger.bootstrapSolo(firstBookName: 'Me');
        final flow = OnboardingFlow()
          ..setYourName('Amrit Kaur')
          ..setBusiness(
            BusinessDraft(
              name: 'Amrit Kaur Agri',
              ownership: BusinessOwnershipChoice.shared,
              fyStartMonth: 4,
            ),
          )
          ..setOwners(const [
            OwnerDraft(name: 'Amrit Kaur', isYou: true, shares: 3),
            OwnerDraft(name: 'Sukhdev Singh', shares: 2),
            OwnerDraft(name: 'Harjit Kaur', shares: 1),
          ]);
        await _pump(
          tester,
          ledger,
          BusinessOpeningHost(flow: flow, startDate: _start),
        );

        final bookId = flow.businessBookId!;
        final config = (await ledger.configOf(bookId))!;
        expect(config.ownership, BookOwnership.shared);

        final chart = await ledger.chartOf(bookId);
        final partners = [
          for (final a in chart.accounts)
            if (a.accountClass == AccountClass.partner) a,
        ]..sort((a, b) => a.createdOrder.compareTo(b.createdOrder));
        expect(partners.map((a) => a.name), [
          'Amrit Kaur — Partner Current A/c',
          'Sukhdev Singh — Partner Current A/c',
          'Harjit Kaur — Partner Current A/c',
        ]);

        // Keyed by account id, not by name: the account may be renamed and the
        // ratio must not move with it (02 §7.1 🔒).
        expect(config.partnerShares, {
          partners[0].id: 3,
          partners[1].id: 2,
          partners[2].id: 1,
        });
        expect(
          config.partnerShares.keys.every(
            (k) => !k.contains('Amrit') && !k.contains('Partner'),
          ),
          isTrue,
          reason: 'the key is an account id, never a display name',
        );
      },
    );

    testWidgets(
      'F1-07-86 a Just me business records no weights, and a dropped owner '
      'row drops its weight with it rather than shifting the ratio',
      (tester) async {
        final ledger = await openTestLedger();
        await ledger.bootstrapSolo(firstBookName: 'Me');

        final solo = OnboardingFlow()
          ..setYourName('Amrit Kaur')
          ..setBusiness(
            BusinessDraft(
              name: 'Amrit Kaur Agri',
              ownership: BusinessOwnershipChoice.justMe,
              fyStartMonth: 4,
            ),
          );
        await _pump(
          tester,
          ledger,
          BusinessOpeningHost(flow: solo, startDate: _start),
        );
        final soloConfig = (await ledger.configOf(solo.businessBookId!))!;
        expect(soloConfig.ownership, BookOwnership.justMe);
        expect(
          soloConfig.partnerShares,
          isEmpty,
          reason: 'a Just me book has no partners, so it records no ratio',
        );

        // An unnamed middle row is not seeded (an account with no name is a
        // chore, not a seed) — so its weight must not be handed to the owner
        // after it.
        final flow = OnboardingFlow()
          ..setYourName('Amrit Kaur')
          ..setBusiness(
            BusinessDraft(
              name: 'Second Agri',
              ownership: BusinessOwnershipChoice.shared,
              fyStartMonth: 4,
            ),
          )
          ..setOwners(const [
            OwnerDraft(name: 'Amrit Kaur', isYou: true, shares: 3),
            OwnerDraft(name: '  ', shares: 7),
            OwnerDraft(name: 'Harjit Kaur', shares: 1),
          ]);
        expect(flow.ownerNames, ['Amrit Kaur', 'Harjit Kaur']);
        expect(flow.ownerShares, [3, 1]);
        await _pump(
          tester,
          ledger,
          // A distinct key, or the framework updates the first host's element
          // in place, `initState` never runs again and nothing is committed.
          BusinessOpeningHost(
            key: const ValueKey('second'),
            flow: flow,
            startDate: _start,
          ),
        );
        final bookId = flow.businessBookId!;
        final config = (await ledger.configOf(bookId))!;
        final chart = await ledger.chartOf(bookId);
        final partners = [
          for (final a in chart.accounts)
            if (a.accountClass == AccountClass.partner) a,
        ]..sort((a, b) => a.createdOrder.compareTo(b.createdOrder));
        expect(partners.length, 2);
        expect(config.partnerShares, {partners[0].id: 3, partners[1].id: 1});
      },
    );

    testWidgets(
      'F1-07-86 the S0.6g trust type is written into book_config as the '
      'organization subtype (07 §3.1.1 🔒), for each of the four',
      (tester) async {
        const cases = {
          TrustType.gurudwara: OrganizationSubtype.gurudwara,
          TrustType.temple: OrganizationSubtype.temple,
          TrustType.society: OrganizationSubtype.society,
          TrustType.registeredTrust: OrganizationSubtype.registeredTrust,
        };
        for (final MapEntry(key: chosen, value: stored) in cases.entries) {
          final ledger = await openTestLedger();
          await ledger.bootstrapSolo(firstBookName: 'Me');
          final flow = OnboardingFlow()
            ..setYourName('Amrit Kaur')
            ..setTrust(TrustDraft(name: 'Guru Nanak Gurudwara', type: chosen));
          await _pump(
            tester,
            ledger,
            // Keyed per case: the host commits from `initState`, so reusing
            // the element would silently create nothing.
            TrustOpeningHost(
              key: ValueKey(chosen),
              flow: flow,
              startDate: _start,
            ),
          );
          final config = (await ledger.configOf(flow.trustBookId!))!;
          expect(config.type, BookType.organization);
          expect(config.organizationSubtype, stored);
        }
      },
    );
  });
}
