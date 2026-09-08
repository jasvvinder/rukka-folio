// scripts/src/contrast.dart — pure WCAG 2.1 contrast logic behind
// scripts/check_contrast.dart. No dart:io so test/scripts/ can drive it with
// in-memory token maps.
//
// Relative luminance and contrast ratio follow WCAG 2.1 §1.4.3 / §1.4.11
// definitions exactly (sRGB linearisation, (L1+0.05)/(L2+0.05)).
// Translucent tokens (`rgba(...)`) are composited over the ground first —
// what the eye sees is the blend, not the source colour.
import 'dart:math' show pow;

/// An opaque sRGB colour (0–255 channels) plus an alpha in 0–1.
class Rgba {
  const Rgba(this.r, this.g, this.b, [this.a = 1.0]);
  final int r, g, b;
  final double a;

  /// `#RRGGBB`, `#RGB` or `rgba(r,g,b,a)` (spaces allowed).
  static Rgba parse(String s) {
    final t = s.trim();
    final hex = RegExp(r'^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6})$').firstMatch(t);
    if (hex != null) {
      var h = hex.group(1)!;
      if (h.length == 3) h = h.split('').map((c) => '$c$c').join();
      int ch(int i) => int.parse(h.substring(i, i + 2), radix: 16);
      return Rgba(ch(0), ch(2), ch(4));
    }
    final fn = RegExp(
      r'^rgba?\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*(?:,\s*([\d.]+)\s*)?\)$',
    ).firstMatch(t);
    if (fn != null) {
      return Rgba(
        int.parse(fn.group(1)!),
        int.parse(fn.group(2)!),
        int.parse(fn.group(3)!),
        fn.group(4) == null ? 1.0 : double.parse(fn.group(4)!),
      );
    }
    throw FormatException('unparseable colour "$s"');
  }

  /// This colour laid over an opaque [ground] (source-over).
  Rgba over(Rgba ground) {
    if (a >= 1.0) return this;
    int mix(int fg, int bg) => (fg * a + bg * (1 - a)).round();
    return Rgba(mix(r, ground.r), mix(g, ground.g), mix(b, ground.b));
  }
}

double _linear(int c) {
  final v = c / 255;
  return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4).toDouble();
}

/// WCAG 2.1 relative luminance of an opaque colour.
double relativeLuminance(Rgba c) =>
    0.2126 * _linear(c.r) + 0.7152 * _linear(c.g) + 0.0722 * _linear(c.b);

/// WCAG 2.1 contrast ratio between [fg] (composited over [ground]) and
/// an opaque [ground]. Always ≥ 1.
double contrastRatio(Rgba fg, Rgba ground) {
  final l1 = relativeLuminance(fg.over(ground));
  final l2 = relativeLuminance(ground);
  final hi = l1 > l2 ? l1 : l2;
  final lo = l1 > l2 ? l2 : l1;
  return (hi + 0.05) / (lo + 0.05);
}

/// How a token is used, which sets its WCAG threshold.
enum Role {
  /// Body / amount / status text — WCAG 1.4.3 AA, ≥ 4.5:1.
  text(4.5),

  /// Large text, icons, focus rings, meaningful UI parts — 1.4.11 / large
  /// text, ≥ 3:1.
  ui(3.0),

  /// Disabled content (WCAG 1.4.3 exemption: "inactive user interface
  /// component"). Reported, no threshold.
  disabled(null),

  /// Purely decorative (1.4.11 exemption): hairlines, skeleton blocks,
  /// loader track, scrims. Reported, no threshold.
  decorative(null),

  /// The colour IS a ground; not measured as a foreground.
  ground(null),

  /// Text that only ever sits on `primary`; measured against it alone.
  onPrimary(4.5);

  const Role(this.threshold);
  final double? threshold;
}

/// The four grounds design-system §3 / §3.1 🔒 require every token to be
/// measured against.
const grounds = ['bg', 'surface', 'sunk', 'danger-surface'];

/// Token name → role. Decided from tokens.json `role` text and
/// design-system §2/§3; unknown tokens default to [Role.text] (the strict
/// reading — a new token must be classified here to relax it).
const roles = <String, Role>{
  'bg': Role.ground,
  'surface': Role.ground,
  'sunk': Role.ground,
  'danger-surface': Role.ground,
  'text': Role.text,
  'text-muted': Role.text,
  'primary': Role.text, // headers, links (tokens.json role)
  'credit': Role.text, // amounts
  'debit': Role.text,
  'pending': Role.text, // status word + amount (design-system §2)
  'accent': Role.ui, // §3: seal, icons, large text only — never body text
  'focus': Role.ui, // 2px ring — 1.4.11
  'loader-segment': Role.ui, // the moving indicator
  'locked': Role.disabled, // §3: marks disabled content, 🔒 icon accompanies
  'hairline': Role.decorative,
  'loader-track': Role.decorative,
  'skeleton-label': Role.decorative,
  'skeleton-amount': Role.decorative,
  'scrim': Role.decorative,
  'on-primary': Role.onPrimary,
};

/// A (mode, token, ground) pair a design-system ruling excludes from the
/// threshold. Keep minimal; every entry cites its ruling.
class Waiver {
  const Waiver(
    this.mode,
    this.token,
    this.ground,
    this.reason, {
    this.pendingRuling = false,
  });
  final String mode, token, ground, reason;

  /// True when the docs have not ruled yet — printed as ⚠️ SPEC and counted
  /// separately so the owner sees it every run.
  final bool pendingRuling;
}

