// The reader rules that stand in front of the structural fold
// (ADR 2026-09-14b §2, §5). `payload_codec.dart` decodes and never judges:
// `BusinessSetting.requestId` is nullable there so that reading cannot throw on
// a policy question. The policy lives here, in one place, and produces exactly
// what `Mirror.quarantine` takes — an envelope id and a reason — so nothing is
// ever silently skipped.
//
// Two rules, one shape:
//   * **The deed is frozen** (§2): a later `book_config` version whose
//     structural keys differ from the creation version is an invariant
//     violation; the reader refuses that version and the earlier terms stand.
//   * **A `business_setting` counts only when it is authorised** (§5): its
//     `request_id` must name a `structural_approval` request of this book whose
//     `evaluateStructural(...).isApplied` is true, and its `settings` must equal
//     that request's payload.
//
// Neither rule is a projector rule: `decodeEvent` returns null for a
// `business_setting`, `projectedObjectTypes` excludes it, and `project()` never
// sees either object — the golden `content_hash` is untouched by construction
// (03 §3.3 rule 2).
import 'package:core_ledger/core_ledger.dart';
import 'package:meta/meta.dart';

import 'payload_codec.dart';

/// Why a reader refused an object. Typed so a caller branches on the rule
/// rather than on a message (05 §9: a typed state, never a string).
enum StructuralQuarantineReason {
  /// A later `book_config` version's structural keys differ from the creation
  /// version's — the deed is frozen (ADR 2026-09-14b §2).
  deedFrozen,

  /// A `business_setting` with no `request_id`: no authorising request, so
  /// nothing authorised it.
  noRequest,

  /// Its `request_id` names no `structural_approval` request of this book.
  unknownRequest,

  /// The named request exists but is not approved (pending, vetoed, lapsed).
  requestNotApplied,

  /// The named request is approved but its action sets no settings
  /// ([StructuralAction.changesConfig] false) — `applyStructural` would apply
  /// nothing, so neither may the fold.
  requestSetsNothing,

  /// Its `settings` differ from the approved request's payload.
  payloadMismatch,

  /// The record belongs to another book than the one being read.
  otherBook,
}

/// One object a reader refused, with the reason it records against the
/// envelope (`Mirror.quarantine(objectId, detail)`).
@immutable
final class StructuralQuarantine {
  /// Creates the entry.
  const StructuralQuarantine({
    required this.objectId,
    required this.reason,
    required this.detail,
  });

  /// The envelope (for a `book_config` version) or record id refused.
  final String objectId;

  /// Which rule refused it.
  final StructuralQuarantineReason reason;

  /// The human-readable reason, as written to `envelopes_local`.
  final String detail;

  @override
  String toString() => '$objectId: $detail';
}

/// One version of a book's `book_config` object as the mirror holds it: the
/// envelope it arrived in, its HLC, and the decoded payload.
@immutable
final class BookConfigVersion {
  /// Creates a version.
  const BookConfigVersion({
    required this.envelopeId,
    required this.hlc,
    required this.config,
  });

  /// Envelope id — what a refusal is recorded against.
  final String envelopeId;

  /// HLC; with [envelopeId], the version's place in the `(hlc, envelope_id)`
  /// order every device folds in.
  final Hlc hlc;

  /// The decoded payload.
  final BookConfig config;
}

/// The reading of a `book_config` object's versions (ADR 2026-09-14b §2).
@immutable
final class BookConfigReading {
  /// Creates a reading.
  const BookConfigReading({
    required this.deed,
    required this.inForce,
    required this.quarantined,
  });

  /// The creation version — the deed, whose structural keys are the frozen
  /// ones. Null only when there are no versions at all.
  final BookConfig? deed;

  /// The latest **accepted** version: the deed as amended by every routine
  /// amend that carried the structural keys forward verbatim. This is the
  /// config a reader shows and the one [structuralSettingsInForce] is folded
  /// from. Null only when there are no versions at all.
  final BookConfig? inForce;

  /// The versions refused, in `(hlc, envelope_id)` order.
  final List<StructuralQuarantine> quarantined;
}

