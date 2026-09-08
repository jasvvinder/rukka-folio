// F1-10-2 … F1-10-8 — scripts/gen_l10n_arb.dart merge + identifier stages
// (PLAN.md P0 "ARB parts"; 01 §1 rule 9 🔒; CLAUDE.md rule 8). In-memory
// fixtures only — no processes, no repo files.
import 'package:test/test.dart';

import '../../scripts/src/arb_merge.dart';

ArbPart part(String feature, String lang, String body) => ArbPart(
  path: 'parts/${feature}_$lang.arb',
  text: '{"@@locale": "$lang"${body.isEmpty ? '' : ', $body'}}',
);

List<ArbPart> trio(String feature, Map<String, String> byLang) => [
  for (final l in languages) part(feature, l, byLang[l] ?? ''),
];

void main() {
  test('F1-10-2 merge: parts of two features → one ARB per language, '
      'sorted, marked generated, meta kept', () {
    final r = mergeParts([
      ...trio('core', {
        'en': '"app.name": "Rukka Folio", "@app.name": {"description": "d"}',
        'pa': '"app.name": "Rukka Folio"',
        'hi': '"app.name": "Rukka Folio"',
      }),
      ...trio('home', {
        'en': '"home.title": "Home"',
        'pa': '"home.title": "ਘਰ"',
        'hi': '"home.title": "घर"',
      }),
    ]);
    final en = r.byLanguage['en']!;
    expect(en.keys.toList(), [
      '@@locale',
      generatedMarker,
      'app.name',
      '@app.name',
      'home.title',
    ]);
    expect(en['@@locale'], 'en');
    expect(r.byLanguage['pa']!['home.title'], 'ਘਰ');
    expect(r.byLanguage['hi']!.containsKey('@app.name'), isFalse);
    expect(r.owner['pa']!['home.title'], 'parts/home_pa.arb');
    expect(r.owner['en']!['app.name'], 'parts/core_en.arb');
  });

  test('F1-10-3 merge fails when a key is defined in two parts', () {
    expect(
      () => mergeParts([
        ...trio('core', {for (final l in languages) l: '"app.name": "x"'}),
        ...trio('shell', {for (final l in languages) l: '"app.name": "y"'}),
      ]),
      throwsA(
        isA<ArbError>().having(
          (e) => e.message,
          'message',
          allOf(
            contains('"app.name"'),
            contains('parts/core_en.arb'),
            contains('parts/shell_en.arb'),
          ),
        ),
      ),
    );
  });

  test('F1-10-4 merge fails on a key present in one language of a feature '
      'but not the other two, naming the part that lacks it', () {
    expect(
      () => mergeParts(
        trio('home', {
          'en': '"home.title": "Home", "home.empty": "Nothing yet"',
          'pa': '"home.title": "ਘਰ"',
          'hi': '"home.title": "घर", "home.empty": "अभी कुछ नहीं"',
        }),
      ),
      throwsA(
        isA<ArbError>().having(
          (e) => e.message,
          'message',
          allOf(contains('"home.empty"'), contains('parts/home_pa.arb')),
        ),
      ),
    );
  });

  test('F1-10-5 merge fails when a feature lacks a whole language file', () {
    expect(
      () => mergeParts([
        part('home', 'en', '"home.title": "Home"'),
        part('home', 'pa', '"home.title": "ਘਰ"'),
      ]),
      throwsA(
        isA<ArbError>().having(
          (e) => e.message,
          'message',
          contains('home_hi.arb'),
        ),
      ),
    );
  });

  group('F1-10-6 malformed ARB is rejected with the file named', () {
    final cases = <String, String>{
      'not JSON': '{"@@locale": "en", ',
      'top level not an object': '["a"]',
      'non-string value': '{"@@locale": "en", "a.b": 3}',
      'meta not an object': '{"@@locale": "en", "a.b": "x", "@a.b": "d"}',
      'meta without key': '{"@@locale": "en", "@a.b": {"description": "d"}}',
      'wrong @@locale': '{"@@locale": "pa", "a.b": "x"}',
      'foreign @@ attribute': '{"@@locale": "en", "@@author": "me"}',
    };
    for (final c in cases.entries) {
      test(c.key, () {
        expect(
          () => parseArb('parts/x_en.arb', c.value, lang: 'en'),
          throwsA(
            isA<ArbError>().having(
              (e) => e.message,
              'message',
              startsWith('parts/x_en.arb:'),
            ),
          ),
        );
      });
    }
    test('F1-10-16 part file name must be <feature>_<lang>.arb', () {
      expect(
        () => mergeParts([
          ArbPart(path: 'parts/home.arb', text: '{"@@locale":"en"}'),
        ]),
        throwsA(isA<ArbError>()),
      );
    });
  });

  test('F1-10-7 identifier stage: dotted → camelCase, meta follows, '
      'generated marker dropped, collisions rejected', () {
    final out = toIdentifierArb('app_en.arb', {
      '@@locale': 'en',
      generatedMarker: generatedNote,
      'app.name': 'Rukka Folio',
      '@app.name': {'description': 'd'},
      'home.money_in.label': 'Money in',
    });
    expect(out, {
      '@@locale': 'en',
      'appName': 'Rukka Folio',
      '@appName': {'description': 'd'},
      'homeMoneyInLabel': 'Money in',
    });
    expect(identifier('splash.opening'), 'splashOpening');
    expect(
      () => toIdentifierArb('app_en.arb', {'a.b': 'x', 'a_b': 'y'}),
      throwsA(isA<ArbError>()),
    );
    expect(() => identifier('1.bad'), throwsA(isA<ArbError>()));
  });

  test('F1-10-8 merging the same parts twice is byte-stable', () {
    final parts = trio('core', {
      for (final l in languages) l: '"b.x": "1", "a.y": "2"',
    });
    final one = encodeArb(mergeParts(parts).byLanguage['en']!);
    final two = encodeArb(mergeParts(parts.reversed).byLanguage['en']!);
    expect(one, two);
    expect(one, endsWith('\n'));
  });
}
