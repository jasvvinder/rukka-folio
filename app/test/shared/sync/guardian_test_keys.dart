// Real keys for the guardian-set tests (04 §7.3).
//
// There is no fake path to a [VerifiedUmkPublic] and there should not be: the
// ceremony is the only producer (04 §8.2 🔒), so these helpers run it for
// real over libsodium, exactly as `core_crypto/test/helpers.dart` does. A
// test that wants a share sealed must therefore verify a key first — which is
// the property under test.
import 'package:core_crypto/core_crypto.dart';
import 'package:sodium/sodium.dart';

Sodium? _sodium;

/// The process-wide libsodium binding (built under `flutter test`).
Future<CryptoSuite> liveSuite() async =>
    CryptoSuite(_sodium ??= await SodiumInit.init());

/// Synthetic ids — never real ones (rule 4). Canonical uuids, because the
/// ceremony's `QrPayload` refuses anything else.
const String userMe = '44444444-4444-4444-8444-444444444440';

/// Five guardian ids, enough for the whole of 04 §7.3's `n = 2..5`.
const List<String> userGuardians = [
  '44444444-4444-4444-8444-444444444441',
  '44444444-4444-4444-8444-444444444442',
  '44444444-4444-4444-8444-444444444443',
  '44444444-4444-4444-8444-444444444444',
  '44444444-4444-4444-8444-444444444445',
];

/// A guardian: a UMK pair, its user id, and the key a ceremony verified.
final class TestGuardian {
  /// Runs the QR ceremony (04 §6.3) over [umk]'s own public halves, which is
  /// the only way to obtain the verified type.
  TestGuardian(CryptoSuite suite, this.userId, this.umk)
    : verified = (Ceremony.verifyQr(
        suite,
        scanned: QrPayload(
          userId: userId,
          umk: umk.public,
          nonce: suite.randomBytes(16),
        ),
        relayed: umk.public,
        relayedUserId: userId,
      ) as CeremonyVerified).verified;

  /// Generates a fresh guardian.
  factory TestGuardian.generate(CryptoSuite suite, String userId) =>
      TestGuardian(suite, userId, UmkKeyPair.generate(suite));

  /// Their user id — the `guardian_user_id` on the wire.
  final String userId;

  /// Their UMK pair; `dispose` it in a tear-down.
  final UmkKeyPair umk;

  /// The ceremony-verified public half.
  final VerifiedUmkPublic verified;
}
