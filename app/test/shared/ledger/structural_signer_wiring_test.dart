// F1-200-31 — the structural reader's signer is **installed by the
// composition root**, not only by tests (TRUST200 hand-off step 6; 02 §7.2.1
// 🔒: *each approval is authored on that owner's own device, so the server
// cannot manufacture one*).
//
// TEST HONESTY: the ledger here is `productionLedger` — the builder
// `bootstrap.dart` opens its one ledger through (C-04b-2) — and the wiring is
// `wireLedgerTrust`, the function `bootstrap.dart` calls over the trust store
// it builds, pinned below against the root's own code. If the root stopped
// calling it, or it stopped installing a signer, `structuralSignerOf` would be
// null and every other owner's record would read `signerUnknown`: the honest
// approval below would not be named, and this test would go red.
//
// F1-200-32 — the certificates the ledger **retains** (review TRUSTWIRE-1;
// 03 *Deletion mechanics* 🔒): the view `wireLedgerTrust` returns, which both
// structural signers read, offers every certificate the live store answers
// to `retainPeerCert`, answers from the retained copy where the live store
// has none, and applies the removal cut-off to the owner it names. TEST
// HONESTY: the ledger is a real `productionLedger`, the wiring is the root's
// own function, and what was kept is read back by a second ledger opened over
// the same key store — if the view offered nothing, or the ledger kept or
// reloaded nothing, the reopened ledger would hold no certificate and the
// test goes red.
//
// Synthetic names only (CLAUDE.md rule 4). Injected clock.
import 'dart:io';

import 'package:core_crypto/core_crypto.dart';
import 'package:core_ledger/core_ledger.dart';
import 'package:data/data.dart' show BookOwnership, StructuralQuarantineReason;
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/bootstrap.dart'
    show productionLedger, wireLedgerTrust;
import 'package:rukka_folio/shared/ledger/local_ledger.dart';
import 'package:rukka_folio/shared/ledger/retained_certs.dart';
import 'package:rukka_folio/shared/seams/key_store.dart' show FakeKeyStore;
import 'package:sync_engine/sync_engine.dart' as eng;

import '../../features/inbox/structural_fixture.dart' as fx;
import '../test_app.dart';

/// `lib/bootstrap.dart` with `//` comments stripped, so a pin cannot pass on
/// prose that merely names the call (the F1-24b-3 reader).
String _bootstrapCode() {
  for (final path in ['lib/bootstrap.dart', 'app/lib/bootstrap.dart']) {
    final file = File(path);
    if (!file.existsSync()) continue;
    final text = file.readAsStringSync();
    expect(text, isNotEmpty, reason: 'the root was really read');
    return [
      for (final line in text.split('\n'))
        line.contains('//') ? line.substring(0, line.indexOf('//')) : line,
    ].join('\n');
  }
  fail('lib/bootstrap.dart not found from ${Directory.current.path}');
}

/// [event] sealed under [b]'s book key and signed on [phone] — the envelope a
/// pull hands the mirror.
Envelope _signedOn(fx.SharedBook b, fx.RemotePhone phone, StructuralEvent e) {
  final l = b.ledger;
  final keys = l.keyMaterial.bookKeys;
  final version = keys.highestVersion(b.bookId)!;
  return EnvelopeBuilder.seal(
    l.suite,
    tenantId: keys.tenantIdOf(b.bookId)!,
    bookId: b.bookId,
    objectId: e.id,
    objectType: 'structural_approval',
    envelopeId: l.newId(),
    hlc: e.hlc.raw,
    authorSeq: 1,
    object: encodeStructuralEvent(e),
    bookKey: keys.bookKey(BookKeyRef(bookId: b.bookId, keyVersion: version))!,
    author: phone.device,
  );
}

