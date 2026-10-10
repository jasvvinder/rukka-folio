// Suite A — who signed it (02 §7.2.1 🔒: *each approval is authored on that
// owner's own device, so the server cannot manufacture one*). TRUST200.
//
// Sync proves which **device** signed an envelope (04 §8 rule 3); the
// `by_user` inside the payload is a claim. Until this slice the engine counted
// the claim alone, so one member's phone could approve, veto or initiate "as"
// every owner (lane F200I, review F200I-1). The engine now takes the reader's
// certified device → user map as an injected function (`signerOf`) and counts
// a record only when the device that signed it is certified to the user it
// names. A device the reader cannot certify — no certificate, or revoked at
// or before the record — is *nobody*: the record is not counted and, because
// it may be the veto that closed the request, the request is not applied
// either (`signersConfirmed` false). Nothing here reads a clock or a store:
// the map is injected, exactly like the time (CLAUDE.md rule 3).
//
// The signer is asked by **signing identity** — `(authorDevice, authorSeq)`,
// unique per envelope (05 per-author sequence 🔒) — never by the record's id
// or `by_user`, which are the claims under test (review TRUST200 #1: a signer
// keyed by record id let a member's payload reusing an owner's record id take
// that owner's signer). `signerOf` has no default: a caller that passes null
// asserts it bound every record per envelope itself (the Inbox); A-02-94 and
// A-02-95 exercise that contract with `signerOf: null` written out.
//
// Synthetic data only (the Kaur farm of 02 §7.1); no real entry.
@Tags(['A'])
library;

import 'package:core_ledger/core_ledger.dart';
import 'package:test/test.dart';

int day(int n) => n * 86400000;

Hlc at(int dayNo, [int counter = 0]) =>
    Hlc.compose(physicalMs: day(dayNo), counter: counter);

/// The certificates this reader holds: device → the user it is certified
/// to. `d-mem` is a member's (not an owner's) phone; `d-ghost` has none.
const certs = {
  'd-amrit': 'amrit',
  'd-sukhdev': 'sukhdev',
  'd-harjit': 'harjit',
  'd-mem': 'gurpreet',
};

String? signerOf(String? device, int? seq) => certs[device];

