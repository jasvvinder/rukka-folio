// ADR 2026-10-10 ruling 2 🔒 (F1-1010-1, F1-1010-2): a held engine shows no
// sync chip and disables no control. Before S0.2 mints this phone's keys the
// sync engine is held *not registered yet* (ADR 2026-10-09 §1) and its status
// reads `Offline` (05 §9 has no sixth state) — which, read as Offline, turned
// S0.2's Send off on every real install, so no one could ask for a code.
//
// These tests run the screens over a REAL `EngineSyncClient` wrapping a REAL
// `SyncEngine.late` whose identity source answers *not registered yet* — the
// SYNC168 rig (packages/sync_engine/test/late_binding_test.dart) — never over
// `FakeSyncClient`, which answers `Synced` and is how the bug hid. In-memory
// SQLite, the in-memory sync server, synthetic ids only.
@Tags(['F1'])
library;

import 'package:data/data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/auth/screens/s0_2_phone_otp_screen.dart';
import 'package:rukka_folio/features/recovery/screens/s11_6_fork_screen.dart';
import 'package:rukka_folio/features/recovery/screens/s11_3_sheet_screen.dart';
import 'package:rukka_folio/features/auth/screens/s19_1_update_required_screen.dart';
import 'package:rukka_folio/features/auth/http_auth_client.dart'
    show UpdateRequired;
import 'package:rukka_folio/l10n/gen/app_localizations.dart';
import 'package:rukka_folio/l10n/l10n.dart';
import 'package:rukka_folio/shared/app_scope.dart';
import 'package:rukka_folio/shared/seams/auth_client.dart';
import 'package:rukka_folio/shared/seams/key_store.dart';
import 'package:rukka_folio/shared/seams/recovery_ladder.dart';
import 'package:rukka_folio/shared/seams/sync_client.dart';
import 'package:rukka_folio/shared/sync/engine_sync_client.dart';
import 'package:rukka_folio/shared/theme.dart';
import 'package:sync_engine/sync_engine.dart' as eng;

import '../../shared/test_app.dart';
import 'sign_in_harness.dart';

const _device = 'phone-a';
const _typed = '9999900001'; // reserved test block (ADR 2026-09-05i §7)
const _authChip = 'Offline — you need internet for the code.';
const _forkChip = 'Offline — connect once so we can check your ways back in.';

/// A held phone: the composition root's shape before S0.2 — an engine built
/// late over an identity source that answers *not registered yet*.
final class _HeldPhone {
  _HeldPhone(this.db, this.identity, this.transport, this.engine, this.client);

  final LedgerDatabase db;
  final eng.ManualIdentity identity;
  final eng.FakeTransport transport;
  final eng.SyncEngine engine;
  final EngineSyncClient client;

  /// What S0.2 does to the engine's world: the keys exist, the device is
  /// registered, and the next round runs under it (ADR 2026-10-09 §1).
  void register() => identity.identity = const eng.RegisteredIdentity(
    deviceId: _device,
    userId: 'u-a',
    tenantId: 't-1',
  );

  static Future<_HeldPhone> open() async {
    final db = await openTestDb();
    final clock = eng.ManualClock(1000 * 24 * 60 * 60 * 1000);
    final server = eng.FakeSyncServer(
      clock: clock,
      rateLimits: eng.RateLimits.none,
    );
    final transport = server.transportFor(_device);
    final trust = eng.RecordTrustStore(umks: const eng.MapUmkSource({}));
    final identity = eng.ManualIdentity();
    final engine = eng.SyncEngine.late(
      db: db,
      mirror: Mirror(db, hasher: eng.fnv1a32),
      transport: transport,
      clock: clock,
      guard: eng.PlainGuard(trust: trust),
      trust: trust,
      identity: identity,
    );
    final client = EngineSyncClient(engine: engine, memberName: (id) => id);
    addTearDown(client.dispose);
    await client.start();
    return _HeldPhone(db, identity, transport, engine, client);
  }
}

/// Opens a held phone outside the fake clock (real SQLite underneath).
Future<_HeldPhone> _openHeld(WidgetTester tester) async =>
    (await tester.runAsync(_HeldPhone.open))!;

