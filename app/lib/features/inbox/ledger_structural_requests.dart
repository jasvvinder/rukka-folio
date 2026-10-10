// [StructuralRequests] over the real ledger — what S6's structural section and
// S6.3 read and write through in the shipped app (07 §26 🔒, 02 §7.2.1 🔒,
// 13 §3.2 row S6.3). Until desk 200 (c) nothing implemented the seam and
// `StructuralRequestsScope.of` fell back to an empty fake in production.
//
// It is a **composer**, not a decider. Every judgement is somebody else's:
//
//   * what is in force and who the owners are — `packages/data`'s
//     `readStructuralState` (ADR 2026-09-14b §2, §3, §5);
//   * where a request stands — `core_ledger`'s `evaluateStructural`
//     (A-02-94, A-02-95): the count, the threshold, the veto, the 14 days;
//   * signing — `LocalLedger.authorStructural`, which seals one
//     `structural_approval` envelope under the book key, signs it with this
//     device's key and queues it for push. It applies nothing (02 §7.2.1 🔒).
//
// What it adds is the one rule none of those apply: **who signed it**. Sync
// verifies an envelope's signature chain (04 §8 rule 3), which proves *which
// device* authored it; the `by_user` inside the payload is a claim like any
// other. 02 §7.2.1 🔒 counts an approval because *"each approval is authored
// on that owner's own device"*, so a record is read here only when the device
// that signed it is certified to the user it names (`signerOf` — in the app
// `certifiedSignerOf`, which re-runs the signature chain over the stored
// envelope at every read: the certificate under its user's ceremony-verified
// UMK, the envelope's own signature under the certified device key; never
// the server's `devices` row). A member's phone cannot approve, veto or
// initiate in an owner's name.
//
// A record whose signer this phone **cannot yet name** — no certificate it
// can check: one this install has never held, before the meta read brings
// it (the engine keeps certificates in memory only; the composition root's
// signer also reads the ones this install retained when they proved a
// signature, so a removed member's records stay nameable — review
// TRUSTWIRE-1) — is not the same as one signed in somebody else's name. It is
// not counted, but it is not dropped either: the book is marked *signers
// unconfirmed*, every request in it withholds Approve and Veto with that
// reason, and the snapshot carries how many records wait (S6 says so). An
// unseen veto must never leave a request reading open and signable
// (02 §7.2.1 🔒 *any owner may veto, which closes the request immediately*).
//
// `LocalLedger.structuralStateOf` — the ratio and interest a distribution
// applies — makes the same per-envelope judgement since TRUSTWIRE (its
// `structuralSignerOf`, the same chain over the same certificates, through
// `wireLedgerTrust`), so the Inbox and the fold agree on who signed.
//
// The opening loop below repeats `LocalLedger.structuralStateOf`'s, because
// that method returns the reading but not the events, and the events are what
// S6.3 draws. ⚠️ It belongs on `LocalLedger` (`structuralEventsOf`) — reported.
//
// No plaintext financial data leaves this file in an error (CLAUDE.md rule 4):
// failures carry a type name and a reason enum, never a payload.
//
// Money is signed integer paise (CLAUDE.md rule 1).
import 'dart:async';
import 'dart:typed_data';

import 'package:core_crypto/core_crypto.dart' show Envelope, suiteVersion;
import 'package:core_ledger/core_ledger.dart';
import 'package:data/data.dart'
    show
        BlobHeader,
        BlobOk,
        CryptoPayloadOpener,
        EnvelopesLocalData,
        BookConfig,
        BookConfigVersion,
        BooksPData,
        BusinessSetting,
        StructuralReading,
        partnerSharesInForce,
        readStructuralState;
import 'package:drift/drift.dart'
    show BooleanExpressionOperators, OrderingTerm, TableUpdateQuery;
import 'package:flutter/foundation.dart' show immutable;

import '../../shared/ledger/local_ledger.dart';
import 'structural_requests.dart';

/// The object types the structural reading needs, from the mirror.
const _structuralTypes = [
  'book_config',
  'structural_approval',
  'business_setting',
];

/// One envelope of a book's structural stream, opened — what
/// [readStructuralBook] reads. Built from a mirror row that is verified and
/// not quarantined, whose blob decrypted once.
@immutable
final class OpenedStructuralEnvelope {
  /// Creates the envelope.
  const OpenedStructuralEnvelope({
    required this.envelopeId,
    required this.objectId,
    required this.bookId,
    required this.objectType,
    required this.authorDevice,
    required this.authorSeq,
    required this.hlc,
    required this.json,
    this.seq,
    this.sealed,
  });

