@Tags(['C'])
library;

// Suite C — the real [ServerMembersRepository] against the server 0008
// hardened (06 §1, §1.0 🔒, §1.1 🔒, §7 🔒; ADR 2026-09-05d §7 and §9 🔒).
//
// The load-bearing one is **C-05d-7**: `rf.membership_guard` refuses to
// believe a `verification_events` row that no signed record backs, and this
// client must be no more credulous. Every "the server said active" case below
// stays `joined_pending_verification` until a signed, believed record says so
// too — because a server that can mint "she was verified" is the whole attack
// ADR 2026-09-05d §7 removes.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/members/members_api.dart';
import 'package:rukka_folio/features/members/members_repository.dart';
import 'package:rukka_folio/features/members/server_members_repository.dart';
import 'package:sync_engine/sync_engine.dart' show MetaResponse;

// ---------------------------------------------------------------- the cast
const tenant = 'tenant-ghar';
const otherTenant = 'tenant-dukaan';
const amrit = 'user-amrit'; // admin, the signed-in user
const sunita = 'user-sunita'; // head, already verified
const harpreet = 'user-harpreet'; // joined, waiting for a ceremony
const ghar = 'book-ghar';
const dukaan = 'book-dukaan';
const elsewhere = 'book-elsewhere'; // belongs to `otherTenant`
const amritPhone = 'phone-amrit-device';
const sunitaPhone = 'phone-sunita-device';

String b64(List<int> bytes) =>
    base64Url.encode(Uint8List.fromList(bytes)).replaceAll('=', '');

/// One `signed_records` wire row (⚠️ WIRE `route.ts` recordToWire).
Map<String, Object?> record(
  String id,
  String kind,
  Map<String, Object?> payload, {
  String device = amritPhone,
  String tenantId = tenant,
  int hlc = 1,
  int seq = 1,
}) => {
  'id': id,
  'seq': seq,
  'suite_version': 1,
  'tenant_id': tenantId,
  'kind': kind,
  'payload_json': b64(utf8.encode(jsonEncode(payload))),
  'author_device_id': device,
  'author_sig': b64(List.filled(64, 7)),
  'hlc': hlc,
};

Map<String, Object?> membership(
  String user,
  String status, {
  String t = tenant,
}) => {'id': '$t:$user', 'tenant_id': t, 'user_id': user, 'status': status};

Map<String, Object?> bookRole(
  String book,
  String user,
  String role, {
  int? paise,
}) => {
  'id': '$book:$user',
  'book_id': book,
  'user_id': user,
  'role': role,
  if (paise != null) 'limits': {'auto_post_limit_paise': paise},
};

Map<String, Object?> book(String id, {String t = tenant}) => {
  'id': id,
  'tenant_id': t,
  'type': 'shared',
  'fy_start_month': 4,
};

Map<String, Object?> device(String id, String user) => {
  'id': id,
  'user_id': user,
  'pub_ed': b64(List.filled(32, 1)),
  'pub_x': b64(List.filled(32, 2)),
  'status': 'certified',
};

Map<String, Object?> ceremony({
  required String subject,
  required String verifier,
  String method = 'qr_in_person',
  String result = 'verified',
  String? sourceRecordId,
  String t = tenant,
  int atMs = 1_757_000_000_000,
}) => {
  'id': 've-$subject',
  'tenant_id': t,
  'subject_user': subject,
  'verifier_user': verifier,
  'method': method,
  'result': result,
  'at': atMs,
  'source_record_id': sourceRecordId,
};

Map<String, Object?> ceremonyRecord(
  String id, {
  required String subject,
  required String verifier,
  String method = 'qr_in_person',
  String result = 'verified',
  String device = sunitaPhone,
  String tenantId = tenant,
}) => record(
  id,
  'verification_event',
  {
    'subject_user_id': subject,
    'verifier_user_id': verifier,
    'method': method,
    'result': result,
  },
  device: device,
  tenantId: tenantId,
);

Map<String, Object?> invite(
  String id, {
  String t = tenant,
  String status = 'sent',
  int expiresAtMs = 1_757_600_000_000,
  String createdBy = amrit,
  List<Map<String, Object?>> roles = const [],
}) => {
  'id': id,
  'tenant_id': t,
  'status': status,
  'roles': roles,
  'expires_at': expiresAtMs,
  'created_by': createdBy,
  'source_record_id': 'rec-invite-$id',
};