void main() {
  const book = 'farm';
  const three = OwnerSetVersion(
    version: 1,
    ownerIds: {'amrit', 'sukhdev', 'harjit'},
    quorum: StructuralQuorum.allOwners,
  );
  const majority = OwnerSetVersion(
    version: 1,
    ownerIds: {'amrit', 'sukhdev', 'harjit'},
    quorum: StructuralQuorum.majority,
  );
  const alone = OwnerSetVersion(
    version: 1,
    ownerIds: {'amrit'},
    quorum: StructuralQuorum.allOwners,
  );

  StructuralRequest request({
    String by = 'amrit',
    String? device = 'd-amrit',
    Hlc? hlc,
  }) => StructuralRequest(
    id: 'req-ratio',
    bookId: book,
    hlc: hlc ?? at(10),
    action: StructuralAction.ownershipRatio,
    byUser: by,
    ownerSetVersion: 1,
    payload: const {
      'partner_shares': {
        'farm:amrit': 40,
        'farm:sukhdev': 30,
        'farm:harjit': 30,
      },
    },
    authorDevice: device,
    authorSeq: 1,
  );

  StructuralApproval approve(
    String by,
    Hlc hlc, {
    required String? device,
    String? id,
    int seq = 1,
    String requestId = 'req-ratio',
  }) => StructuralApproval(
    id: id ?? 'ok-$by-${hlc.raw}',
    bookId: book,
    hlc: hlc,
    requestId: requestId,
    byUser: by,
    ownerSetVersion: 1,
    authorDevice: device,
    authorSeq: seq,
  );

  StructuralVeto veto(String by, Hlc hlc, {required String? device}) =>
      StructuralVeto(
        id: 'veto-$by',
        bookId: book,
        hlc: hlc,
        requestId: 'req-ratio',
        byUser: by,
        ownerSetVersion: 1,
        reason: 'not agreed',
        authorDevice: device,
        authorSeq: 1,
      );

  StructuralOutcome run(
    List<StructuralEvent> records, {
    StructuralRequest? req,
    OwnerSetVersion owners = three,
    int asOfDay = 15,
    StructuralSignerOf? signer = signerOf,
  }) => evaluateStructural(
    request: req ?? request(),
    records: records,
    owners: [owners],
    asOfMs: day(asOfDay),
    signerOf: signer,
  );

  StructuralIgnored? ignoredOf(StructuralOutcome o, String id) =>
      o.ignored.where((i) => i.recordId == id).firstOrNull;

  group('A-02-97 an approval counts only when signed on that owner\'s own '
      'certified device (02 §7.2.1 🔒)', () {
    test('A-02-97 forged by_user: an approval "by" an owner signed on another '
        'member\'s or another owner\'s certified device never counts, and '
        'does not use up the owner\'s own slot', () {
      // Pre-fix: approved at day 13 — three claims, one device.
      final out = run([
        // A member's phone claims amrit first …
        approve('amrit', at(11), device: 'd-mem', id: 'forged-amrit'),
        approve('sukhdev', at(12), device: 'd-sukhdev'),
        // … and sukhdev's phone claims harjit.
        approve('harjit', at(13), device: 'd-sukhdev', id: 'forged-harjit'),
        // amrit's real approval, after the forgery in her name.
        approve('amrit', at(14), device: 'd-amrit'),
      ]);
      expect(out.status, StructuralStatus.pending);
      expect(out.isApplied, isFalse);
      expect(out.approvedBy, ['sukhdev', 'amrit']);
      expect(
        ignoredOf(out, 'forged-amrit')?.reason,
        StructuralIgnoreReason.signerNotBound,
      );
      expect(
        ignoredOf(out, 'forged-harjit')?.reason,
        StructuralIgnoreReason.signerNotBound,
      );
      // Every record was attributed — the forgeries are refused, not unknown.
      expect(out.signersConfirmed, isTrue);
      expect(out.threshold, 3);
    });

    test('A-02-97 the signer is asked by signing identity (author device, '
        'author seq), never by record id or by_user: a member\'s record whose '
        'id and by_user copy an owner\'s cannot take that owner\'s signer, '
        'however it sorts', () {
      // Review TRUST200 #1: a signer keyed by record id let the later of two
      // records sharing an id overwrite the earlier one's signer. Here the
      // engine is handed a spy that records exactly what it is asked.
      final asked = <(String?, int?)>[];
      String? spy(String? device, int? seq) {
        asked.add((device, seq));
        return certs[device];
      }

      // The member's forgery copies amrit's record id and sorts BEFORE amrit's
      // own approval; sukhdev's phone copies harjit's id and sorts AFTER.
      final out = run(
        [
          approve('amrit', at(11), device: 'd-mem', id: 'ok-1', seq: 3),
          approve('amrit', at(12), device: 'd-amrit', id: 'ok-1', seq: 1),
          approve('harjit', at(13), device: 'd-harjit', id: 'ok-2', seq: 1),
          approve('harjit', at(14), device: 'd-sukhdev', id: 'ok-2', seq: 2),
          approve('sukhdev', at(15), device: 'd-sukhdev', id: 'ok-3', seq: 3),
        ],
        signer: spy,
        asOfDay: 16,
      );
      expect(out.status, StructuralStatus.approved);
      expect(out.approvedBy, ['amrit', 'harjit', 'sukhdev']);
      expect(out.decidedAt, at(15));
      // The two copies were refused on their own signing identity; the
      // owners' own records counted on theirs.
      expect(
        out.ignored
            .where((i) => i.reason == StructuralIgnoreReason.signerNotBound)
            .map((i) => i.recordId),
        ['ok-1', 'ok-2'],
      );
      // The signer was asked once per record, by (device, seq) only — the
      // record id and by_user never reach it (the type has no place for them).
      expect(asked, [
        ('d-amrit', 1), // the request
        ('d-mem', 3),
        ('d-amrit', 1),
        ('d-harjit', 1),
        ('d-sukhdev', 2),
        ('d-sukhdev', 3),
      ]);

      // The probe of review TRUST200 #1: majority of three, amrit approves,
      // harjit vetoes, sukhdev approves → vetoed. A member envelope answering
      // ANOTHER request in the member's own name, whose id copies the veto's,
      // changes nothing: it is not this request's record at all, and even
      // were it, it would be asked about on its own device.
      final vetoed = run([
        approve('amrit', at(11), device: 'd-amrit'),
        veto('harjit', at(12), device: 'd-harjit'),
        approve('sukhdev', at(13), device: 'd-sukhdev'),
        approve(
          'gurpreet',
          at(14),
          device: 'd-mem',
          id: 'veto-harjit',
          seq: 9,
          requestId: 'req-other',
        ),
      ], owners: majority);
      expect(vetoed.status, StructuralStatus.vetoed);
      expect(vetoed.veto?.byUser, 'harjit');
      expect(vetoed.ignored.where((i) => i.recordId == 'veto-harjit'), isEmpty);
      expect(vetoed.approvedBy, ['amrit']);
    });

    test('A-02-97 nobody: a device the reader cannot certify — none, or '
        'revoked at or before the record — is not counted, and the request is '
        'not applied even once the others reach quorum (an unseen record may '
        'be the veto that closed it)', () {
      // Pre-fix: approved at day 12 (majority of three = 2) with the ghost's.
      final out = run([
        approve('harjit', at(11), device: 'd-ghost', id: 'ghost'),
        approve('amrit', at(12), device: 'd-amrit'),
        approve('sukhdev', at(13), device: 'd-sukhdev'),
      ], owners: majority);
      expect(out.status, StructuralStatus.pending);
      expect(out.isApplied, isFalse);
      expect(out.signersConfirmed, isFalse);
      expect(out.approvedBy, ['amrit', 'sukhdev']);
      expect(
        ignoredOf(out, 'ghost')?.reason,
        StructuralIgnoreReason.signerUnknown,
      );
      // The hold is not a lapse: inside the window it is pending.
      expect(out.decidedAt, isNull);

      // A revoked device is nobody from its cut-off on (04 §9.2: the cut-off
      // is a seq). The reader's function models the chain: harjit's phone was
      // revoked at seq 5.
      String? chain(String? device, int? seq) {
        if (device == 'd-harjit' && (seq ?? 0) >= 5) return null;
        return certs[device];
      }

      final before = run([
        approve('amrit', at(11), device: 'd-amrit'),
        approve('sukhdev', at(12), device: 'd-sukhdev'),
        approve('harjit', at(13), device: 'd-harjit', seq: 4),
      ], signer: chain);
      expect(before.status, StructuralStatus.approved);
      expect(before.signersConfirmed, isTrue);

      final after = run([
        approve('amrit', at(11), device: 'd-amrit'),
        approve('sukhdev', at(12), device: 'd-sukhdev'),
        approve('harjit', at(13), device: 'd-harjit', seq: 5),
      ], signer: chain);
      expect(after.status, StructuralStatus.pending);
      expect(after.signersConfirmed, isFalse);
      expect(after.approvedBy, ['amrit', 'sukhdev']);

      // A record with no author device at all is nobody too (fail closed).
      final bare = run([
        approve('amrit', at(11), device: 'd-amrit'),
        approve('sukhdev', at(12), device: 'd-sukhdev'),
        approve('harjit', at(13), device: null, id: 'bare'),
      ]);
      expect(bare.status, StructuralStatus.pending);
      expect(
        ignoredOf(bare, 'bare')?.reason,
        StructuralIgnoreReason.signerUnknown,
      );
    });

    test('A-02-97 an unattributed record ordered after the decision point '
        'does not unsettle a decided request', () {
      final out = run([
        approve('amrit', at(11), device: 'd-amrit'),
        approve('sukhdev', at(12), device: 'd-sukhdev'),
        approve('harjit', at(13), device: 'd-harjit'),
        approve('harjit', at(14), device: 'd-ghost', id: 'late-ghost'),
      ]);
      expect(out.status, StructuralStatus.approved);
      expect(out.decidedAt, at(13));
      expect(out.signersConfirmed, isTrue);
      expect(
        ignoredOf(out, 'late-ghost')?.reason,
        StructuralIgnoreReason.afterDecision,
      );
    });

    test('A-02-97 a veto is bound the same way: a certified owner\'s veto '
        'closes a request whose other records are unattributed; a veto "by" '
        'an owner from another device closes nothing', () {
      // A real veto beats an unknown approval before it — closed is closed.
      final closed = run([
        approve('amrit', at(11), device: 'd-ghost', id: 'ghost'),
        veto('harjit', at(12), device: 'd-harjit'),
      ]);
      expect(closed.status, StructuralStatus.vetoed);
      expect(closed.veto?.id, 'veto-harjit');
      expect(closed.signersConfirmed, isFalse);

      // Pre-fix: vetoed at day 12 by a member's phone.
      final forged = run([
        approve('amrit', at(11), device: 'd-amrit'),
        veto('harjit', at(12), device: 'd-mem'),
        approve('sukhdev', at(13), device: 'd-sukhdev'),
        approve('harjit', at(14), device: 'd-harjit'),
      ]);
      expect(forged.status, StructuralStatus.approved);
      expect(forged.decidedAt, at(14));
      expect(forged.veto, isNull);
      expect(
        ignoredOf(forged, 'veto-harjit')?.reason,
        StructuralIgnoreReason.signerNotBound,
      );
      expect(forged.signersConfirmed, isTrue);
    });

    test('A-02-97 the initiation is bound too: a single-owner book\'s request '
        'signed on another device applies nothing (the quorum of one is the '
        'owner\'s own signature), an unattributed one is held, and a forged '
        'request can never be approved', () {
      // Pre-fix: approved at its own order point, by a member's phone.
      final forgedAlone = run(
        const [],
        req: request(device: 'd-mem'),
        owners: alone,
      );
      expect(forgedAlone.status, StructuralStatus.pending);
      expect(forgedAlone.isApplied, isFalse);
      expect(forgedAlone.decidedAt, isNull);
      expect(
        ignoredOf(forgedAlone, 'req-ratio')?.reason,
        StructuralIgnoreReason.signerNotBound,
      );
      expect(forgedAlone.signersConfirmed, isTrue);

      final unknownAlone = run(
        const [],
        req: request(device: 'd-ghost'),
        owners: alone,
      );
      expect(unknownAlone.status, StructuralStatus.pending);
      expect(unknownAlone.signersConfirmed, isFalse);
      expect(
        ignoredOf(unknownAlone, 'req-ratio')?.reason,
        StructuralIgnoreReason.signerUnknown,
      );

      // The owner's own initiation still applies as before (A-02-94).
      final own = run(const [], req: request(), owners: alone);
      expect(own.status, StructuralStatus.approved);
      expect(own.decidedById, 'req-ratio');

      // Three real approvals cannot rescue a forged request: nothing is
      // counted against a request nobody certified initiated.
      final forgedThree = run([
        approve('amrit', at(11), device: 'd-amrit'),
        approve('sukhdev', at(12), device: 'd-sukhdev'),
        approve('harjit', at(13), device: 'd-harjit'),
      ], req: request(device: 'd-mem'));
      expect(forgedThree.status, StructuralStatus.pending);
      expect(forgedThree.approvedBy, isEmpty);
      expect(forgedThree.threshold, 3);
      // Past the window it lapses like any request nobody approved.
      final lapsed = run(const [], req: request(device: 'd-mem'), asOfDay: 30);
      expect(lapsed.status, StructuralStatus.lapsed);
    });

    test('A-02-97 a lapse record is bound too: one logged "by" a member from '
        'another device is not a recorded lapse, though the window still '
        'closes by time', () {
      final out = run([
        StructuralLapse(
          id: 'lapse',
          bookId: book,
          hlc: at(25),
          requestId: 'req-ratio',
          byUser: 'amrit',
          authorDevice: 'd-mem',
          authorSeq: 1,
        ),
      ], asOfDay: 30);
      expect(out.status, StructuralStatus.lapsed);
      expect(out.lapseRecorded, isFalse);
      expect(
        ignoredOf(out, 'lapse')?.reason,
        StructuralIgnoreReason.signerNotBound,
      );
    });

    test(
      'A-02-97 deterministic: arrival order never changes a bound outcome',
      () {
        final records = [
          approve('harjit', at(11), device: 'd-ghost', id: 'ghost'),
          approve('amrit', at(12), device: 'd-amrit'),
          approve('sukhdev', at(13), device: 'd-sukhdev'),
          approve('harjit', at(14), device: 'd-mem', id: 'forged'),
        ];
        final a = run(records);
        final b = run(records.reversed.toList());
        expect(a.status, b.status);
        expect(a.approvedBy, b.approvedBy);
        expect(a.signersConfirmed, b.signersConfirmed);
        expect(
          a.ignored.map((i) => '${i.recordId}:${i.reason.name}'),
          b.ignored.map((i) => '${i.recordId}:${i.reason.name}'),
        );
      },
    );
  });
}
