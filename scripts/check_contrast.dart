// scripts/check_contrast.dart — the contrast audit (design-system §3, §3.1 🔒;
// ADR 2026-09-05f §H2, §H10). Run by ci.sh right after the generated-files step.
//
// Reads design/tokens/tokens.json (the sole token source) and computes WCAG 2.1
// contrast for EVERY colour token, both modes, against ALL FOUR grounds —
// `bg`, `surface`, `sunk`, `danger-surface` — plus `on-primary` against
// `primary`. Translucent tokens are composited over the ground first.
//
// Role → threshold (the mapping itself lives in scripts/src/contrast.dart
// `roles`; unknown tokens default to the strict text role):
//   text       ≥ 4.5   text, text-muted, primary (links/headers), credit,
//                       debit, pending (amounts and status words)
//   ui         ≥ 3.0   accent (seal/icons/large text only, §3), focus (ring),
//                       loader-segment
//   on-primary ≥ 4.5   on-primary, measured against `primary` only
//   disabled   —       locked (WCAG 1.4.3 inactive-component exemption; §3:
//                       "never the only signal, 🔒 icon always accompanies")
//   decorative —       hairline, loader-track, skeleton-*, scrim (1.4.11
//                       decoration exemption) — reported, not gated
//   ground     —       bg, surface, sunk, danger-surface
//
// Waivers (`waivers` in contrast.dart) are pairs a design-system ruling puts
// out of scope — amounts never sit on danger-surface (§3.1). Entries marked
// `pendingRuling` print ⚠ and DO NOT fail the gate, but are the owner's to
// close at the token session; deleting one turns the pair into a hard failure.
//
// Legend in the table:  ✗ fails   ⚠ below threshold, ruling pending
//                        ~ below threshold, waived by ruling
//
//   dart run scripts/check_contrast.dart
import 'dart:convert';
import 'dart:io';

import 'src/contrast.dart';

const tokensPath = 'design/tokens/tokens.json';

void main() {
  final tokens =
      jsonDecode(File(tokensPath).readAsStringSync()) as Map<String, Object?>;
  final ms = audit(tokens);
  stdout.writeln(renderTable(ms));

  final warns = ms.where((m) => m.warns).toList();
  final fails = ms.where((m) => m.fails).toList();
  for (final m in warns) {
    stdout.writeln(
      '⚠ ${m.mode} ${m.token} on ${m.ground}: ${m.ratio.toStringAsFixed(2)}:1 '
      '< ${m.threshold} — ${m.waiver!.reason}',
    );
  }
  for (final m in fails) {
    stderr.writeln(
      '✗ ${m.mode} ${m.token} on ${m.ground}: ${m.ratio.toStringAsFixed(2)}:1 '
      '< ${m.threshold} (${m.role.name})',
    );
  }
  final gated = ms.where((m) => m.threshold != null).length;
  if (fails.isNotEmpty) {
    stderr.writeln(
      'contrast: ${fails.length} of $gated gated pairs fail — do not edit '
      'tokens.json in a lane; report to the owner (design-system §3.1)',
    );
    exit(1);
  }
  stdout.writeln(
    'contrast ok: $gated gated pairs pass'
    '${warns.isEmpty ? '' : ' (${warns.length} waived pending ruling)'}',
  );
}
