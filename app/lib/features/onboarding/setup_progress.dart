// What the S0.7 setup checklist needs to know about sign-up after the chain
// has handed over to Home (ADR 2026-10-07 ruling 3), kept on the device so the
// rows survive a cold start (ADR 2026-10-06b ruling 2):
//
// - the purpose card chosen on S0.3 — which also lets a chain resumed after a
//   cold start take the right branch instead of dropping it (the old
//   `onboarding_gate.dart` ⚠️ SPEC);
// - the one branch step that may be skipped and brought back: the family's or
//   trust's invite step (S0.6e / S0.6h, ruling 2), open · done · not needed;
// - whether the printed recovery sheet has been scanned back (04 §7.4).
//
// Not financial data: a purpose name, a state, a book id and one bit. Kept in
// the same protected device store as the shell's other small values
// ([RkPrefs]); every key is in [RkPrefKeys]. An unreadable store reads as
// "nothing recorded" — the conservative reading, which leaves a row open as a
// door rather than hiding one (07 §1 rule 6).
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../shared/prefs.dart';
import 'screens/s0_3_purpose_screen.dart' show OnboardingPurpose;

/// Where the skipped invite step stands.
enum SetupBranchState {
  /// Skipped and not yet done — the checklist shows *Finish* + the book's
  /// name.
  open,

  /// Done from the checklist — the row ticks and strikes through.
  done,

  /// ⋮ → *Not needed* — the row is hidden; nothing is deleted.
  notNeeded,
}

/// The family's or trust's skipped invite step.
@immutable
final class SetupBranch {
  /// Creates the record.
  const SetupBranch({required this.purpose, required this.state, this.bookId});

  /// [OnboardingPurpose.family] or [OnboardingPurpose.trust] — the only
  /// branches with a skippable step (ADR 2026-10-07 ruling 2).
  final OnboardingPurpose purpose;

  /// Open, done or not needed.
  final SetupBranchState state;

  /// The branch's book (the joint fund's or the trust's), once S0.6f / S0.6i
  /// has made it; null before.
  final String? bookId;

  /// A copy with [state] / [bookId] replaced.
  SetupBranch copyWith({SetupBranchState? state, String? bookId}) =>
      SetupBranch(
        purpose: purpose,
        state: state ?? this.state,
        bookId: bookId ?? this.bookId,
      );

  String _encode() => jsonEncode({
    'purpose': purpose.name,
    'state': state.name,
    'book': ?bookId,
  });