void main() {
  test('F1-200-31 the root installs a chain-checked structural signer: '
      'productionLedger + wireLedgerTrust names an owner\'s certified phone, '
      'never a forger\'s or a relabelled one, and bootstrap.dart calls exactly '
      'that wiring over the trust store it builds', () async {
    // ── the root's own code ──────────────────────────────────────────────
    final root = _bootstrapCode();
    final trustAt = root.indexOf(
      RegExp(
        r'final\s+trust\s*=\s*eng\.RecordTrustStore\(\s*umks:\s*'
        r'eng\.BoundUmkSource\(\s*identity\s*\)',
      ),
    );
    expect(trustAt, greaterThan(0), reason: 'the trust store the root builds');
    expect(
      RegExp(r'final\s+identity\s*=\s*ledger\.binding;').hasMatch(root),
      isTrue,
    );
    final wired = RegExp(
      r'wireLedgerTrust\(\s*ledger\s*,\s*trust\s*,\s*suite\s*\)\s*;',
    ).allMatches(root).toList();
    expect(wired, hasLength(1), reason: 'called once, from bootstrap()');
    expect(wired.single.start, greaterThan(trustAt));
    expect(
      wired.single.start,
      greaterThan(root.indexOf('Future<void> bootstrap() async {')),
      reason: 'inside bootstrap()',
    );
    expect(
      root.indexOf(RegExp(r'runApp\(\s*MembersRepositoryScope\(')),
      greaterThan(wired.single.start),
      reason: 'installed before the app\'s first frame reads anything',
    );
    expect(
      RegExp(r'structuralSignerOf\s*=').allMatches(root),
      hasLength(1),
      reason: 'set in wireLedgerTrust and nowhere else — never cleared',
    );
    // TRUSTWIRE-1: both structural signers read the one view the wiring
    // returns — the ledger's through wireLedgerTrust, the Inbox's here.
    expect(
      RegExp(
        r'final\s+signers\s*=\s*wireLedgerTrust\(\s*ledger\s*,\s*trust\s*,'
        r'\s*suite\s*\)\s*;',
      ).hasMatch(root),
      isTrue,
    );
    expect(
      RegExp(r'signerOf:\s*certifiedSignerOf\(\s*signers\s*,\s*suite\s*\)')
          .hasMatch(root),
      isTrue,
      reason: 'the Inbox names — and retains — through the same view',
    );

    // ── the ledger the root builds, wired as the root wires it ───────────
    final testClock = TestClock();
    final ledger = productionLedger(
      db: await openTestDb(),
      keys: FakeKeyStore(),
      suite: await testSuite(),
      now: testClock.call,
    );
    addTearDown(ledger.dispose);
    final id = await ledger.bootstrapSolo();
    await ledger.confirmIdentity(id.userId);
    expect(
      ledger.structuralSignerOf,
      isNull,
      reason: 'nothing names a signer until the root wires one',
    );

    final trust = eng.RecordTrustStore(
      umks: eng.BoundUmkSource(ledger.binding),
    );
    final view = wireLedgerTrust(ledger, trust, ledger.suite);
    final signer = ledger.structuralSignerOf;
    expect(signer, isNotNull);

    // The own certificate reaches the store live (the wiring moved here).
    await ledger.installOwnCert(ledger.issueOwnCert().cert);
    expect(trust.certs[ledger.identity.deviceId], isNotNull);

    final me = ledger.identity.userId;
    final bookId = await ledger.createBook(
      name: 'Sharma Brothers',
      type: BookType.business,
      ownership: BookOwnership.shared,
      ownerNames: const ['Amrit Kaur', 'Sukhdev Singh', 'Harjit Kaur'],
      ownerShares: const [1, 1, 1],
      ownerMemberIds: [me, fx.sukhdev, fx.harjit],
      startDate: ledger.today().addDays(-20),
    );
    final b = fx.SharedBook(
      ledger,
      testClock,
      bookId,
      await ledger.chartOf(bookId),
    );
    final sukhdev = await fx.remotePhone(b, fx.sukhdev)
      ..fileCertIn(trust);
    final ramesh = await fx.remotePhone(b, fx.ramesh)
      ..fileCertIn(trust);

    StructuralRequest requestBy(String user) => StructuralRequest(
      id: ledger.newId(),
      bookId: bookId,
      hlc: Hlc.compose(
        physicalMs: testClock().millisecondsSinceEpoch,
        counter: 0,
      ),
      action: StructuralAction.ownershipRatio,
      byUser: user,
      ownerSetVersion: 1,
      payload: const {'note': 'synthetic'},
    );

    // The signer itself: the certified user, by the chain, at this read.
    expect(
      signer!(_signedOn(b, sukhdev, requestBy(fx.sukhdev)), seq: 1),
      fx.sukhdev,
    );
    expect(
      signer(_signedOn(b, ramesh, requestBy(fx.sukhdev)), seq: 2),
      fx.ramesh,
      reason: 'the device that signed, whatever by_user claims',
    );
    trust.certs[ramesh.deviceId] = fx.relabelled(ramesh.cert, fx.sukhdev);
    expect(
      signer(_signedOn(b, ramesh, requestBy(fx.sukhdev)), seq: 3),
      isNull,
      reason: 'a label the server wrote is not a certificate that verifies',
    );
    ramesh.fileCertIn(trust);

    // A device the live store holds nothing for is named through the
    // certificate this install retained — the view wireLedgerTrust returns,
    // which the Inbox's signer reads too (TRUSTWIRE-1).
    final harjit = await fx.remotePhone(b, fx.harjit);
    expect(
      signer(_signedOn(b, harjit, requestBy(fx.harjit)), seq: 4),
      isNull,
      reason: 'no certificate, live or retained',
    );
    await ledger.retainPeerCert(harjit.cert);
    expect(trust.certs[harjit.deviceId], isNull, reason: 'not in meta');
    expect(view.certOf(harjit.deviceId), same(harjit.cert));
    expect(
      signer(_signedOn(b, harjit, requestBy(fx.harjit)), seq: 5),
      fx.harjit,
    );

    // And through the structural read the distribution gate trusts.
    final honest = await fx.receiveFrom(
      b,
      sukhdev,
      requestBy(fx.sukhdev),
      trust: trust,
      authorSeq: 1,
      seq: 1,
    );
    final forged = await fx.receiveFrom(
      b,
      ramesh,
      requestBy(fx.sukhdev),
      trust: trust,
      authorSeq: 1,
      seq: 2,
    );
    expect([honest, forged], [true, true], reason: 'both chains held');
    final reading = await ledger.structuralStateOf(bookId);
    expect(reading.signersConfirmed, isTrue);
    expect(reading.recordRefusals.map((q) => q.reason), [
      StructuralQuarantineReason.signerNotBound,
    ], reason: 'only Ramesh\'s "Sukhdev requests" is refused');
  });
  test('F1-200-32 the view wireLedgerTrust returns retains every certificate '
      'the live store answers a structural signer with — only one that '
      'verifies under its user\'s ceremony-verified UMK, never this device\'s '
      'own — answers from the retained copy where the live store has none, '
      'applies the removal cut-off to its owner, and the next launch reads '
      'back what was kept', () async {
    final testClock = TestClock();
    final keys = FakeKeyStore();
    final db = await openTestDb();
    final suite = await testSuite();
    final ledger = productionLedger(
      db: db,
      keys: keys,
      suite: suite,
      now: testClock.call,
    );
    addTearDown(ledger.dispose);
    final id = await ledger.bootstrapSolo();
    await ledger.confirmIdentity(id.userId);
    await ledger.bootstrapSolo(firstBookName: 'Me');
    final bookId = (await ledger.mirror.bookIds()).single;
    final b = fx.SharedBook(
      ledger,
      testClock,
      bookId,
      await ledger.chartOf(bookId),
    );
    final trust = eng.RecordTrustStore(
      umks: eng.BoundUmkSource(ledger.binding),
    );
    final view = wireLedgerTrust(ledger, trust, suite);
    expect(view, isA<RetainedCertTrust>());
    final signer = ledger.structuralSignerOf!;

    StructuralRequest requestBy(String user) => StructuralRequest(
      id: ledger.newId(),
      bookId: bookId,
      hlc: Hlc.compose(
        physicalMs: testClock().millisecondsSinceEpoch,
        counter: 0,
      ),
      action: StructuralAction.ownershipRatio,
      byUser: user,
      ownerSetVersion: 1,
      payload: const {'note': 'synthetic'},
    );

    // A structural read with the live certificate retains it.
    final sukhdev = await fx.remotePhone(b, fx.sukhdev)
      ..fileCertIn(trust);
    expect(ledger.retainedCertOf(sukhdev.deviceId), isNull);
    expect(
      signer(_signedOn(b, sukhdev, requestBy(fx.sukhdev)), seq: 1),
      fx.sukhdev,
    );
    expect(ledger.retainedCertOf(sukhdev.deviceId), same(sukhdev.cert));

    // Offered, kept by nobody: a relabelled certificate, one of a user no
    // ceremony here verified, and this device's own.
    final ramesh = await fx.remotePhone(b, fx.ramesh);
    trust.certs[ramesh.deviceId] = fx.relabelled(ramesh.cert, fx.sukhdev);
    expect(view.certOf(ramesh.deviceId), isNotNull, reason: 'live answers');
    final stranger =
        await fx.remotePhone(b, ledger.newId(), verifiedHere: false)
          ..fileCertIn(trust);
    expect(view.certOf(stranger.deviceId), same(stranger.cert));
    await ledger.installOwnCert(ledger.issueOwnCert().cert);
    expect(view.certOf(id.deviceId), isNotNull);
    await pumpEventQueue();
    expect(ledger.retainedCertOf(ramesh.deviceId), isNull);
    expect(ledger.retainedCertOf(stranger.deviceId), isNull);
    expect(ledger.retainedCertOf(id.deviceId), isNull);

    // The live store answers first; the retained copy only where it has
    // nothing — and then it still names the signer, through the chain.
    trust.certs.remove(sukhdev.deviceId);
    expect(view.certOf(sukhdev.deviceId), same(sukhdev.cert));
    expect(
      signer(_signedOn(b, sukhdev, requestBy(fx.sukhdev)), seq: 2),
      fx.sukhdev,
    );
    final other = fx.relabelled(sukhdev.cert, fx.ramesh);
    trust.certs[sukhdev.deviceId] = other;
    expect(view.certOf(sukhdev.deviceId), same(other));
    expect(
      signer(_signedOn(b, sukhdev, requestBy(fx.sukhdev)), seq: 3),
      isNull,
      reason: 'a relabel the server serves now names nobody (E-200-35)',
    );
    trust.certs.remove(sukhdev.deviceId);

    // The removal cut-off reaches a device only the retained copy names:
    // the live store knows no owner for it, so on its own it applies none.
    trust.removals.add(
      eng.RemovalRecord(
        recordId: ledger.newId(),
        seq: 10,
        removedUserId: fx.sukhdev,
      ),
    );
    expect(trust.revocationSeqOf(sukhdev.deviceId), isNull);
    expect(view.revocationSeqOf(sukhdev.deviceId), 10);
    expect(
      signer(_signedOn(b, sukhdev, requestBy(fx.sukhdev)), seq: 9),
      fx.sukhdev,
      reason: 'before the removal',
    );
    expect(
      signer(_signedOn(b, sukhdev, requestBy(fx.sukhdev)), seq: 10),
      isNull,
      reason: 'at or after the removal (ADR 2026-09-05b §5)',
    );

    // The next launch reads back what was kept — and only that. A confirmed
    // install with a verified member reopens: until this repair the
    // directory was folded before the stored confirmation was applied, and
    // the reopen threw `IdentityNotConfirmed`.
    await pumpEventQueue();
    ledger.dispose();
    final again = productionLedger(
      db: db,
      keys: keys,
      suite: suite,
      now: testClock.call,
    );
    addTearDown(again.dispose);
    await again.bootstrapSolo();
    expect(
      again.retainedCertOf(sukhdev.deviceId)?.signature,
      sukhdev.cert.signature,
    );
    for (final none in [ramesh.deviceId, stranger.deviceId, id.deviceId]) {
      expect(again.retainedCertOf(none), isNull);
    }
  });
}
