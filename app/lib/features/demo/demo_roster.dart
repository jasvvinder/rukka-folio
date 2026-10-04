// The demo roster (owner-directed, 4 Oct 2026): who a debug build can build
// books for, and which books each person holds in which role.
//
// DEBUG ONLY. The owner's real roster never enters the repository: it lives in
// the git-ignored `.demo/demo_roster.json` and reaches a debug build only as
// the compile-time define `RF_DEMO_ROSTER` (base64 of that file), which
// scripts/run_dev.sh passes and scripts/check_release_flags.sh refuses on any
// release build. Without the define — and in every test — the build uses the
// FICTIONAL roster in `demo_roster_fallback.dart`.
//
// Shape (the file's): `cases[] → people[] {key, name, phone, …}`,
// `books[] {key, name, kind, shares?, roles}`, `personal_books_for[]`.
// Fields this reader does not use are ignored, never an error: the roster is
// the owner's working file and grows notes freely.
import 'dart:convert';

/// A role a person holds on one roster book. Only [admin] and [head] can be
/// built on one device; the others need the owner's key (see
/// `demo_builder.dart`).
enum DemoRole {
  admin,
  head,
  member,
  operator,
  viewer;

  /// Whether this role makes the person the book's owner on this device.
  bool get owns => this == admin || this == head;

  static DemoRole? parse(Object? wire) => switch (wire) {
    'admin' => admin,
    'head' => head,
    'member' => member,
    'operator' => operator,
    'viewer' => viewer,
    _ => null,
  };
}

/// The kind of a roster book, as the roster spells it.
enum DemoBookKind {
  personal,
  business,
  joint,
  family,
  organization;

  static DemoBookKind? parse(Object? wire) => switch (wire) {
    'personal' => personal,
    'business' => business,
    'joint' => joint,
    'family' => family,
    'organization' => organization,
    _ => null,
  };
}

/// One person of a case.
final class DemoPerson {
  const DemoPerson({
    required this.key,
    required this.name,
    required this.phone,
  });

  /// Roster key — stable, never shown.
  final String key;

  /// Display name — roster data, never an ARB string.
  final String name;

  /// As the roster writes it (`+91 5000 0CC NNN`). Compared through
  /// [phonesMatch], never verbatim.
  final String phone;
}

/// One book of a case.
final class DemoBook {
  const DemoBook({
    required this.key,
    required this.name,
    required this.kind,
    this.shares = const [],
    this.roles = const {},
  });

  final String key;
  final String name;
  final DemoBookKind kind;

  /// Partner shares in roster order: person key → `'1/3'`, `'50%'` or a whole
  /// number. Empty when the roster names none.
  final List<(String, String)> shares;

  /// Person key → role.
  final Map<String, DemoRole> roles;
}

/// One case — a household, a business owner, a trust.
final class DemoCase {
  const DemoCase({
    required this.people,
    required this.books,
    this.personalBooksFor = const [],
  });

  final List<DemoPerson> people;
  final List<DemoBook> books;

  /// People of this case who each keep a personal book the roster does not
  /// list under [books] (`personal_books_for`).
  final List<String> personalBooksFor;

  DemoPerson? person(String key) {
    for (final p in people) {
      if (p.key == key) return p;
    }
    return null;
  }
}

/// The whole roster.
final class DemoRoster {
  const DemoRoster(this.cases);

  /// The roster a release build carries: nobody.
  static const empty = DemoRoster([]);

  final List<DemoCase> cases;

  /// The person whose roster phone is [phone], with their case — or null.
  (DemoPerson, DemoCase)? personForPhone(String? phone) {
    if (phone == null) return null;
    for (final c in cases) {
      for (final p in c.people) {
        if (phonesMatch(p.phone, phone)) return (p, c);
      }
    }
    return null;
  }

  /// Reads the roster file's JSON. Throws [FormatException] on a shape this
  /// reader cannot use; [decodeDemoRosterDefine] turns that into the
  /// fictional fallback.
  factory DemoRoster.fromJson(Object? json) {
    final root = _map(json, 'roster');
    final cases = <DemoCase>[];
    for (final c in _list(root['cases'], 'cases')) {
      final cm = _map(c, 'case');
      final people = [
        for (final p in _list(cm['people'], 'people'))
          DemoPerson(
            key: _string(_map(p, 'person')['key'], 'person.key'),
            name: _string(_map(p, 'person')['name'], 'person.name'),
            phone: _string(_map(p, 'person')['phone'], 'person.phone'),
          ),
      ];
      final books = <DemoBook>[];
      for (final b in _list(cm['books'], 'books')) {
        final bm = _map(b, 'book');
        final kind = DemoBookKind.parse(bm['kind']);
        if (kind == null) {
          throw FormatException('unknown book kind', '${bm['kind']}');
        }
        final rawShares = bm['shares'];
        final rawRoles = bm['roles'];
        books.add(
          DemoBook(
            key: _string(bm['key'], 'book.key'),
            name: _string(bm['name'], 'book.name'),
            kind: kind,
            shares: [
              if (rawShares != null)
                for (final e in _map(rawShares, 'shares').entries)
                  (e.key, _string(e.value, 'share')),
            ],
            roles: {
              if (rawRoles != null)
                for (final e in _map(rawRoles, 'roles').entries)
                  e.key:
                      DemoRole.parse(e.value) ??
                      (throw FormatException('unknown role', '${e.value}')),
            },
          ),
        );
      }
      final personal = cm['personal_books_for'];
      cases.add(
        DemoCase(
          people: people,
          books: books,
          personalBooksFor: [
            if (personal != null)
              for (final k in _list(personal, 'personal_books_for'))
                _string(k, 'personal_books_for[]'),
          ],
        ),
      );
    }
    return DemoRoster(cases);
  }
}

