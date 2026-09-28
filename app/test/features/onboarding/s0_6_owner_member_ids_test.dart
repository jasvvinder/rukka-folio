// F1 tests: what owner member ids an onboarding host hands `createBook`, and
// the gap that keeps the owner set underivable on every shared business the
// UI can create today.
//
// Why it matters: the owner set that counts a structural quorum is derived
// from each Partner Current A/c's member (ADR 2026-09-14b; the reader is
// `packages/data` `structural_reader.dart` `_ownersNamed`). A partner account
// with no member makes the whole set *not derivable*, and every
// `business_setting` of the book is then quarantined (03 §2, ADR 2026-09-14b
// §5).
//
// ⚠️ SPEC / BLOCKER (lane report M11-OWN1, `open`): that defect is **not
// fixed** by this slice on any path S0.6a1 can reach. S0.6a1 always emits at
// least two owners — it seeds two rows, never drops below two
// (`s0_6a1_business_owners_screen.dart` `_rows.length > 2`) and needs a phone
// on every row that is not you — so every UI-created shared business has an
// invited co-owner. An invited owner has no member id (02 §7.1 🔒), and
// `createBook(ownerMemberIds:)` takes all ids or none, so onboarding passes
// none — not even the creator's. F1-07-544 is the honest statement of the
// reachable case and stays skipped until `createBook` takes a nullable id per
// owner (outside onboarding). F1-07-540/542 cover only the creator-only set,
// which a programmatic flow can build but S0.6a1 cannot.
//
// Family and trust books are **not** settled either: 06 §1.0 and 02 §7.2.1
// put structural changes under an owners' quorum on any shared book, and no
// doc says how a family or trust book's owner set is derived. No test pins
// either answer (lane report M11-OWN1, `open`).
//
// Sources: 02 §7.1 *Where the ratio lives* 🔒 (no member identity exists for
// an owner who is only invited), ADR 2026-09-09 §1 (the creating user is the
// first owner row), CLAUDE.md rule 11 (never guess an id).
@Tags(['F1'])
library;

import 'package:core_ledger/core_ledger.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/onboarding/onboarding_flow.dart';
import 'package:rukka_folio/features/onboarding/screens/s0_6a1_business_owners_screen.dart';
import 'package:rukka_folio/features/onboarding/screens/s0_6a_business_name_screen.dart';
import 'package:rukka_folio/features/onboarding/widgets/business_opening_host.dart';
import 'package:rukka_folio/shared/ledger/local_ledger.dart';

import '../../shared/test_app.dart';

final _start = LocalDate(2026, 9, 7);

OnboardingFlow _sharedBusiness(List<OwnerDraft> owners) => OnboardingFlow()
  ..setYourName('Amrit Kaur')
  ..setBusiness(
    const BusinessDraft(
      name: 'Amrit Kaur Agri',
      ownership: BusinessOwnershipChoice.shared,
      fyStartMonth: 4,
    ),
  )
  ..setOwners(owners);

