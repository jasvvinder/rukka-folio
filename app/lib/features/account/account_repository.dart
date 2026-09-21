// The account feature's seam to the identity record (06 §9.1 🔒: phone, name,
// photo, language) and to the deletion lifecycle (06 §9.3 🔒,
// ADR 2026-09-05h §2). Phase A: the screens run against
// [FakeAccountRepository]; the real one lands with the auth/server lanes.
//
// ⚠️ WIRE — the whole interface is this lane's; the server's `users` row and
// the deletion endpoint shape it at integration. Nothing here holds money,
// and nothing here holds a key: deletion is requested, never performed, from
// the UI.
import 'dart:async';

import 'package:flutter/widgets.dart';

import 'deletion_window.dart';

/// **There is no photo pipeline in the app** — no picker, no camera path, no
/// storage, no dependency (the M11 row records the same gap). 06 §9.1 lists a
/// photo among the plaintext fields the account *may* hold, so the field is
/// named here and deletion is honest about erasing it; the UI stands initials
/// in its place and says so, rather than drawing a control that does nothing.
const accountPhotoSupported = false;

/// One or two letters standing in for the absent photo: the first *grapheme*
/// of the first two words, in whatever script the name is written — never
/// transliterated, never a silhouette icon. Grapheme, not code unit, so a
/// Gurmukhi or Devanagari letter keeps its matra instead of being cut in half.
String accountInitialsOf(String name) {
  final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
  if (words.isEmpty) return '';
  return words.take(2).map((w) => w.characters.first).join();
}

/// The identity record the user may see and edit (06 §9.1 🔒).
@immutable
final class AccountProfile {
  /// Creates the profile.
  const AccountProfile({
    required this.name,
    required this.phone,
    required this.languageCode,
    this.nameLang = 'en',
  });

  /// The user's own name, as they typed it.
  final String name;

  /// Their own number, in the form they registered it — shown only on their
  /// own device, never rendered anywhere else (ADR 2026-09-05h §3).
  final String phone;

  /// `en` · `pa` · `hi` — the per-member language of 01 §1 rule 1.
  final String languageCode;

  /// Script tag of [name] for screen-reader pronunciation and font choice
  /// (01 §1 rule 9 🔒): a user-typed string carries its own language.
  final String nameLang;

  /// One or two letters standing in for the absent photo
  /// ([accountInitialsOf]).
  String get initials => accountInitialsOf(name);

  /// Copy with a new [name] (and optionally its [nameLang]).
  AccountProfile copyWith({String? name, String? nameLang}) => AccountProfile(
    name: name ?? this.name,
    phone: phone,
    languageCode: languageCode,
    nameLang: nameLang ?? this.nameLang,
  );
}

/// What S16 / S16.1 / S16.3 render.
@immutable
final class AccountSnapshot {
  /// Creates the snapshot.
  const AccountSnapshot({
    required this.profile,
    this.window,
    this.request,
    this.readOnly = false,
  });

  /// The identity record.
  final AccountProfile profile;

  /// A running 15-day cooling period, or null (06 §9.3 🔒).
  final DeletionWindow? window;

  /// A support request waiting to be accepted, or null
  /// (ADR 2026-09-05h §2) — never a clock.
  final DeletionRequest? request;

  /// S12.5 pattern: the account cannot be changed from here (read-only mode).
  /// Deletion and export are never blocked by it — export is plan-independent
  /// (06 §9.2 🔒) and deletion is a right, not a feature.
  final bool readOnly;

  /// Copy. Pass [clearWindow] / [clearRequest] to remove one.
  AccountSnapshot copyWith({
    AccountProfile? profile,
    DeletionWindow? window,
    DeletionRequest? request,
    bool clearWindow = false,
    bool clearRequest = false,
    bool? readOnly,
  }) => AccountSnapshot(
    profile: profile ?? this.profile,
    window: clearWindow ? null : (window ?? this.window),
    request: clearRequest ? null : (request ?? this.request),
    readOnly: readOnly ?? this.readOnly,
  );
}

/// Thrown by repository calls that failed; screens show the error state and
/// keep the way forward (07 §1 rule 6).
final class AccountFailure implements Exception {
  /// Creates the failure.
  const AccountFailure([this.message = '']);

  /// Diagnostic only — never rendered (CLAUDE.md rule 4: no raw codes, 07 §1
  /// rule 12).
  final String message;

  @override
  String toString() => 'AccountFailure($message)';
}

/// What the account screens need.
abstract class AccountRepository {
  /// Current snapshot, then every change. Emits the current value on listen.
  Stream<AccountSnapshot> watch();

  /// Latest snapshot without subscribing; null until the first load.
  AccountSnapshot? get current;

  /// (Re)loads from the server; throws [AccountFailure].
  Future<void> refresh();

