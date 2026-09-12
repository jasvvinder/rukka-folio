// S12.5 — the read-only / book-full pattern, as one shared pair (13 §4.2: the
// **banner** atom is persistent and is shared by *suspended, read-only, book
// full*; 13 §3.2 row S12.5 scope = `global`).
//
// Two surfaces, one vocabulary:
//   * [RkRestrictionBanner] — persistent, never dismissable, states the fact
//     and offers the path (07 §1 rule 6, no dead ends).
//   * [RkBlockedEntrySheet] — what Save raises: what is blocked, what still
//     works, the route to S12.1 Plans, and a dismiss that returns to a
//     **still-filled** screen. The sheet is a modal route over the caller; it
//     never touches the caller's draft (07 §5 final paragraph 🔒, ADR
//     2026-09-05f §B: *drafts preserved*).
//
// **Export is never blocked by either surface** (ADR 2026-09-05g §3: "Reads,
// pulls, statements and exports are never blocked by a quota"; §5: expiry →
// read-only + *full export forever*). Both surfaces therefore carry an
// always-enabled export action.
//
// Everything is injected. There is **no entitlement or quota source in the app
// yet** — the signal lands with sync (ADR 2026-09-05b §7) — so nothing here
// reads state, a clock or a network: the caller passes the kind and the copy.
//
// Colour is never alone (07 §1 rule 3): every variant pairs its tint with an
// icon *and* the word. Tints come from tokens only.
import 'package:flutter/material.dart';

import '../theme.dart';
import '../tokens.dart';

/// Which restriction the surfaces are narrating.
///
/// 13 §5 insists on **two graces, two copies** (ADR 2026-09-05g §4): dunning →
/// read-only is *tenant-wide and server-declared*, while offline grace is
/// *device-local* and must never say the plan lapsed before the server has
/// said so. They are separate members here so no caller can accidentally show
/// the lapse words to a phone that has merely been off-network.
///
/// `suspended` (S15.4) shares this banner atom in 13 §4.2 but its copy is
/// owned by the devices/security surface (07 §15) and is not minted here.
enum RkRestrictionKind {
  /// Tenant-wide, server-declared: the plan lapsed (or dunning grace ran out).
  /// Reading and exports keep working; new entries are blocked.
  readOnly,

  /// Device-local: this phone has not reached the server since the last
  /// entitlement token. **Nothing is blocked and nothing has lapsed** — the
  /// banner asks for one connection (07 §20 🔒: *"Connect once to keep
  /// entering"*).
  offlineGrace,

  /// `rejected:quota` — the book hit its plan limit. Posting only is blocked;
  /// the draft is preserved and reads/exports keep working (ADR 2026-09-05b
  /// §7, ADR 2026-09-05f §B).
  bookFull;

  /// Whether this kind blocks posting a new entry.
  ///
  /// Offline grace does not: read-only engages only after the device has
  /// reached the server **and been told lapsed** (ADR 2026-09-05g §4).
  bool get blocksEntry => this != RkRestrictionKind.offlineGrace;

  /// Export is never blocked — by any kind, ever. Present as a getter so a
  /// call site reads the rule rather than restating it.
  bool get blocksExport => false;
}

/// The strings the two surfaces render, injected by the caller so this file
/// stays free of the l10n class (same rule as `RkTabBar`). Build one with
/// `RkRestrictionCopy.of(context, kind)` from `rk_restriction_copy.dart`.
@immutable
class RkRestrictionCopy {
  /// Creates a copy set. [sheetTitle]/[sheetBlocked]/[sheetStillWorks] are
  /// required only for kinds that block entry, but are always supplied by the
  /// l10n mapping so a caller cannot half-fill the sheet.
  const RkRestrictionCopy({
    required this.bannerTitle,
    required this.bannerBody,
    required this.bannerActionLabel,
    required this.sheetTitle,
    required this.sheetBlocked,
    required this.sheetStillWorks,
    required this.sheetActionLabel,
    required this.sheetDismissLabel,
    required this.exportLabel,
  });