/// Reads a book's `book_config` [versions], newest last, and applies
/// *the deed is frozen* (ADR 2026-09-14b §2).
///
/// The **creation version** is the earliest in `(hlc, envelope_id)` order — the
/// one order every device agrees on — and its [structuralSettingKeys] are the
/// deed. A later version is accepted only when it carries those keys forward
/// **verbatim**, which is what makes a structural key inside a routinely
/// amendable object safe: it can be *read* from there and cannot be *moved*
/// there. A version that changes one, drops one, adds one, or rewrites a value
/// this build cannot even interpret is refused whole — it is an envelope like
/// any other and readers re-check (02 preamble) — so its routine fields do not
/// land either and the last accepted version stands.
///
/// Input order does not matter and nothing is mutated. Every version is either
/// accepted or listed in [BookConfigReading.quarantined]; none is dropped.
///
/// ⚠️ SPEC (ADR 2026-09-14b §2): the ADR says "the creation version" without
/// saying how a reader identifies it, and this takes it as the earliest in the
/// canonical order. A backdated version would therefore sort first and take the
/// deed's place — but the two disagree, so one of them is always refused and no
/// version whose structural keys differ is ever silently applied. Which of the
/// pair is the impostor is a signature/authorship question, not a fold
/// question; see the lane report.
BookConfigReading readBookConfigVersions(Iterable<BookConfigVersion> versions) {
  final ordered = versions.toList()
    ..sort(
      (a, b) => compareEventOrder(a.hlc, a.envelopeId, b.hlc, b.envelopeId),
    );
  if (ordered.isEmpty) {
    return const BookConfigReading(deed: null, inForce: null, quarantined: []);
  }
  final deed = ordered.first.config;
  final frozen = _structuralOf(deed);
  var inForce = deed;
  final quarantined = <StructuralQuarantine>[];
  for (final version in ordered.skip(1)) {
    final theirs = _structuralOf(version.config);
    final changed = _changedKeys(frozen, theirs);
    if (changed.isEmpty) {
      inForce = version.config;
      continue;
    }
    quarantined.add(
      StructuralQuarantine(
        objectId: version.envelopeId,
        reason: StructuralQuarantineReason.deedFrozen,
        detail:
            'book_config: the deed is frozen — ${changed.join(', ')} '
            'differs from the creation version (ADR 2026-09-14b §2)',
      ),
    );
  }
  return BookConfigReading(
    deed: deed,
    inForce: inForce,
    quarantined: List.unmodifiable(quarantined),
  );
}

/// The structural keys of [config] as they travel on the wire — so a value this
/// build cannot interpret, which rides in [BookConfig.extra], is compared too.
Map<String, Object?> _structuralOf(BookConfig config) {
  final wire = config.toJson();
  return {
    for (final k in structuralSettingKeys)
      if (wire.containsKey(k)) k: wire[k],
  };
}

/// The structural keys that differ between two versions — present in one and
/// absent in the other counts, and so does a value changed anywhere inside.
List<String> _changedKeys(
  Map<String, Object?> deed,
  Map<String, Object?> later,
) => [
  for (final k in structuralSettingKeys)
    if (deed.containsKey(k) != later.containsKey(k) ||
        !jsonValuesEqual(deed[k], later[k]))
      k,
];

/// The reading of a book's `business_setting` records (ADR 2026-09-14b §5).
@immutable
final class BusinessSettingReading {
  /// Creates a reading.
  const BusinessSettingReading({
    required this.applied,
    required this.quarantined,
  });

  /// The records that are authorised, in `(hlc, id)` order — and the only ones
  /// that may be handed to [structuralSettingsInForce].
  final List<BusinessSetting> applied;

  /// The records refused, in `(hlc, id)` order, each with its reason.
  final List<StructuralQuarantine> quarantined;
}

