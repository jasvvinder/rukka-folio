// The quick chips of the money-account slot (07 §5 step 2 🔒): the three
// most-used money accounts plus **+ More** for the full list. The row is
// **absent entirely** when no money account is involved — milk on khata
// (`Dr Milk Expense · Cr Vardhman Dairy`) shows no chips rather than three
// chips that must not be tapped. **No chip is pre-selected** (ADR 2026-09-05f
// §C): a wrong default posts a wrong entry and nobody notices until the month
// will not reconcile.
//
// Selection is never colour alone (07 §1 rule 5) — the chosen chip carries a
// tick as well as its tone.
import 'package:flutter/material.dart';

import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';

/// One money-account chip.
class EntryAccountChip extends StatelessWidget {
  /// Creates the chip.
  const EntryAccountChip({
    super.key,
    required this.name,
    required this.selected,
    this.onTap,
  });

  /// The account's own name, in whatever script the user typed it.
  final String name;

  /// True when this chip is the slot's answer.
  final bool selected;

  /// Chooses this account.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final status = RkStatusColors.of(context);
    // The chip draws at its own height (body line + 2 × s2, the frame's
    // 36 px stadium) but its hit area is at least [entryMinTarget] tall
    // (13 §8): the Ink paints the tone inside a taller tappable box.
    return Padding(
      padding: const EdgeInsets.only(right: RkSpace.s2),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          customBorder: const StadiumBorder(),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: entryMinTarget),
            child: Center(
              widthFactor: 1,
              child: Ink(
                decoration: BoxDecoration(
                  color: selected ? scheme.primary : status.sunk,
                  borderRadius: BorderRadius.circular(RkRadius.lg),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: RkSpace.s3,
                    vertical: RkSpace.s2,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (selected)
                        Padding(
                          padding: const EdgeInsets.only(right: RkSpace.s1),
                          child: Icon(
                            Icons.check,
                            size: 16,
                            color: scheme.onPrimary,
                          ),
                        ),
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: RkType.body.copyWith(
                          color: selected ? scheme.onPrimary : scheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Keys for the chip row.
abstract final class EntryChipRowKeys {
  /// The **+ More** chip.
  static const more = Key('entry.chips.more');
}

/// The chip row: chips, then **+ More**. The chips pan horizontally — this
/// screen never scrolls *vertically* (07 §5 🔒) — but **+ More** sits outside
/// the panning part, so it is always wholly on screen (PLAN desk 193 (f): at
/// 390 wide it was clipped to "+ Mc" at the end of the pan).
class EntryChipRow extends StatelessWidget {
  /// Creates the row.
  const EntryChipRow({
    super.key,
    required this.names,
    required this.selectedId,
    required this.onPick,
    required this.onMore,
    required this.moreLabel,
  });

  /// Account id → name, in chip order.
  final List<(String, String)> names;

  /// The slot's answer, or null while nothing is chosen.
  final String? selectedId;

  /// Chooses an account.
  final void Function(String id) onPick;

  /// Opens the full list in the lower region (never a sheet, 07 §5 🔒).
  final VoidCallback onMore;

  /// The **+ More** label — the chip's tooltip and spoken name; the chip
  /// itself draws the canvas 2 dashed `+` (*State 3 · chosen*).
  final String moreLabel;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Flexible(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final (id, name) in names)
                    EntryAccountChip(
                      key: ValueKey('entry.chip.$id'),
                      name: name,
                      selected: id == selectedId,
                      onTap: () => onPick(id),
                    ),
                ],
              ),
            ),
          ),
          _MoreChip(
            key: EntryChipRowKeys.more,
            label: moreLabel,
            onTap: onMore,
          ),
        ],
      ),
    );
  }
}

/// The smallest hit area any entry control may have — 13 §8 *Touch targets
/// ≥ 44dp*, design-system §3.1 item 9 (tokens.json carries `minTouchTarget:
/// 44` only as a pending token, so it is spelt on the 4 pt grid, as
/// `authMinTarget` is).
const double entryMinTarget = RkSpace.s10 + RkSpace.s1;

/// The dashed `+` chip at the end of the row (canvas 2 *State 3 · chosen*).
///
/// The frame draws a 36 px circle; the drawn stadium here is the chips'
/// height (body line + 2 × s2) and the icon's width plus 2 × s3, but the
/// **hit area** is at least [entryMinTarget] square (13 §8) — the row grows
/// to 44 and the chips stay centred at their own height. The spoken node
/// carries the tap action, so TalkBack / VoiceOver can activate it (the
/// excluded InkWell's own action never reaches the tree).
class _MoreChip extends StatelessWidget {
  const _MoreChip({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final status = RkStatusColors.of(context);
    final size = MediaQuery.textScalerOf(context).scale(RkType.body.fontSize!);
    final line = size * (RkType.body.height ?? 1);
    return Semantics(
      button: true,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: Tooltip(
        message: label,
        child: InkWell(
          onTap: onTap,
          customBorder: const StadiumBorder(),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minWidth: entryMinTarget,
              minHeight: entryMinTarget,
            ),
            child: Center(
              widthFactor: 1,
              child: CustomPaint(
                painter: _DashedStadium(color: status.hairline),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: RkSpace.s3,
                    vertical: RkSpace.s2,
                  ),
                  child: SizedBox(
                    height: line,
                    child: Icon(Icons.add, size: size, color: status.muted),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DashedStadium extends CustomPainter {
  const _DashedStadium({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          (Offset.zero & size).deflate(0.5),
          const Radius.circular(RkRadius.lg),
        ),
      );
    const dash = RkSpace.s1;
    for (final metric in path.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += dash * 2) {
        canvas.drawPath(metric.extractPath(d, d + dash), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedStadium old) => old.color != color;
}