MetaResponse meta({
  List<Map<String, Object?>> memberships = const [],
  List<Map<String, Object?>> bookRoles = const [],
  List<Map<String, Object?>> books = const [],
  List<Map<String, Object?>> devices = const [],
  List<Map<String, Object?>> records = const [],
  List<Map<String, Object?>> ceremonies = const [],
  List<Map<String, Object?>> invites = const [],
  List<Map<String, Object?>> freezes = const [],
}) => MetaResponse.fromJson({
  'store_epoch': 'epoch-1',
  'next': null,
  'has_more': false,
  'memberships': memberships,
  'book_roles': bookRoles,
  'books': books,
  'devices': devices,
  'signed_records': records,
  'verification_events': ceremonies,
  'invites': invites,
  'tenant_freezes': freezes,
});

// --------------------------------------------------------------- the fakes
final class FakeApi implements MembersApi {
  FakeApi(this.page);

  MetaResponse page;
  int pulls = 0;
  final issued = <({Map<String, Object?> record, String phone})>[];
  final posted = <List<Map<String, Object?>>>[];
  final accepted = <String>[];
  List<String> nextResults = const ['ok'];

  @override
  Future<MetaResponse> pullMeta({String? after}) async {
    pulls++;
    return page;
  }

  @override
  Future<IssuedInvite> issueInvite({
    required Map<String, Object?> record,
    required String phoneE164,
  }) async {
    issued.add((record: record, phone: phoneE164));
    return IssuedInvite(
      inviteId: 'invite-${issued.length}',
      recordId: record['id']! as String,
    );
  }

  @override
  Future<List<InviteOffer>> myInvites() async => const [];

  @override
  Future<String> acceptInvite(String inviteId) async {
    accepted.add(inviteId);
    return 'joined_pending_verification';
  }

  @override
  Future<List<String>> postRecords(List<Map<String, Object?>> records) async {
    posted.add(records);
    return nextResults;
  }
}

final class FakeAuthor implements MembersRecordAuthor {
  final signed = <({String kind, Map<String, Object?> payload})>[];
  int _n = 0;

  @override
  Uint8List nonce16() => Uint8List.fromList(List.filled(16, 9));

  @override
  Future<Map<String, Object?>> sign({
    required String tenantId,
    required String kind,
    required Map<String, Object?> payload,
  }) async {
    signed.add((kind: kind, payload: payload));
    return record('rec-signed-${++_n}', kind, payload, tenantId: tenantId);
  }
}

ServerMembersRepository repoFor(
  FakeApi api, {
  Set<String> believe = const {},
  String user = amrit,
  String tenantId = tenant,
  MembersRecordAuthor? author,
  MemberDirectory? directory,
  DateTime? now,
}) => ServerMembersRepository(
  api: api,
  tenantId: tenantId,
  userId: user,
  believes: (r) => believe.contains(r.id),
  unknownVerifierName: 'someone in this book',
  someoneToMeetName: 'someone already in this book',
  bookName: (id) => 'Book $id',
  author: author,
  directory:
      directory ??
      InMemoryMemberDirectory(
        names: const {amrit: 'Amrit', sunita: 'Sunita', harpreet: 'Harpreet'},
      ),
  clock: () => now ?? DateTime.fromMillisecondsSinceEpoch(1_757_100_000_000),
);

Member memberOf(MembersSnapshot s, String id) =>
    s.members.firstWhere((m) => m.id == id);

