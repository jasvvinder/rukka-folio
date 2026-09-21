// S18.4 Open-source licences (13 §3.2 row S18.4) — a document page through
// the shared template's language (ADR 2026-09-02), but the only S18 document
// whose content is *not* the owner's prose: it is the bundle's own licence
// registry, so the page can be true today.
//
// Every state of 13 §4.3 ships: loading (the ruled skeleton, never a spinner
// — 11 §4.5), error-with-retry, empty with the one next action, and
// populated. Nothing here reads the network, so there is no offline state to
// draw — the licences are compiled into the app.
//
// Colour never carries a state on its own (07 §1 rule 3): the skeleton is
// announced in words, the error carries an icon and a sentence.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';
import '../../../shared/widgets/rk_fit_text.dart';
import '../../../shared/widgets/rk_states.dart';

/// One package and the licence paragraphs that came with it.
@immutable
class LicenceGroup {
  /// Creates the group.
  const LicenceGroup({required this.package, required this.paragraphs});

  /// Package name, as the registry reports it.
  final String package;

  /// The licence text, paragraph by paragraph.
  final List<String> paragraphs;
}

/// Where the licences come from. Injected so a test can drive every state
/// without depending on what happens to be linked into the test binary.
typedef LicenceSource = Stream<LicenseEntry> Function();

/// S18.4 — Open-source licences.
class LicencesScreen extends StatefulWidget {
  /// Creates the page.
  const LicencesScreen({super.key, this.source, this.onBack});

  /// Defaults to Flutter's own [LicenseRegistry].
  final LicenceSource? source;

  /// The one next action out of the empty state (07 §1 rule 12).
  final VoidCallback? onBack;

  @override
  State<LicencesScreen> createState() => _LicencesScreenState();
}

class _LicencesScreenState extends State<LicencesScreen> {
  List<LicenceGroup>? _groups;
  bool _failed = false;
  int _attempt = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant LicencesScreen old) {
    super.didUpdateWidget(old);
    // A new source means a new document. Without this the page would keep
    // whatever the previous source produced: the element is reused when the
    // widget type is unchanged, so `initState` never runs a second time.
    if (old.source != widget.source) unawaited(_load());
  }

  Future<void> _load() async {
    final attempt = ++_attempt;
    setState(() {
      _groups = null;
      _failed = false;
    });
    final byPackage = <String, List<String>>{};
    try {
      final source = widget.source ?? () => LicenseRegistry.licenses;
      await for (final entry in source()) {
        final text = entry.paragraphs.map((p) => p.text.trim()).toList();
        for (final package in entry.packages) {
          (byPackage[package] ??= <String>[]).addAll(text);
        }
      }
    } on Object {
      if (mounted && attempt == _attempt) setState(() => _failed = true);
      return;
    }
    if (!mounted || attempt != _attempt) return;
    final names = byPackage.keys.toList()..sort();
    setState(() {
      _groups = [
        for (final n in names)
          LicenceGroup(package: n, paragraphs: byPackage[n]!),
      ];
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final groups = _groups;
    return Scaffold(
      appBar: AppBar(title: RkFitText(l10n.legalLicencesTitle)),
      body: SafeArea(
        child: switch ((_failed, groups)) {
          (true, _) => RkErrorState(
            text: l10n.legalLicencesError,
            retryLabel: l10n.legalLicencesRetry,
            onRetry: () => unawaited(_load()),
          ),
          (false, null) => RkSkeleton(label: l10n.legalLicencesLoading),
          (false, final g) when g!.isEmpty => _Empty(onBack: widget.onBack),
          (false, final g) => ListView.builder(
            padding: const EdgeInsets.only(bottom: RkSpace.s10),
            itemCount: g!.length,
            itemBuilder: (context, i) => _LicenceTile(group: g[i]),
          ),
        },
      ),
    );
  }
}

class _LicenceTile extends StatelessWidget {
  const _LicenceTile({required this.group});

  final LicenceGroup group;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final status = RkStatusColors.of(context);
    return ExpansionTile(
      title: RkFitText(group.package, style: text.bodyLarge),
      childrenPadding: const EdgeInsets.fromLTRB(
        RkSpace.gutter,
        0,
        RkSpace.gutter,
        RkSpace.s4,
      ),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final p in group.paragraphs)
          Padding(
            padding: const EdgeInsets.only(bottom: RkSpace.s2),
            child: RkFitText(
              p,
              style: text.bodySmall?.copyWith(color: status.muted),
            ),
          ),
      ],
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.onBack});

  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListView(
      padding: const EdgeInsets.all(RkSpace.s6),
      children: [
        const SizedBox(height: RkSpace.s8),
        RkFitText(l10n.legalLicencesEmpty, textAlign: TextAlign.center),
        const SizedBox(height: RkSpace.s4),
        Center(
          child: FilledButton(
            onPressed: onBack,
            child: RkFitText(l10n.legalLicencesEmptyAction),
          ),
        ),
      ],
    );
  }
}
