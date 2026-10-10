// A shared business book on a real, in-memory ledger, for the S6.3 tests that
// must run on what production runs (desk 200 (c)): a pending structural
// request is raised the only way the app raises one today —
// `LocalLedger.proposeDistribution` on a book with more than one owner
// (02 §7.1 🔒, §7.2.1 🔒) — and read back through `LedgerStructuralRequests`.
//
// Another owner's own phone is modelled the way production meets one
// (review F200I-3): a real UMK, verified by a real ceremony filed through the
// ledger's own door; a real device pair that UMK certified (04 §3.4); the
// envelope sealed under the book key and signed by that device, checked by
// `ChainVerifier` over the trust store production builds
// (`RecordTrustStore` over `ledger.binding`) before the mirror holds it as
// verified — exactly what the sync engine does on a pull.
//
// Synthetic names and sums only (CLAUDE.md rule 4). Injected clock.
import 'package:core_crypto/core_crypto.dart';
import 'package:core_ledger/core_ledger.dart';
import 'package:data/data.dart' show BookOwnership, EnvelopeRecord;
import 'package:rukka_folio/shared/ledger/local_ledger.dart';
import 'package:sync_engine/sync_engine.dart' as eng;

import '../../shared/test_app.dart';

/// The two other owners' user ids. Their devices are not on this phone, so
/// nothing they sign can be authored here — which is the point of the
/// binding tests. Canonical uuids: a device certificate names its user by one
/// (04 §3.4).
const sukhdev = '5d000000-0000-4000-8000-0000000000a1';

/// See [sukhdev].
const harjit = '4a000000-0000-4000-8000-0000000000a2';

/// A member of the book who is **not** an owner — whose phone a server might
/// try to pass off as an owner's.
const ramesh = '7e000000-0000-4000-8000-0000000000a3';

/// A shared business with three partner accounts, profit in the open year.
final class SharedBook {
  SharedBook(this.ledger, this.clock, this.bookId, this.chart);

  /// The facade — this device, this user.
  final LocalLedger ledger;

  /// The clock the ledger reads.
  final TestClock clock;

  /// The book.
  final String bookId;

  /// Its chart, as seeded.
  final Chart chart;

  /// The reader's own user id.
  String get me => ledger.identity.userId;

  /// The partner A/c whose name starts with [prefix].
  Account partner(String prefix) => chart.accounts.firstWhere(
    (a) => a.accountClass == AccountClass.partner && a.name.startsWith(prefix),
  );

  /// Display names this phone holds for the members (the members
  /// repository's answer in production).
  String nameOf(String userId) => switch (userId) {
    sukhdev => 'Sukhdev Singh',
    harjit => 'Harjit Kaur',
    _ when userId == me => 'Amrit Kaur',
    _ => 'Someone in this book',
  };

  /// Raises a profit distribution through the real write path and returns
  /// the signed request it authored.
  Future<StructuralRequest> proposeDistribution() async {
    final outcome = await ledger.proposeDistribution(bookId);
    return (outcome as DistributionProposed).request;
  }
}

/// Seeds the book. With [viewerIsOwner] false the reader is a member who is
/// not one of the owners (the owners are Sukhdev and Harjit only).
Future<SharedBook> sharedBook({bool viewerIsOwner = true}) async {
  final clock = TestClock();
  final ledger = await openTestLedger(now: clock.call);
  await ledger.bootstrapSolo(
    firstBookName: 'Me',
    startDate: ledger.today().addDays(-30),
  );
  final me = ledger.identity.userId;
  final bookId = await ledger.createBook(
    name: 'Sharma Brothers',
    type: BookType.business,
    ownership: BookOwnership.shared,
    ownerNames: viewerIsOwner
        ? const ['Amrit Kaur', 'Sukhdev Singh', 'Harjit Kaur']
        : const ['Sukhdev Singh', 'Harjit Kaur'],
    ownerShares: viewerIsOwner ? const [1, 1, 1] : const [1, 1],
    ownerMemberIds: viewerIsOwner ? [me, sukhdev, harjit] : [sukhdev, harjit],
    startDate: ledger.today().addDays(-20),
    categories: const [SeedCategory('Crop Sale', AccountClass.categoryIncome)],
  );
  var chart = await ledger.chartOf(bookId);
  final cash = chart.accounts.firstWhere(
    (a) => a.accountClass == AccountClass.money,
  );
  final sale = chart.accounts.firstWhere((a) => a.name == 'Crop Sale');
  await ledger.moneyIn(
    bookId: bookId,
    into: cash.id,
    from: sale.id,
    paise: 3_00_000_00,
    date: ledger.today().addDays(-1),
    note: 'Harvest lot',
  );
  chart = await ledger.chartOf(bookId);
  return SharedBook(ledger, clock, bookId, chart);
}

/// The trust store the composition root builds (bootstrap.dart:
/// `eng.RecordTrustStore(umks: eng.BoundUmkSource(identity))`, `identity =
/// ledger.binding`): it believes this user's UMK and every member a ceremony
/// on this phone verified, and holds whatever certificates meta delivered —
/// none, until a test files them, as on every launch before the meta read.
eng.RecordTrustStore productionTrust(SharedBook b) =>
    eng.RecordTrustStore(umks: eng.BoundUmkSource(b.ledger.binding));