  /// Envelope id.
  final String envelopeId;

  /// The object the envelope carries — for a `structural_approval`, the event
  /// itself.
  final String objectId;

  /// The book the envelope was routed in (and sealed to: it is in the
  /// blob's associated data).
  final String bookId;

  /// `book_config`, `structural_approval` or `business_setting`.
  final String objectType;

  /// The device whose signature the envelope carries.
  final String authorDevice;

  /// Its per-author sequence.
  final int authorSeq;

  /// Raw HLC.
  final int hlc;

  /// The decrypted payload.
  final Map<String, Object?> json;

  /// The server `seq`, once known — a revocation cut-off is a `seq`
  /// (ADR 2026-09-05b §5).
  final int? seq;

  /// The envelope as signed — routing fields and the stored blob, which
  /// carries the author's signature (`nonce ‖ author_sig ‖ ciphertext`) — so
  /// a reader can re-check *who signed it* rather than trust a flag set
  /// under certificates that may since have changed. Null where the mirror's
  /// opener is not the crypto one (no signature can be checked: nobody).
  final Envelope? sealed;
}

/// Whose signature [envelope] carries **at this read** — the user its author
/// device is certified to, by a chain that verifies now — or null when this
/// phone cannot say. The app's is `certifiedSignerOf` (certified_signer.dart).
typedef StructuralSigner = String? Function(OpenedStructuralEnvelope envelope);

/// Why a structural envelope was not read. Typed so a caller branches on the
/// rule (05 §9: a typed state, never a string).
enum StructuralEnvelopeRefusal {
  /// This build cannot decode it (an unknown phase or action, a malformed
  /// field). Nothing is approved by something nobody can read.
  unreadable,

  /// The payload's `id` is not the object id the envelope carries.
  notThisObject,

  /// The payload names another book than the one it was routed in.
  otherBook,

  /// The device that signed it is certified to **another** user than the one
  /// the payload names (02 §7.2.1 🔒) — a record signed in somebody else's
  /// name. It is never counted; the rest of the book still reads.
  signerNotBound,

  /// This phone cannot yet say whose device signed it: no certificate it can
  /// verify names the device (none arrived yet, or it does not verify under
  /// its user's ceremony-verified UMK). Not counted — and the whole book's
  /// requests withhold a decision until it can be read
  /// ([StructuralItem.signersConfirmed]).
  signerUnknown,

  /// More than one envelope carries this request's object id, so an approval
  /// naming it could be counted for either; neither is read.
  ambiguousRequest,
}

/// What one book's structural stream says, as this phone may show it.
@immutable
final class StructuralBookView {
  /// Creates the view.
  const StructuralBookView({
    required this.items,
    required this.ownersInForce,
    required this.refused,
  });

  /// An empty view — no structural envelope in the book.
  static const empty = StructuralBookView(
    items: [],
    ownersInForce: null,
    refused: {},
  );

  /// Every request this phone may show, whatever its status, newest first.
  final List<StructuralItem> items;

  /// The owner set in force, or null when it is not derivable.
  final OwnerSetVersion? ownersInForce;

  /// Envelope id → why it was not read. Never silently skipped.
  final Map<String, StructuralEnvelopeRefusal> refused;

  /// Records waiting for this phone to name their signer
  /// ([StructuralEnvelopeRefusal.signerUnknown]).
  int get unconfirmed => refused.values
      .where((r) => r == StructuralEnvelopeRefusal.signerUnknown)
      .length;
}

