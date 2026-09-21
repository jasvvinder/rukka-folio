// Widgets private to the account feature (features/README "Layout").
//
// Three shapes, all of them tokens-only (a hex literal here is
// review-blocking): the initials disc that stands in for the photo the app
// cannot take, the two row shapes of 13 §4.3 (navigable, and
// disabled-with-reason), and the fact list S16.3 uses for *what is erased*
// and *what stays*.
//
// Every string draws through [RkFitText] where a row must not grow: at 200 %
// on a 360 px phone a title alone can need more width than the row has, and
// Flutter draws the overflow past the edge without throwing — a green test
// over an unreadable row.
import 'package:flutter/material.dart';

import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';
import '../../../shared/widgets/rk_fit_text.dart';

/// The initials disc. **Not a photo** — the app has no photo pipeline, so
/// this is what the account has instead, in whatever script the name is
/// written in (01 §1 rule 9 🔒: a user-typed string keeps its own language).
class AccountAvatar extends StatelessWidget {
  /// Creates the disc.
  const AccountAvatar({
    super.key,
    required this.initials,
    required this.semanticLabel,
    required this.nameLang,
    this.diameter = 56,
  });

  /// One or two letters from the name.
  final String initials;

  /// What a screen reader hears — it says *initials*, never "photo".
  final String semanticLabel;

  /// Script tag of the name (`en` · `pa` · `hi`).
  final String nameLang;

  /// Disc size at text scale 1; it grows with the text so the letters fit.
  final double diameter;

  @override
  Widget build(BuildContext context) {
    final status = RkStatusColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    final scaled = MediaQuery.textScalerOf(context).scale(diameter);
    return Semantics(
      label: semanticLabel,
      image: false,
      child: ExcludeSemantics(
        child: Container(
          width: scaled,
          height: scaled,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: status.sunk,
            shape: BoxShape.circle,
            border: Border.all(color: status.hairline),
          ),
          child: Localizations.override(
            context: context,
            locale: Locale(nameLang),
            child: Builder(
              builder: (context) => Text(
                initials,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: scheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One navigable account row: title, optional value, chevron.
class AccountRow extends StatelessWidget {
  /// Creates the row.
  const AccountRow({
    super.key,
    required this.title,
    this.value,
    this.subtitle,
    this.onTap,
  });

  /// The row's label.
  final String title;

  /// The current value, under the title.
  final String? value;

  /// A quieter second line (where the control actually lives, and so on).
  final String? subtitle;

  /// Where the row goes.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final status = RkStatusColors.of(context);
    return Semantics(
      button: onTap != null,
      label: [
        title,
        if (value != null) value,
        if (subtitle != null) subtitle,
      ].join('. '),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.zero,
          child: Container(
            constraints: const BoxConstraints(minHeight: RkSpace.rowMinHeight),
            padding: const EdgeInsets.symmetric(
              horizontal: RkSpace.gutter,
              vertical: RkSpace.s3,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      RkFitText(title, style: text.bodyLarge),
                      if (value != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: RkFitText(
                            value!,
                            style: text.bodyMedium?.copyWith(
                              color: status.muted,
                            ),
                          ),
                        ),
                      if (subtitle != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: RkFitText(
                            subtitle!,
                            style: text.bodySmall?.copyWith(
                              color: status.muted,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: RkSpace.s2),
                Icon(Icons.chevron_right, color: status.muted, size: 22),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A row whose destination does not exist yet. Never a dead end (07 §1 rule
/// 6): it stays in the list, dimmed, with a clock icon paired to a sentence,
/// so the state never rides on colour alone (07 §1 rule 3). There is no
/// `onTap` at all — a tap that does nothing is worse than a disabled row.
class AccountDisabledRow extends StatelessWidget {
  /// Creates the row.
  const AccountDisabledRow({
    super.key,
    required this.title,
    required this.reason,
    this.value,
  });

  /// The row's label.
  final String title;

  /// The current value, under the title.
  final String? value;

  /// Why it cannot be entered.
  final String reason;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final status = RkStatusColors.of(context);
    return Semantics(
      enabled: false,
      label: '$title. ${value == null ? '' : '$value. '}$reason',
      child: ExcludeSemantics(
        child: Container(
          constraints: const BoxConstraints(minHeight: RkSpace.rowMinHeight),
          padding: const EdgeInsets.symmetric(
            horizontal: RkSpace.gutter,
            vertical: RkSpace.s3,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              RkFitText(
                title,
                style: text.bodyLarge?.copyWith(color: status.muted),
              ),
              if (value != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: RkFitText(
                    value!,
                    style: text.bodyMedium?.copyWith(color: status.muted),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.only(top: RkSpace.s1),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.schedule, size: 14, color: status.muted),
                    const SizedBox(width: RkSpace.s1),
                    Expanded(
                      child: Text(
                        reason,
                        style: text.bodySmall?.copyWith(color: status.muted),
                      ),
                    ),
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

/// A headed list of plain facts — S16.3's *what is erased* and *what stays*.
/// The icon travels with every line so the two lists are told apart without
/// colour (07 §1 rule 3), and the heading is a real heading for a screen
/// reader.
class AccountFactList extends StatelessWidget {
  /// Creates the list.
  const AccountFactList({
    super.key,
    required this.heading,
    required this.icon,
    required this.items,
    this.tint,
    this.footnote,
  });

  /// The list's heading.
  final String heading;

  /// The mark on every line.
  final IconData icon;

  /// The facts, in the order the spec states them.
  final List<String> items;

  /// Status-family tint for the icon; never the only carrier of meaning.
  final Color? tint;

  /// A quieter closing line under the list.
  final String? footnote;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final status = RkStatusColors.of(context);
    final mark = tint ?? status.muted;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(header: true, child: Text(heading, style: text.titleLarge)),
        const SizedBox(height: RkSpace.s2),
        for (final line in items)
          Padding(
            padding: const EdgeInsets.only(bottom: RkSpace.s2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Icon(icon, size: 18, color: mark),
                ),
                const SizedBox(width: RkSpace.s2),
                Expanded(child: Text(line, style: text.bodyMedium)),
              ],
            ),
          ),
        if (footnote != null)
          Padding(
            padding: const EdgeInsets.only(top: RkSpace.s1),
            child: Text(
              footnote!,
              style: text.bodySmall?.copyWith(color: status.muted),
            ),
          ),
      ],
    );
  }
}

/// Script tag of a user-typed [name] — `pa` for Gurmukhi, `hi` for
/// Devanagari, `en` otherwise (01 §1 rule 9 🔒). Deliberately crude: it
/// decides a font and a screen-reader voice, not a meaning.
String accountScriptOf(String name) {
  for (final unit in name.runes) {
    if (unit >= 0x0A00 && unit <= 0x0A7F) return 'pa';
    if (unit >= 0x0900 && unit <= 0x097F) return 'hi';
  }
  return 'en';
}