/// design-system §3.1 🔒 rulings (5 Sep 2026, ADR 2026-09-05f §H2) plus the
/// two pairs awaiting the token session. Removing a `pendingRuling` entry
/// flips CI red until tokens.json changes.
const waivers = <Waiver>[
  Waiver(
    'light',
    'credit',
    'danger-surface',
    'amounts are never placed on danger-surface (design-system §3.1)',
  ),
  Waiver(
    'light',
    'debit',
    'danger-surface',
    'amounts are never placed on danger-surface (design-system §3.1)',
  ),
  Waiver(
    'light',
    'pending',
    'danger-surface',
    'amounts are never placed on danger-surface (design-system §3.1)',
  ),
  Waiver(
    'dark',
    'credit',
    'danger-surface',
    'amounts are never placed on danger-surface (design-system §3.1)',
  ),
  Waiver(
    'dark',
    'debit',
    'danger-surface',
    'amounts are never placed on danger-surface (design-system §3.1)',
  ),
  Waiver(
    'dark',
    'pending',
    'danger-surface',
    'amounts are never placed on danger-surface (design-system §3.1)',
  ),
  Waiver(
    'light',
    'credit',
    'sunk',
    'ruled: light credit darkened one step, hex at the token session '
        '(design-system §2, §3.1; tokens.json _proposed_2026-09-05f)',
    pendingRuling: true,
  ),
  Waiver(
    'light',
    'text-muted',
    'sunk',
    '⚠️ SPEC: unruled — fails the design-system §3.1 four-ground rule; found '
        '7 Sep 2026 by check_contrast; owner to darken text-muted or keep '
        'captions off sunk',
    pendingRuling: true,
  ),
  Waiver(
    'light',
    'text-muted',
    'danger-surface',
    '⚠️ SPEC: unruled — fails the design-system §3.1 four-ground rule; found '
        '7 Sep 2026 by check_contrast; owner to darken text-muted or keep '
        'captions off danger-surface',
    pendingRuling: true,
  ),
];

/// One measured pair.
class Measurement {
  Measurement({
    required this.mode,
    required this.token,
    required this.ground,
    required this.role,
    required this.ratio,
    this.waiver,
  });
  final String mode, token, ground;
  final Role role;
  final double ratio;
  final Waiver? waiver;

  double? get threshold => role.threshold;
  bool get belowThreshold => threshold != null && ratio < threshold!;

  /// Fails the gate: below threshold and not waived.
  bool get fails => belowThreshold && waiver == null;

  /// Below threshold, waived, but the docs have not ruled.
  bool get warns => belowThreshold && (waiver?.pendingRuling ?? false);
}

/// Measures every token in `tokens['color'][mode]` against [grounds] (and
/// `on-primary` against `primary`). [tokens] is the parsed tokens.json.
List<Measurement> audit(
  Map<String, Object?> tokens, {
  Map<String, Role> roleOf = roles,
  List<Waiver> waived = waivers,
}) {
  final color = tokens['color'] as Map<String, Object?>;
  final modes =
      ((tokens[r'$meta'] as Map<String, Object?>?)?['modes'] as List<Object?>?)
          ?.cast<String>() ??
      ['light', 'dark'];
  final out = <Measurement>[];
  for (final mode in modes) {
    final set = color[mode] as Map<String, Object?>;
    final values = <String, Rgba>{
      for (final e in set.entries)
        e.key: Rgba.parse((e.value as Map<String, Object?>)['value'] as String),
    };
    for (final g in grounds) {
      if (!values.containsKey(g)) {
        throw StateError('$mode has no "$g" ground (design-system §3.1)');
      }
    }
    final names = values.keys.toList()..sort();
    for (final token in names) {
      final role = roleOf[token] ?? Role.text;
      if (role == Role.ground) continue;
      final against = role == Role.onPrimary ? ['primary'] : grounds;
      for (final g in against) {
        final ground = values[g];
        if (ground == null) continue;
        out.add(
          Measurement(
            mode: mode,
            token: token,
            ground: g,
            role: role,
            ratio: contrastRatio(values[token]!, ground),
            waiver: waived.cast<Waiver?>().firstWhere(
              (w) => w!.mode == mode && w.token == token && w.ground == g,
              orElse: () => null,
            ),
          ),
        );
      }
    }
  }
  return out;
}

/// Plain-text table, one row per token per mode.
String renderTable(List<Measurement> ms) {
  final b = StringBuffer();
  final byKey = <String, List<Measurement>>{};
  for (final m in ms) {
    (byKey['${m.mode}|${m.token}'] ??= []).add(m);
  }
  String? lastMode;
  for (final e in byKey.entries) {
    final first = e.value.first;
    if (first.mode != lastMode) {
      lastMode = first.mode;
      b.writeln();
      b.writeln(
        '${first.mode.padRight(16)} role        '
        '${grounds.map((g) => g.padLeft(9)).join('  ')}',
      );
    }
    final cells = <String>[];
    for (final g in first.role == Role.onPrimary ? ['primary'] : grounds) {
      final m = e.value.firstWhere((m) => m.ground == g);
      final mark = m.fails
          ? ' ✗'
          : m.warns
          ? ' ⚠'
          : m.belowThreshold
          ? ' ~' // waived by a ruling
          : '  ';
      cells.add('${m.ratio.toStringAsFixed(2).padLeft(7)}$mark');
    }
    final role = first.role.threshold == null
        ? first.role.name
        : '${first.role.name} ≥${first.role.threshold}';
    b.writeln(
      '${first.token.padRight(16)} ${role.padRight(11)} '
      '${cells.join('  ')}'
      '${first.role == Role.onPrimary ? '   (on primary)' : ''}',
    );
  }
  return b.toString();
}
