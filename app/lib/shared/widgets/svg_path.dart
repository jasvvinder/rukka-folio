// A small SVG path-data parser — enough for the feather-style stroke glyphs
// design-system §4.1 locks (M/L/H/V/A/Z, absolute and relative, implicit
// line-tos after a move). Kept in-house so the tab bar carries no dependency;
// anything richer (curves) throws so a redraw never silently degrades.
import 'dart:ui';

/// Parses SVG `d` path data into a Flutter [Path] in viewBox units.
Path parseSvgPath(String d) {
  final path = Path();
  final tokens = _tokenize(d);
  var i = 0;
  var cx = 0.0, cy = 0.0; // current point
  var sx = 0.0, sy = 0.0; // subpath start
  String? cmd;

  double next() {
    if (i >= tokens.length) throw FormatException('path ended early: $d');
    final t = tokens[i++];
    final v = double.tryParse(t);
    if (v == null) throw FormatException('expected number, got "$t" in $d');
    return v;
  }

  while (i < tokens.length) {
    final t = tokens[i];
    if (double.tryParse(t) == null) {
      cmd = t;
      i++;
      if (cmd == 'Z' || cmd == 'z') {
        path.close();
        cx = sx;
        cy = sy;
        continue;
      }
    } else if (cmd == null) {
      throw FormatException('path must start with a command: $d');
    }
    final rel = cmd!.toLowerCase() == cmd;
    switch (cmd.toUpperCase()) {
      case 'M':
        var x = next(), y = next();
        if (rel) {
          x += cx;
          y += cy;
        }
        path.moveTo(x, y);
        cx = sx = x;
        cy = sy = y;
        // Further coordinate pairs are implicit line-tos (same relativity).
        cmd = rel ? 'l' : 'L';
      case 'L':
        var x = next(), y = next();
        if (rel) {
          x += cx;
          y += cy;
        }
        path.lineTo(x, y);
        cx = x;
        cy = y;
      case 'H':
        var x = next();
        if (rel) x += cx;
        path.lineTo(x, cy);
        cx = x;
      case 'V':
        var y = next();
        if (rel) y += cy;
        path.lineTo(cx, y);
        cy = y;
      case 'A':
        final rx = next(), ry = next(), rot = next();
        final large = next() != 0, sweep = next() != 0;
        var x = next(), y = next();
        if (rel) {
          x += cx;
          y += cy;
        }
        path.arcToPoint(
          Offset(x, y),
          radius: Radius.elliptical(rx, ry),
          rotation: rot,
          largeArc: large,
          clockwise: sweep,
        );
        cx = x;
        cy = y;
      default:
        throw FormatException('unsupported path command "$cmd" in $d');
    }
    // Repeated parameter sets without a command letter repeat the command
    // (the loop re-enters with `cmd` unchanged while numbers remain).
  }
  return path;
}

/// Splits `d` into command letters and numbers. Handles the compact forms
/// (`h-6l-2 3`, `.5.5`, flags glued to numbers) SVG allows.
List<String> _tokenize(String d) {
  final out = <String>[];
  final b = StringBuffer();
  void flush() {
    if (b.isNotEmpty) {
      out.add(b.toString());
      b.clear();
    }
  }

  for (var k = 0; k < d.length; k++) {
    final c = d[k];
    if (RegExp(r'[A-Za-z]').hasMatch(c)) {
      flush();
      out.add(c);
    } else if (c == ' ' || c == ',' || c == '\n' || c == '\t') {
      flush();
    } else if (c == '-') {
      // A minus starts a new number unless it follows an exponent marker.
      if (b.isNotEmpty && !b.toString().endsWith('e')) flush();
      b.write(c);
    } else if (c == '.') {
      // A second dot starts a new number: ".5.5" → ".5", ".5".
      if (b.toString().contains('.')) flush();
      b.write(c);
    } else {
      b.write(c);
    }
  }
  flush();
  return out;
}
