// E-200-11…22: `LedgerStructuralRequests` — S6.3's seam over the **real**
// ledger (desk 200 (c)). Until this slice `StructuralRequestsScope.of` fell
// back to an empty fake in production, so 02 §7.2.1's structural approvals
// could be neither seen nor decided in the app.
//
// What these tests hold in place (07 §26 🔒, 02 §7.2.1 🔒):
//  · a request raised through the real write path (`proposeDistribution`)
//    reaches the seam with the **engine's** count (`evaluateStructural`) —
//    test honesty: every test here fails if the adapter yields nothing;
//  · Approve and Veto each author **one** signed `structural_approval`
//    envelope bound to the request's id and book, queued for push, and apply
//    nothing;
//  · trust: a record counts only when the device that signed it belongs to
//    the user it names — an approval this phone "signs for" another owner is
//    not that owner's approval (02 §7.2.1 🔒 *authored on that owner's own
//    device*); a request whose id two envelopes claim binds no approval and is
//    not shown; quarantined or unverified rows are not read;
//  · nothing is approvable once decided or lapsed, or by a non-owner, or where
//    the phone cannot state what would change.
//
// In-memory SQLite, FakeKeyStore, injected clock. Synthetic data only.
import 'dart:async';

import 'package:core_ledger/core_ledger.dart';
import 'package:drift/drift.dart' show OrderingTerm, Value;
import 'package:data/data.dart' show EnvelopesLocalCompanion;
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/inbox/certified_signer.dart';
import 'package:rukka_folio/features/inbox/ledger_structural_requests.dart';
import 'package:rukka_folio/features/inbox/structural_requests.dart';
import 'package:rukka_folio/shared/ledger/local_ledger.dart'
    show encodeStructuralEvent;

import 'structural_fixture.dart';

/// The adapter over [b], disposed at tear-down. Other devices' signers are
/// looked up in [certs] (device id → user id); [signerOf], when given, is
/// used instead — the production `certifiedSignerOf` in the trust tests.
LedgerStructuralRequests adapterOver(
  SharedBook b, {
  Map<String, String> certs = const {},
  StructuralSigner? signerOf,
}) {
  final a = LedgerStructuralRequests(
    b.ledger,
    nameOf: b.nameOf,
    signerOf: signerOf ?? (e) => certs[e.authorDevice],
  );
  addTearDown(a.dispose);
  return a;
}

Future<StructuralInbox> loaded(LedgerStructuralRequests a) async {
  await a.refresh();
  return a.current!;
}

Future<int> structuralRows(SharedBook b) async {
  final db = b.ledger.db;
  final rows = await (db.select(
    db.envelopesLocal,
  )..where((t) => t.objectType.equals('structural_approval'))).get();
  return rows.length;
}

