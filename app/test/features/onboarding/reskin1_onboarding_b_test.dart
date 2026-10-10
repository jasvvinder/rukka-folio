// RESKIN1 audit captures for the onboarding branch steps (ADR 2026-10-05 §2;
// ADR 2026-10-10b §1; PLAN desk 142). Phase 1 is an audit: these captures are
// paired against the canvas frames and the differences recorded in
// design/match/<S-id>.json — no production code changes with them.
//
// Each state mirrors what the frame draws (canvas number in brackets):
// S0.6a  default   — 'Sharma Textile', FY 1 April (c1/c12 "Name the business").
// S0.6a1 equal     — you + two owners to invite, 1 share each (c1 "Who owns it").
// S0.6a1 different — the same three at 2:1:1 (c1 "Different shares").
// S0.6c  default   — one business added (c1/c12 "Add another business?").
// S0.6d  default   — 'Sharma Family' (c1/c13 "Name the family").
// S0.6e  default   — two household heads to invite (c1/c13 "Who else is in it?").
// S0.6f  filled    — the seeded 'Joint Cash A/c' with a figure (c13 "The
//                    family's shared accounts"); the ₹0 default is captured by
//                    s0_6_branch_openings_design_test.dart.
// S0.6g  default   — 'Singh Sabha Gurudwara', gurudwara (c1/c14 "Name the trust").
// S0.6h  default   — chairman, president, trustees, sevadars (c1/c14 "Who runs it?").
// S0.6i  filled    — the seeded 'Cash' and 'Gollak Cash' with figures (c14
//                    "The trust's accounts · gollak"); the ₹0 default is in the
//                    branch-openings capture.
//
// S0.6f/S0.6i show only what production can reach: the rows are the seeded
// names (LocalLedger.defaultCashName, gollakName) and no onAddAccount is
// passed, because no route passes one (onboarding_routes.dart — Family/
// TrustOpeningHost), so '+ Add a bank account' is drawn disabled and the
// frames' bank rows cannot be captured. Recorded in S0.6f/S0.6i.json.
@Tags(['F1'])
library;

import 'package:core_ledger/core_ledger.dart' show LocalDate;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/onboarding/onboarding_routes.dart';
import 'package:rukka_folio/features/onboarding/screens/s0_6g_trust_name_screen.dart'
    show TrustType;

import '../../shared/design_capture.dart';

final _start = LocalDate(2026, 9, 9);

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 1));
}

Future<void> _both(
  WidgetTester tester,
  String sid,
  String state,
  Widget Function() build,
) async {
  for (final target in RkDesignTarget.values) {
    await rkDesignCapture(
      tester,
      sid: sid,
      state: state,
      target: target,
      child: build(),
    );
    await _unmount(tester);
  }
}

const _owners = [
  OwnerDraft(name: 'Amrit Kaur', isYou: true),
  OwnerDraft(name: 'Sukhdev Singh', phone: '98140 22119'),
  OwnerDraft(name: 'Harjit Kaur', phone: '99155 40712'),
];