Future<void> _pump(WidgetTester tester, LocalLedger ledger, Widget host) async {
  tester.view.physicalSize = const Size(420, 3200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await pumpRk(tester, host, ledger: ledger);
  await tester.pumpAndSettle();
}

Future<LocalLedger> _ledger() async {
  final ledger = await openTestLedger();
  await ledger.bootstrapSolo(firstBookName: 'Me');
  return ledger;
}

void main() {
  group('owner member ids at book creation (ADR 2026-09-14b, 02 §7.1)', () {
    testWidgets(
      'F1-07-540 host wiring: a creator-only owner set (programmatic only — '
      'S0.6a1 cannot emit one) reaches createBook with the creating user\'s '
      'own member id on their Partner Current A/c',
      (tester) async {
        final ledger = await _ledger();
        final flow = _sharedBusiness(const [
          OwnerDraft(name: 'Amrit Kaur', isYou: true),
        ]);
        await _pump(
          tester,
          ledger,
          BusinessOpeningHost(flow: flow, startDate: _start),
        );

        final chart = await ledger.chartOf(flow.businessBookId!);
        final partner = chart.byClass(AccountClass.partner).single;
        // The id is the open ledger's own user — never a literal, never a
        // name, never empty.
        expect(partner.memberId, ledger.identity.userId);
        expect(partner.memberId, isNotEmpty);
      },
    );

    testWidgets(
      'F1-07-541 an invited co-owner is given no member id — none exists '
      'until they join (02 §7.1), and none is guessed',
      (tester) async {
        final ledger = await _ledger();
        final flow = _sharedBusiness(const [
          OwnerDraft(name: 'Amrit Kaur', isYou: true),
          OwnerDraft(name: 'Sukhdev Singh', phone: '+919812345678'),
        ]);
        await _pump(
          tester,
          ledger,
          BusinessOpeningHost(flow: flow, startDate: _start),
        );

        final chart = await ledger.chartOf(flow.businessBookId!);
        final invited = chart
            .byClass(AccountClass.partner)
            .singleWhere((a) => a.name.startsWith('Sukhdev Singh'));
        // Not the creator's id, not the phone number, not the name. This
        // guards against a guessed id only; it is also true at HEAD and says
        // nothing about the defect — F1-07-544 does.
        expect(invited.memberId, isNull);
      },
    );

    testWidgets(
      'F1-07-544 the smallest shared business S0.6a1 can produce (you plus '
      'one invited owner) binds the creating user\'s member id to their own '
      'Partner Current A/c',
      (tester) async {
        final ledger = await _ledger();
        // Exactly what S0.6a1 onSubmit hands the flow at its minimum: two
        // rows, a name on each, a phone on the row that is not you.
        final flow = _sharedBusiness(const [
          OwnerDraft(name: '', isYou: true),
          OwnerDraft(name: 'Sukhdev Singh', phone: '+919812345678'),
        ]);
        await _pump(
          tester,
          ledger,
          BusinessOpeningHost(flow: flow, startDate: _start),
        );

        final chart = await ledger.chartOf(flow.businessBookId!);
        final partners = chart.byClass(AccountClass.partner).toList();
        final mine = partners.singleWhere(
          (a) => a.name.startsWith('Amrit Kaur'),
        );
        final invited = partners.singleWhere(
          (a) => a.name.startsWith('Sukhdev Singh'),
        );
        expect(mine.memberId, ledger.identity.userId);
        expect(invited.memberId, isNull);
      },
      // ⚠️ SPEC / BLOCKER: fails today — `createBook(ownerMemberIds:)` is
      // all-or-none (`local_ledger.dart`), so `OnboardingFlow.ownerMemberIds`
      // must return [] here and the creator's account stays unbound. Needs a
      // nullable id per owner in `shared/ledger` plus the invitee-binding
      // amend no doc defines yet (ADR 2026-09-14b *Open*). Lane report
      // M11-OWN1, `open`.
      skip: true,
    );

    test(
      'F1-07-542 owner names never go without member ids when the owners are '
      'identifiable: the creator-only set always yields the id',
      () {
        final flow = _sharedBusiness(const [
          OwnerDraft(name: 'Amrit Kaur', isYou: true),
        ]);
        expect(flow.ownerNames, ['Amrit Kaur']);
        final ids = flow.ownerMemberIds('user-self');
        expect(ids, isNotEmpty, reason: 'names given, ids identifiable');
        expect(ids, hasLength(flow.ownerNames.length));
        expect(ids, ['user-self']);

        // The unnamed creator row that falls back to the S0.4 name is still
        // the creator.
        final fallback = _sharedBusiness(const [
          OwnerDraft(name: '', isYou: true),
        ]);
        expect(fallback.ownerMemberIds('user-self'), ['user-self']);

        // *Just me* has no owner rows and no Partner Current A/c to bind.
        final justMe = OnboardingFlow()
          ..setYourName('Amrit Kaur')
          ..setBusiness(
            const BusinessDraft(
              name: 'Amrit Kaur Agri',
              ownership: BusinessOwnershipChoice.justMe,
              fyStartMonth: 4,
            ),
          );
        expect(justMe.ownerMemberIds('user-self'), isEmpty);
        // An unknown own id is never replaced by a guess.
        expect(flow.ownerMemberIds(''), isEmpty);
      },
    );
  });
}