/// Reads one book's structural stream — pure: no clock, no I/O.
///
/// [envelopes] are the book's opened `book_config`, `structural_approval`
/// and `business_setting` envelopes, any order. [signerOf] answers the user
/// whose certified device signed an envelope, or null when this phone cannot
/// say (no chain it can verify). [asOfMs] is the injected physical time.
///
/// A `structural_approval` envelope is read only when it decodes, carries the
/// object id it claims, names the book it was routed in, and was signed by a
/// device certified to the user it names. A request whose object id more than
/// one envelope carries is not read at all. A record whose signer cannot be
/// named yet is not read, and marks every request of the book
/// [StructuralItem.signersConfirmed] false — a decision is never offered over
/// a count that may be missing a veto. What survives goes to
/// `readStructuralState` (the owner set, the terms in force) and then, one
/// request at a time, to `evaluateStructural`; nothing here counts.
StructuralBookView readStructuralBook({
  required String bookId,
  required String bookName,
  required Iterable<OpenedStructuralEnvelope> envelopes,
  required Iterable<Account> accounts,
  required String viewerId,
  required StructuralSigner signerOf,
  required String Function(String userId) nameOf,
  required int asOfMs,
}) {
  final configVersions = <BookConfigVersion>[];
  final settings = <BusinessSetting>[];
  final events = <StructuralEvent>[];
  final refused = <String, StructuralEnvelopeRefusal>{};
  final carriers = <String, int>{}; // object id → envelopes carrying it
  final requestEnvelope = <String, String>{}; // request id → envelope id

  final mine = envelopes.where((e) => e.bookId == bookId).toList();
  for (final e in mine) {
    if (e.objectType == 'structural_approval') {
      carriers[e.objectId] = (carriers[e.objectId] ?? 0) + 1;
    }
  }

  for (final e in mine) {
    switch (e.objectType) {
      case 'book_config':
        try {
          final config = BookConfig.fromJson(e.json);
          if (config.id != bookId) {
            refused[e.envelopeId] = StructuralEnvelopeRefusal.otherBook;
            continue;
          }
          configVersions.add(
            BookConfigVersion(
              envelopeId: e.envelopeId,
              hlc: Hlc(e.hlc),
              config: config,
            ),
          );
        } on Object {
          refused[e.envelopeId] = StructuralEnvelopeRefusal.unreadable;
        }
      case 'business_setting':
        try {
          settings.add(BusinessSetting.fromJson(e.json));
        } on Object {
          refused[e.envelopeId] = StructuralEnvelopeRefusal.unreadable;
        }
      case 'structural_approval':
        final ev = decodeStructuralEvent(
          e.json,
          authorDevice: e.authorDevice,
          authorSeq: e.authorSeq,
        );
        final StructuralEnvelopeRefusal? why;
        if (ev == null) {
          why = StructuralEnvelopeRefusal.unreadable;
        } else if (ev.id != e.objectId) {
          why = StructuralEnvelopeRefusal.notThisObject;
        } else if (ev.bookId != bookId) {
          why = StructuralEnvelopeRefusal.otherBook;
        } else {
          final signer = signerOf(e);
          if (signer == null) {
            why = StructuralEnvelopeRefusal.signerUnknown;
          } else if (signer != _claimedBy(ev)) {
            why = StructuralEnvelopeRefusal.signerNotBound;
          } else {
            why = ev is StructuralRequest && carriers[ev.id]! > 1
                ? StructuralEnvelopeRefusal.ambiguousRequest
                : null;
          }
        }
        if (why != null) {
          refused[e.envelopeId] = why;
          continue;
        }
        events.add(ev!);
        if (ev is StructuralRequest) requestEnvelope[ev.id] = e.envelopeId;
    }
  }

  final StructuralReading reading;
  try {
    reading = readStructuralState(
      bookId: bookId,
      configVersions: configVersions,
      accounts: accounts,
      structuralEvents: events,
      businessSettings: settings,
      asOfMs: asOfMs,
      signerOf: null, // each envelope bound above, l.283-296
    );
  } on ArgumentError {
    // A book_config of another book reached the reader — filtered above, so
    // this is a contract breach, not a state: nothing is shown as decidable.
    return StructuralBookView(
      items: const [],
      ownersInForce: null,
      refused: Map.unmodifiable(refused),
    );
  }
  final chart = <String, Account>{
    for (final a in accounts)
      if (a.bookId == bookId) a.id: a,
  };
  // One record this phone cannot attribute may be the veto that closed a
  // request, or the approvals that decided it: nothing in this book is
  // decidable here until it can be read.
  final signersConfirmed = !refused.values.contains(
    StructuralEnvelopeRefusal.signerUnknown,
  );
  final versions = reading.owners.versions;
  final inForce = reading.owners.inForce;
  // Who signs, when the owner set is not derivable: the chart's own partner
  // → member mapping. Used for *names and visibility only* — the engine
  // counts nothing against a set it does not hold, and the card says so.
  final partnerMembers = [
    for (final a
        in chart.values.toList()
          ..sort((x, y) => x.createdOrder.compareTo(y.createdOrder)))
      if (a.accountClass == AccountClass.partner &&
          (a.memberId?.isNotEmpty ?? false))
        a.memberId!,
  ];

  final items = <StructuralItem>[];
  for (final request in events.whereType<StructuralRequest>()) {
    final outcome = evaluateStructural(
      request: request,
      records: events,
      owners: versions,
      asOfMs: asOfMs,
      signerOf: null, // each envelope bound above, l.283-296
    );
    final atRequest = versions
        .where((v) => v.version == request.ownerSetVersion)
        .firstOrNull;
    final ownerIds = atRequest?.ownerIds ?? partnerMembers.toSet();
    final named = <String>[
      ...ownerIds,
      for (final id in outcome.approvedBy)
        if (!ownerIds.contains(id)) id,
      if (outcome.veto case final v? when !ownerIds.contains(v.byUser))
        v.byUser,
    ];
    final terms = _termsOf(request, reading: reading, chart: chart);
    items.add(
      StructuralItem(
        request: request,
        outcome: outcome,
        bookName: bookName,
        initiatorName: nameOf(request.byUser),
        ownerNames: {for (final id in named) id: nameOf(id)},
        viewerId: viewerId,
        viewerIsOwner: inForce?.ownerIds.contains(viewerId) ?? false,
        terms: terms.terms,
        subject: terms.subject,
        termsKnown: terms.known,
        signersConfirmed: signersConfirmed,
        // ⚠️ SPEC: 02 §7.2.1 *an admin initiates*, and this app has no
        // book-role source to say who the admin is (the gap
        // `LedgerReviewQueue` records). Raising a request again also needs
        // its terms re-derived — a distribution's lines are a figure of the
        // day they were drawn — which only the screen that raised it can do
        // (S14.1). So the Inbox offers no re-initiation; the lapsed card
        // says who can raise it again.
        viewerCanInitiate: false,
      ),
    );
  }
  items.sort((a, b) {
    final byHlc = b.request.hlc.compareTo(a.request.hlc);
    return byHlc != 0 ? byHlc : a.request.id.compareTo(b.request.id);
  });
  return StructuralBookView(
    items: List.unmodifiable(items),
    ownersInForce: inForce,
    refused: Map.unmodifiable(refused),
  );
}