/// [child] under the production theme and strings, over [phone]'s REAL
/// engine-backed client — `pumpRk` takes only the fake, so the scope is
/// built here the way `pumpRk` builds it.
Future<void> _pumpOver(
  WidgetTester tester,
  _HeldPhone phone,
  Widget child, {
  required FakeAuthClient auth,
  DateTime Function() now = testNow,
}) async {
  await tester.pumpWidget(
    RkScope(
      db: phone.db,
      sync: phone.client,
      auth: auth,
      keys: FakeKeyStore(),
      now: now,
      child: MaterialApp(
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: rkLocalizationsDelegates,
        theme: rkTheme(Brightness.light),
        home: child,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The one filled action on the number step.
FilledButton _send(WidgetTester tester) =>
    tester.widget<FilledButton>(find.byType(FilledButton));

/// The *Send again* link on the code step.
TextButton _resend(WidgetTester tester) =>
    tester.widget<TextButton>(find.widgetWithText(TextButton, 'Send again'));

/// A movable clock for the resend cooldown.
final class _Clock {
  DateTime now = testNow();
  DateTime call() => now;
}

void main() {
  group(
    'ADR 2026-10-10 §2 — a held engine shows no chip, disables nothing',
    () {
      testWidgets(
        'F1-1010-1 S0.2 over a real held EngineSyncClient: no offline '
        'chip, Send live with a complete number and reaching the auth '
        'client, Send again live once the wait is over; and once the engine '
        'is registered and really offline the quiet chip is back (05 §9) '
        'while Send again stays live — sync status disables nothing',
        (tester) async {
          final phone = await _openHeld(tester);
          // The precondition the bug lived on: the engine really is held, and
          // its status really does read Offline.
          expect(phone.engine.hold, eng.SyncHold.notRegistered);
          expect(phone.client.current, isA<Offline>());
          expect(phone.client.held, isTrue);

          final clock = _Clock();
          final auth = FakeAuthClient();
          await _pumpOver(
            tester,
            phone,
            const PhoneOtpScreen(),
            auth: auth,
            now: clock.call,
          );
          expect(find.text(_authChip), findsNothing);

          await tapKeys(tester, _typed);
          expect(_send(tester).onPressed, isNotNull);
          await tester.tap(find.byType(FilledButton));
          await tester.pumpAndSettle();
          expect(auth.requestedPhones, ['+91$_typed']);
          expect(find.text('Enter the code'), findsOneWidget);
          expect(find.text(_authChip), findsNothing);

          // Send again rests on the auth client's own cooldown, never on sync.
          clock.now = clock.now.add(const Duration(seconds: 31));
          await tester.pump(const Duration(seconds: 1));
          expect(_resend(tester).onPressed, isNotNull);
          await tester.tap(find.text('Send again'));
          await tester.pumpAndSettle();
          expect(auth.requestedPhones, ['+91$_typed', '+91$_typed']);

          // Registered and genuinely offline: the quiet chip is back (05 §9,
          // 07 §1 rule 7), and Send again still rests on the auth client alone
          // (ADR 2026-10-10 §2: never on sync status).
          phone.register();
          phone.transport.online = false;
          await tester.runAsync(phone.client.syncNow);
          await tester.pumpAndSettle();
          expect(phone.client.held, isFalse);
          expect(phone.client.current, isA<Offline>());
          expect(find.text(_authChip), findsOneWidget);
          clock.now = clock.now.add(const Duration(seconds: 61));
          await tester.pump(const Duration(seconds: 1));
          expect(_resend(tester).onPressed, isNotNull);
          await tester.tap(find.text('Send again'));
          await tester.pumpAndSettle();
          expect(auth.requestedPhones, hasLength(3));
        },
      );

      testWidgets(
        'F1-1010-1 the held-to-registered window as production runs it: '
        'the S0.2 mint registers the identity and NO round follows; the '
        'next rebuild draws no offline chip (the held engine\'s Offline is '
        'never paired with the registered hold), the client catches up to '
        'the registered engine\'s own status by itself, and Send again '
        'stays live throughout',
        (tester) async {
          final phone = await _openHeld(tester);
          final clock = _Clock();
          final auth = FakeAuthClient();
          await _pumpOver(
            tester,
            phone,
            const PhoneOtpScreen(),
            auth: auth,
            now: clock.call,
          );
          await enterNumberAndSend(tester, _typed);
          expect(find.text('Enter the code'), findsOneWidget);
          final rounds = phone.client.cycles;

          // The mint (http_auth_client → LocalLedger) flips the identity and
          // runs no round. One keypad tap rebuilds the screen.
          phone.register();
          expect(phone.engine.hold, isNot(eng.SyncHold.notRegistered));
          await tapKeys(tester, '1');
          expect(find.text(_authChip), findsNothing);

          await tester.runAsync(() => phone.client.settled);
          await tester.pumpAndSettle();
          expect(phone.client.cycles, rounds, reason: 'no round was run');
          expect(phone.client.held, isFalse);
          expect(phone.client.current, isA<Synced>());
          expect(find.text(_authChip), findsNothing);
          // A fresh subscription (every rebuild makes one) agrees. Taken in
          // the real zone, like `settled` above: the client was built there,
          // and awaiting its stream from the fake zone left the next pump
          // spinning (the test hung at 10 min; a real-zone read does not).
          expect(
            await tester.runAsync(() => phone.client.chipStatus.first),
            isA<Synced>(),
          );
          clock.now = clock.now.add(const Duration(seconds: 31));
          await tester.pump(const Duration(seconds: 1));
          expect(_resend(tester).onPressed, isNotNull);
        },
      );

      testWidgets('F1-1010-1 a request that fails while held shows the auth '
          'client\'s own answer (06 §2), and Send stays live to try again', (
        tester,
      ) async {
        final phone = await _openHeld(tester);
        final auth = FakeAuthClient()
          ..failNext = const AuthFailure(AuthFailureKind.unavailable);
        await _pumpOver(tester, phone, const PhoneOtpScreen(), auth: auth);
        await enterNumberAndSend(tester, _typed);
        expect(
          find.text('Couldn’t connect. Check your internet and try again.'),
          findsOneWidget,
        );
        expect(find.text(_authChip), findsNothing);
        expect(_send(tester).onPressed, isNotNull);
      });

      testWidgets(
        'F1-1010-2 S11.6 over the same held client shows no sync chip; '
        'once registered and really offline the quiet chip is back',
        (tester) async {
          final phone = await _openHeld(tester);
          await _pumpOver(
            tester,
            phone,
            RecoveryForkScreen(ladder: FakeRecoveryLadder()),
            auth: FakeAuthClient(),
          );
          expect(
            find.text('Let’s get your books back on this phone'),
            findsOne,
          );
          expect(find.text(_forkChip), findsNothing);

          phone.register();
          phone.transport.online = false;
          await tester.runAsync(phone.client.syncNow);
          await tester.pumpAndSettle();
          expect(find.text(_forkChip), findsOneWidget);
        },
      );

      testWidgets('F1-1010-2 regression guard: not held + Offline still shows '
          'S0.2\'s quiet chip; held + Offline shows none, and flips live; '
          'Send stays live in every state (never gated on sync status)', (
        tester,
      ) async {
        final sync = FakeSyncClient(initial: const Offline());
        await pumpRk(tester, const PhoneOtpScreen(), sync: sync);
        await tapKeys(tester, _typed);
        expect(find.text(_authChip), findsOneWidget);
        expect(_send(tester).onPressed, isNotNull);

        sync.held = true;
        await tester.pumpAndSettle();
        expect(find.text(_authChip), findsNothing);
        expect(_send(tester).onPressed, isNotNull);

        sync.held = false;
        await tester.pumpAndSettle();
        expect(find.text(_authChip), findsOneWidget);
        expect(_send(tester).onPressed, isNotNull);
      });

      testWidgets('F1-1010-2 S19.1 and S11.3 (reachable before S0.2): held + '
          'Offline draws no offline line; not held + Offline still does', (
        tester,
      ) async {
        for (final held in [true, false]) {
          await pumpRk(
            tester,
            UpdateRequiredScreen(
              key: ValueKey('s19-$held'),
              gate: const UpdateRequired(
                currentVersion: '1',
                requiredVersion: '2',
              ),
            ),
            sync: FakeSyncClient(initial: const Offline(), held: held),
          );
          expect(
            find.text('You’ll need internet to update.'),
            held ? findsNothing : findsOneWidget,
            reason: 'S19.1, held: $held',
          );
          await pumpRk(
            tester,
            RecoverySheetScreen(
              key: ValueKey('s11-3-$held'),
              sheet: FakeRecoverySheet(),
            ),
            sync: FakeSyncClient(initial: const Offline(), held: held),
            viewport: rkTallViewport,
          );
          expect(
            find.textContaining('Offline'),
            held ? findsNothing : findsOneWidget,
            reason: 'S11.3, held: $held',
          );
        }
      });
    },
  );
}