/// Where the roster in force came from — for the decode test (F1-DEMO-12).
enum DemoRosterSource {
  /// The `RF_DEMO_ROSTER` define, decoded.
  define,

  /// No define: the fictional roster.
  fallback,

  /// A define that would not decode: the fictional roster, no crash.
  malformed,
}

/// Decodes a base64 `RF_DEMO_ROSTER` value. Empty → the fictional
/// [fallback]; anything that fails to decode → [fallback] too, flagged
/// [DemoRosterSource.malformed]. Never throws, never logs (the define carries
/// real names and numbers — CLAUDE.md rule 4).
(DemoRoster, DemoRosterSource) decodeDemoRosterDefine(
  String define, {
  required DemoRoster fallback,
}) {
  if (define.trim().isEmpty) return (fallback, DemoRosterSource.fallback);
  try {
    final bytes = base64.decode(base64.normalize(define.trim()));
    final roster = DemoRoster.fromJson(jsonDecode(utf8.decode(bytes)));
    if (roster.cases.isEmpty) return (fallback, DemoRosterSource.malformed);
    return (roster, DemoRosterSource.define);
  } on Object {
    return (fallback, DemoRosterSource.malformed);
  }
}

/// The national ten digits of a number written any way (`+91 5000 0CC NNN`,
/// `+915000…`, `5000…`), or null when it has fewer than ten digits.
String? nationalDigits(String phone) {
  final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.length < 10) return null;
  return digits.substring(digits.length - 10);
}

/// Whether two spellings name the same number.
bool phonesMatch(String a, String b) {
  final x = nationalDigits(a);
  return x != null && x == nationalDigits(b);
}

/// The roster's share strings as 02 §7.1 integer weights, lowest terms:
/// `1/3 ×3` → `[1, 1, 1]`, `50/30/20 %` → `[5, 3, 2]`, `25 % ×4` →
/// `[1, 1, 1, 1]`. Pure integer arithmetic — no ratio ever passes through a
/// double. Throws [FormatException] on a share it cannot read.
List<int> shareWeights(List<String> shares) {
  final fractions = [for (final s in shares) _fraction(s)];
  if (fractions.isEmpty) return const [];
  var lcm = 1;
  for (final (_, d) in fractions) {
    lcm = lcm ~/ _gcd(lcm, d) * d;
  }
  final scaled = [for (final (n, d) in fractions) n * (lcm ~/ d)];
  var g = 0;
  for (final w in scaled) {
    g = _gcd(g, w);
  }
  if (g == 0) throw const FormatException('every share is zero');
  return [for (final w in scaled) w ~/ g];
}

(int, int) _fraction(String share) {
  final s = share.trim();
  final percent = RegExp(r'^(\d+)\s*%$').firstMatch(s);
  if (percent != null) return (int.parse(percent[1]!), 100);
  final ratio = RegExp(r'^(\d+)\s*/\s*(\d+)$').firstMatch(s);
  if (ratio != null) {
    final d = int.parse(ratio[2]!);
    if (d == 0) throw FormatException('zero denominator', share);
    return (int.parse(ratio[1]!), d);
  }
  final whole = RegExp(r'^(\d+)$').firstMatch(s);
  if (whole != null) return (int.parse(whole[1]!), 1);
  throw FormatException('unreadable share', share);
}

int _gcd(int a, int b) {
  var x = a.abs();
  var y = b.abs();
  while (y != 0) {
    final t = x % y;
    x = y;
    y = t;
  }
  return x;
}

Map<String, Object?> _map(Object? v, String what) => v is Map
    ? v.cast<String, Object?>()
    : throw FormatException('$what is not an object');

List<Object?> _list(Object? v, String what) =>
    v is List ? v : throw FormatException('$what is not a list');

String _string(Object? v, String what) => v is String && v.trim().isNotEmpty
    ? v
    : throw FormatException('$what is not a string');