/// The user a structural record says signed it.
String _claimedBy(StructuralEvent e) => switch (e) {
  StructuralRequest(:final byUser) => byUser,
  StructuralApproval(:final byUser) => byUser,
  StructuralVeto(:final byUser) => byUser,
  StructuralLapse(:final byUser) => byUser,
};

/// The *what will change* lines of [request], or `known: false` when this
/// build cannot state everything it changes (07 §26 🔒).
///
/// ⚠️ SPEC: only two payload shapes are fixed anywhere. A
/// `changesConfig` action carries *the settings fields to set*
/// (`core_ledger` `StructuralRequest.payload`; ADR 2026-09-14b § Open bullet
/// 4 reads an `owner_add_or_remove` as the whole new `partner_shares` map),
/// and `profit_distribution` carries the lines `LocalLedger
/// .distributionPayload` writes. Member removal, year re-open, FY-start
/// change, interest terms, archive/delete and the quorum rule have no
/// documented payload and no writer in the app, so they read as *cannot
/// state* — drawn, vetoable, never approvable here.
({List<StructuralTerm> terms, String? subject, bool known}) _termsOf(
  StructuralRequest request, {
  required StructuralReading reading,
  required Map<String, Account> chart,
}) {
  const unknown = (terms: <StructuralTerm>[], subject: null, known: false);
  int order(String id) => chart[id]!.createdOrder;
  bool isPartner(String id) => chart[id]?.accountClass == AccountClass.partner;

  switch (request.action) {
    case StructuralAction.profitDistribution:
      const keys = {
        'from',
        'to',
        'accounting_date',
        'fy_start_year',
        'fy_start_month',
        'net_profit_paise',
        'interest_paise',
        'lines',
      };
      if (!keys.containsAll(request.payload.keys)) return unknown;
      final raw = request.payload['lines'];
      if (raw is! List || raw.isEmpty) return unknown;
      final lines = <Line>[];
      try {
        for (final l in raw) {
          if (l is! Map<String, Object?>) return unknown;
          lines.add(Line.fromJson(l));
        }
      } on Object {
        return unknown;
      }
      // The one multi-line entry of 02 §7.1: Profit Distributed against each
      // Partner Current A/c, balanced, moving no cash. Anything else is not
      // what the card's title says it is.
      var sum = 0;
      final credit = <String, int>{};
      for (final l in lines) {
        sum += l.amount.raw;
        final account = chart[l.accountId];
        if (account == null) return unknown;
        switch (account.accountClass) {
          case AccountClass.partner:
            credit[l.accountId] = (credit[l.accountId] ?? 0) - l.amount.raw;
          case AccountClass.equitySystem
              when account.systemRole == SystemRole.profitDistributed:
            break;
          case _:
            return unknown;
        }
      }
      if (sum != 0 || credit.isEmpty) return unknown;
      final ids = credit.keys.toList()..sort((a, b) => order(a) - order(b));
      return (
        terms: [
          for (final id in ids)
            StructuralTerm(
              subject: chart[id]!.name,
              // ⚠️ SPEC: a distribution has no "term in force"; *now* is what
              // this request has credited so far — nothing — beside what it
              // would credit (the shape S6.3's screens were built against).
              current: const StructuralMoney(0),
              proposed: StructuralMoney(credit[id]!),
            ),
        ],
        subject: null,
        known: true,
      );

    case StructuralAction.ownershipRatio:
    case StructuralAction.ownerAddOrRemove:
      if (request.payload.keys.toSet().difference({
        'partner_shares',
      }).isNotEmpty) {
        return unknown;
      }
      final raw = request.payload['partner_shares'];
      final proposed = partnerSharesInForce(request.payload);
      if (raw is! Map || proposed.isEmpty || proposed.length != raw.length) {
        return unknown;
      }
      final current = reading.partnerShares;
      if (!proposed.keys.every(isPartner) || !current.keys.every(isPartner)) {
        return unknown;
      }
      // A *ratio* change keeps the owners; one that adds or drops an account
      // is an owner change in disguise (ADR 2026-09-14b §3 moves the owner
      // set by `owner_add_or_remove` only), and the card would misname it.
      if (request.action == StructuralAction.ownershipRatio &&
          current.isNotEmpty &&
          !(current.keys.toSet().containsAll(proposed.keys) &&
              proposed.keys.toSet().containsAll(current.keys))) {
        return unknown;
      }
      final ids = {...current.keys, ...proposed.keys}.toList()
        ..sort((a, b) => order(a) - order(b));
      return (
        terms: [
          for (final id in ids)
            StructuralTerm(
              subject: chart[id]!.name,
              current: current[id] == null
                  ? null
                  : StructuralText('${current[id]}'),
              proposed: proposed[id] == null
                  ? null
                  : StructuralText('${proposed[id]}'),
            ),
        ],
        subject: null,
        known: true,
      );

    case StructuralAction.interestOnCapital:
    case StructuralAction.memberRemoval:
    case StructuralAction.yearReopen:
    case StructuralAction.fyStartChange:
    case StructuralAction.bookArchiveOrDelete:
    case StructuralAction.quorumSetting:
      return unknown;
  }
}