void main() {
  group('the read side (07 §26 🔒, 02 §7.2.1 🔒)', () {
    test('E-200-11 a profit distribution proposed through the real ledger is '
        'an S6.3 item: pending, the engine\'s 0 of 3, every partner\'s share '
        'in integer paise, and the viewer may decide', () async {
      final b = await sharedBook();
      final request = await b.proposeDistribution();
      final inbox = await loaded(adapterOver(b));

      final item = inbox.visible.single;
      expect(item.request.id, request.id);
      expect(item.action, StructuralAction.profitDistribution);
      expect(item.status, StructuralStatus.pending);
      expect(item.bookName, 'Sharma Brothers');
      expect(item.initiatorName, 'Amrit Kaur');
      // The engine's count, not owners.length: all owners by default.
      expect(item.approvals, 0);
      expect(item.required, 3);
      expect(item.ownerNames.keys.toSet(), {b.me, sukhdev, harjit});
      expect(item.viewerIsOwner, isTrue);
      expect(item.viewerIsInitiator, isTrue);
      expect(item.viewerMayDecide, isTrue);
      expect(item.block, isNull);
      // What will change: one line per partner, money in paise, summing to
      // the profit shared out (₹3,00,000 over 1 · 1 · 1).
      expect(item.termsKnown, isTrue);
      expect(item.terms.map((t) => t.subject).toList(), [
        b.partner('Amrit').name,
        b.partner('Sukhdev').name,
        b.partner('Harjit').name,
      ]);
      final shares = [
        for (final t in item.terms) (t.proposed! as StructuralMoney).paise,
      ];
      expect(shares.fold<int>(0, (s, p) => s + p), 3_00_000_00);
      expect(shares, [1_00_000_00, 1_00_000_00, 1_00_000_00]);
    });

    test('E-200-12 the live stream carries a request the moment it is '
        'authored — no refresh', () async {
      final b = await sharedBook();
      final a = adapterOver(b);
      final seen = Completer<StructuralInbox>();
      final sub = a.watch().listen((s) {
        if (!s.isEmpty && !seen.isCompleted) seen.complete(s);
      });
      addTearDown(sub.cancel);
      final request = await b.proposeDistribution();
      final inbox = await seen.future.timeout(const Duration(seconds: 10));
      expect(inbox.visible.single.request.id, request.id);
    });

    test('E-200-13 a request this phone authored "for" another owner is not '
        'theirs, and approvals it signs in their names are not counted — '
        'the signer must be the user the record names', () async {
      final b = await sharedBook();
      final request = await b.proposeDistribution();
      // Forged on this device: an approval and a request in Sukhdev's name.
      await b.ledger.authorStructural(
        (hlc, id) => StructuralApproval(
          id: id,
          bookId: b.bookId,
          hlc: hlc,
          requestId: request.id,
          byUser: sukhdev,
          ownerSetVersion: 1,
        ),
      );
      final forged = await b.ledger.authorStructural(
        (hlc, id) => request.copyWith(id: id, hlc: hlc).withByUser(sukhdev),
      );
      final inbox = await loaded(adapterOver(b));
      final item = inbox.visible.single;
      expect(item.request.id, request.id);
      expect(item.approvals, 0, reason: 'the forged approval is not counted');
      expect(
        inbox.items.where((i) => i.request.id == forged.id),
        isEmpty,
        reason: 'a request signed by someone other than its initiator',
      );
    });

    test('E-200-14 a request id claimed by two initiation envelopes binds no '
        'approval and is not shown', () async {
      final b = await sharedBook();
      final request = await b.proposeDistribution();
      final a = adapterOver(b);
      // An approval that counts while the request is unambiguous (the
      // positive precondition: this test fails if the adapter yields nothing).
      await b.ledger.authorStructural(
        (hlc, id) => StructuralApproval(
          id: id,
          bookId: b.bookId,
          hlc: hlc,
          requestId: request.id,
          byUser: b.me,
          ownerSetVersion: request.ownerSetVersion,
        ),
      );
      final before = await loaded(a);
      expect(before.visible, hasLength(1));
      expect(before.visible.single.request.id, request.id);
      expect(before.visible.single.approvals, 1);
      expect(a.refused, isEmpty);

      // A second envelope under the same object id, different terms.
      await b.ledger.authorStructural(
        (hlc, _) => request.copyWith(hlc: hlc, payload: const {'lines': []}),
      );
      final inbox = await loaded(a);
      expect(
        inbox.items,
        isEmpty,
        reason: 'neither version is shown, so the approval binds to nothing',
      );
      final db = b.ledger.db;
      final carriers = await (db.select(
        db.envelopesLocal,
      )..where((t) => t.objectId.equals(request.id))).get();
      expect(carriers, hasLength(2));
      expect(a.refused, {
        for (final r in carriers)
          r.envelopeId: StructuralEnvelopeRefusal.ambiguousRequest,
      }, reason: 'both carriers refused for exactly this reason, nothing else');
      expect(inbox.unconfirmed, 0);
    });

    test('E-200-15 a quarantined or unverified envelope is not read', () async {
      final b = await sharedBook();
      final request = await b.proposeDistribution();
      final a = adapterOver(b);
      expect((await loaded(a)).visible, hasLength(1));

      final db = b.ledger.db;
      await (db.update(db.envelopesLocal)
            ..where((t) => t.objectId.equals(request.id)))
          .write(const EnvelopesLocalCompanion(quarantined: Value(1)));
      expect((await loaded(a)).items, isEmpty);

      await (db.update(
        db.envelopesLocal,
      )..where((t) => t.objectId.equals(request.id))).write(
        const EnvelopesLocalCompanion(
          quarantined: Value(0),
          verified: Value(0),
        ),
      );
      expect((await loaded(a)).items, isEmpty);
    });

    test('E-200-16 past its 14-day window a request reads lapsed and offers '
        'no decision; a fortnight after that it leaves the Inbox', () async {
      final b = await sharedBook();
      final request = await b.proposeDistribution();
      final a = adapterOver(b);
      b.clock.advance(const Duration(days: 15));
      final item = (await loaded(a)).visible.single;
      expect(item.request.id, request.id);
      expect(item.status, StructuralStatus.lapsed);
      expect(item.viewerMayDecide, isFalse);
      final before = await structuralRows(b);
      await expectLater(
        a.approve(request.id),
        throwsA(isA<StructuralRequestFailure>()),
      );
      expect(await structuralRows(b), before);

      b.clock.advance(const Duration(days: 15));
      expect((await loaded(a)).items, isEmpty);
    });

    test('E-200-17 a member who is not an owner sees the request, is told who '
        'decides, and cannot sign either way', () async {
      final b = await sharedBook(viewerIsOwner: false);
      final request = await b.proposeDistribution();
      final a = adapterOver(b);
      final item = (await loaded(a)).visible.single;
      expect(item.viewerIsOwner, isFalse);
      expect(item.block, StructuralBlock.notAnOwner);
      expect(item.required, 2);
      final before = await structuralRows(b);
      await expectLater(
        a.approve(request.id),
        throwsA(isA<StructuralRequestFailure>()),
      );
      await expectLater(
        a.veto(requestId: request.id, reason: 'not agreed'),
        throwsA(isA<StructuralRequestFailure>()),
      );
      expect(await structuralRows(b), before);
    });
  });

  group('the write side — one signed envelope each, nothing applied', () {
    test('E-200-18 Approve authors one signed approval bound to the request '
        'and its book, queued for push; the count becomes 1 of 3 and a second '
        'Approve is refused', () async {
      final b = await sharedBook();
      final request = await b.proposeDistribution();
      final a = adapterOver(b);
      await loaded(a);
      final before = await structuralRows(b);

      await a.approve(request.id);

      expect(await structuralRows(b), before + 1);
      final db = b.ledger.db;
      final newest =
          await (db.select(db.envelopesLocal)
                ..where((t) => t.objectType.equals('structural_approval'))
                ..orderBy([(t) => OrderingTerm.desc(t.hlc)])
                ..limit(1))
              .getSingle();
      expect(newest.bookId, b.bookId);
      expect(newest.authorDevice, b.ledger.identity.deviceId);
      final queued = await (db.select(
        db.outbox,
      )..where((o) => o.envelopeId.equals(newest.envelopeId))).get();
      expect(queued, hasLength(1), reason: 'signed and queued for push');

      final item = (await loaded(a)).visible.single;
      // The engine counted it — so it names this request (02 §7.2.1 🔒).
      expect(item.outcome.approvedBy, [b.me]);
      expect(item.approvals, 1);
      expect(item.required, 3);
      expect(item.status, StructuralStatus.pending);
      expect(item.block, StructuralBlock.alreadyApproved);

      await expectLater(
        a.approve(request.id),
        throwsA(isA<StructuralRequestFailure>()),
      );
      expect(await structuralRows(b), before + 1);
    });

    test('E-200-19 Veto with a reason closes the request, records who and '
        'why, and nothing can be signed on it afterwards', () async {
      final b = await sharedBook();
      final request = await b.proposeDistribution();
      final a = adapterOver(b);
      await loaded(a);

      await a.veto(requestId: request.id, reason: 'Wait for the bank loan');

      final item = (await loaded(a)).visible.single;
      expect(item.status, StructuralStatus.vetoed);
      expect(item.vetoReason, 'Wait for the bank loan');
      expect(item.vetoBy, 'Amrit Kaur');
      final before = await structuralRows(b);
      await expectLater(
        a.approve(request.id),
        throwsA(isA<StructuralRequestFailure>()),
      );
      expect(await structuralRows(b), before);
      expect(
        () => a.veto(requestId: request.id, reason: '  '),
        throwsArgumentError,
      );
    });

    test('E-200-20 re-initiation is not offered: nobody here may raise one '
        'and the seam refuses rather than reviving a request', () async {
      final b = await sharedBook();
      final request = await b.proposeDistribution();
      final a = adapterOver(b);
      b.clock.advance(const Duration(days: 15));
      final item = (await loaded(a)).visible.single;
      expect(item.viewerCanInitiate, isFalse);
      final before = await structuralRows(b);
      await expectLater(
        a.reinitiate(request.id),
        throwsA(isA<StructuralRequestFailure>()),
      );
      expect(await structuralRows(b), before);
    });
  });

  group('trust, across devices (pure — the read rule itself)', () {
    const book = 'b1';
    const device = 'device-amrit';
    const sukhdevDevice = 'device-sukhdev';
    const harjitDevice = 'device-harjit';
    final now = DateTime(2026, 9, 7, 10).millisecondsSinceEpoch;
    Hlc at(int minutes) =>
        Hlc.compose(physicalMs: now - 60 * 60 * 1000 + minutes, counter: 0);

    final accounts = [
      for (final (i, (id, name, member)) in const [
        ('acc-amrit', 'Amrit', 'u-amrit'),
        ('acc-sukhdev', 'Sukhdev', 'u-sukhdev'),
        ('acc-harjit', 'Harjit', 'u-harjit'),
      ].indexed)
        Account(
          id: id,
          bookId: book,
          name: name,
          accountClass: AccountClass.partner,
          memberId: member,
          createdOrder: i,
        ),
      Account(
        id: 'acc-pd',
        bookId: book,
        name: 'Profit Distributed',
        accountClass: AccountClass.equitySystem,
        systemRole: SystemRole.profitDistributed,
        createdOrder: 9,
      ),
    ];

    OpenedStructuralEnvelope env(
      String device,
      StructuralEvent e, {
      String? objectId,
      String bookId = book,
    }) => OpenedStructuralEnvelope(
      envelopeId: 'env-${e.id}-$device',
      objectId: objectId ?? e.id,
      bookId: bookId,
      objectType: 'structural_approval',
      authorDevice: device,
      authorSeq: 1,
      hlc: e.hlc.raw,
      json: encodeStructuralEvent(e),
    );

    final deed = OpenedStructuralEnvelope(
      envelopeId: 'env-deed',
      objectId: book,
      bookId: book,
      objectType: 'book_config',
      authorDevice: device,
      authorSeq: 0,
      hlc: at(0).raw,
      json: {
        'id': book,
        'tenant_id': 't1',
        'type': 'business',
        'name': 'Sharma Brothers',
        'partner_shares': {'acc-amrit': 1, 'acc-sukhdev': 1, 'acc-harjit': 1},
      },
    );

    StructuralRequest ratio({Map<String, Object?>? payload}) =>
        StructuralRequest(
          id: 'r1',
          bookId: book,
          hlc: at(1),
          action: StructuralAction.ownershipRatio,
          byUser: 'u-amrit',
          ownerSetVersion: 1,
          payload:
              payload ??
              const {
                'partner_shares': {
                  'acc-amrit': 40,
                  'acc-sukhdev': 30,
                  'acc-harjit': 30,
                },
              },
        );

    StructuralApproval approval(String by, int minute) => StructuralApproval(
      id: 'a-$by',
      bookId: book,
      hlc: at(minute),
      requestId: 'r1',
      byUser: by,
      ownerSetVersion: 1,
    );

    const certs = {
      device: 'u-amrit',
      sukhdevDevice: 'u-sukhdev',
      harjitDevice: 'u-harjit',
    };

    StructuralItem? read(
      List<OpenedStructuralEnvelope> envs, {
      String viewer = 'u-harjit',
      Map<String, String> known = certs,
    }) {
      final view = readStructuralBook(
        bookId: book,
        bookName: 'Sharma Brothers',
        envelopes: [deed, ...envs],
        accounts: accounts,
        viewerId: viewer,
        signerOf: (e) => known[e.authorDevice],
        nameOf: (u) => u,
        asOfMs: now,
      );
      return view.items.where((i) => i.request.id == 'r1').firstOrNull;
    }

    test('E-200-21 an approval signed on another owner\'s certified device '
        'counts; the same record from a device certified to someone else, or '
        'to nobody this phone knows, does not', () {
      final r = ratio();
      final bound = read([
        env(device, r),
        env(device, approval('u-amrit', 2)),
        env(sukhdevDevice, approval('u-sukhdev', 3)),
      ])!;
      expect(bound.outcome.approvedBy, ['u-amrit', 'u-sukhdev']);
      expect(bound.approvals, 2);
      expect(bound.required, 3);
      expect(bound.viewerMayDecide, isTrue, reason: 'Harjit, the third owner');

      final crossSigned = read([
        env(device, r),
        env(device, approval('u-amrit', 2)),
        // Harjit's device "approving" as Sukhdev.
        env(harjitDevice, approval('u-sukhdev', 3)),
      ])!;
      expect(crossSigned.outcome.approvedBy, ['u-amrit']);

      expect(
        crossSigned.signersConfirmed,
        isTrue,
        reason: 'a record signed in another\'s name is refused, not unknown',
      );
      expect(crossSigned.viewerMayDecide, isTrue);

      final unknownDevice = read([
        env(device, r),
        env(device, approval('u-amrit', 2)),
        env('device-unseen', approval('u-sukhdev', 3)),
      ])!;
      expect(unknownDevice.outcome.approvedBy, ['u-amrit']);
      // …but the book is not decidable until that signer can be named.
      expect(unknownDevice.signersConfirmed, isFalse);
      expect(unknownDevice.block, StructuralBlock.signersUnconfirmed);
      expect(unknownDevice.viewerMayDecide, isFalse);
      expect(unknownDevice.viewerMayVeto, isFalse);
    });

    test('E-200-22 a veto counts only from its owner\'s own device; a record '
        'naming another book or another object is not read', () {
      final r = ratio();
      final veto = StructuralVeto(
        id: 'v1',
        bookId: book,
        hlc: at(2),
        requestId: 'r1',
        byUser: 'u-sukhdev',
        ownerSetVersion: 1,
        reason: 'Not this season',
      );
      expect(
        read([env(device, r), env(sukhdevDevice, veto)])!.status,
        StructuralStatus.vetoed,
      );
      expect(
        read([env(device, r), env(harjitDevice, veto)])!.status,
        StructuralStatus.pending,
        reason: 'a veto signed by Harjit in Sukhdev\'s name',
      );
      // The request's envelope routed in another book, or carried under
      // another object id, is not this request.
      expect(read([env(device, r, bookId: 'b2')]), isNull);
      expect(read([env(device, r, objectId: 'r-other')]), isNull);
    });

    test('E-200-23 a ratio change states each owner\'s weight now and '
        'proposed; one carrying a change the card cannot state offers Veto '
        'but not Approve', () {
      final ok = read([env(device, ratio())])!;
      expect(ok.termsKnown, isTrue);
      expect(
        [
          for (final t in ok.terms)
            (
              t.subject,
              (t.current! as StructuralText).text,
              (t.proposed! as StructuralText).text,
            ),
        ],
        [('Amrit', '1', '40'), ('Sukhdev', '1', '30'), ('Harjit', '1', '30')],
      );

      // A ratio change that also moves the quorum rule: the card would say
      // "ownership shares" and hide the rest (02 §7.2.1 🔒; ADR 2026-09-14b).
      final smuggled = read([
        env(
          device,
          ratio(
            payload: const {
              'partner_shares': {
                'acc-amrit': 40,
                'acc-sukhdev': 30,
                'acc-harjit': 30,
              },
              'structural_quorum': 'majority',
            },
          ),
        ),
      ])!;
      expect(smuggled.termsKnown, isFalse);
      expect(smuggled.block, StructuralBlock.termsUnknown);
      expect(smuggled.viewerMayDecide, isFalse);
      expect(smuggled.viewerMayVeto, isTrue);

      // A "ratio change" that drops an owner is an owner change in disguise.
      final drops = read([
        env(
          device,
          ratio(
            payload: const {
              'partner_shares': {'acc-amrit': 1, 'acc-sukhdev': 1},
            },
          ),
        ),
      ])!;
      expect(drops.termsKnown, isFalse);

      // An action whose payload no doc fixes.
      final archive = read([
        env(
          device,
          StructuralRequest(
            id: 'r1',
            bookId: book,
            hlc: at(1),
            action: StructuralAction.bookArchiveOrDelete,
            byUser: 'u-amrit',
            ownerSetVersion: 1,
            payload: const {'mode': 'delete'},
          ),
        ),
      ])!;
      expect(archive.termsKnown, isFalse);
      expect(archive.viewerMayDecide, isFalse);
    });
  });

  // Review F200I-1…3: the production signer check, on the production trust
  // store, over envelopes another phone really signed. Every test here starts
  // from a positive reading through `certifiedSignerOf`, so none of them
  // passes on a seam that names nobody.
  group('trust, on the production signer (certifiedSignerOf over '
      'RecordTrustStore, 04 §3.4)', () {
    test('E-200-24 an approval signed on another owner\'s own certified '
        'phone, chain-verified into the mirror, is counted through '
        'certifiedSignerOf — and only while its certificate is held', () async {
      final b = await sharedBook();
      final request = await b.proposeDistribution();
      final trust = productionTrust(b);
      final phone = await remotePhone(b, sukhdev);
      phone.fileCertIn(trust);
      expect(
        await receiveFrom(
          b,
          phone,
          approvalOf(b, request, sukhdev),
          trust: trust,
          authorSeq: 1,
        ),
        isTrue,
        reason: 'the engine\'s own chain check passes for this envelope',
      );
      final a = adapterOver(
        b,
        signerOf: certifiedSignerOf(trust, b.ledger.suite),
      );
      final item = (await loaded(a)).visible.single;
      expect(item.request.id, request.id);
      expect(item.outcome.approvedBy, [sukhdev]);
      expect(item.approvals, 1);
      expect(item.signersConfirmed, isTrue);
      expect(item.viewerMayDecide, isTrue);
      expect(a.refused, isEmpty);

      // The same envelope with no certificate held — a launch before the
      // meta read — is not counted, and is not silently dropped either.
      trust.certs.clear();
      final cold = await loaded(a);
      expect(cold.visible.single.approvals, 0);
      expect(cold.unconfirmed, 1);
      expect(a.refused.values, [StructuralEnvelopeRefusal.signerUnknown]);
    });

    test(
      'E-200-25 a server that relabels a member\'s phone as an owner\'s '
      'gets nobody: the approval that phone signed in the owner\'s name is '
      'not counted, though the user id alone would have counted it',
      () async {
        final b = await sharedBook();
        final request = await b.proposeDistribution();
        final trust = productionTrust(b);
        // Harjit is a verified owner; Ramesh a verified member, not an owner.
        await remotePhone(b, harjit);
        final member = await remotePhone(b, ramesh);
        member.fileCertIn(trust);
        // Ramesh's phone signs an approval "by" Harjit. The chain holds — it
        // proves the device, not the payload's by_user.
        expect(
          await receiveFrom(
            b,
            member,
            approvalOf(b, request, harjit),
            trust: trust,
            authorSeq: 1,
          ),
          isTrue,
        );
        final production = adapterOver(
          b,
          signerOf: certifiedSignerOf(trust, b.ledger.suite),
        );
        var item = (await loaded(production)).visible.single;
        expect(item.approvals, 0, reason: 'Ramesh is not Harjit');
        expect(production.refused.values, [
          StructuralEnvelopeRefusal.signerNotBound,
        ]);
        expect(item.signersConfirmed, isTrue);

        // The server now says Ramesh's device is Harjit's: the certificate the
        // engine rebuilds carries the devices row's user, signature untouched.
        trust.certs[member.deviceId] = relabelled(member.cert, harjit);

        // What the slice shipped before this repair — the label alone — would
        // count it (the attack is real on this fixture)…
        final labelOnly = adapterOver(
          b,
          signerOf: (e) => trust.certOf(e.authorDevice)?.userId,
        );
        expect((await loaded(labelOnly)).visible.single.outcome.approvedBy, [
          harjit,
        ]);
        // …the production signer re-runs the chain and names nobody.
        item = (await loaded(production)).visible.single;
        expect(item.approvals, 0);
        expect(item.outcome.approvedBy, isEmpty);
        expect(production.refused.values, [
          StructuralEnvelopeRefusal.signerUnknown,
        ]);
        expect(item.block, StructuralBlock.signersUnconfirmed);
      },
    );

    test('E-200-26 a certificate for the same device id over other keys names '
        'nobody for the envelopes those keys did not sign', () async {
      final b = await sharedBook();
      final request = await b.proposeDistribution();
      final trust = productionTrust(b);
      final owner = await remotePhone(b, sukhdev);
      // A member's phone that took Sukhdev's device id, under the member's
      // own (verified) UMK and its own keys.
      final impostor = await remotePhone(b, ramesh, deviceId: owner.deviceId);
      impostor.fileCertIn(trust);
      expect(
        await receiveFrom(
          b,
          impostor,
          approvalOf(b, request, sukhdev),
          trust: trust,
          authorSeq: 1,
        ),
        isTrue,
        reason: 'verified under the impostor\'s own certificate',
      );
      // Later the genuine certificate for that id is served.
      owner.fileCertIn(trust);
      final labelOnly = adapterOver(
        b,
        signerOf: (e) => trust.certOf(e.authorDevice)?.userId,
      );
      expect((await loaded(labelOnly)).visible.single.approvals, 1);
      final production = adapterOver(
        b,
        signerOf: certifiedSignerOf(trust, b.ledger.suite),
      );
      final item = (await loaded(production)).visible.single;
      expect(item.approvals, 0);
      expect(production.refused.values, [
        StructuralEnvelopeRefusal.signerUnknown,
      ]);

      // Sukhdev's own approval from his own keys still counts.
      expect(
        await receiveFrom(
          b,
          owner,
          approvalOf(b, request, sukhdev, minutes: 2),
          trust: trust,
          authorSeq: 2,
          seq: 2,
        ),
        isTrue,
      );
      expect((await loaded(production)).visible.single.outcome.approvedBy, [
        sukhdev,
      ]);
    });

    test(
      'E-200-27 a launch before the meta read: another owner\'s veto and '
      'request are not counted, but nothing in the book is offered to sign '
      '— approve() and veto() author nothing — and the snapshot counts what '
      'waits; once the certificate arrives the veto closes the request',
      () async {
        final b = await sharedBook();
        final request = await b.proposeDistribution();
        final online = productionTrust(b);
        final phone = await remotePhone(b, sukhdev);
        phone.fileCertIn(online);
        final veto = StructuralVeto(
          id: b.ledger.newId(),
          bookId: b.bookId,
          hlc: hlcAfter(request.hlc, 1),
          requestId: request.id,
          byUser: sukhdev,
          ownerSetVersion: request.ownerSetVersion,
          reason: 'Not this season',
        );
        expect(
          await receiveFrom(b, phone, veto, trust: online, authorSeq: 1),
          isTrue,
        );
        final raised = request
            .copyWith(id: b.ledger.newId(), hlc: hlcAfter(request.hlc, 2))
            .withByUser(sukhdev);
        expect(
          await receiveFrom(
            b,
            phone,
            raised,
            trust: online,
            authorSeq: 2,
            seq: 2,
          ),
          isTrue,
        );
        // While the certificate is held: vetoed, and Sukhdev's own request is
        // read (positive precondition).
        final warm = adapterOver(
          b,
          signerOf: certifiedSignerOf(online, b.ledger.suite),
        );
        final warmInbox = await loaded(warm);
        expect(
          warmInbox.items.firstWhere((i) => i.request.id == request.id).status,
          StructuralStatus.vetoed,
        );
        expect(warmInbox.items.map((i) => i.request.id), contains(raised.id));

        // Relaunch, offline: a trust store built from scratch holds no other
        // device's certificate (bootstrap seeds only this device's own).
        final cold = productionTrust(b);
        final a = adapterOver(
          b,
          signerOf: certifiedSignerOf(cold, b.ledger.suite),
        );
        final inbox = await loaded(a);
        final item = inbox.visible.single;
        expect(item.request.id, request.id);
        expect(
          item.status,
          StructuralStatus.pending,
          reason: 'what is confirmed',
        );
        expect(item.signersConfirmed, isFalse);
        expect(item.block, StructuralBlock.signersUnconfirmed);
        expect(item.viewerMayDecide, isFalse);
        expect(item.viewerMayVeto, isFalse);
        expect(inbox.unconfirmed, 2, reason: 'the veto and the request wait');
        expect(inbox.isEmpty, isFalse);
        final before = await structuralRows(b);
        await expectLater(
          a.approve(request.id),
          throwsA(isA<StructuralRequestFailure>()),
        );
        await expectLater(
          a.veto(requestId: request.id, reason: 'No'),
          throwsA(isA<StructuralRequestFailure>()),
        );
        expect(await structuralRows(b), before, reason: 'nothing was signed');

        // The meta read lands: the same seam now reads the veto.
        phone.fileCertIn(cold);
        final after = await loaded(a);
        expect(after.unconfirmed, 0);
        final closed = after.items.firstWhere(
          (i) => i.request.id == request.id,
        );
        expect(closed.status, StructuralStatus.vetoed);
        expect(closed.vetoBy, 'Sukhdev Singh');
        expect(after.items.map((i) => i.request.id), contains(raised.id));
      },
    );
  });
}

extension on StructuralRequest {
  /// The same request claiming another initiator — what a forger would sign.
  StructuralRequest withByUser(String user) => StructuralRequest(
    id: id,
    bookId: bookId,
    hlc: hlc,
    action: action,
    byUser: user,
    ownerSetVersion: ownerSetVersion,
    payload: payload,
  );
}