void main() {
  testWidgets('F1-R1B-1 design capture S0.6a (default)', (tester) async {
    await _both(
      tester,
      'S0.6a',
      'default',
      () => BusinessNameScreen(
        startDate: _start,
        onSubmit: (_) {},
        initial: const BusinessDraft(
          name: 'Sharma Textile',
          ownership: BusinessOwnershipChoice.justMe,
          fyStartMonth: 4,
        ),
      ),
    );
  });

  testWidgets('F1-R1B-2 design capture S0.6a1 (equal · different)', (
    tester,
  ) async {
    await _both(
      tester,
      'S0.6a1',
      'equal',
      () => BusinessOwnersScreen(
        yourName: 'Amrit Kaur',
        onSubmit: (_) {},
        onJustMeAfterAll: () {},
        initialOwners: _owners,
      ),
    );
    await _both(
      tester,
      'S0.6a1',
      'different',
      () => BusinessOwnersScreen(
        yourName: 'Amrit Kaur',
        onSubmit: (_) {},
        onJustMeAfterAll: () {},
        initialOwners: [_owners[0].copyWith(shares: 2), _owners[1], _owners[2]],
      ),
    );
  });

  testWidgets('F1-R1B-3 design capture S0.6c (default)', (tester) async {
    await _both(
      tester,
      'S0.6c',
      'default',
      () => AddAnotherBusinessScreen(
        businesses: const [
          AddedBusiness(name: 'Sharma Textile', fyStartMonth: 4),
        ],
        onAddAnother: () {},
        onDone: () {},
        // Production passes Skip (onboarding_routes.dart, S0.6c route).
        onSkip: () {},
      ),
    );
  });

  testWidgets('F1-R1B-4 design capture S0.6d (default)', (tester) async {
    await _both(
      tester,
      'S0.6d',
      'default',
      () => FamilyNameScreen(
        startDate: _start,
        onSubmit: (_) {},
        initial: const FamilyDraft(name: 'Sharma Family'),
      ),
    );
  });

  testWidgets('F1-R1B-5 design capture S0.6e (default)', (tester) async {
    await _both(
      tester,
      'S0.6e',
      'default',
      () => FamilyMembersScreen(
        yourName: 'Ramesh Sharma',
        onSubmit: (_) {},
        onSkip: () {},
        initialMembers: const [
          FamilyMemberDraft(name: 'Ramesh Sharma', isYou: true),
          FamilyMemberDraft(name: 'Pankaj Sharma', phone: '98140 22119'),
          FamilyMemberDraft(name: 'Geeta Sharma', phone: '99155 40712'),
        ],
      ),
    );
  });

  testWidgets('F1-R1B-6 design capture S0.6f (filled)', (tester) async {
    await _both(
      tester,
      'S0.6f',
      'filled',
      () => FamilySharedAccountsScreen(
        rows: const [
          OpeningRow(
            accountId: 'cash',
            name: 'Joint Cash A/c',
            group: OpeningGroup.have,
            initialPaise: 1880000,
          ),
        ],
        startDate: _start,
        onSave: (_) {},
      ),
    );
  });

  testWidgets('F1-R1B-7 design capture S0.6g (default)', (tester) async {
    await _both(
      tester,
      'S0.6g',
      'default',
      () => TrustNameScreen(
        startDate: _start,
        onSubmit: (_) {},
        initial: const TrustDraft(
          name: 'Singh Sabha Gurudwara',
          type: TrustType.gurudwara,
        ),
      ),
    );
  });

  testWidgets('F1-R1B-8 design capture S0.6h (default)', (tester) async {
    await _both(
      tester,
      'S0.6h',
      'default',
      () => TrustMembersScreen(
        yourName: 'Harjit Singh',
        onSubmit: (_) {},
        onSkip: () {},
        initialMembers: const [
          TrustMemberDraft(
            name: 'Harjit Singh',
            isYou: true,
            role: TrustRole.chairman,
          ),
          TrustMemberDraft(
            name: 'Amritpal Singh',
            phone: '98140 22119',
            role: TrustRole.president,
          ),
          TrustMemberDraft(
            name: 'Gurpreet Kaur',
            phone: '99155 40712',
            role: TrustRole.trustee,
          ),
          TrustMemberDraft(
            name: 'Balwant Singh',
            phone: '98722 10045',
            role: TrustRole.sevadar,
          ),
        ],
      ),
    );
  });

  testWidgets('F1-R1B-9 design capture S0.6i (filled)', (tester) async {
    await _both(
      tester,
      'S0.6i',
      'filled',
      () => TrustAccountsScreen(
        rows: const [
          OpeningRow(accountId: 'cash', name: 'Cash', group: OpeningGroup.have),
          OpeningRow(
            accountId: 'gollak',
            name: 'Gollak Cash',
            group: OpeningGroup.have,
            initialPaise: 10240000,
            isCollection: true,
          ),
        ],
        startDate: _start,
        onSave: (_) {},
      ),
    );
  });
}