/// Whether S6 lists [item] at [asOfMs]: every pending request, and a decided
/// one for a while after it was decided.
///
/// ⚠️ SPEC: `StructuralItem` is *"one pending — or lately decided —
/// structural request"* and no doc says how late is lately. The request's own
/// window (02 §7.2.1: 14 days) is reused rather than a new number invented;
/// the record stays in the admin-actions feed forever either way.
bool shownInInbox(StructuralItem item, {required int asOfMs}) {
  if (item.status == StructuralStatus.pending) return true;
  final decidedMs =
      item.outcome.decidedAt?.physicalMs ?? item.outcome.deadlineMs;
  return asOfMs - decidedMs <= structuralExpiryMs;
}

/// [StructuralRequests] backed by [LocalLedger], across every book on this
/// device — the Inbox is one surface (07 §9 🔒), as `LedgerReviewQueue` and
/// `LedgerLateArrivals` settled.
final class LedgerStructuralRequests implements StructuralRequests {
  /// Creates the seam over [ledger] and starts watching.
  ///
  /// [nameOf] resolves a user id to the name this phone holds (the members
  /// repository's — the ledger holds no contact book, ADR 2026-09-05c §4).
  /// [signerOf] answers whose certified device signed an envelope at this
  /// read, or null when this phone cannot say — the composition root passes
  /// `certifiedSignerOf` (certified_signer.dart), which re-runs the signature
  /// chain of 04 §3.4 over the stored envelope; this device's own envelopes
  /// are its own user's by construction.
  /// [refreshOn] re-reads on each event — the composition root passes the
  /// sync status, because a certificate that arrives on the meta channel
  /// changes what may be read without any envelope changing.
  LedgerStructuralRequests(
    this.ledger, {
    String Function(String userId)? nameOf,
    StructuralSigner? signerOf,
    Stream<Object?>? refreshOn,
  }) : _nameOf = nameOf ?? _noName,
       _signerOf = signerOf ?? _nobody {
    _subs
      ..add(ledger.watchBooks().listen(_onBooks, onError: _onError))
      ..add(
        ledger.db
            .tableUpdates(TableUpdateQuery.onTable(ledger.db.envelopesLocal))
            .listen((_) => unawaited(_emit()), onError: _onError),
      );
    if (refreshOn != null) {
      _subs.add(refreshOn.listen((_) => unawaited(_emit()), onError: _onError));
    }
  }

