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
import 'screens/s0_6g_trust_name_screen.dart';
import 'screens/s0_6h_trust_members_screen.dart';

/// The answers gathered so far. Mutated in place by the route callbacks; read
/// by the steps that need an earlier answer.
class OnboardingFlow extends ChangeNotifier {
  /// The user's own name (S0.4, 07 §3.1 step 4). Empty until they answer.
  String yourName = '';

  /// The purpose card chosen on S0.3, which branches the setup (07 §3.1.1).
  OnboardingPurpose? purpose;

  /// Every business this onboarding has collected, in the order they were
  /// named. The *My businesses* card loops O6a → O6b → **O6c** → O6a
  /// (07 §3.1.1), so one answer set is never enough: each pass appends an
  /// entry and each entry becomes its own book.
  ///
  /// The single-business accessors below ([business], [owners],
  /// [businessBookId]) all read and write **the entry being collected now**,
  /// which is why S0.6a, S0.6a1 and the committing step need no idea that a
  /// list exists.
  List<BusinessEntry> get businesses => List.unmodifiable(_businesses);
  final List<BusinessEntry> _businesses = [];

  /// Index of the business being collected. Equal to `_businesses.length`
  /// between S0.6c's *Add another* and the next S0.6a answer — that is what
  /// makes the loop's S0.6a blank rather than a re-edit of the last one.
  int _cursor = 0;

  /// The names of the businesses collected so far, for S0.6c's recap. An
  /// entry whose S0.6a is still unanswered contributes nothing.
  List<String> get businessNames => [
    for (final b in _businesses)
      if (b.draft case final draft?) draft.name,
  ];

  BusinessEntry? get _current =>
      _cursor < _businesses.length ? _businesses[_cursor] : null;

  BusinessEntry _ensureCurrent() {
    while (_businesses.length <= _cursor) {
      _businesses.add(BusinessEntry());
    }
    return _businesses[_cursor];
  }

  /// The S0.6a answers of the business being collected — name, ownership, FY
  /// start. Null on a fresh pass round the loop.
  BusinessDraft? get business => _current?.draft;

  /// The S0.6a1 owners of the business being collected, first row the
  /// creating user (ADR 2026-09-09 §1). Empty on the *Just me* branch.
  List<OwnerDraft> get owners => _current?.owners ?? const [];

  /// The book created at the committing step for the business being
  /// collected, once it exists. Set so a resumed step (07 §3.1.1: every
  /// branch step is resumable) never creates a second book for the same
  /// answers.
  String? get businessBookId => _current?.bookId;

  set businessBookId(String? value) {
    _ensureCurrent().bookId = value;
    notifyListeners();
  }

  /// S0.6c's *Add another business* (07 §3.1.1: O6c loops back to O6a).
  /// Moves the cursor past the finished entry so the next [setBusiness]
  /// starts a new business instead of editing the last one — nothing
  /// already collected is touched, and nothing already created is re-created.
  void addAnotherBusiness() {
    _cursor = _businesses.length;
    notifyListeners();
  }

  /// The S0.6d answer — the family's name. Null on every other branch.
  FamilyDraft? family;

  /// The S0.6e invited heads. Empty on *Skip for now* and on every other
  /// branch.
  List<FamilyMemberDraft> familyMembers = const [];

  /// The pool book created at S0.6f, once it exists (07 §3.1.1: resumable —
  /// never a second book for the same answers).
  String? familyBookId;

  /// The S0.6g answer — the trust's name and illustrative type. Null on
  /// every other branch.
  TrustDraft? trust;

  /// The S0.6h invited committee. Empty on *Skip for now* and on every other
  /// branch.
  List<TrustMemberDraft> trustMembers = const [];

  /// The trust book created at S0.6i, once it exists (07 §3.1.1: resumable —
  /// never a second book for the same answers).
  String? trustBookId;

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

  /// Records S0.6a's answers for the business being collected. Changing them
  /// invalidates any owners collected under the previous ownership choice.
  void setBusiness(BusinessDraft draft) {
    final entry = _ensureCurrent();
    entry.draft = draft;
    if (draft.ownership == BusinessOwnershipChoice.justMe) {
      entry.owners = const [];
    }
    notifyListeners();
  }

  /// Records S0.6a1's answers for the business being collected.
  void setOwners(List<OwnerDraft> value) {
    _ensureCurrent().owners = List.unmodifiable(value);
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

  /// Records S0.6g's answer.
  void setTrust(TrustDraft draft) {
    trust = draft;
    notifyListeners();
  }

  /// Records S0.6h's answers.
  void setTrustMembers(List<TrustMemberDraft> value) {
    trustMembers = List.unmodifiable(value);
    notifyListeners();
  }

  /// The owners `createBook` seeds one Partner Current A/c each from, in the
  /// order S0.6a1 showed them (ADR 2026-09-09c §1). Unnamed rows fall back to
  /// the creating user's own name for row one and are dropped otherwise —
  /// an account with no name would be a chore, not a seed.
  ///
  /// Name and weight are taken in **one pass** so they cannot drift apart: a
  /// dropped row must drop its weight too, or every later owner would be
  /// seeded with the share of the one before them (ADR 2026-09-09 §2 — the
  /// ratio is fixed at creation and never re-asked).
  List<({String name, int shares})> get ownerSeeds => [
    for (final (i, o) in owners.indexed)
      if (o.name.trim().isNotEmpty)
        (name: o.name.trim(), shares: o.shares)
      else if (i == 0 && yourName.isNotEmpty)
        (name: yourName, shares: o.shares),
  ];

  /// The seeded partner account names, in S0.6a1 order.
  List<String> get ownerNames => [for (final o in ownerSeeds) o.name];

  /// The share weights of [ownerNames], index for index (02 §7.1 🔒 divides by
  /// weight). Empty when no owners were collected — *Just me*, or a branch
  /// that never reached S0.6a1 — so nothing is recorded rather than a ratio
  /// being invented.
  List<int> get ownerShares => [for (final o in ownerSeeds) o.shares];
}

/// One business collected by the branch: its S0.6a answers, its S0.6a1 owners
/// and the book it became. The *My businesses* card can produce several
/// (07 §3.1.1 O6c), and each becomes its own book through the ordinary seed
/// path (ADR 2026-09-09c §3, ADR 2026-09-09d §1) — nothing about `createBook`
/// changes because there are now two of them.
///
/// The S0.6a1 **share weights** ([OwnerDraft.shares]) are held here only until
/// the committing step: `createBook` writes them into that business's
/// `book_config` envelope keyed by Partner Current A/c id, which is where
/// 02 §7.1's division reads its ratio from afterwards. Per business, never per
/// flow — two businesses collected by the O6c loop have two ratios.
final class BusinessEntry {
  /// Creates an entry; every field is filled as its step is answered.
  BusinessEntry({this.draft, this.owners = const [], this.bookId});

  /// The S0.6a answers, once that step has been answered.
  BusinessDraft? draft;

  /// The S0.6a1 owners; empty on the *Just me* branch.
  List<OwnerDraft> owners;

  /// The book created for this business at the committing step.
  String? bookId;
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