/// Another person's own phone.
final class RemotePhone {
  RemotePhone._(this.userId, this.umk, this.device, this.cert);

  /// Whose phone it is.
  final String userId;

  /// Their UMK — never on this phone in real life; here only to issue [cert].
  final UmkKeyPair umk;

  /// The phone's own keys.
  final DeviceKeyPair device;

  /// The certificate [umk] issued for [device] (04 §3.4).
  final DeviceCert cert;

  /// The phone's device id.
  String get deviceId => device.deviceId;

  /// [cert] as the sync engine files it from meta (`trust.certs[id] = cert`,
  /// engine.dart `_applyMeta`).
  void fileCertIn(eng.RecordTrustStore trust) => trust.certs[deviceId] = cert;
}

/// [userId]'s phone. With [verifiedHere] (the default) a ceremony on this
/// phone verified their UMK and was filed through `verifiedMembers` — the
/// only way to a `VerifiedUmkPublic` (04 §8.2 🔒). [deviceId] defaults to a
/// fresh id; [umk] to a fresh UMK.
Future<RemotePhone> remotePhone(
  SharedBook b,
  String userId, {
  bool verifiedHere = true,
  String? deviceId,
  UmkKeyPair? umk,
}) async {
  final suite = b.ledger.suite;
  final key = umk ?? UmkKeyPair.generate(suite);
  if (verifiedHere) {
    final r = Ceremony.verifyQr(
      suite,
      scanned: QrPayload(
        userId: userId,
        umk: key.public,
        nonce: suite.randomBytes(ceremonyNonceBytes),
      ),
      relayed: key.public,
      relayedUserId: userId,
    );
    await b.ledger.verifiedMembers.storeVerified(
      userId: userId,
      verified: (r as CeremonyVerified).verified,
      method: VerificationMethod.qrInPerson,
    );
  }
  final device = DeviceKeyPair.generate(
    suite,
    deviceId: deviceId ?? b.ledger.newId(),
  );
  final cert = DeviceCert.issue(
    suite,
    issuer: key,
    userId: userId,
    device: device.public,
    issuedAtMs: b.clock().millisecondsSinceEpoch,
  );
  return RemotePhone._(userId, key, device, cert);
}

/// [cert] with its plaintext user id swapped — what `CryptoGuard.buildCert`
/// builds when the server's `devices` row names [userId] for the device. The
/// signature is untouched (04 §3.4 does not sign the user id).
DeviceCert relabelled(DeviceCert cert, String userId) => DeviceCert(
  suiteVersion: cert.suiteVersion,
  userId: userId,
  device: cert.device,
  issuedAtMs: cert.issuedAtMs,
  signature: cert.signature,
);

/// [event], sealed under the book's key and signed on [phone], arriving as a
/// pull delivers it: `ChainVerifier` over [trust] decides `verified` before
/// the mirror stores it (04 §8 rule 3), exactly as the engine does. Returns
/// whether the chain held.
Future<bool> receiveFrom(
  SharedBook b,
  RemotePhone phone,
  StructuralEvent event, {
  required eng.RecordTrustStore trust,
  required int authorSeq,
  int seq = 1,
}) async {
  final l = b.ledger;
  final suite = l.suite;
  final keys = l.keyMaterial.bookKeys;
  final version = keys.highestVersion(b.bookId)!;
  final env = EnvelopeBuilder.seal(
    suite,
    tenantId: keys.tenantIdOf(b.bookId)!,
    bookId: b.bookId,
    objectId: event.id,
    objectType: 'structural_approval',
    envelopeId: l.newId(),
    hlc: event.hlc.raw,
    authorSeq: authorSeq,
    object: encodeStructuralEvent(event),
    bookKey: keys.bookKey(BookKeyRef(bookId: b.bookId, keyVersion: version))!,
    author: phone.device,
  );
  final hash = env.blobHash(suite);
  final verdict = ChainVerifier(
    suite,
    trust,
  ).verifyEnvelope(env, seq: seq, expectedBlobHash: hash);
  final ok = verdict is ChainVerified;
  await l.mirror.append(
    EnvelopeRecord(
      envelopeId: env.envelopeId,
      bookId: b.bookId,
      objectId: event.id,
      objectType: 'structural_approval',
      keyVersion: version,
      hlc: event.hlc.raw,
      authorDevice: phone.deviceId,
      authorSeq: authorSeq,
      blob: env.blob,
      blobHash: hash,
      seq: seq,
      verified: ok,
    ),
  );
  return ok;
}

/// An HLC [minutes] after [after] on the injected clock's scale.
Hlc hlcAfter(Hlc after, int minutes) =>
    Hlc.compose(physicalMs: after.physicalMs + minutes * 60 * 1000, counter: 0);

/// [by]'s approval of [request].
StructuralApproval approvalOf(
  SharedBook b,
  StructuralRequest request,
  String by, {
  int minutes = 1,
}) => StructuralApproval(
  id: b.ledger.newId(),
  bookId: b.bookId,
  hlc: hlcAfter(request.hlc, minutes),
  requestId: request.id,
  byUser: by,
  ownerSetVersion: request.ownerSetVersion,
);