  /// The ledger facade. One instance per app, installed by the shell.
  final LocalLedger ledger;

  final String Function(String userId) _nameOf;
  final StructuralSigner _signerOf;

  static String _noName(String _) => '';
  static String? _nobody(OpenedStructuralEnvelope _) => null;

  final _controller = StreamController<StructuralInbox>.broadcast();
  final _subs = <StreamSubscription<Object?>>[];
  final _names = <String, String>{};

  /// Request id → book id, from the last composition.
  final _bookOf = <String, String>{};

  /// Envelope id → why it was not read, from the last composition.
  Map<String, StructuralEnvelopeRefusal> _refused = const {};

  StructuralInbox? _current;
  Object? _lastError;
  Future<void>? _inFlight;
  bool _again = false;
  Future<void> _writes = Future<void>.value();

  @override
  StructuralInbox? get current => _current;

  /// What the last composition failed with, or null. Developer-facing only.
  Object? get lastError => _lastError;

  /// Every structural envelope the last composition did not read, across all
  /// books, and why (envelope id → reason). Developer-facing: the screen
  /// shows [StructuralInbox.unconfirmed] and each item's
  /// [StructuralItem.signersConfirmed]; ids and reasons only, no payload.
  Map<String, StructuralEnvelopeRefusal> get refused => _refused;

  /// The snapshot as it changes, starting with the one standing now —
  /// subscribed before the replay, so nothing lands in the gap (the shape
  /// `LedgerReviewQueue.watch` explains).
  @override
  Stream<StructuralInbox> watch() {
    late final StreamController<StructuralInbox> out;
    StreamSubscription<StructuralInbox>? sub;
    out = StreamController<StructuralInbox>(
      onListen: () {
        final standing = _current;
        sub = _controller.stream.listen(
          out.add,
          onError: out.addError,
          onDone: out.close,
        );
        if (standing != null) out.add(standing);
      },
      onCancel: () => sub?.cancel(),
    );
    return out.stream;
  }

  /// A fresh read of every book. Throws [StructuralRequestFailure] — never a
  /// silently empty Inbox (13 §4.3) and never a payload (CLAUDE.md rule 4).
  @override
  Future<void> refresh() async {
    try {
      _setBooks(await ledger.watchBooks().first);
    } on Object catch (e) {
      throw StructuralRequestFailure(
        'structural requests unavailable: ${e.runtimeType}',
      );
    }
    await _emit();
    final e = _lastError;
    if (e != null) {
      throw StructuralRequestFailure(
        'structural requests unavailable: ${e.runtimeType}',
      );
    }
  }

  /// Signs one approval (02 §7.2.1 🔒) — on this device, in this user's name,
  /// naming [requestId] and the owner-set version in force. Applies nothing.
  @override
  Future<void> approve(String requestId) => _decide(requestId);

  /// Signs one veto with [reason], which closes the request (02 §7.2.1 🔒).
  @override
  Future<void> veto({required String requestId, required String reason}) {
    if (reason.trim().isEmpty) {
      // A programming error, not a state: the veto sheet never yields one.
      throw ArgumentError.value(reason, 'reason', 'a veto records its reason');
    }
    return _decide(requestId, vetoReason: reason);
  }

  /// Never offered ([StructuralItem.viewerCanInitiate] is false — see
  /// [readStructuralBook]), so reaching it is refused rather than reviving a
  /// request (02 §7.2.1: a re-initiation is a *new* request).
  @override
  Future<void> reinitiate(String requestId) async =>
      throw const StructuralRequestFailure('re-initiation is not offered here');

  /// Stops watching. A composition still in flight finishes into a closed
  /// controller and publishes nothing; a failed read there is caught like any
  /// other (the last good snapshot simply stops mattering).
  Future<void> dispose() async {
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    await _controller.close();
  }