  /// S16.1 — renames the account holder (06 §9.1). [lang] is the script the
  /// name is written in (01 §1 rule 9 🔒).
  Future<void> setName(String name, {String lang});

  /// S16.3 — starts the 15-day cooling period from **this** device
  /// (06 §9.3 🔒). Only the user's own certified device may call it.
  Future<void> startDeletion();

  /// S16.3 — accepts a support request and starts the same 15 days
  /// (ADR 2026-09-05h §2).
  Future<void> acceptDeletionRequest(String requestId);

  /// S16.3 — declines a support request. Nothing was running, so nothing
  /// stops; the card goes away.
  Future<void> declineDeletionRequest(String requestId);

  /// S16.3 — cancel-anytime, up to the last second (06 §9.3 🔒).
  Future<void> cancelDeletion();
}

/// In-memory fake for tests and the Phase A shell.
class FakeAccountRepository implements AccountRepository {
  /// Creates the fake over [initial] (null = nothing loaded yet, which is
  /// what makes the loading state reachable in a test).
  FakeAccountRepository({AccountSnapshot? initial, DateTime Function()? now})
    : _current = initial,
      _now = now ?? DateTime.now;

  final _controller = StreamController<AccountSnapshot>.broadcast();
  final DateTime Function() _now;
  AccountSnapshot? _current;

  /// Next call to any method throws this once, then clears.
  AccountFailure? failNext;

  /// Names passed to [setName], with their script tag.
  final renames = <({String name, String lang})>[];

  /// Times [startDeletion] ran.
  int deletionsStarted = 0;

  /// Request ids passed to [acceptDeletionRequest].
  final accepted = <String>[];

  /// Request ids passed to [declineDeletionRequest].
  final declined = <String>[];

  /// Times [cancelDeletion] ran.
  int deletionsCancelled = 0;

  /// What [refresh] loads when it runs (null keeps the current snapshot).
  AccountSnapshot? onRefresh;

  @override
  AccountSnapshot? get current => _current;

  /// Replaces the snapshot and notifies listeners.
  set current(AccountSnapshot? s) {
    _current = s;
    if (s != null) _controller.add(s);
  }

  void _maybeFail() {
    final f = failNext;
    if (f != null) {
      failNext = null;
      throw f;
    }
  }

  @override
  Stream<AccountSnapshot> watch() async* {
    final c = _current;
    if (c != null) yield c;
    yield* _controller.stream;
  }

  @override
  Future<void> refresh() async {
    _maybeFail();
    final next = onRefresh;
    if (next != null) current = next;
  }

  @override
  Future<void> setName(String name, {String lang = 'en'}) async {
    _maybeFail();
    renames.add((name: name, lang: lang));
    final c = _current;
    if (c != null) {
      current = c.copyWith(
        profile: c.profile.copyWith(name: name, nameLang: lang),
      );
    }
  }

  @override
  Future<void> startDeletion() async {
    _maybeFail();
    deletionsStarted++;
    _start(DeletionOrigin.user, 'del-${_now().microsecondsSinceEpoch}');
  }

  @override
  Future<void> acceptDeletionRequest(String requestId) async {
    _maybeFail();
    accepted.add(requestId);
    _start(DeletionOrigin.support, requestId);
    final c = _current;
    if (c != null) current = c.copyWith(clearRequest: true);
  }

  @override
  Future<void> declineDeletionRequest(String requestId) async {
    _maybeFail();
    declined.add(requestId);
    final c = _current;
    if (c != null) current = c.copyWith(clearRequest: true);
  }

  @override
  Future<void> cancelDeletion() async {
    _maybeFail();
    deletionsCancelled++;
    final c = _current;
    if (c != null) current = c.copyWith(clearWindow: true);
  }

  void _start(DeletionOrigin origin, String id) {
    final c = _current;
    if (c == null) return;
    current = c.copyWith(
      window: DeletionWindow(id: id, origin: origin, startedAt: _now()),
    );
  }

  /// Closes the stream.
  Future<void> dispose() => _controller.close();
}

/// Provides the repository to the account screens. Integration wraps the app
/// in one; absent, screens fall back to a shared empty fake so a shell-only
/// test still renders rather than throwing.
class AccountRepositoryScope extends InheritedWidget {
  /// Creates the scope.
  const AccountRepositoryScope({
    super.key,
    required this.repository,
    required super.child,
  });

  /// The repository the screens below read.
  final AccountRepository repository;

  static final _fallback = FakeAccountRepository(
    initial: const AccountSnapshot(
      profile: AccountProfile(name: '', phone: '', languageCode: 'en'),
    ),
  );

  /// The nearest repository, or the fallback.
  static AccountRepository of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<AccountRepositoryScope>()
          ?.repository ??
      _fallback;

  @override
  bool updateShouldNotify(AccountRepositoryScope old) =>
      repository != old.repository;
}