void main() {
  group('C-05d-7 a verification is believed only when a signed record backs it', () {
    /// A tenant where the server claims Harpreet is `active`. Only the
    /// backing evidence changes between cases.
    FakeApi serverClaimsActive({
      List<Map<String, Object?>> ceremonies = const [],
      List<Map<String, Object?>> records = const [],
    }) => FakeApi(
      meta(
        memberships: [
          membership(amrit, 'active'),
          membership(harpreet, 'active'),
        ],
        books: [book(ghar)],
        bookRoles: [
          bookRole(ghar, amrit, 'admin'),
          bookRole(ghar, harpreet, 'member'),
        ],
        devices: [device(amritPhone, amrit), device(sunitaPhone, sunita)],
        records: records,
        ceremonies: ceremonies,
      ),
    );

    test('C-05d-7 an unsigned verification_events row is not believed: the '
        'membership stays joined_pending_verification however loudly the '
        'server says active (ADR 2026-09-05d §7 🔒, migration 0008)', () async {
      final api = serverClaimsActive(
        ceremonies: [
          ceremony(subject: harpreet, verifier: sunita, sourceRecordId: null),
        ],
      );
      final repo = repoFor(api);
      await repo.refresh();

      final him = memberOf(repo.current!, harpreet);
      expect(him.state, MembershipState.joinedPendingVerification);
      expect(him.verification, isNull, reason: 'no ceremony to log');
    });

    test(
      'C-05d-7 an event naming a record that is not in the pull, or a record '
      'of the wrong kind, or one of another tenant, is no ceremony either',
      () async {
        for (final (label, records) in <(String, List<Map<String, Object?>>)>[
          ('no such record', const []),
          (
            'wrong kind',
            [
              record('rec-ceremony', 'membership_status', {
                'user_id': harpreet,
                'status': 'active',
              }, device: sunitaPhone),
            ],
          ),
          (
            'another tenant',
            [
              ceremonyRecord(
                'rec-ceremony',
                subject: harpreet,
                verifier: sunita,
                tenantId: otherTenant,
              ),
            ],
          ),
        ]) {
          final api = serverClaimsActive(
            records: records,
            ceremonies: [
              ceremony(
                subject: harpreet,
                verifier: sunita,
                sourceRecordId: 'rec-ceremony',
              ),
            ],
          );
          final repo = repoFor(api, believe: const {'rec-ceremony'});
          await repo.refresh();

          expect(
            memberOf(repo.current!, harpreet).state,
            MembershipState.joinedPendingVerification,
            reason: label,
          );
        }
      },
    );

    test(
      'C-05d-7 a record this device does not believe — the chain fails, or it '
      'was never verified — activates nobody',
      () async {
        final api = serverClaimsActive(
          records: [
            ceremonyRecord('rec-ceremony', subject: harpreet, verifier: sunita),
          ],
          ceremonies: [
            ceremony(
              subject: harpreet,
              verifier: sunita,
              sourceRecordId: 'rec-ceremony',
            ),
          ],
        );
        // believes nothing: the posture of a device that has verified nobody.
        final repo = repoFor(api);
        await repo.refresh();

        expect(
          memberOf(repo.current!, harpreet).state,
          MembershipState.joinedPendingVerification,
        );
      },
    );

    test('C-05d-7 where the row and the signed bytes disagree the bytes win: a '
        'record about somebody else, or reporting a mismatch, does not activate '
        'the subject the row names', () async {
      final api = serverClaimsActive(
        records: [
          ceremonyRecord(
            'rec-other-subject',
            subject: sunita,
            verifier: sunita,
          ),
          ceremonyRecord(
            'rec-mismatch',
            subject: harpreet,
            verifier: sunita,
            result: 'mismatch',
          ),
        ],
        ceremonies: [
          // The server re-points Harpreet's row at a record about Sunita …
          ceremony(
            subject: harpreet,
            verifier: sunita,
            sourceRecordId: 'rec-other-subject',
          ),
          // … and re-labels a failed ceremony as a pass.
          {
            ...ceremony(
              subject: harpreet,
              verifier: sunita,
              sourceRecordId: 'rec-mismatch',
            ),
            'id': 've-harpreet-2',
          },
        ],
      );
      final repo = repoFor(
        api,
        believe: const {'rec-other-subject', 'rec-mismatch'},
      );
      await repo.refresh();

      expect(
        memberOf(repo.current!, harpreet).state,
        MembershipState.joinedPendingVerification,
      );
    });

    test(
      'C-05d-7 all five conditions met: the membership is active and the 04 '
      '§6.4 log line says who verified whom, by which method, on which day',
      () async {
        final api = serverClaimsActive(
          records: [
            ceremonyRecord(
              'rec-ceremony',
              subject: harpreet,
              verifier: sunita,
              method: 'code_remote',
            ),
          ],
          ceremonies: [
            ceremony(
              subject: harpreet,
              verifier: sunita,
              method: 'code_remote',
              sourceRecordId: 'rec-ceremony',
              atMs: 1_757_000_000_000,
            ),
          ],
        );
        final repo = repoFor(api, believe: const {'rec-ceremony'});
        await repo.refresh();

        final him = memberOf(repo.current!, harpreet);
        expect(him.state, MembershipState.active);
        expect(him.verification!.verifiedByName, 'Sunita');
        expect(him.verification!.method, VerificationMethod.codeRemote);
        expect(
          him.verification!.on,
          DateTime.fromMillisecondsSinceEpoch(1_757_000_000_000),
        );
      },
    );

    test(
      'C-05d-7 the founder is the one active membership without a ceremony '
      '(06 §5): a believed membership_status record they authored themselves',
      () async {
        final api = FakeApi(
          meta(
            memberships: [membership(amrit, 'active')],
            books: [book(ghar)],
            bookRoles: [bookRole(ghar, amrit, 'admin')],
            devices: [device(amritPhone, amrit)],
            records: [
              record('rec-founding', 'membership_status', {
                'user_id': amrit,
                'status': 'active',
              }),
            ],
          ),
        );
        final repo = repoFor(api, believe: const {'rec-founding'});
        await repo.refresh();

        expect(memberOf(repo.current!, amrit).state, MembershipState.active);
        expect(repo.current!.readOnly, isFalse);
      },
    );
  });

  group('C-05d-9 the link alone admits nobody', () {
    test('C-05d-9 a joiner with a different number on the same link gets '
        'invite_not_for_you, and an invite id that does not exist refuses '
        'identically — the client is no more an oracle than the route is '
        '(ADR 2026-09-05d §9 🔒)', () async {
      final transport = ScriptedTransport()
        ..on(
          'invites/accept',
          const MembersHttpResponse(403, '{"error":"invite_not_for_you"}'),
        )
        ..on(
          'invites/accept',
          const MembersHttpResponse(403, '{"error":"invite_not_for_you"}'),
        );
      final api = HttpMembersApi(
        transport: transport,
        functionsRoot: Uri.parse('https://edge.example/functions/v1/'),
        accessToken: () async => 'jwt',
      );

      final wrongNumber = await api
          .acceptInvite('invite-1')
          .then<MembersFailure?>((_) => null)
          .onError<MembersFailure>((e, _) => e);
      final unknownInvite = await api
          .acceptInvite('invite-does-not-exist')
          .then<MembersFailure?>((_) => null)
          .onError<MembersFailure>((e, _) => e);

      expect(wrongNumber!.reason, MembersRefusal.inviteNotForYou);
      expect(
        unknownInvite!.reason,
        wrongNumber.reason,
        reason: 'one answer for both, exactly as the server gives one body',
      );

      // The request carries the id and nothing else: no number, ever.
      expect(transport.bodies, hasLength(2));
      for (final body in transport.bodies) {
        expect(body.keys.toList(), ['invite_id']);
      }
    });

    test(
      'C-05d-9 the number the admin actually invited walks in at '
      'joined_pending_verification — never active: the ceremony grants that',
      () async {
        final transport = ScriptedTransport()
          ..on(
            'invites/accept',
            const MembersHttpResponse(
              200,
              '{"invite_id":"invite-1","status":"joined_pending_verification"}',
            ),
          );
        final api = HttpMembersApi(
          transport: transport,
          functionsRoot: Uri.parse('https://edge.example/functions/v1/'),
          accessToken: () async => 'jwt',
        );

        expect(
          await api.acceptInvite('invite-1'),
          'joined_pending_verification',
        );
      },
    );

    test(
      'C-05d-9 every other named refusal keeps its own name, and a transport '
      'that never answered is offline — not a claim that the server spoke',
      () async {
        Future<MembersRefusal> refusalFor(MembersHttpResponse response) async {
          final transport = ScriptedTransport()..on('invites/accept', response);
          final api = HttpMembersApi(
            transport: transport,
            functionsRoot: Uri.parse('https://edge.example/functions/v1/'),
            accessToken: () async => 'jwt',
          );
          try {
            await api.acceptInvite('invite-1');
            fail('expected a refusal');
          } on MembersFailure catch (e) {
            return e.reason;
          }
        }

        expect(
          await refusalFor(
            const MembersHttpResponse(410, '{"error":"invite_expired"}'),
          ),
          MembersRefusal.inviteExpired,
        );
        expect(
          await refusalFor(
            const MembersHttpResponse(409, '{"error":"invite_not_live"}'),
          ),
          MembersRefusal.inviteNotLive,
        );
        expect(
          await refusalFor(
            const MembersHttpResponse(403, '{"error":"not_admin"}'),
          ),
          MembersRefusal.notAdmin,
        );

        final offline = ScriptedTransport()..offline = true;
        final api = HttpMembersApi(
          transport: offline,
          functionsRoot: Uri.parse('https://edge.example/functions/v1/'),
          accessToken: () async => 'jwt',
        );
        await expectLater(
          api.acceptInvite('invite-1'),
          throwsA(
            isA<MembersFailure>().having(
              (e) => e.reason,
              'reason',
              MembersRefusal.offline,
            ),
          ),
        );
      },
    );
  });

  group('C-06-14 identity model', () {
    test(
      'C-06-14 one number is one human is one account: the same user_id is one '
      'person in n tenants, and the tenant this repository shows is the only '
      'one it shows (06 §1 🔒, §1.1 🔒)',
      () async {
        final page = meta(
          memberships: [
            membership(amrit, 'active'),
            membership(amrit, 'active', t: otherTenant),
            membership(sunita, 'active', t: otherTenant),
          ],
          books: [
            book(ghar),
            book(elsewhere, t: otherTenant),
          ],
          bookRoles: [
            bookRole(ghar, amrit, 'admin'),
            bookRole(elsewhere, amrit, 'viewer'),
          ],
          devices: [device(amritPhone, amrit)],
          records: [
            record('rec-founding', 'membership_status', {
              'user_id': amrit,
              'status': 'active',
            }),
          ],
        );

        final here = repoFor(FakeApi(page), believe: const {'rec-founding'});
        await here.refresh();
        final there = repoFor(
          FakeApi(page),
          believe: const {'rec-founding'},
          tenantId: otherTenant,
        );
        await there.refresh();

        expect(here.current!.members.map((m) => m.id), [amrit]);
        expect(memberOf(here.current!, amrit).isYou, isTrue);
        expect(here.current!.books.map((b) => b.id), [ghar]);

        // The same identity, a second tenant, a different role — and Sunita,
        // who is not in the first tenant at all.
        expect(there.current!.members.map((m) => m.id).toSet(), {
          amrit,
          sunita,
        });
        expect(memberOf(there.current!, amrit).isYou, isTrue);
        expect(there.current!.yourRoles, {elsewhere: BookRole.viewer});
      },
    );
  });

  group('C-06-15 designations are labels; capability is granted', () {
    test(
      'C-06-15 a designation record changes the label and nothing else — a '
      'Chairman holding viewer is still no admin, and the invite refusal '
      'happens before the number leaves the phone (06 §1.0 🔒 Option B)',
      () async {
        final api = FakeApi(
          meta(
            memberships: [
              membership(amrit, 'active'),
              membership(sunita, 'active'),
            ],
            books: [book(ghar)],
            bookRoles: [
              bookRole(ghar, amrit, 'viewer'),
              bookRole(ghar, sunita, 'admin'),
            ],
            devices: [device(amritPhone, amrit), device(sunitaPhone, sunita)],
            records: [
              ceremonyRecord('rec-me', subject: amrit, verifier: sunita),
              record('rec-title', 'designation', {
                'user_id': amrit,
                'designation_label': 'Chairman',
              }, device: sunitaPhone),
              // An unbelieved record names a grander title; it is not a label
              // this device shows, because it is not a record it believes.
              record(
                'rec-forged',
                'designation',
                {'user_id': amrit, 'designation_label': 'Owner'},
                device: sunitaPhone,
                hlc: 9,
              ),
            ],
            ceremonies: [
              ceremony(
                subject: amrit,
                verifier: sunita,
                sourceRecordId: 'rec-me',
              ),
            ],
          ),
        );
        final author = FakeAuthor();
        final repo = repoFor(
          api,
          believe: const {'rec-me', 'rec-title'},
          author: author,
        );
        await repo.refresh();

        final me = memberOf(repo.current!, amrit);
        expect(me.designationLabel, 'Chairman');
        expect(
          me.grants.single.role,
          BookRole.viewer,
          reason: 'the label is not a power',
        );
        expect(repo.current!.adminOf(ghar), isFalse);
        expect(repo.current!.youAreAdminSomewhere, isFalse);

        await expectLater(
          repo.invite(
            const InviteRequest(
              phoneE164: '+919876500011',
              grants: [BookGrant(bookId: ghar, role: BookRole.member)],
            ),
          ),
          throwsA(
            isA<MembersFailure>().having(
              (e) => e.reason,
              'reason',
              MembersRefusal.notAdmin,
            ),
          ),
        );
        expect(api.issued, isEmpty, reason: 'the number never left the phone');
        expect(author.signed, isEmpty, reason: 'and nothing was signed');
      },
    );
  });

  group('C-06-16 multi-tenancy: one role per book, never global', () {
    FakeApi twoBooks() => FakeApi(
      meta(
        memberships: [
          membership(amrit, 'active'),
          membership(sunita, 'active'),
        ],
        books: [
          book(ghar),
          book(dukaan),
          book(elsewhere, t: otherTenant),
        ],
        bookRoles: [
          bookRole(ghar, amrit, 'admin'),
          bookRole(dukaan, amrit, 'viewer'),
          bookRole(ghar, sunita, 'head', paise: 500000),
          // Another tenant's book: this repository must not read it.
          bookRole(elsewhere, amrit, 'admin'),
        ],
        devices: [device(amritPhone, amrit), device(sunitaPhone, sunita)],
        records: [
          record('rec-founding', 'membership_status', {
            'user_id': amrit,
            'status': 'active',
          }),
          ceremonyRecord('rec-sunita', subject: sunita, verifier: amrit),
        ],
        ceremonies: [
          ceremony(
            subject: sunita,
            verifier: amrit,
            sourceRecordId: 'rec-sunita',
          ),
        ],
      ),
    );

    test(
      'C-06-16 a role is per book: admin here, viewer there, nothing global — '
      'and a book_role of another tenant is not read (06 §1.1 🔒)',
      () async {
        final repo = repoFor(
          twoBooks(),
          believe: const {'rec-founding', 'rec-sunita'},
        );
        await repo.refresh();
        final s = repo.current!;

        expect(s.yourRoles, {ghar: BookRole.admin, dukaan: BookRole.viewer});
        expect(s.adminOf(ghar), isTrue);
        expect(s.adminOf(dukaan), isFalse);
        expect(s.books.map((b) => b.id).toSet(), {ghar, dukaan});
        expect(
          memberOf(s, sunita).grantFor(dukaan),
          isNull,
          reason: 'no row means no access to that book',
        );
        expect(
          memberOf(s, sunita).grantFor(ghar)!.autoPostLimitPaise,
          500000,
          reason: 'the limit is integer paise (rule 1)',
        );
      },
    );

    test(
      'C-06-16 a limit is an admin power in the book it belongs to: refused in '
      'the book where I am a viewer, signed as a book_role record in the one '
      'where I am admin, in integer paise',
      () async {
        final api = twoBooks();
        final author = FakeAuthor();
        final repo = repoFor(
          api,
          believe: const {'rec-founding', 'rec-sunita'},
          author: author,
        );
        await repo.refresh();

        await expectLater(
          repo.setAutoPostLimit(memberId: sunita, bookId: dukaan, paise: 100),
          throwsA(
            isA<MembersFailure>().having(
              (e) => e.reason,
              'reason',
              MembersRefusal.notAdmin,
            ),
          ),
        );
        expect(api.posted, isEmpty);

        await repo.setAutoPostLimit(
          memberId: sunita,
          bookId: ghar,
          paise: 250000,
        );
        expect(author.signed.single.kind, 'book_role');
        expect(author.signed.single.payload, {
          'book_id': ghar,
          'user_id': sunita,
          'role': 'head',
          'auto_post_limit_paise': 250000,
        });
        expect(api.posted.single.single['kind'], 'book_role');
      },
    );

    test('C-06-16 a refusal from the record route keeps the server\'s name and '
        'nothing is claimed to have changed', () async {
      final api = twoBooks()..nextResults = const ['rejected:unauthorized'];
      final repo = repoFor(
        api,
        believe: const {'rec-founding', 'rec-sunita'},
        author: FakeAuthor(),
      );
      await repo.refresh();
      final pullsBefore = api.pulls;

      await expectLater(
        repo.setAutoPostLimit(memberId: sunita, bookId: ghar, paise: 1),
        throwsA(
          isA<MembersFailure>().having(
            (e) => e.reason,
            'reason',
            MembersRefusal.unauthorized,
          ),
        ),
      );
      expect(api.pulls, pullsBefore, reason: 'no refresh on a refusal');
    });
  });

  group('C-06-18 the invitation & membership state machine', () {
    test('C-06-18 every state of 06 §7 🔒 reads as itself: invited from a live '
        'invite, joined from a membership, active only with a ceremony, blocked '
        'after a failed one — and removed is gone', () async {
      final api = FakeApi(
        meta(
          memberships: [
            membership(amrit, 'active'),
            membership(harpreet, 'joined_pending_verification'),
            membership(sunita, 'blocked'),
            membership('user-gone', 'removed'),
          ],
          books: [book(ghar)],
          bookRoles: [bookRole(ghar, amrit, 'admin')],
          devices: [device(amritPhone, amrit)],
          records: [
            record('rec-founding', 'membership_status', {
              'user_id': amrit,
              'status': 'active',
            }),
          ],
          invites: [
            invite(
              'invite-live',
              roles: [
                {
                  'book_id': ghar,
                  'role': 'member',
                  'auto_post_limit_paise': 100000,
                },
              ],
            ),
            invite('invite-old', expiresAtMs: 1_756_000_000_000),
            invite('invite-taken', status: 'accepted'),
            invite('invite-dropped', status: 'revoked'),
          ],
        ),
      );
      final repo = repoFor(api, believe: const {'rec-founding'});
      await repo.refresh();
      final s = repo.current!;

      expect(memberOf(s, amrit).state, MembershipState.active);
      expect(
        memberOf(s, harpreet).state,
        MembershipState.joinedPendingVerification,
      );
      expect(memberOf(s, sunita).state, MembershipState.blocked);
      expect(s.members.any((m) => m.id == 'user-gone'), isFalse);

      final live = memberOf(s, 'invite-live');
      expect(live.state, MembershipState.invited);
      expect(live.expiresOn, isNotNull);
      expect(live.invitedByName, 'Amrit');
      expect(live.grants.single.role, BookRole.member);
      expect(live.grants.single.autoPostLimitPaise, 100000);

      // Lazy expiry binds when the list is read, exactly as the server binds
      // it at accept time — a missed sweep never shows a live link.
      expect(memberOf(s, 'invite-old').state, MembershipState.expired);
      expect(s.members.any((m) => m.id == 'invite-taken'), isFalse);
      expect(s.members.any((m) => m.id == 'invite-dropped'), isFalse);
    });

    test(
      'C-06-18 an invite is signed on this device and the number travels only '
      'in the request: the record carries {roles, nonce} and no identifier of '
      'the invitee at all (06 §7 🔒, 0008 ⚠️ SPEC)',
      () async {
        final api = FakeApi(
          meta(
            memberships: [membership(amrit, 'active')],
            books: [book(ghar)],
            bookRoles: [bookRole(ghar, amrit, 'admin')],
            devices: [device(amritPhone, amrit)],
            records: [
              record('rec-founding', 'membership_status', {
                'user_id': amrit,
                'status': 'active',
              }),
            ],
          ),
        );
        final author = FakeAuthor();
        final repo = repoFor(
          api,
          believe: const {'rec-founding'},
          author: author,
        );
        await repo.refresh();

        await repo.invite(
          const InviteRequest(
            phoneE164: '+919876500011',
            grants: [
              BookGrant(
                bookId: ghar,
                role: BookRole.member,
                autoPostLimitPaise: 500000,
              ),
            ],
            designationLabel: 'Treasurer',
          ),
        );

        final payload = author.signed.single;
        expect(payload.kind, 'invite');
        expect(payload.payload.keys.toSet(), {'roles', 'nonce'});
        expect((payload.payload['nonce']! as String).isNotEmpty, isTrue);
        expect(payload.payload['roles'], [
          {'book_id': ghar, 'role': 'member', 'auto_post_limit_paise': 500000},
        ]);
        expect(
          jsonEncode(payload.payload).contains('9876500011'),
          isFalse,
          reason: 'no identifier of the invitee is signed (ADR 2026-09-05c §4)',
        );
        expect(api.issued.single.phone, '+919876500011');
      },
    );

    test(
      'C-06-18 one-tap re-invite belongs to the phone that holds the contact '
      'card: it re-issues to the remembered number, and a second admin — who '
      'has the invite but not the number — is refused rather than guessing',
      () async {
        final api = FakeApi(
          meta(
            memberships: [membership(amrit, 'active')],
            books: [book(ghar)],
            bookRoles: [bookRole(ghar, amrit, 'admin')],
            devices: [device(amritPhone, amrit)],
            records: [
              record('rec-founding', 'membership_status', {
                'user_id': amrit,
                'status': 'active',
              }),
            ],
            invites: [
              invite(
                'invite-mine',
                expiresAtMs: 1_756_000_000_000,
                roles: [
                  {'book_id': ghar, 'role': 'member'},
                ],
              ),
              invite('invite-theirs', expiresAtMs: 1_756_000_000_000),
            ],
          ),
        );
        final repo = repoFor(
          api,
          believe: const {'rec-founding'},
          author: FakeAuthor(),
          directory: InMemoryMemberDirectory(
            names: const {amrit: 'Amrit'},
            invitees: const {
              'invite-mine': (phone: '+919876500011', name: 'Harpreet'),
            },
          ),
        );
        await repo.refresh();

        await repo.reinvite('invite-mine');
        expect(api.issued.single.phone, '+919876500011');

        await expectLater(
          repo.reinvite('invite-theirs'),
          throwsA(
            isA<MembersFailure>().having(
              (e) => e.reason,
              'reason',
              MembersRefusal.unknownInvitee,
            ),
          ),
        );
        expect(api.issued.length, 1, reason: 'no number was invented');
      },
    );

    test(
      'C-06-18 a member who is not yet verified sees the shared books as named '
      'placeholders and can change nothing (06 §7, 07 §12 🔒, S12.5)',
      () async {
        final api = FakeApi(
          meta(
            memberships: [
              membership(harpreet, 'joined_pending_verification'),
              membership(sunita, 'active'),
            ],
            books: [book(ghar)],
            bookRoles: [
              bookRole(ghar, harpreet, 'member'),
              bookRole(ghar, sunita, 'admin'),
            ],
            devices: [device(sunitaPhone, sunita)],
            records: [
              ceremonyRecord('rec-sunita', subject: sunita, verifier: sunita),
            ],
            ceremonies: [
              ceremony(
                subject: sunita,
                verifier: sunita,
                sourceRecordId: 'rec-sunita',
              ),
            ],
          ),
        );
        final repo = repoFor(
          api,
          believe: const {'rec-sunita'},
          user: harpreet,
        );
        await repo.refresh();
        final s = repo.current!;

        expect(
          memberOf(s, harpreet).state,
          MembershipState.joinedPendingVerification,
        );
        expect(s.pendingBooks.single.name, 'Book $ghar');
        expect(s.pendingBooks.single.activateWithName, 'Sunita');
        expect(s.readOnly, isTrue);
      },
    );
  });
}

