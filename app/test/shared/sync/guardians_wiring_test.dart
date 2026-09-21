// The shell's side of 04 §7.3 Setup: the scope that hands S11.1 a real
// repository instead of the seam's fake.
//
// This is a wiring fact of the kind that fails silently. With no scope the
// screen falls back to [FakeGuardians], which **accepts a set and reports a
// split that never happened** — a green trusted-member screen over a recovery
// that cannot work. So the test that matters is not that the scope compiles
// but that what comes out of it is not the fake.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/shared/seams/guardians.dart';
import 'package:rukka_folio/shared/seams/http_transport.dart';
import 'package:rukka_folio/shared/sync/guardians_seams.dart';
import 'package:sync_engine/sync_engine.dart' show MapUmkSource;

void main() {
  testWidgets(
    'F1-06-45 GuardiansScope hands the live producer down, a screen reads it '
    'without knowing which it got, and what it gets is not the fake',
    (tester) async {
      final repository = ServerGuardians(
        api: HttpGuardiansApi(
          transport: FakeRkHttpTransport(
            (method, url, headers, body) => const RkHttpResponse(200, '{}'),
          ),
          functionsRoot: Uri.parse('https://api.example.test/functions/v1/'),
          accessToken: () async => 'tok',
        ),
        roster: () async => const GuardianRoster(),
        verified: const MapUmkSource({}),
      );
      addTearDown(repository.dispose);

      GuardiansRepository? seen;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: GuardiansScope(
            repository: repository,
            child: Builder(
              builder: (context) {
                seen = GuardiansScope.maybeOf(context);
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );

      expect(seen, same(repository));
      expect(seen, isNot(isA<FakeGuardians>()));
    },
  );

  testWidgets(
    'F1-06-46 with no scope the seam answers null, which is what lets a '
    'screen fall back on its own rather than throw (07 §1 rule 6)',
    (tester) async {
      GuardiansRepository? seen = FakeGuardians();
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Builder(
            builder: (context) {
              seen = GuardiansScope.maybeOf(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(seen, isNull);
    },
  );
}
