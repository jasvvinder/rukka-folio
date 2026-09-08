// libsodium for lane C tests. `package:sodium` builds the library under
// `flutter test` (same as core_crypto's suite B helper); test code may use
// the clock — the purity rule binds lib/, not test/.
import 'package:core_crypto/core_crypto.dart';
import 'package:sodium/sodium.dart';

Sodium? _sodium;

/// The process-wide binding.
Future<Sodium> sodium() async => _sodium ??= await SodiumInit.init();

/// A suite over libsodium's real CSPRNG.
Future<CryptoSuite> liveSuite() async => CryptoSuite(await sodium());

/// A settable clock: `clock.now` is what the code under test reads.
final class TestClock {
  TestClock(this.now);

  DateTime now;

  DateTime call() => now;

  void advance(Duration d) => now = now.add(d);
}