  /// Banner headline — the fact, in one line.
  final String bannerTitle;

  /// Banner body — why, and what still works.
  final String bannerBody;

  /// Banner's one way forward (07 §1 rule 6).
  final String bannerActionLabel;

  /// Sheet headline.
  final String sheetTitle;

  /// What exactly is blocked.
  final String sheetBlocked;

  /// What keeps working — reading and exports, always.
  final String sheetStillWorks;

  /// Sheet's primary action; for read-only and book full this is S12.1 Plans.
  final String sheetActionLabel;

  /// Dismiss — returns to the screen, draft intact.
  final String sheetDismissLabel;

  /// Export, on both surfaces, always enabled.
  final String exportLabel;
}

/// Tint + icon per kind. Colour never alone: the icon travels with the tint,
/// and the words carry the meaning on their own.
///
/// Tints come from the status family landed at the 12 Sep token session
/// (design-system §3.1; every value contrast-checked on all four grounds in
/// both modes). The family is near-iso-luminant, so the icon is not a
/// decoration — it is the signal that survives grayscale (07 §18).
///
/// `readOnly` is `info`, not `danger`: a lapsed plan is a state, not a
/// security event, and 13 §5 forbids alarming copy before the server has
/// spoken. `bookFull` is `warning` — the user can act on it. `offlineGrace`
/// is `info` at lower weight: nothing is blocked and nothing has lapsed.
({Color tint, IconData icon}) _look(RkRestrictionKind kind, RkStatusColors s) =>
    switch (kind) {
      RkRestrictionKind.readOnly => (tint: s.info, icon: Icons.lock_outline),
      RkRestrictionKind.offlineGrace => (
        tint: s.info,
        icon: Icons.cloud_off_outlined,
      ),
      RkRestrictionKind.bookFull => (
        tint: s.warning,
        icon: Icons.inventory_2_outlined,
      ),
    };

/// The persistent banner (13 §4.2). Sits under the app bar, is never
/// dismissable, and is announced as a live region.
class RkRestrictionBanner extends StatelessWidget {
  /// Creates the banner. [onAction] is the way forward — S12.1 Plans for
  /// read-only and book full, a retry for offline grace. [onExport] is
  /// optional and, when given, is **always enabled**.
  const RkRestrictionBanner({
    super.key,
    required this.kind,
    required this.copy,
    required this.onAction,
    this.onExport,
  });

  /// Which restriction is being narrated.
  final RkRestrictionKind kind;

  /// The strings.
  final RkRestrictionCopy copy;

  /// The one way forward.
  final VoidCallback onAction;