/// A [MembersTransport] that answers from a scripted queue keyed by the
/// route's trailing path, and records every body it was given.
final class ScriptedTransport implements MembersTransport {
  final Map<String, List<MembersHttpResponse>> script = {};
  final bodies = <Map<String, Object?>>[];
  bool offline = false;

  void on(String path, MembersHttpResponse r) => (script[path] ??= []).add(r);

  MembersHttpResponse _answer(Uri url) {
    final key = script.keys
        .where(url.path.endsWith)
        .fold<String?>(
          null,
          (best, k) => best == null || k.length > best.length ? k : best,
        );
    final queue = key == null ? null : script[key];
    if (queue == null || queue.isEmpty) {
      return const MembersHttpResponse(500, '');
    }
    return queue.length == 1 ? queue.first : queue.removeAt(0);
  }

  @override
  Future<MembersHttpResponse> get(
    Uri url, {
    required Map<String, String> headers,
  }) async {
    if (offline) throw const MembersTransportException();
    return _answer(url);
  }

  @override
  Future<MembersHttpResponse> post(
    Uri url, {
    required Map<String, String> headers,
    required String body,
  }) async {
    if (offline) throw const MembersTransportException();
    bodies.add(jsonDecode(body) as Map<String, Object?>);
    return _answer(url);
  }
}
