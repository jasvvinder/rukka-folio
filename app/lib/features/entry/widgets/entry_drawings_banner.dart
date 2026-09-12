// S2.5 — the drawings confirmation (07 §5 "Owner's drawings" paragraph 🔒,
// ratified 2 Sep 2026, ADR 2026-09-02, design B5; 13 §3.2 row S2.5).
//
// In a business book, money the owner takes for himself posts to **Drawings
// (equity)**, never to an expense category. When Money out's ledger slot
// (the FOR account, 07 §5 slots-by-verb table) is the book's Drawings
// account, this one-line confirmation states it plainly, on S2 itself — it
// is not a sheet or a second screen (the single-screen block governs S2
// throughout), just a banner that appears the moment the counterpart makes
// it true and disappears the moment it no longer is. The posting itself is
// 02 §7.1's equity rule; this banner only ever narrates it.
import 'package:flutter/material.dart';

import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';

/// Key the screen's own tests drive this by.
abstract final class EntryDrawingsBannerKeys {
  /// The banner itself.
  static const banner = Key('entry.drawings.banner');
}

/// The one-line confirmation (07 §5 🔒 wording, from ARB — never composed
/// here, 01 §1 rule 7).
class EntryDrawingsBanner extends StatelessWidget {
  /// Creates the banner.
  const EntryDrawingsBanner({super.key, required this.message});

  /// `l10n.entryDrawingsConfirmation`.
  final String message;

  @override
  Widget build(BuildContext context) {
    final status = RkStatusColors.of(context);
    return Container(
      key: EntryDrawingsBannerKeys.banner,
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: RkSpace.s2),
      padding: const EdgeInsets.symmetric(
        horizontal: RkSpace.s3,
        vertical: RkSpace.s2,
      ),
      decoration: BoxDecoration(
        color: status.sunk,
        border: Border(
          left: BorderSide(color: status.locked, width: RkRadius.ruleLeftWidth),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 16, color: status.muted),
          const SizedBox(width: RkSpace.s2),
          Expanded(
            child: Text(
              message,
              style: RkType.caption.copyWith(color: status.muted),
            ),
          ),
        ],
      ),
    );
  }
}
