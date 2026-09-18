// ADR 2026-09-16 — one device, one id. The ledger mints the device id at
// first run; the auth client registers under that same id; every envelope,
// before and after registration, carries it. In-memory SQLite, FakeKeyStore,
// injected clock, libsodium via the sodium build hook. Synthetic amounts.
@Tags(['F1'])
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:core_crypto/core_crypto.dart' show Bytes, Uuid16;
import 'package:core_ledger/core_ledger.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/auth/auth_transport.dart';
import 'package:rukka_folio/features/auth/http_auth_client.dart';
import 'package:rukka_folio/shared/ledger/local_ledger.dart';
import 'package:rukka_folio/shared/seams/key_store.dart';

import '../test_app.dart';

/// A server that follows ADR 2026-09-16 §2: it records the `device_id` the
/// client sends and echoes it. Everything else is the minimum happy path.
final class EchoingAuthServer implements AuthTransport {
  final bodies = <String, Map<String, Object?>>{};

  @override
  Future<AuthHttpResponse> post(
    Uri url, {
    required Map<String, String> headers,
    required String body,
  }) async {
    final b = jsonDecode(body) as Map<String, Object?>;
    final path = url.path.split('/auth-challenge/').last;
    bodies[path] = b;
    Map<String, Object?> out;
    switch (path) {
      case 'otp/request':
        out = {'ok': true, 'resend_after_s': 30};
      case 'otp/verify':
        out = {'ticket': 'tk-1', 'user_id': 'u-1', 'expires_in_s': 600};
      case 'devices':
        out = {
          'device_id': b['device_id'],
          'user_id': 'u-1',
          'status': 'registered',
        };
      case 'challenge':
        out = {
          'nonce': Bytes.base64Url(Uint8List.fromList(List.filled(32, 7))),
          'expires_in_s': 60,
        };
      case 'token':
        out = {
          'access_token': 'acc-1',
          'expires_in': 900,
          'refresh_token': 'ref-1',
          'refresh_expires_at': 1790000000000,
          'user_id': 'u-1',
          'device_id': b['device_id'],
          'device_status': 'registered',
        };
      default:
        return const AuthHttpResponse(404, '');
    }
    return AuthHttpResponse(200, jsonEncode(out));
  }
}

void main() {
  late FakeKeyStore keys;
  late EchoingAuthServer server;

  Future<HttpAuthClient> authOver(FakeKeyStore keys) async => HttpAuthClient(
    transport: server,
    suite: await testSuite(),
    keys: keys,
    now: testNow,
    baseUrl: Uri.parse('https://api.test/functions/v1/'),
    clientVersion: '1.0.0',
  );

  Future<void> postOne(
    LocalLedger l,
    String bookId,
    String into,
    String from,
  ) => l.moneyIn(
    bookId: bookId,
    into: into,
    from: from,
    paise: 250_00,
    date: l.today(),
  );

  setUp(() {
    keys = FakeKeyStore();
    server = EchoingAuthServer();
  });

  test('F1-05-49 one device, one id: the id bootstrapSolo mints is the id readStoredIdentity yields, the id the device key pair carries, the id POST devices sends and the id the session and SessionItems hold — and the public key registered is the ledger device\'s', () async {
    final l = await openTestLedger(keys: keys);
    final id = await l.bootstrapSolo(firstBookName: 'Me');
    expect(Uuid16.isCanonical(id.deviceId), isTrue);

    final stored = await readStoredIdentity(keys);
    expect(stored, isNotNull);
    expect(stored!.deviceId, id.deviceId);
    expect(stored.userId, id.userId);
    expect(stored.tenantId, id.tenantId);
    expect(l.keyMaterial.device.deviceId, id.deviceId);

    final auth = await authOver(keys);
    await auth.requestOtp('+919999999999');
    final ticket = await auth.verifyOtp('123456');
    final session = await auth.activateDevice(ticket);

    final reg = server.bodies['devices']!;
    expect(reg['device_id'], id.deviceId);
    expect(
      Bytes.fromBase64Url(reg['pub_ed'] as String),
      l.keyMaterial.device.public.ed25519,
    );
    expect(
      Bytes.fromBase64Url(reg['pub_x'] as String),
      l.keyMaterial.device.public.x25519,
    );
    expect(session.deviceId, id.deviceId);
    expect(server.bodies['challenge']!['device_id'], id.deviceId);
    expect(server.bodies['token']!['device_id'], id.deviceId);
    expect(utf8.decode((await keys.read(SessionItems.deviceId))!), id.deviceId);
    // Registration rewrote nothing the ledger owns.
    expect(keys.writes.where((w) => w == LocalLedgerKeys.identity).length, 1);
    expect(keys.writes.where((w) => w == KeyIds.deviceSigningKey).length, 1);
    expect(keys.writes.where((w) => w == KeyIds.deviceAgreementKey).length, 1);
  });

  test('F1-05-50 nothing is stranded (rule 2, ADR 2026-09-16 §5): envelopes authored before registration and after it carry the same author_device_id, which is the registered id', () async {
    final l = await openTestLedger(keys: keys);
    final id = await l.bootstrapSolo(firstBookName: 'Me');
    final bookId = (await l.mirror.bookIds()).single;
    final cash = await l.addAccount(
      bookId,
      name: 'Cash',
      accountClass: AccountClass.money,
      subtype: MoneySubtype.cash,
    );
    final sales = await l.addAccount(
      bookId,
      name: 'Sales',
      accountClass: AccountClass.categoryIncome,
    );
    await postOne(l, bookId, cash.id, sales.id);
    final before = await l.db.select(l.db.envelopesLocal).get();
    expect(before, isNotEmpty);

    final auth = await authOver(keys);
    await auth.requestOtp('+919999999999');
    final session = await auth.activateDevice(await auth.verifyOtp('123456'));

    await postOne(l, bookId, cash.id, sales.id);
    final after = await l.db.select(l.db.envelopesLocal).get();
    expect(after.length, greaterThan(before.length));

    final authors = after.map((e) => e.authorDevice).toSet();
    expect(authors, {id.deviceId});
    expect(session.deviceId, id.deviceId);
    // And a new ledger over the same store reopens the same id — a Keychain
    // remnant (06 §5) is the same device to the server too.
    final again = await openTestLedger(keys: keys, db: l.db);
    expect((await again.bootstrapSolo()).deviceId, id.deviceId);
  });
}
