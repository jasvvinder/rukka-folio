// The camera frame: S9.3's and the recovery scan's, so every scanner
// implementation sits in the same square. Extracted from S9.3 unchanged.
import 'package:flutter/material.dart';

import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';

/// The camera frame — the screen owns it, so every scanner implementation
/// sits in the same square.
class CeremonyViewfinder extends StatelessWidget {
  /// Frames [child].
  const CeremonyViewfinder({super.key, required this.child});

  /// The scanner's preview.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final status = RkStatusColors.of(context);
    // Capped: a square viewfinder the full width of the phone pushes
    // *Enter code instead* — which 04 §6.2 🔒 requires on the screen — past the
    // fold, and at 200 % text scale far past it. Two-fifths of the height is
    // still a big target to aim a phone with.
    final maxHeight = MediaQuery.sizeOf(context).height * 0.4;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: AspectRatio(
        aspectRatio: 1,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: status.sunk,
            borderRadius: BorderRadius.circular(RkRadius.md),
            border: Border.all(color: status.hairline, width: RkIcon.stroke),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(RkRadius.md),
            child: child,
          ),
        ),
      ),
    );
  }
}