  static SetupBranch? _decode(String? raw) {
    if (raw == null) return null;
    try {
      final map = jsonDecode(raw);
      if (map is! Map) return null;
      final purpose = _purposeNamed(map['purpose']);
      final state = SetupBranchState.values
          .where((s) => s.name == map['state'])
          .firstOrNull;
      if (purpose == null || state == null) return null;
      final book = map['book'];
      return SetupBranch(
        purpose: purpose,
        state: state,
        bookId: book is String && book.isNotEmpty ? book : null,
      );
    } on Object {
      return null;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is SetupBranch &&
      other.purpose == purpose &&
      other.state == state &&
      other.bookId == bookId;

  @override
  int get hashCode => Object.hash(purpose, state, bookId);
}

/// A branch book sign-up made (S0.6b / S0.6f / S0.6i), kept on the device
/// so a cold start resumes over it rather than making another (ADR
/// 2026-10-06b ruling 2 🔒; 07 §3.1.1).
@immutable
final class SetupBranchBook {
  /// Creates the record.
  const SetupBranchBook({
    required this.purpose,
    required this.bookId,
    this.shared = false,
  });

  /// The purpose card whose branch made the book.
  final OnboardingPurpose purpose;

  /// The book `createBook` returned.
  final String bookId;

  /// A business S0.6a marked *Shared with others*; false otherwise. Not kept
  /// by the book projection, and S0.6c's recap and S0.6b's Back read it.
  final bool shared;

  Map<String, Object> _toJson() => {
    'purpose': purpose.name,
    'book': bookId,
    if (shared) 'shared': true,
  };

  static SetupBranchBook? _fromJson(Object? json) {
    if (json is! Map) return null;
    final purpose = _purposeNamed(json['purpose']);
    final book = json['book'];
    if (purpose == null || book is! String || book.isEmpty) return null;
    return SetupBranchBook(
      purpose: purpose,
      bookId: book,
      shared: json['shared'] == true,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SetupBranchBook &&
      other.purpose == purpose &&
      other.bookId == bookId &&
      other.shared == shared;

  @override
  int get hashCode => Object.hash(purpose, bookId, shared);
}

OnboardingPurpose? _purposeNamed(Object? name) =>
    OnboardingPurpose.values.where((p) => p.name == name).firstOrNull;

/// The device record of sign-up's progress, read by the S0.7 checklist.
abstract final class SetupProgress {
  /// Bumped on every write, so Home re-reads the rows without a restart.
  static final ValueNotifier<int> changes = ValueNotifier<int>(0);

  static Future<String?> _read(RkPrefs? prefs, String key) async {
    if (prefs == null) return null;
    try {
      return await prefs.read(key);
    } on Object {
      return null;
    }
  }

  static Future<void> _write(RkPrefs? prefs, String key, String? value) async {
    if (prefs != null) {
      try {
        if (value == null) {
          await prefs.remove(key);
        } else {
          await prefs.write(key, value);
        }
      } on Object {
        // Nothing to report: the row reads as not recorded, still a door.
      }
    }
    changes.value++;
  }

  /// The purpose chosen on S0.3, or null.
  static Future<OnboardingPurpose?> purpose(RkPrefs? prefs) async =>
      _purposeNamed(await _read(prefs, RkPrefKeys.setupPurpose));

  /// Records S0.3's answer.
  static Future<void> recordPurpose(RkPrefs? prefs, OnboardingPurpose value) =>
      _write(prefs, RkPrefKeys.setupPurpose, value.name);

  /// The skipped invite step, or null when nothing was skipped.
  static Future<SetupBranch?> branch(RkPrefs? prefs) async =>
      SetupBranch._decode(await _read(prefs, RkPrefKeys.setupBranch));

  /// S0.6e / S0.6h *Skip for now* inside the chain: the step is open. A book
  /// already made for [purpose] (a second pass) is kept.
  static Future<void> invitesSkipped(
    RkPrefs? prefs,
    OnboardingPurpose purpose, {
    String? bookId,
  }) async {
    final before = await branch(prefs);
    final keep = before != null && before.purpose == purpose
        ? before.bookId
        : null;
    await _write(
      prefs,
      RkPrefKeys.setupBranch,
      SetupBranch(
        purpose: purpose,
        state: SetupBranchState.open,
        bookId: bookId ?? keep,
      )._encode(),
    );
  }

  /// S0.6e / S0.6h *Continue* inside the chain: nothing was skipped, so the
  /// checklist has no branch row at all (ruling 3: the row appears only
  /// while the invite step was skipped).
  static Future<void> invitesAnsweredInChain(RkPrefs? prefs) =>
      _write(prefs, RkPrefKeys.setupBranch, null);

  /// Moves an existing record to [state]; a no-op when there is none.
  static Future<void> setBranchState(
    RkPrefs? prefs,
    SetupBranchState state,
  ) async {
    final before = await branch(prefs);
    if (before == null) return;
    await _write(
      prefs,
      RkPrefKeys.setupBranch,
      before.copyWith(state: state)._encode(),
    );
  }

  /// S0.6f / S0.6i made the branch book: remember which book the row names.
  /// Only an open record for the same [purpose] takes it.
  static Future<void> attachBook(
    RkPrefs? prefs,
    OnboardingPurpose purpose,
    String bookId,
  ) async {
    final before = await branch(prefs);
    if (before == null ||
        before.purpose != purpose ||
        before.bookId == bookId) {
      return;
    }
    await _write(
      prefs,
      RkPrefKeys.setupBranch,
      before.copyWith(bookId: bookId)._encode(),
    );
  }

  /// The branch books sign-up has made, oldest first; empty when none (or
  /// when the store cannot be read — the chain then asks the name, the
  /// pre-existing behaviour).
  static Future<List<SetupBranchBook>> branchBooks(RkPrefs? prefs) async {
    final raw = await _read(prefs, RkPrefKeys.setupBranchBooks);
    if (raw == null) return const [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return const [];
      return [for (final item in list) ?SetupBranchBook._fromJson(item)];
    } on Object {
      return const [];
    }
  }

  /// The committing step's `createBook` made [book]: keep it, once.
  static Future<void> recordBranchBook(
    RkPrefs? prefs,
    SetupBranchBook book,
  ) async {
    final before = await branchBooks(prefs);
    if (before.any((b) => b.bookId == book.bookId)) return;
    await _write(
      prefs,
      RkPrefKeys.setupBranchBooks,
      jsonEncode([
        for (final b in [...before, book]) b._toJson(),
      ]),
    );
  }

  /// True once the printed recovery sheet was scanned back (04 §7.4).
  static Future<bool> recoverySheetVerified(RkPrefs? prefs) async =>
      await _read(prefs, RkPrefKeys.recoverySheetVerified) == '1';

  /// Records S0.5b's check. `true`: a printed sheet was checked back.
  /// `false`: a **new** sheet was made — it is not yet checked, and the sheet
  /// checked before no longer works (04 §7.4: regenerating rotates RK), so
  /// the S0.7 row opens again. A failed check records nothing.
  static Future<void> recordRecoverySheetVerified(
    RkPrefs? prefs,
    bool verified,
  ) async {
    await _write(
      prefs,
      RkPrefKeys.recoverySheetVerified,
      verified ? '1' : null,
    );
  }
}
