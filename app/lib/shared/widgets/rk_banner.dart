// The **banner** atom of 13 §4.2 — one surface, every user of it.
//
// 13 §4.2 lists the banner once ("persistent: suspended, read-only, book
// full"); there is therefore one implementation, not one per feature. Two
// families sit on top of it and nothing else may hand-roll a third:
//
//   * `RkRestrictionBanner` (`rk_restriction.dart`) — the persistent family
//     the atom names: suspended (S15.4), read-only (S12.5), book full, and
//     the device-local offline grace.
//   * `RkConnectionNotice` (`rk_connection_notice.dart`) — S19.3 *No
//     connection*, non-blocking (13 §3.2 row S19.3, 07 §24).
//
// The surface itself knows nothing about restrictions, entitlements, the
// network or the clock: it is given a tone, an icon, words and zero or more
// actions. Colour is never alone (07 §1 rule 3) — the icon travels with the
// tint and the words carry the meaning without either.
import 'package:flutter/material.dart';

import '../theme.dart';
import '../tokens.dart';

/// How loud the banner is. Tints come from the status family only
/// (design-system §3.1; tokens are the sole source — a hex literal here is
/// review-blocking).
enum RkBannerTone {
  /// A state, not an event: read-only, offline, no connection.
  info,

  /// The user can act on it: book full.
  warning,

  /// A security position: this phone is suspended (S15.4).
  danger;

  /// Resolves to the token for this tone.
  Color tint(RkStatusColors s) => switch (this) {
    RkBannerTone.info => s.info,
    RkBannerTone.warning => s.warning,
    RkBannerTone.danger => s.danger,
  };
}

/// The shared banner surface: sunk ground, the brand's 3 px left rule
/// (brand §4.1), icon + title, an optional body and optional actions.
///
/// Announced as one live region so a screen reader hears the fact once,
/// whole, when it appears.
class RkBannerSurface extends StatelessWidget {
  /// Creates the surface. [body] and [actions] are optional: several
  /// placements state a single line and let the screen beneath carry the way
  /// forward (S15.4 does exactly that).
  const RkBannerSurface({
    super.key,
    required this.tone,
    required this.icon,
    required this.title,
    this.body,
    this.actions = const [],
  });

  /// Tint family.
  final RkBannerTone tone;

  /// The icon that carries the meaning when the tint cannot (grayscale,
  /// colour vision deficiency — 07 §18).
  final IconData icon;

  /// The fact, in one line.
  final String title;

  /// Why, and what still works. Omitted where the screen says it.
  final String? body;

  /// Ways forward. Omitted where the screen beneath owns them; never a
  /// dismiss that leaves the user nowhere (07 §1 rule 6).
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final status = RkStatusColors.of(context);
    final text = Theme.of(context).textTheme;
    final body = this.body;
    return Semantics(
      container: true,
      liveRegion: true,
      label: body == null ? title : '$title. $body',
      child: Material(
        color: status.sunk,
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              // The 3px left rule of the brand's card language (brand §4.1).
              left: BorderSide(
                color: tone.tint(status),
                width: RkRadius.ruleLeftWidth,
              ),
              bottom: BorderSide(color: status.hairline),
            ),
          ),
          padding: const EdgeInsets.all(RkSpace.cardPadding),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: tone.tint(status), size: RkIcon.grid),
              const SizedBox(width: RkSpace.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: text.titleSmall?.copyWith(color: scheme.onSurface),
                    ),
                    if (body != null) ...[
                      const SizedBox(height: RkSpace.s1),
                      Text(
                        body,
                        style: text.bodySmall?.copyWith(color: status.muted),
                      ),
                    ],
                    if (actions.isNotEmpty) ...[
                      const SizedBox(height: RkSpace.s2),
                      // Wrap, not Row: at 200 % text scale on 360 px the
                      // actions stack instead of overflowing (07 §18).
                      Wrap(
                        spacing: RkSpace.s4,
                        runSpacing: RkSpace.s1,
                        children: actions,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
