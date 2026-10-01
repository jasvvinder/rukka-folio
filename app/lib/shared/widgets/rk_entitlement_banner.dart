// The S12.5 read-only signal, read live for a surface that is not a Save path
// (13 §3.2 row S12.5 scope = `global`; ADR 2026-09-24b §13, §14; ADR
// 2026-09-05g §5 *lapsed ≠ locked*).
//
// Two pieces:
//   * [RkEntryRestrictionBuilder] — asks the **same** public gate every Save
//     path asks (`entryRestrictionFor`, features/entry), so a surface that
//     draws the restriction and a Save that enforces it can never disagree.
//     It re-asks when the [EntitlementScope] above hands down a different
//     source and whenever the app comes back to the foreground: the seam has
//     no change stream (`EntitlementSource.read()` is one-shot), and a resume
//     is when a meta refresh (05 §5) can have changed the reading.
//   * [RkEntitlementBanner] — the shell's global banner: the read-only kind
//     of [RkRestrictionBanner], words and an icon (07 §1 rule 3), and one way
//     forward, *Renew* → S12.1 Plans (07 §1 rule 6).
//
// Rules this file does not restate but inherits from the gate: offline grace
// never reads as read-only (ADR 2026-09-05g §4 🔒), no token is Free and never
// locked (§1 🔒), and a failed read is untokened (ADR 2026-09-24b §14). Until
// the gate has answered, the builder reports **no** restriction — the
// untokened reading, the one the ADRs require of a phone that knows nothing
// yet — so a slow read never flashes a lock over a live tenant.
//
// ⚠️ SPEC: `rk_restriction.dart` says the banner "sits under the app bar";
// the shell cannot reach under each tab's own app bar, and the canvas has not
// drawn the global placement (design-system.md:111, PLAN S12.5 *banner still
// undrawn*). The shell therefore sets it directly above the navigation (tab
// bar or rail), in view on every tab, touching no tab's safe area. Owner item.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/entry/entry_restriction.dart';
import '../../features/subscription/entitlement_source.dart';
import '../../features/subscription/subscription_paths.dart';
import '../theme.dart';
import '../tokens.dart';
import 'rk_banner.dart';
import 'rk_fit_text.dart';
import 'rk_restriction.dart';
import 'rk_restriction_copy.dart';

/// Builds [builder] with the restriction the S12.5 gate reports for
/// [bookIds] — null when entry may go ahead.
///
/// With [bookIds] empty (the default) only the tenant-wide read-only kind can
/// come back: book full is per book (ADR 2026-09-05b §7) and is asked by the
/// paths that know which book they append to.
class RkEntryRestrictionBuilder extends StatefulWidget {
  /// Creates the builder.
  const RkEntryRestrictionBuilder({
    super.key,
    required this.builder,
    this.bookIds = const [],
  });

  /// Draws the surface for the current restriction.
  final Widget Function(BuildContext context, RkRestrictionKind? kind) builder;

  /// The books the surface would append to, if any.
  final List<String> bookIds;

  @override
  State<RkEntryRestrictionBuilder> createState() =>
      _RkEntryRestrictionBuilderState();
}

class _RkEntryRestrictionBuilderState extends State<RkEntryRestrictionBuilder>
    with WidgetsBindingObserver {
  EntitlementSource? _source;
  RkRestrictionKind? _kind;
  int _asked = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Registers the dependency, so a new source above rebuilds us; the gate's
    // own lookup deliberately does not (it is an event-handler read).
    EntitlementScope.maybeOf(context);
    final sources = entryRestrictionSourcesOf(context);
    if (!identical(sources.entitlement, _source)) {
      _source = sources.entitlement;
      _ask();
    }
  }

  @override
  void didUpdateWidget(RkEntryRestrictionBuilder old) {
    super.didUpdateWidget(old);
    if (!_sameBooks(old.bookIds, widget.bookIds)) _ask();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _ask();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _ask() {
    // Captured before the await (the gate's contract), and numbered so an
    // older answer arriving late never overwrites a newer one.
    final sources = entryRestrictionSourcesOf(context);
    final asked = ++_asked;
    unawaited(
      entryRestrictionFor(sources, widget.bookIds).then((kind) {
        if (!mounted || asked != _asked || kind == _kind) return;
        setState(() => _kind = kind);
      }),
    );
  }

  static bool _sameBooks(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _kind);
}

/// The shell's global S12.5 banner: drawn only while the tenant is read-only,
/// nothing at all otherwise.
///
/// Never dismissable (13 §4.2). Its one action opens S12.1 Plans — [onRenew]
/// when given, otherwise [SubscriptionPaths.plans] on the ambient router
/// (13 §3.2 row S12.5 → S12.1; DESIGN-PACK §11 names the button *Renew*).
/// No *Export everything* button: ADR 2026-09-24b §14 omits it until the
/// whole-tenant export route exists, rather than drawing a dead one.
class RkEntitlementBanner extends StatelessWidget {
  /// Creates the banner.
  const RkEntitlementBanner({super.key, this.onRenew, this.maxHeight});