/// Verifies [records] against the book's `structural_approval` envelopes
/// (ADR 2026-09-14b §5): a record counts only when its
/// [BusinessSetting.requestId] names a [StructuralRequest] of [bookId] whose
/// `evaluateStructural(...).isApplied` is true **and** whose payload equals the
/// record's [BusinessSetting.settings].
///
/// [structuralEvents] is every `structural_approval` envelope of the book — the
/// requests among them are the ones a record may name, the rest are the
/// approvals, vetoes and lapses `evaluateStructural` counts. [owners] are the
/// book's owner-set versions and [asOfMs] is the injected physical time (never
/// a clock read here; `core_ledger` decides only pending-vs-lapsed with it).
///
/// A record with no request, an unknown or unapproved request, a request whose
/// action sets no settings, a differing payload, or another book's id is
/// **quarantined with its reason, never silently skipped**: every input appears
/// in exactly one of the two lists. Nothing is mutated.
///
/// ⚠️ SPEC (ADR 2026-09-14b § Open, for the 05 owner): `05` line 97 puts
/// `business_setting` in the **all-time** bootstrap set while
/// `structural_approval` envelopes are fetched with their FY. A device that
/// bootstrapped years later therefore holds the record without the approvals
/// that authorise it, and this reader can only say
/// [StructuralQuarantineReason.unknownRequest] — *not yet verifiable* is
/// indistinguishable here from *never existed*. Until that rule is settled, a
/// caller that does not hold every FY must treat `unknownRequest` as
/// provisional and re-verify on fetch, and must not write it to
/// `envelopes_local` as a permanent refusal. The other five reasons are
/// decidable from the envelopes in hand.
BusinessSettingReading verifyBusinessSettings({
  required String bookId,
  required Iterable<BusinessSetting> records,
  required Iterable<StructuralEvent> structuralEvents,
  required Iterable<OwnerSetVersion> owners,
  required int asOfMs,
}) {
  final events = structuralEvents.toList(growable: false);
  final requests = <String, StructuralRequest>{
    for (final e in events.whereType<StructuralRequest>())
      // A request of another book never authorises anything here; to this book
      // it simply does not exist.
      if (e.bookId == bookId) e.id: e,
  };
  final outcomes = <String, StructuralOutcome>{};
  StructuralOutcome outcomeOf(StructuralRequest request) =>
      outcomes[request.id] ??= evaluateStructural(
        request: request,
        records: events,
        owners: owners,
        asOfMs: asOfMs,
      );

  final ordered = records.toList()
    ..sort((a, b) => compareEventOrder(a.hlc, a.id, b.hlc, b.id));
  final applied = <BusinessSetting>[];
  final quarantined = <StructuralQuarantine>[];
  void refuse(
    BusinessSetting record,
    StructuralQuarantineReason reason,
    String detail,
  ) => quarantined.add(
    StructuralQuarantine(
      objectId: record.id,
      reason: reason,
      detail: 'business_setting: $detail',
    ),
  );

  for (final record in ordered) {
    if (record.bookId != bookId) {
      refuse(
        record,
        StructuralQuarantineReason.otherBook,
        'record of book ${record.bookId}, read as $bookId',
      );
      continue;
    }
    final requestId = record.requestId;
    if (requestId == null) {
      refuse(
        record,
        StructuralQuarantineReason.noRequest,
        'no request_id — nothing authorised it (ADR 2026-09-14b §5)',
      );
      continue;
    }
    final request = requests[requestId];
    if (request == null) {
      refuse(
        record,
        StructuralQuarantineReason.unknownRequest,
        'request $requestId is not a structural_approval request of this book',
      );
      continue;
    }
    final outcome = outcomeOf(request);
    if (!outcome.isApplied) {
      refuse(
        record,
        StructuralQuarantineReason.requestNotApplied,
        'request $requestId is ${outcome.status.name}, not approved',
      );
      continue;
    }
    if (!request.action.changesConfig) {
      // `applyStructural` applies nothing for these actions, and the fold is
      // `applyStructural` composed: an approved year_reopen or member_removal
      // can never carry a ratio in on its payload.
      refuse(
        record,
        StructuralQuarantineReason.requestSetsNothing,
        'request $requestId is ${request.action.wire}, which changes no '
        'settings',
      );
      continue;
    }
    if (!jsonValuesEqual(record.settings, request.payload)) {
      refuse(
        record,
        StructuralQuarantineReason.payloadMismatch,
        'settings differ from the payload approved in request $requestId',
      );
      continue;
    }
    applied.add(record);
  }
  return BusinessSettingReading(
    applied: List.unmodifiable(applied),
    quarantined: List.unmodifiable(quarantined),
  );
}