  // ── the write side ─────────────────────────────────────────────────────────

  /// One approval or veto, judged against a **fresh** read of the request's
  /// book at the moment of signing — never against the card the screen holds,
  /// which may be stale by a sync. The record names the request by its id
  /// (its object id, carried by exactly one envelope) and its own book, and
  /// is signed by this device in this user's name. Serialised, so a double
  /// tap cannot sign twice.
  Future<void> _decide(String requestId, {String? vetoReason}) {
    final run = _writes.then((_) async {
      try {
        var bookId = _bookOf[requestId];
        if (bookId == null) {
          await _emit();
          bookId = _bookOf[requestId];
        }
        if (bookId == null) {
          throw const StructuralRequestFailure('request not readable here');
        }
        final view = await _readBook(
          bookId,
          _names[bookId] ?? '',
          ledger.now().millisecondsSinceEpoch,
        );
        final item = view.items
            .where((i) => i.request.id == requestId)
            .firstOrNull;
        if (item == null) {
          throw const StructuralRequestFailure('request not readable here');
        }
        final may = vetoReason == null
            ? item.viewerMayDecide
            : item.viewerMayVeto;
        final version = view.ownersInForce?.version;
        if (!may || version == null) {
          throw StructuralRequestFailure(
            'not decidable: ${item.block?.name ?? item.status.name}',
          );
        }
        final me = ledger.identity.userId;
        final request = item.request;
        if (vetoReason == null) {
          await ledger.authorStructural(
            (hlc, id) => StructuralApproval(
              id: id,
              bookId: request.bookId,
              hlc: hlc,
              requestId: request.id,
              byUser: me,
              ownerSetVersion: version,
            ),
          );
        } else {
          await ledger.authorStructural(
            (hlc, id) => StructuralVeto(
              id: id,
              bookId: request.bookId,
              hlc: hlc,
              requestId: request.id,
              byUser: me,
              ownerSetVersion: version,
              reason: vetoReason,
            ),
          );
        }
      } on StructuralRequestFailure {
        rethrow;
      } on Object catch (e) {
        throw StructuralRequestFailure('decision failed: ${e.runtimeType}');
      }
      await _emit();
    });
    _writes = run.then<void>((_) {}, onError: (Object _) {});
    return run;
  }

  // ── the read side ──────────────────────────────────────────────────────────

  void _setBooks(List<BooksPData> rows) {
    _names
      ..clear()
      ..addEntries([for (final b in rows) MapEntry(b.id, b.name)]);
  }

  void _onBooks(List<BooksPData> rows) {
    _setBooks(rows);
    unawaited(_emit());
  }

  void _onError(Object error) {
    // An error is never a silently empty Inbox: the last good snapshot stands
    // and `refresh()` is what the screen's *Try again* calls.
    _lastError = error;
  }

  /// Composes and publishes, coalescing: a trigger that lands while a
  /// composition runs schedules exactly one more, and every caller's future
  /// completes after the composition that saw its trigger.
  Future<void> _emit() {
    final running = _inFlight;
    if (running != null) {
      _again = true;
      return running;
    }
    return _inFlight = _loop();
  }

  Future<void> _loop() async {
    try {
      do {
        _again = false;
        if (_controller.isClosed) return;
        try {
          final read = await _compose();
          if (_controller.isClosed) return;
          _lastError = null;
          _refused = Map.unmodifiable(read.refused);
          _current = StructuralInbox(
            items: List.unmodifiable(read.items),
            unconfirmed: read.refused.values
                .where((r) => r == StructuralEnvelopeRefusal.signerUnknown)
                .length,
          );
          _controller.add(_current!);
        } on Object catch (e) {
          // A closed ledger (app lock, sign-out) or a failed read: the last
          // good snapshot stands.
          _lastError = e;
        }
      } while (_again);
    } finally {
      _inFlight = null;
    }
  }

  Future<
    ({
      List<StructuralItem> items,
      Map<String, StructuralEnvelopeRefusal> refused,
    })
  >
  _compose() async {
    final asOfMs = ledger.now().millisecondsSinceEpoch;
    final items = <StructuralItem>[];
    final refused = <String, StructuralEnvelopeRefusal>{};
    final bookOf = <String, String>{};
    for (final MapEntry(key: bookId, value: name) in _names.entries.toList()) {
      final view = await _readBook(bookId, name, asOfMs);
      // Never silently skipped: what was not read travels with the snapshot.
      refused.addAll(view.refused);
      for (final item in view.items) {
        bookOf[item.request.id] = bookId;
        if (shownInInbox(item, asOfMs: asOfMs)) items.add(item);
      }
    }
    _bookOf
      ..clear()
      ..addAll(bookOf);
    // Newest first across books (S6), stable between rebuilds.
    items.sort((a, b) {
      final byHlc = b.request.hlc.compareTo(a.request.hlc);
      return byHlc != 0 ? byHlc : a.request.id.compareTo(b.request.id);
    });
    return (items: items, refused: refused);
  }

