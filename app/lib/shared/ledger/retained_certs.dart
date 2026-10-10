// Other devices' certificates, kept past the session that saw them (03
// *Deletion mechanics* 🔒 · 04 §3.4 · 02 §7.2.1 🔒) — review TRUSTWIRE-1.
//
// Why. The structural reader names whose certified device signed each
// `structural_approval` by re-running the signature chain over the stored
// envelope at every read (`chainCertifiedSigner`, `certifiedSignerOf`). The
// chain needs the author device's certificate, and the sync engine holds
// certificates in memory only (`RecordTrustStore.certs`), re-read from the
// meta channel at every launch. The server never serves a **removed**
// member's certificate again (`device_certs_select` → `rf.device_visible` →
// `rf.shares_tenant`, which excludes `status = 'removed'`), while their
// signed records stay in the book for ever (rule 2). Without a copy kept here,
// one relaunch after a removal turned every record they signed into
// `signerUnknown` — and every ratio or interest change they approved stopped
// counting, and every distribution of that book was refused, permanently.
//
// What is kept, and why it is safe to keep. A certificate is retained only
// when it verifies under the ceremony-verified UMK of the user it names
// (`LocalLedger.retainPeerCert`) — the very check the chain makes — and it
// is **re-verified at every use**: [RetainedCertTrust] only *offers* it to
// `ChainVerifier`, which still checks it against the UMK this phone believes
// now, the envelope's signature against its keys, and the revocation /
// removal cut-off against the row's `seq`. Retaining therefore adds no
// belief: it keeps a proof this phone already accepted, so that the same
// proof can be checked again tomorrow. It is public material (a signature and
// two public keys per device), stored beside this install's own certificate.
//
// The live store answers first: a certificate the server serves now is the
// one checked, exactly as before — a relabelled one names nobody (E-200-35),
// never the retained one's user. The retained copy is read only for a device
// the live store holds nothing for.
//
// What retains. Every certificate the live store answers a structural signer
// with is offered to the ledger as it is answered. The composition root's
// signers are the only readers of this view, and the Inbox re-reads every
// book's structural records whenever `envelopes_local` changes — so a
// member's certificate is offered the moment a record they signed arrives,
// while the server still serves it. Nothing here reads a clock, does I/O or
// logs.
import 'dart:async';

import 'package:core_crypto/core_crypto.dart';
import 'package:sync_engine/sync_engine.dart' as eng;

/// Answers [TrustStore.certOf] from [live] and, for a device [live] holds no
/// certificate for, from the certificates this install retained ([retained],
/// `LocalLedger.retainedCertOf`). Everything else is [live]'s.
///
/// A certificate [live] answers is also handed to [retain]
/// (`LocalLedger.retainPeerCert`, which keeps it only when it verifies under
/// its user's ceremony-verified UMK and never throws). Not awaited: the chain
/// asks synchronously, and the ledger's in-memory copy is updated before its
/// first await.
///
/// The revocation cut-off is [live]'s, judged **also** against the owner the
/// certificate answered here names: [eng.RecordTrustStore] finds a device's
/// owner through its own certificates or the server's `devices` rows, and the
/// server sends neither for a removed member — so without this the removal
/// cut-off (ADR 2026-09-05b §5) would not apply to a retained certificate's
/// device. The earlier of the two cut-offs is returned, never the later.
final class RetainedCertTrust implements TrustStore {
  /// Creates the view over [live] and [retained].
  const RetainedCertTrust(
    this.live, {
    required this.retained,
    required this.retain,
  });

  /// The sync engine's trust store (certificates from this launch's meta).
  final eng.RecordTrustStore live;

  /// The retained certificate of a device, or null.
  final DeviceCert? Function(String deviceId) retained;

  /// Where a certificate [live] answers is offered.
  final Future<void> Function(DeviceCert cert) retain;

  @override
  DeviceCert? certOf(String deviceId) {
    final now = live.certOf(deviceId);
    if (now == null) return retained(deviceId);
    unawaited(retain(now));
    return now;
  }

  @override
  VerifiedUmkPublic? verifiedUmkOf(String userId) => live.verifiedUmkOf(userId);

  @override
  int? revocationSeqOf(String deviceId) {
    final byLive = live.revocationSeqOf(deviceId);
    final owner = (live.certOf(deviceId) ?? retained(deviceId))?.userId;
    if (owner == null) return byLive;
    final byOwner = live.revocationSeqFor(deviceId, ownerUserId: owner);
    if (byLive == null) return byOwner;
    if (byOwner == null) return byLive;
    return byLive < byOwner ? byLive : byOwner;
  }
}
