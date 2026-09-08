// F1-10-9 … F1-10-14 — scripts/check_contrast.dart (design-system §3 / §3.1 🔒;
// ADR 2026-09-05f §H2, §H10). WCAG 2.1 arithmetic, role thresholds, the four
// grounds, alpha compositing and the waiver semantics — on in-memory tokens.
import 'package:test/test.dart';

import '../../scripts/src/contrast.dart';

Map<String, Object?> tokens(Map<String, Map<String, String>> byMode) => {
  r'$meta': {'modes': byMode.keys.toList()},
  'color': {
    for (final m in byMode.entries)
      m.key: {
        for (final t in m.value.entries) t.key: {'value': t.value, 'role': ''},
      },
  },
};

const paperGrounds = {
  'bg': '#F5F0E4',
  'surface': '#FBF8F0',
  'sunk': '#EFE9DA',
  'danger-surface': '#F6E3DD',
};

Measurement pick(List<Measurement> ms, String mode, String token, String g) =>
    ms.firstWhere((m) => m.mode == mode && m.token == token && m.ground == g);

void main() {
  test('F1-10-9 WCAG 2.1 arithmetic: black/white 21:1, identical 1:1, '
      'published brand figures reproduced', () {
    expect(
      contrastRatio(Rgba.parse('#000000'), Rgba.parse('#FFFFFF')),
      closeTo(21.0, 0.001),
    );
    expect(contrastRatio(Rgba.parse('#123456'), Rgba.parse('#123456')), 1.0);
    // design-system §3.1 measured values (4 Sep 2026 ruling).
    expect(
      contrastRatio(Rgba.parse('#CB6F6F'), Rgba.parse('#24231F')),
      closeTo(4.53, 0.01),
    );
    expect(
      contrastRatio(Rgba.parse('#4FA37A'), Rgba.parse('#1A1A18')),
      closeTo(5.69, 0.01),
    );
    expect(relativeLuminance(Rgba.parse('#FFFFFF')), closeTo(1.0, 1e-9));
    expect(relativeLuminance(Rgba.parse('#000')), 0.0);
  });

  test('F1-10-10 colour parsing: #RRGGBB, #RGB, rgba(); junk rejected', () {
    final c = Rgba.parse('rgba(26, 26, 24, 0.14)');
    expect([c.r, c.g, c.b, c.a], [26, 26, 24, 0.14]);
    expect(Rgba.parse('#abc').r, 0xAA);
    expect(() => Rgba.parse('tomato'), throwsFormatException);
  });

  test('F1-10-11 translucent tokens are composited over the ground before '
      'measuring (a 14% ink hairline is ~1.3:1, not 15:1)', () {
    final ink14 = Rgba.parse('rgba(26,26,24,0.14)');
    final paper = Rgba.parse('#F5F0E4');
    final r = contrastRatio(ink14, paper);
    expect(r, closeTo(1.33, 0.02));
    expect(ink14.over(paper).a, 1.0);
  });

  test('F1-10-12 every non-ground token is measured on all four grounds in '
      'every mode; on-primary against primary only; grounds skipped', () {
    final ms = audit(
      tokens({
        'light': {
          ...paperGrounds,
          'text': '#1A1A18',
          'primary': '#2B3A67',
          'on-primary': '#F5F0E4',
        },
        'dark': {
          'bg': '#1A1A18',
          'surface': '#24231F',
          'sunk': '#1F1E1B',
          'danger-surface': '#3A2723',
          'text': '#F5F0E4',
          'primary': '#93A5D6',
          'on-primary': '#1A1A18',
        },
      }),
    );
    for (final mode in ['light', 'dark']) {
      for (final token in ['text', 'primary']) {
        expect(
          ms
              .where((m) => m.mode == mode && m.token == token)
              .map((m) => m.ground)
              .toSet(),
          grounds.toSet(),
        );
      }
      final onP = ms.where((m) => m.mode == mode && m.token == 'on-primary');
      expect(onP.map((m) => m.ground).toList(), ['primary']);
      expect(onP.single.ratio, greaterThan(4.5));
    }
    expect(ms.any((m) => m.role == Role.ground), isFalse);
    expect(ms.any((m) => m.token == 'bg'), isFalse);
    expect(ms.where((m) => m.fails), isEmpty);
    // A missing ground is a hard error — §3.1 requires all four.
    expect(
      () => audit(
        tokens({
          'light': {'bg': '#FFFFFF', 'text': '#000000'},
        }),
      ),
      throwsStateError,
    );
  });

  test('F1-10-13 thresholds by role: text 4.5, ui 3.0, disabled/decorative '
      'reported but never gated; unknown tokens default to text', () {
    final ms = audit(
      tokens({
        'light': {
          ...paperGrounds,
          'text-muted': '#767676', // ~4.3 on paper: text → fails
          'accent': '#767676', // ui → passes (≥ 3)
          'locked': '#BBBBBB', // disabled → below 3, not gated
          'hairline': '#E3DCCB', // decorative → 1.2, not gated
          'brand-new': '#767676', // unknown → text → fails
        },
      }),
      waived: const [],
    );
    expect(pick(ms, 'light', 'text-muted', 'bg').fails, isTrue);
    expect(pick(ms, 'light', 'accent', 'bg').fails, isFalse);
    expect(pick(ms, 'light', 'accent', 'bg').ratio, greaterThan(3.0));
    final locked = pick(ms, 'light', 'locked', 'bg');
    expect(locked.ratio, lessThan(3.0));
    expect(locked.fails, isFalse);
    expect(locked.threshold, isNull);
    expect(pick(ms, 'light', 'hairline', 'bg').fails, isFalse);
    expect(pick(ms, 'light', 'brand-new', 'bg').role, Role.text);
    expect(pick(ms, 'light', 'brand-new', 'bg').fails, isTrue);
    expect(renderTable(ms), contains('✗'));
  });

  test('F1-10-14 waivers: a ruled pair is excluded (~), a pending-ruling '
      'pair warns (⚠) but neither fails; a non-matching waiver changes '
      'nothing', () {
    final t = tokens({
      'light': {...paperGrounds, 'credit': '#2F7A55', 'text-muted': '#6E6A5E'},
    });
    // Unwaived: the real light-credit-on-sunk (4.30) fails.
    final bare = audit(t, waived: const []);
    expect(pick(bare, 'light', 'credit', 'sunk').fails, isTrue);
    expect(pick(bare, 'light', 'credit', 'bg').fails, isFalse);

    final waivedMs = audit(
      t,
      waived: const [
        Waiver('light', 'credit', 'sunk', 'ruled', pendingRuling: false),
        Waiver('light', 'credit', 'danger-surface', 'ruled'),
        Waiver('light', 'text-muted', 'sunk', 'unruled', pendingRuling: true),
        Waiver(
          'light',
          'text-muted',
          'danger-surface',
          'unruled',
          pendingRuling: true,
        ),
        Waiver('dark', 'credit', 'sunk', 'wrong mode'),
      ],
    );
    final ruled = pick(waivedMs, 'light', 'credit', 'sunk');
    expect(ruled.fails, isFalse);
    expect(ruled.warns, isFalse);
    expect(ruled.belowThreshold, isTrue);
    final pending = pick(waivedMs, 'light', 'text-muted', 'sunk');
    expect(pending.fails, isFalse);
    expect(pending.warns, isTrue);
    expect(waivedMs.where((m) => m.fails), isEmpty);
    final table = renderTable(waivedMs);
    expect(table, contains('~'));
    expect(table, contains('⚠'));
    expect(table, isNot(contains('✗')));
  });

  test('F1-10-15 the shipped waiver list is minimal: every entry cites a '
      'design-system section and names one of the four grounds', () {
    for (final w in waivers) {
      expect(grounds, contains(w.ground));
      expect(w.reason, contains('design-system'), reason: w.token);
      expect(['light', 'dark'], contains(w.mode));
    }
    expect(waivers.length, lessThanOrEqualTo(9));
  });
}