/// Deep equality over decoded JSON values — maps compared by key regardless of
/// insertion order, lists in order, everything else by `==`. Used where two
/// payloads must be *the same claim*: the deed's structural keys against a
/// later version's, and a record's `settings` against its request's payload.
/// Values this build cannot interpret compare like any other (03 §3.3.4 🔒 —
/// they round-trip verbatim, so they compare verbatim).
bool jsonValuesEqual(Object? a, Object? b) {
  if (identical(a, b)) return true;
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final MapEntry(:key, :value) in a.entries) {
      if (!b.containsKey(key)) return false;
      if (!jsonValuesEqual(value, b[key])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!jsonValuesEqual(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}

// ---------------------------------------------------------------------------
// The owner-set fold (ADR 2026-09-14b §3 and § Open bullet 4)
// ---------------------------------------------------------------------------
//
// `evaluateStructural` counts approvals against `OwnerSetVersion`s it is
// handed; nothing in `core_ledger` says where those versions come from. They
// come from here: the deed's `partner_shares`, read through the book's chart,
// then one version per approved `owner_add_or_remove` or `quorum_setting`,
// folded in `(hlc, envelope_id)` order.
//
// Three rules keep the fold honest, and each exists because breaking it makes
// quorum *easier*:
//
//   1. **A set that cannot be derived is not a smaller set.** If the deed names
//      a partner account the chart cannot tie to a member, the founding set is
//      refused whole. Dropping that owner would turn *all owners* of three into
//      *all owners* of two, and two signatures would carry a change three
//      people had to agree to.
//   2. **Nothing is applied early** (02 §7.2.1 🔒). A version exists only from
//      the order point at which quorum was reached — never from the order point
//      the request was initiated — so a pending `quorum_setting` can never be
//      the rule its own approvals are counted under.
//   3. **The fold never reads a `business_setting`.** Those records are the
//      *output* side of the reader and are themselves authorised by a quorum
//      counted under these versions; letting one in here would let a record
//      vouch for its own quorum. The quorum rule of a version therefore comes
//      from the deed and from approved `quorum_setting` **requests** only.

/// Why the owner-set fold refused a claim about who owns the book.
///
/// Typed like [StructuralQuarantineReason] so a caller branches on the rule.
/// These are **not** envelope quarantines: an owner-set refusal is a statement
/// about the chart and the payloads in hand, and the chart may still be
/// arriving (an account envelope not yet opened reads exactly like an account
/// that never existed). A caller writes one to `envelopes_local` only when it
/// holds the book's whole chart.
enum OwnerSetRefusalReason {
  /// No `partner_shares` this build can read: the deed records none (02 §7.1 🔒
  /// — absent or empty is *not recorded*, never *equal*), or a request's
  /// payload carries a value that is not a map of whole positive weights.
  sharesNotRecorded,

  /// A `quorum_setting` request whose payload carries no `structural_quorum`
  /// key at all — it names no rule, so it changes none.
  quorumNotRecorded,

  /// A named id is not a `partner`-class account of this book: absent from the
  /// chart, another class, or another book's. The ratio's keys are claims from
  /// an envelope like any other and are not evidence (02 preamble, §7.1 🔒).
  notPartnerAccount,

  /// A `partner` account with no [Account.memberId]: the chart cannot say who
  /// signs for it, so the set it belongs to is **not derivable**.
  ownerNotIdentified,

  /// Two named partner accounts belong to the same member — one Partner
  /// Current A/c per owner (02 §7.1 🔒). Counting both would inflate the owner
  /// count and, under *majority*, the threshold with it.
  ownerAlreadyPresent,

  /// The change would leave the book with no owners at all.
  noOwnersLeft,
}

/// One claim the owner-set fold refused, with the reason it records.
///
/// [objectId] is the request that made the claim, or — for the founding set —
/// the book id, since the deed is identified by the book and not by an envelope
/// at this layer ([BookConfigReading.deed] carries no envelope id).
@immutable
final class OwnerSetRefusal {
  /// Creates the entry.
  const OwnerSetRefusal({
    required this.objectId,
    required this.reason,
    required this.detail,
  });

  /// The request id, or the book id for the deed.
  final String objectId;

  /// Which rule refused it.
  final OwnerSetRefusalReason reason;

  /// The human-readable reason.
  final String detail;

  @override
  String toString() => '$objectId: $detail';
}

/// The reading of a book's owner-set versions.
@immutable
final class OwnerSetReading {
  /// Creates a reading.
  const OwnerSetReading({required this.versions, required this.refused});

  /// The versions, ascending, version 1 first. **Empty** when the founding set
  /// is not derivable — which is not "no owners" but "no reader can say", and
  /// `evaluateStructural` then applies nothing at all.
  final List<OwnerSetVersion> versions;

  /// The claims refused, each with its reason. Never silently skipped.
  final List<OwnerSetRefusal> refused;

  /// The version in force at the end of the fold, or null when there is none.
  OwnerSetVersion? get inForce => versions.isEmpty ? null : versions.last;
}

/// The owner-set versions of a book: who signs, and how many must.
///
/// **Version 1 is the founding set** — the [Account.memberId] of every
/// `partner`-class account the [deed]'s `partner_shares` names, with the deed's
/// `structural_quorum` (absent, or a value this build cannot interpret, is *all
/// owners* — the strictest rule; ADR 2026-09-14b §3). The ratio's key is the
/// Partner Current A/c id (02 §7.1 🔒) and `memberId` is the chart's own
/// mapping from that key to the member who signs (`accounts.dart`: *for
/// `advance` and `partner`: the member / owner this account belongs to*).
///
/// **Every later version** is one approved structural request that changes the
/// set or the rule — [StructuralAction.ownerAddOrRemove] and
/// [StructuralAction.quorumSetting], the two the ADR names and no others.
/// Requests are walked in `(hlc, id)` order and each is evaluated once through
/// `evaluateStructural` against the versions **before it**, so a request is
/// counted under the owner set in force at its own order point (the K1
/// precedent of ADR 2026-09-06 §3: the threshold is the earliest version among
/// the request and the approvals that counted, so a re-versioned set neither
/// resets the count nor raises the bar). A pending, vetoed or lapsed request
/// bumps nothing.
///
/// A version comes into force at the order point **quorum was reached**
/// ([StructuralOutcome.decidedAt], never before the request's own order point),
/// not when the request was initiated — 02 §7.2.1 🔒 *nothing is applied
/// early*. Two consequences, both deliberate:
///   * a request initiated while an owner change is still pending is counted
///     under the old set, and
///   * a change is folded onto the version in force **when it lands**, so an
///     add approved after a quorum change carries the new rule forward rather
///     than reverting it.
///
/// [structuralEvents] is every `structural_approval` envelope of the book and
/// [accounts] its chart; both are filtered to [deed]'s book. [asOfMs] is the
/// injected physical time — the fold reads no clock (CLAUDE.md rule 3) and
/// `evaluateStructural` uses it for one thing only: whether a request past its
/// window is pending or lapsed.
///
/// Input order does not matter, nothing is mutated, and every claim is either
/// folded in or listed in [OwnerSetReading.refused].
///
/// ⚠️ SPEC (ADR 2026-09-14b § Open bullet 4): the ADR leaves the payload of an
/// `owner_add_or_remove` to this lane. It is read as the engine's own contract
/// for a [StructuralAction.changesConfig] action — *the settings fields to
/// set*, applied by `applyStructural` as `{...settings, ...payload}`, a
/// key-level replace — so its `partner_shares` is the **whole new map**, and
/// the owner added or removed is its difference from the map in force. A
/// delta-shaped payload (only the added account) is not a shape the engine
/// defines, and would read here as a removal of everyone else; a writer must
/// author the full map. No writer exists yet (M7: no `owner_add_or_remove` is
/// authored anywhere in `app/`), so this is the shape to build to.
OwnerSetReading ownerSetVersions({
  required BookConfig deed,
  required Iterable<Account> accounts,
  required Iterable<StructuralEvent> structuralEvents,
  required int asOfMs,
}) {
  final refused = <OwnerSetRefusal>[];
  final chart = <String, Account>{
    for (final a in accounts)
      if (a.bookId == deed.id) a.id: a,
  };
  OwnerSetReading stop() =>
      OwnerSetReading(versions: const [], refused: List.unmodifiable(refused));

  if (deed.partnerShares.isEmpty) {
    // Either no ratio was recorded, or the recorded value is one this build
    // cannot read (the codec leaves it in `extra`). A book whose deed names no
    // partner account names no signer: not derivable, and *not* a set of one.
    refused.add(
      OwnerSetRefusal(
        objectId: deed.id,
        reason: OwnerSetRefusalReason.sharesNotRecorded,
        detail:
            'the deed records no partner_shares this build can read, so it '
            'names no owner (02 §7.1 🔒: absent or empty is not recorded, '
            'never equal)',
      ),
    );
    return stop();
  }
  final founding = _ownersNamed(
    deed.partnerShares.keys,
    chart: chart,
    objectId: deed.id,
    subject: 'the deed of book ${deed.id}',
    refused: refused,
  );
  if (founding == null) return stop();

  final versions = <OwnerSetVersion>[
    OwnerSetVersion(
      version: 1,
      ownerIds: founding,
      // Read off the wire, so a value held in `extra` is seen and read
      // conservatively as all owners rather than silently defaulted.
      quorum: structuralQuorumOf(deed.toJson()),
    ),
  ];

  final events = structuralEvents
      .where((e) => e.bookId == deed.id)
      .toList(growable: false);
  final requests = events.whereType<StructuralRequest>().toList()
    ..sort((a, b) => compareEventOrder(a.hlc, a.id, b.hlc, b.id));

  // Versions whose quorum has been reached but whose order point has not yet
  // been passed by the walk, kept in `(hlc, id)` order of that point.
  final waiting = <_PendingOwnerSet>[];
  void promoteBefore(Hlc hlc, String id) {
    while (waiting.isNotEmpty &&
        compareEventOrder(waiting.first.hlc, waiting.first.id, hlc, id) < 0) {
      _promote(waiting.removeAt(0), versions, chart, refused);
    }
  }

  for (final request in requests) {
    promoteBefore(request.hlc, request.id);
    if (request.action != StructuralAction.ownerAddOrRemove &&
        request.action != StructuralAction.quorumSetting) {
      continue;
    }
    final outcome = evaluateStructural(
      request: request,
      records: events,
      owners: versions,
      asOfMs: asOfMs,
    );
    if (!outcome.isApplied) continue;
    // The order point the change lands at: where quorum was reached, but never
    // before the request itself — a backdated approval cannot bring a version
    // into force before the change it approves was even proposed.
    var hlc = outcome.decidedAt ?? request.hlc;
    var id = outcome.decidedById ?? request.id;
    if (compareEventOrder(hlc, id, request.hlc, request.id) < 0) {
      hlc = request.hlc;
      id = request.id;
    }
    final pending = _PendingOwnerSet(request: request, hlc: hlc, id: id);
    var at = 0;
    while (at < waiting.length &&
        compareEventOrder(waiting[at].hlc, waiting[at].id, hlc, id) < 0) {
      at++;
    }
    waiting.insert(at, pending);
  }
  while (waiting.isNotEmpty) {
    _promote(waiting.removeAt(0), versions, chart, refused);
  }

  return OwnerSetReading(
    versions: List.unmodifiable(versions),
    refused: List.unmodifiable(refused),
  );
}

/// An approved owner-set change waiting for the walk to reach its order point.
@immutable
final class _PendingOwnerSet {
  const _PendingOwnerSet({
    required this.request,
    required this.hlc,
    required this.id,
  });

  final StructuralRequest request;

  /// The order point at which the change comes into force.
  final Hlc hlc;

  /// The envelope id at that point.
  final String id;
}

/// Folds one approved change onto the version in force, or refuses it.
///
/// Derived here — at the order point the change lands — and not where it was
/// evaluated: the version in force may have moved in between, and a change
/// folded onto a stale version would silently revert whatever moved it.
void _promote(
  _PendingOwnerSet pending,
  List<OwnerSetVersion> versions,
  Map<String, Account> chart,
  List<OwnerSetRefusal> refused,
) {
  final request = pending.request;
  final current = versions.last;
  void refuse(OwnerSetRefusalReason reason, String detail) => refused.add(
    OwnerSetRefusal(objectId: request.id, reason: reason, detail: detail),
  );

  switch (request.action) {
    case StructuralAction.ownerAddOrRemove:
      final raw = request.payload['partner_shares'];
      if (raw is! Map) {
        refuse(
          OwnerSetRefusalReason.sharesNotRecorded,
          'owner_add_or_remove names no partner_shares map, so it names no '
          'owner set',
        );
        return;
      }
      if (raw.isEmpty) {
        refuse(
          OwnerSetRefusalReason.noOwnersLeft,
          'owner_add_or_remove would leave the book with no owners; a book '
          'with no owner has no one who could ever approve anything again',
        );
        return;
      }
      final shares = partnerSharesInForce(request.payload);
      if (shares.isEmpty) {
        refuse(
          OwnerSetRefusalReason.sharesNotRecorded,
          'owner_add_or_remove carries partner_shares this build cannot read '
          '(weights must be whole and positive)',
        );
        return;
      }
      final owners = _ownersNamed(
        shares.keys,
        chart: chart,
        objectId: request.id,
        subject: 'owner_add_or_remove ${request.id}',
        refused: refused,
      );
      if (owners == null) return;
      versions.add(
        OwnerSetVersion(
          version: versions.length + 1,
          ownerIds: owners,
          // An owner change moves the set, never the rule.
          quorum: current.quorum,
        ),
      );
    case StructuralAction.quorumSetting:
      if (!request.payload.containsKey(structuralQuorumKey)) {
        refuse(
          OwnerSetRefusalReason.quorumNotRecorded,
          'quorum_setting names no $structuralQuorumKey, so it changes no rule',
        );
        return;
      }
      versions.add(
        OwnerSetVersion(
          version: versions.length + 1,
          ownerIds: current.ownerIds,
          // A value this build cannot interpret reads as all owners — the
          // strictest rule (ADR 2026-09-14b §3). It is the safe direction on
          // both sides of the divergence it creates with a newer build: this
          // build demands more approvals and shows pending where the newer one
          // shows approved, so it applies nothing the newer build would not.
          quorum: structuralQuorumOf(request.payload),
        ),
      );
    // Every other action leaves the owner set alone; the caller filters them
    // before a candidate is ever made.
    case _:
      return;
  }
}

/// The members who sign for [accountIds], or null when the chart cannot say.
///
/// Ids are walked in sorted order so the refusals of one malformed claim read
/// the same on every device. A refusal is recorded for every id that fails —
/// the walk does not stop at the first — and any failure makes the whole set
/// undrivable: a partial owner set is a smaller one, and a smaller one is an
/// easier quorum.
Set<String>? _ownersNamed(
  Iterable<String> accountIds, {
  required Map<String, Account> chart,
  required String objectId,
  required String subject,
  required List<OwnerSetRefusal> refused,
}) {
  final byMember = <String, String>{};
  var ok = true;
  void refuse(OwnerSetRefusalReason reason, String detail) => refused.add(
    OwnerSetRefusal(objectId: objectId, reason: reason, detail: detail),
  );

  for (final id in accountIds.toList()..sort()) {
    final account = chart[id];
    if (account == null || account.accountClass != AccountClass.partner) {
      refuse(
        OwnerSetRefusalReason.notPartnerAccount,
        '$subject names $id, which is not a partner account of this book',
      );
      ok = false;
      continue;
    }
    final member = account.memberId;
    if (member == null || member.isEmpty) {
      refuse(
        OwnerSetRefusalReason.ownerNotIdentified,
        '$subject names partner account $id, which names no member — the '
        'owner set is not derivable, and a set without them would be an '
        'easier quorum than the one agreed',
      );
      ok = false;
      continue;
    }
    final held = byMember[member];
    if (held != null) {
      refuse(
        OwnerSetRefusalReason.ownerAlreadyPresent,
        '$subject names both $held and $id for member $member — one Partner '
        'Current A/c per owner (02 §7.1 🔒)',
      );
      ok = false;
      continue;
    }
    byMember[member] = id;
  }
  if (!ok) return null;
  if (byMember.isEmpty) {
    refuse(
      OwnerSetRefusalReason.noOwnersLeft,
      '$subject names no owner at all',
    );
    return null;
  }
  return Set.unmodifiable(byMember.keys.toSet());
}

/// A book's structural terms, read whole: the deed, who owns it, which dated
/// records are authorised, and the settings in force.
@immutable
final class StructuralReading {
  /// Creates a reading.
  const StructuralReading({
    required this.config,
    required this.owners,
    required this.settings,
    required this.inForce,
    required this.quarantined,
  });

  /// The `book_config` versions read (ADR 2026-09-14b §2).
  final BookConfigReading config;

  /// The owner-set versions (§3, § Open bullet 4).
  final OwnerSetReading owners;

  /// The `business_setting` records verified (§5).
  final BusinessSettingReading settings;

  /// The structural settings in force — the deed as overridden by every
  /// authorised record, in `(hlc, envelope_id)` order (§2).
  final Map<String, Object?> inForce;

  /// Every envelope refused by the two envelope-level rules, deed versions
  /// first. Owner-set refusals are kept apart in [ownerRefusals]: they are
  /// statements about the chart, not about an envelope's validity.
  final List<StructuralQuarantine> quarantined;

  /// The creation version — the frozen deed.
  BookConfig? get deed => config.deed;

  /// The claims the owner fold refused.
  List<OwnerSetRefusal> get ownerRefusals => owners.refused;

  /// The ratio in force, `{partner account id: weight}`; empty means *not
  /// recorded*, never *equal* (02 §7.1 🔒).
  Map<String, int> get partnerShares => partnerSharesInForce(inForce);

  /// The quorum rule in force.
  StructuralQuorum get quorum => quorumInForce(inForce);
}

/// Reads a book's structural terms end to end — the one call a caller makes.
///
/// The composition ADR 2026-09-14b describes, in the only order that is sound:
/// the deed in force ([readBookConfigVersions], §2) → the owner-set versions
/// ([ownerSetVersions], §3) → the records those versions authorise
/// ([verifyBusinessSettings], §5) → the settings in force
/// ([structuralSettingsInForce], §2). Each step feeds the next and none reads
/// back: the records never decide who may approve them.
///
/// [bookId] is the book being read; a `book_config` version of another book is
/// a caller error and throws, as a foreign `business_setting` does in
/// [structuralSettingsInForce]. A book with no `book_config` version at all
/// reads as empty rather than throwing — a device mid-bootstrap holds exactly
/// that. [asOfMs] is injected; nothing here reads a clock.
///
/// The caller is S6.3, the distribution wizard: `reading.partnerShares` is the
/// one ratio it hands `splitByRatio` (ADR 2026-09-14b §6), and
/// `reading.owners.inForce` is what its approval count is judged against.
///
/// ⚠️ SPEC (ADR 2026-09-14b §5, for the ADR's owner): §5's reader rule checks
/// that an authorising request is approved and that its payload equals the
/// record's `settings` — it does **not** check that the request's *action* owns
/// the keys it sets. An approved `ownership_ratio` whose payload changes the
/// **key set** of `partner_shares`, or any `changesConfig` request carrying
/// `structural_quorum`, therefore lands in [inForce] through
/// [verifyBusinessSettings] while this fold ignores it — so the displayed terms
/// and the terms a quorum is counted under can disagree. This reading is the
/// conservative one (the owner set moves only by the two actions ADR §3 names,
/// never by a ratio change), and the mismatch is reported to the owner rather
/// than closed here: tightening §5 is a 🔒 change.
StructuralReading readStructuralState({
  required String bookId,
  required Iterable<BookConfigVersion> configVersions,
  required Iterable<Account> accounts,
  required Iterable<StructuralEvent> structuralEvents,
  required Iterable<BusinessSetting> businessSettings,
  required int asOfMs,
}) {
  final config = readBookConfigVersions(configVersions);
  for (final version in configVersions) {
    if (version.config.id != bookId) {
      throw ArgumentError.value(
        version.envelopeId,
        'configVersions',
        'book_config of book ${version.config.id} read as $bookId',
      );
    }
  }
  final deed = config.deed;
  final inForceConfig = config.inForce;
  if (deed == null || inForceConfig == null) {
    return StructuralReading(
      config: config,
      owners: const OwnerSetReading(versions: [], refused: []),
      settings: const BusinessSettingReading(applied: [], quarantined: []),
      inForce: const {},
      quarantined: List.unmodifiable(config.quarantined),
    );
  }

  // The deed — the creation version — is what the owner set is founded on; a
  // routine amend may carry the structural keys forward but may never change
  // them (§2), so the two agree by construction and the deed is the honest
  // one to read.
  final owners = ownerSetVersions(
    deed: deed,
    accounts: accounts,
    structuralEvents: structuralEvents,
    asOfMs: asOfMs,
  );
  final settings = verifyBusinessSettings(
    bookId: bookId,
    records: businessSettings,
    structuralEvents: structuralEvents,
    owners: owners.versions,
    asOfMs: asOfMs,
  );
  return StructuralReading(
    config: config,
    owners: owners,
    settings: settings,
    inForce: structuralSettingsInForce(
      deed: inForceConfig,
      applied: settings.applied,
    ),
    quarantined: List.unmodifiable([
      ...config.quarantined,
      ...settings.quarantined,
    ]),
  );
}
