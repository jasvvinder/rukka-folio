// The answers onboarding collects before anything is written (07 §3.1,
// §3.1.1). Onboarding is a chain of separate routes, so the answers cannot
// live in one screen's state: S0.4's name is needed again on S0.6a1 (the
// creating user is the first owner row, ADR 2026-09-09 §1) and the S0.6a /
// S0.6a1 answers are needed together at the committing step, where
// `createBook` finally runs.
//
// Deliberately a plain holder, not a store: nothing here is persisted and
// nothing is posted. The ledger is written once, at the commit, and from then
// on the book is the source of truth.
import 'package:flutter/widgets.dart';

import 'screens/s0_3_purpose_screen.dart';
import 'screens/s0_6a1_business_owners_screen.dart';
import 'screens/s0_6a_business_name_screen.dart';
import 'screens/s0_6d_family_name_screen.dart';
import 'screens/s0_6e_family_members_screen.dart';

/// The answers gathered so far. Mutated in place by the route callbacks; read
/// by the steps that need an earlier answer.
class OnboardingFlow extends ChangeNotifier {
  /// The user's own name (S0.4, 07 §3.1 step 4). Empty until they answer.
  String yourName = '';

  /// The purpose card chosen on S0.3, which branches the setup (07 §3.1.1).
  OnboardingPurpose? purpose;

  /// The S0.6a answers — name, ownership, FY start.
  BusinessDraft? business;

  /// The S0.6a1 owners, first row the creating user (ADR 2026-09-09 §1).
  /// Empty on the *Just me* branch.
  List<OwnerDraft> owners = const [];

  /// The book created at the committing step, once it exists. Set so a
  /// resumed step (07 §3.1.1: every branch step is resumable) never creates
  /// a second book for the same answers.
  String? businessBookId;

  /// The S0.6d answer — the family's name. Null on every other branch.
  FamilyDraft? family;

  /// The S0.6e invited heads. Empty on *Skip for now* and on every other
  /// branch.
  List<FamilyMemberDraft> familyMembers = const [];

  /// The pool book created at S0.6f, once it exists (07 §3.1.1: resumable —
  /// never a second book for the same answers).
  String? familyBookId;

  /// Whether a recovery sheet has been generated and is still waiting to be
  /// scanned back (S0.5b, 04 §7.4 🔒 verified-storage nag). Null until S0.5b
  /// has produced a sheet at all — a skipped step is not a verified one, and
  /// the Menu badge the nag lives on reads this.
  ///
  /// ⚠️ SPEC: 07 §3.1 step 6 puts the badge on **Menu**, which is another
  /// feature's surface; onboarding can only record the fact. Carrying it to
  /// Menu (and persisting it across a restart) is in the lane report.
  bool? recoverySheetVerified;

  /// Records S0.5b's outcome.
  void setRecoverySheetVerified(bool verified) {
    recoverySheetVerified = verified;
    notifyListeners();
  }

  /// Records S0.4's answer.
  void setYourName(String name) {
    yourName = name.trim();
    notifyListeners();
  }

  /// Records S0.3's answer.
  void setPurpose(OnboardingPurpose value) {
    purpose = value;
    notifyListeners();
  }

  /// Records S0.6a's answers. Changing them invalidates any owners collected
  /// under the previous ownership choice.
  void setBusiness(BusinessDraft draft) {
    business = draft;
    if (draft.ownership == BusinessOwnershipChoice.justMe) owners = const [];
    notifyListeners();
  }

  /// Records S0.6a1's answers.
  void setOwners(List<OwnerDraft> value) {
    owners = List.unmodifiable(value);
    notifyListeners();
  }

  /// Records S0.6d's answer.
  void setFamily(FamilyDraft draft) {
    family = draft;
    notifyListeners();
  }

  /// Records S0.6e's answers.
  void setFamilyMembers(List<FamilyMemberDraft> value) {
    familyMembers = List.unmodifiable(value);
    notifyListeners();
  }

  /// The owner names `createBook` seeds one Partner Current A/c from, in the
  /// order S0.6a1 showed them (ADR 2026-09-09c §1). Unnamed rows fall back to
  /// the creating user's own name for row one and are dropped otherwise —
  /// an account with no name would be a chore, not a seed.
  List<String> get ownerNames => [
    for (final (i, o) in owners.indexed)
      if (o.name.trim().isNotEmpty)
        o.name.trim()
      else if (i == 0 && yourName.isNotEmpty)
        yourName,
  ];
}

/// The [OnboardingFlow] for the widget tree below.
class OnboardingFlowScope extends InheritedNotifier<OnboardingFlow> {
  /// Wraps [child] with [flow].
  const OnboardingFlowScope({
    super.key,
    required OnboardingFlow flow,
    required super.child,
  }) : super(notifier: flow);

  /// The flow, or null when no scope is mounted (a screen pumped alone).
  static OnboardingFlow? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<OnboardingFlowScope>()
      ?.notifier;

  /// The flow; throws when onboarding is not mounted.
  static OnboardingFlow of(BuildContext context) {
    final flow = maybeOf(context);
    if (flow == null) {
      throw FlutterError('No OnboardingFlowScope above this widget');
    }
    return flow;
  }
}
