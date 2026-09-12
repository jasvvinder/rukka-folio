// S15.1 Privacy cover (13 §3.2 row S15.1, 07 §5.6 🔒).
//
// "The moment the app is backgrounded it covers itself with the mark on a
// plain paper field, so **no balance ever appears in the iOS app switcher**."
// A task-switcher screenshot showing ₹4,81,000 is a real leak, and the cover
// must be in place before the system takes its snapshot — which is why it
// reacts to `inactive`, not only `paused`: iOS captures the switcher image
// during the inactive phase, and Android's recents image is taken on pause.
//
// This is the Flutter half only. The platform capture block — Android
// `FLAG_SECURE` over the whole app and iOS capture/recording detection (07
// §5.6 🔒, ADR 2026-09-05 §4) — is native work and is not in this file.
import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/tokens.dart';
import '../../onboarding/widgets/sealed_mark.dart';

/// Wraps [child] and paints [PrivacyCoverSheet] over it whenever the app is
/// not in the foreground. Mount it once, above the router.
class PrivacyCover extends StatefulWidget {
  const PrivacyCover({super.key, required this.child});

  /// The app.
  final Widget child;

  @override
  State<PrivacyCover> createState() => PrivacyCoverState();
}

/// Public so a host can read the state in a test or drive it directly.
class PrivacyCoverState extends State<PrivacyCover>
    with WidgetsBindingObserver {
  bool _covered = false;

  /// Whether the cover is showing right now.
  bool get covered => _covered;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Conservative by construction: anything that is not `resumed` is covered.
    // A state we do not recognise therefore covers rather than exposes.
    final cover = state != AppLifecycleState.resumed;
    if (cover != _covered) setState(() => _covered = cover);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_covered) const Positioned.fill(child: PrivacyCoverSheet()),
      ],
    );
  }
}

/// The cover itself: the mark on a plain paper field and nothing else — no
/// balance, no name, no book (07 §5.6 🔒).
class PrivacyCoverSheet extends StatelessWidget {
  const PrivacyCoverSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Semantics(
      label: l10n.lockCoverSemantics,
      excludeSemantics: true,
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        child: const Center(child: SealedMark(size: RkSpace.s12 * 2)),
      ),
    );
  }
}