  /// Opens one book's structural envelopes from the mirror and reads them.
  ///
  /// Quarantined, unverified and corrupt rows are skipped exactly as
  /// Recompute and `structuralStateOf` skip them: only a row whose signature
  /// chain passed and whose blob decrypted once is read (04 §8 rule 3).
  Future<StructuralBookView> _readBook(
    String bookId,
    String bookName,
    int asOfMs,
  ) async {
    final db = ledger.db;
    final rows =
        await (db.select(db.envelopesLocal)
              ..where(
                (t) =>
                    t.bookId.equals(bookId) &
                    t.objectType.isIn(_structuralTypes),
              )
              ..orderBy([
                (t) => OrderingTerm.asc(t.hlc),
                (t) => OrderingTerm.asc(t.envelopeId),
              ]))
            .get();
    if (!rows.any((r) => r.objectType == 'structural_approval')) {
      return StructuralBookView.empty;
    }
    // The signed envelope is rebuilt exactly as the opener rebuilds it (same
    // tenant source, same assumed payload schema), so the signature a reader
    // re-checks is over the bytes that were opened.
    final opener = ledger.recompute.opener;
    final crypto = opener is CryptoPayloadOpener ? opener : null;
    final tenantId = crypto?.keys.tenantIdOf(bookId);
    final opened = <OpenedStructuralEnvelope>[];
    for (final r in rows) {
      if (r.quarantined == 1 || r.verified != 1) continue;
      final read = ledger.mirror.readBlobOfRow(r);
      if (read is! BlobOk) continue;
      final Map<String, Object?> json;
      try {
        json = ledger.recompute.opener.open(
          read.bytes,
          BlobHeader(
            envelopeId: r.envelopeId,
            bookId: r.bookId,
            objectId: r.objectId,
            objectType: r.objectType,
            keyVersion: r.keyVersion,
            authorDevice: r.authorDevice,
            hlc: r.hlc,
          ),
        );
      } on Object {
        // Recompute quarantines what it cannot open; this read never writes.
        continue;
      }
      opened.add(
        OpenedStructuralEnvelope(
          envelopeId: r.envelopeId,
          objectId: r.objectId,
          bookId: r.bookId,
          objectType: r.objectType,
          authorDevice: r.authorDevice,
          authorSeq: r.authorSeq,
          hlc: r.hlc,
          json: json,
          seq: r.seq,
          sealed: crypto == null || tenantId == null
              ? null
              : _sealedOf(
                  r,
                  read.bytes,
                  tenantId: tenantId,
                  payloadSchema: crypto.payloadSchema,
                ),
        ),
      );
    }
    final identity = ledger.identity;
    return readStructuralBook(
      bookId: bookId,
      bookName: bookName,
      envelopes: opened,
      accounts: (await ledger.chartOf(bookId)).accounts,
      viewerId: identity.userId,
      // This device's own signature is its own user's by construction (the
      // ledger set `verified` on it as it sealed it); every other device is
      // a certificate that verifies now, or nobody.
      signerOf: (e) =>
          e.authorDevice == identity.deviceId ? identity.userId : _signerOf(e),
      nameOf: _nameOf,
      asOfMs: asOfMs,
    );
  }
}

/// The envelope [row] stores, as signed — or null when the parts do not make
/// one (a reader then names no signer: nobody, never a guess).
Envelope? _sealedOf(
  EnvelopesLocalData row,
  Uint8List blob, {
  required String tenantId,
  required int payloadSchema,
}) {
  try {
    return Envelope.fromParts(
      suiteVersion: suiteVersion,
      tenantId: tenantId,
      bookId: row.bookId,
      objectId: row.objectId,
      objectType: row.objectType,
      keyVersion: row.keyVersion,
      payloadSchema: payloadSchema,
      authorDeviceId: row.authorDevice,
      hlc: row.hlc,
      envelopeId: row.envelopeId,
      blob: blob,
    );
  } on Object {
    return null;
  }
}