  /// Opens S12.1; null uses the ambient router.
  final VoidCallback? onRenew;

  /// The tallest the banner may be before its words scroll inside it (the
  /// action stays pinned in view); null is
  /// unbounded. The shell passes [maxShare] of its content height.
  final double? maxHeight;

  /// The most of the shell's height the banner may take — a layout ratio,
  /// not a design token: the tab under it always keeps the larger share.
  static const maxShare = 0.4;

  void _renew(BuildContext context) {
    final onRenew = this.onRenew;
    if (onRenew != null) return onRenew();
    final router = GoRouter.maybeOf(context);
    if (router != null) unawaited(router.push<void>(SubscriptionPaths.plans));
  }

  @override
  Widget build(BuildContext context) => RkEntryRestrictionBuilder(
    builder: (context, kind) {
      if (kind != RkRestrictionKind.readOnly) return const SizedBox.shrink();
      final copy = kind!.copy(context);
      final maxHeight = this.maxHeight;
      if (maxHeight == null || !maxHeight.isFinite) {
        // Beside the rail nothing below the content consumes the bottom
        // inset (under the tab bar, the Scaffold already has), so the banner
        // keeps its words above the home indicator itself. Only while drawn:
        // an empty inset under every tab would be a blank strip for nothing.
        return SafeArea(
          top: false,
          left: false,
          right: false,
          child: RkRestrictionBanner(
            kind: kind,
            copy: copy,
            onAction: () => _renew(context),
          ),
        );
      }
      // At 200 % on a 375×667 phone the full banner (fact, what still works,
      // *Renew*) plus the tab bar is taller than the screen in PA and HI —
      // measured 94 px over (F1-24b-10). A banner may never take the tab
      // away from the person reading it (lapsed ≠ locked, ADR 2026-09-05g
      // §5), so past [maxHeight] its **words** scroll inside it, behind a
      // scrollbar that is always drawn while there is more to read — and its
      // one way forward is pinned below them, never scrolled away (07 §1
      // rule 6; 13 §8: 200 % on 375×667 and 360×800). The cap shrinks with
      // the keyboard (it is a share of the shell's height), which is exactly
      // when a scrolled-away *Renew* would be easiest to lose (F1-24b-13).
      return ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: _CappedBanner(
          kind: kind,
          copy: copy,
          onRenew: () => _renew(context),
        ),
      );
    },
  );
}

/// The capped form: the atom's words in a scroll viewport, the action pinned.
///
/// ⚠️ SPEC: the banner atom (`rk_banner.dart`, not this file's lane) has no
/// slot for actions outside its body, so the pinned strip draws the atom's
/// own ground, left rule and text inset here, from the same tokens. Read-only
/// is the `info` tone (`rk_restriction.dart`'s mapping). If the atom grows a
/// pinned-actions slot, this strip folds into it. Owner / design item.
class _CappedBanner extends StatefulWidget {
  const _CappedBanner({
    required this.kind,
    required this.copy,
    required this.onRenew,
  });

  final RkRestrictionKind kind;
  final RkRestrictionCopy copy;
  final VoidCallback onRenew;

  @override
  State<_CappedBanner> createState() => _CappedBannerState();
}

class _CappedBannerState extends State<_CappedBanner> {
  // Its own controller: a tab's primary scroll controller (status-bar tap,
  // scroll-to-top) must never be captured by the banner.
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final status = RkStatusColors.of(context);
    final label = widget.copy.bannerActionLabel;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Flexible(
          child: Scrollbar(
            controller: _scroll,
            thumbVisibility: true,
            child: SingleChildScrollView(
              controller: _scroll,
              primary: false,
              // No action inside: it is pinned below.
              child: RkRestrictionBanner(kind: widget.kind, copy: widget.copy),
            ),
          ),
        ),
        if (label != null)
          Material(
            color: status.sunk,
            child: Container(
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(
                    color: RkBannerTone.info.tint(status),
                    width: RkRadius.ruleLeftWidth,
                  ),
                  bottom: BorderSide(color: status.hairline),
                ),
              ),
              // Aligned with the atom's words: card padding, icon, gap.
              padding: const EdgeInsetsDirectional.only(
                start: RkSpace.cardPadding + RkIcon.grid + RkSpace.s3,
                end: RkSpace.cardPadding,
                top: RkSpace.s1,
                bottom: RkSpace.s2,
              ),
              alignment: AlignmentDirectional.centerStart,
              // Beside the rail nothing below the content consumes the
              // bottom inset (under the tab bar the Scaffold already has),
              // so the strip keeps *Renew* above the home indicator itself.
              child: SafeArea(
                top: false,
                left: false,
                right: false,
                child: TextButton(
                  onPressed: widget.onRenew,
                  child: RkFitText(label),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