  /// Export — never blocked; omitted where the surface has no export.
  final VoidCallback? onExport;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final status = RkStatusColors.of(context);
    final look = _look(kind, status);
    final text = Theme.of(context).textTheme;
    return Semantics(
      container: true,
      liveRegion: true,
      label: '${copy.bannerTitle}. ${copy.bannerBody}',
      child: Material(
        color: status.sunk,
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              // The 3px left rule of the brand's card language (brand §4.1).
              left: BorderSide(color: look.tint, width: RkRadius.ruleLeftWidth),
              bottom: BorderSide(color: status.hairline),
            ),
          ),
          padding: const EdgeInsets.all(RkSpace.cardPadding),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(look.icon, color: look.tint, size: RkIcon.grid),
              const SizedBox(width: RkSpace.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      copy.bannerTitle,
                      style: text.titleSmall?.copyWith(color: scheme.onSurface),
                    ),
                    const SizedBox(height: RkSpace.s1),
                    Text(
                      copy.bannerBody,
                      style: text.bodySmall?.copyWith(color: status.muted),
                    ),
                    const SizedBox(height: RkSpace.s2),
                    // Wrap, not Row: at 200 % text scale on 360 px the two
                    // actions stack instead of overflowing (07 §18).
                    Wrap(
                      spacing: RkSpace.s4,
                      runSpacing: RkSpace.s1,
                      children: [
                        TextButton(
                          onPressed: onAction,
                          child: Text(copy.bannerActionLabel),
                        ),
                        if (onExport != null)
                          TextButton(
                            onPressed: onExport,
                            child: Text(copy.exportLabel),
                          ),
                      ],
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

/// What the caller learned from the sheet.
enum RkBlockedEntryOutcome {
  /// The user chose the way forward (S12.1 Plans).
  action,

  /// The user came back to the screen. The draft was never touched.
  dismissed,
}

/// The blocked-entry sheet: raised by Save when the kind blocks entry.
///
/// It states what is blocked, states what still works, offers S12.1, and
/// dismisses back to a still-filled screen — this widget holds no draft and
/// mutates nothing of the caller's, which is how the 🔒 "draft preserved" line
/// is honoured (07 §5 final paragraph).
class RkBlockedEntrySheet extends StatelessWidget {
  /// Creates the sheet body. Prefer [showRkBlockedEntrySheet].
  const RkBlockedEntrySheet({
    super.key,
    required this.kind,
    required this.copy,
    required this.onAction,
    required this.onDismiss,
    this.onExport,
  });

  /// Which restriction blocked the save.
  final RkRestrictionKind kind;

  /// The strings.
  final RkRestrictionCopy copy;

  /// Route to S12.1 Plans.
  final VoidCallback onAction;

  /// Back to the screen, draft intact.
  final VoidCallback onDismiss;

  /// Export — always enabled when offered.
  final VoidCallback? onExport;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final status = RkStatusColors.of(context);
    final look = _look(kind, status);
    final text = Theme.of(context).textTheme;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(RkSpace.cardPadding),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(look.icon, color: look.tint, size: RkIcon.grid),
                const SizedBox(width: RkSpace.s3),
                Expanded(
                  child: Text(
                    copy.sheetTitle,
                    style: text.titleMedium?.copyWith(color: scheme.onSurface),
                  ),
                ),
              ],
            ),
            const SizedBox(height: RkSpace.s3),
            Text(
              copy.sheetBlocked,
              style: text.bodyMedium?.copyWith(color: scheme.onSurface),
            ),
            const SizedBox(height: RkSpace.s2),
            Text(
              copy.sheetStillWorks,
              style: text.bodySmall?.copyWith(color: status.muted),
            ),
            const SizedBox(height: RkSpace.s4),
            // Column, not Row: two full-width actions survive 200 % scale on
            // 360 px without truncation (07 §18).
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: onAction,
                child: Text(copy.sheetActionLabel),
              ),
            ),
            if (onExport != null) ...[
              const SizedBox(height: RkSpace.s2),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: onExport,
                  child: Text(copy.exportLabel),
                ),
              ),
            ],
            const SizedBox(height: RkSpace.s2),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: onDismiss,
                child: Text(copy.sheetDismissLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shows [RkBlockedEntrySheet] as a bottom sheet over the current screen and
/// resolves to what the user chose.
///
/// The caller's screen stays mounted underneath with its draft untouched: this
/// function returns an outcome and never a command to clear anything. Both the
/// dismiss button and a barrier tap resolve to
/// [RkBlockedEntryOutcome.dismissed].
Future<RkBlockedEntryOutcome> showRkBlockedEntrySheet(
  BuildContext context, {
  required RkRestrictionKind kind,
  required RkRestrictionCopy copy,
  VoidCallback? onExport,
}) async {
  final chosen = await showModalBottomSheet<RkBlockedEntryOutcome>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => SingleChildScrollView(
      child: RkBlockedEntrySheet(
        kind: kind,
        copy: copy,
        onAction: () =>
            Navigator.of(sheetContext).pop(RkBlockedEntryOutcome.action),
        onDismiss: () =>
            Navigator.of(sheetContext).pop(RkBlockedEntryOutcome.dismissed),
        onExport: onExport,
      ),
    ),
  );
  return chosen ?? RkBlockedEntryOutcome.dismissed;
}
