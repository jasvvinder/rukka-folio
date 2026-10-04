// The S0.3 demo card (owner-directed, 4 Oct 2026) — DEBUG ONLY; the route
// mounts it only through `demoPurposeCard`, which answers null unless
// `demo_gate.dart` is open.
//
// A small state machine of its own: idle → building (determinate: book n of
// m) → done (what was made, what was not, and why) → Continue; or → error →
// Try again. A person who owns none of their books (only member / operator /
// viewer, or a partner with a share and no role) gets a fourth, inert state:
// the shared books are named, nothing is offered to build, and the four
// purpose cards beneath are the way on. Every state has a way on (07 §1 rule 6): the four real purpose
// cards stay beneath it throughout, and Continue carries on exactly where a
// purpose choice would — to S0.4 name, then PIN.
//
// Marked as debug with an icon AND a word, never a colour alone (07 §1 rule 3).
import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/ledger/ledger_scope.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';
import '../demo_builder.dart';
import '../demo_gate.dart';
import '../demo_roster.dart';

/// The demo card for the phone that signed in during this launch, or null —
/// null in a release build, with the demo switch off, or for a phone that is
/// not on the roster, or for a roster person the roster names no book for.
/// [onContinue] is called with the person's name.
Widget? demoPurposeCard({required void Function(String name) onContinue}) {
  final match = demoPersonFor(signedInPhone: demoSignedInPhone.value);
  if (match == null || !demoNamesAnyBook(match.$1, match.$2)) return null;
  return DemoBuildCard(
    person: match.$1,
    demoCase: match.$2,
    onContinue: onContinue,
  );
}

/// Builds [person]'s books on tap, then shows what it made.
class DemoBuildCard extends StatefulWidget {
  const DemoBuildCard({
    super.key,
    required this.person,
    required this.demoCase,
    required this.onContinue,
  });

  final DemoPerson person;
  final DemoCase demoCase;
  final void Function(String name) onContinue;

  @override
  State<DemoBuildCard> createState() => _DemoBuildCardState();
}

/// Results by person key, for this launch: coming back to S0.3 shows the
/// summary again instead of offering a second build.
final Map<String, DemoBuildResult> _results = {};

class _DemoBuildCardState extends State<DemoBuildCard> {
  bool _building = false;
  int _done = 0;
  int _total = 0;
  bool _failed = false;

  DemoBuildResult? get _result => _results[widget.person.key];

  Future<void> _build() async {
    if (_building) return;
    final l10n = AppLocalizations.of(context);
    final ledger = LedgerScope.of(context);
    final words = DemoWords.of(l10n);
    final plan = planDemoBooks(widget.person, widget.demoCase, words);
    setState(() {
      _building = true;
      _failed = false;
      _done = 0;
      _total = plan.toBuild.length;
    });
    try {
      final result = await buildDemoBooks(
        ledger,
        plan,
        words: words,
        onProgress: (done, total) {
          if (mounted) setState(() => _done = done);
        },
      );
      _results[widget.person.key] = result;
      if (mounted) setState(() => _building = false);
    } on Object {
      // Nothing is logged: the roster carries real names (CLAUDE.md rule 4).
      if (mounted) {
        setState(() {
          _building = false;
          _failed = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final status = RkStatusColors.of(context);
    final result = _result;
    final name = widget.person.name;
    final plan = planDemoBooks(
      widget.person,
      widget.demoCase,
      DemoWords.of(l10n),
    );
    final nothing = result == null && plan.nothingToBuild;
    final idle = result == null && !_building && !_failed && !nothing;

    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.science_outlined, size: RkIcon.grid),
            const SizedBox(width: RkSpace.s2),
            Flexible(
              child: Text(
                l10n.demoCardBadge,
                style: text.labelMedium?.copyWith(color: status.muted),
              ),
            ),
          ],
        ),
        const SizedBox(height: RkSpace.s2),
        Text(
          nothing ? l10n.demoCardNoneTitle(name) : l10n.demoCardTitle(name),
          style: text.titleMedium,
        ),
        const SizedBox(height: RkSpace.s1),
        Text(
          nothing ? l10n.demoCardNoneBody(name) : l10n.demoCardBody(name),
          style: text.bodySmall?.copyWith(color: status.muted),
        ),
      ],
    );

    final body = <Widget>[
      header,
      if (_building) ...[
        const SizedBox(height: RkSpace.s3),
        LinearProgressIndicator(
          value: _total == 0 ? null : _done / _total,
          color: status.loaderSegment,
          backgroundColor: status.loaderTrack,
        ),
        const SizedBox(height: RkSpace.s2),
        Text(
          l10n.demoCardBuilding(_done < _total ? _done + 1 : _total, _total),
          style: text.bodyMedium,
        ),
      ],
      if (_failed) ...[
        const SizedBox(height: RkSpace.s3),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.error_outline,
              size: RkIcon.grid,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(width: RkSpace.s2),
            Expanded(child: Text(l10n.demoCardError, style: text.bodyMedium)),
          ],
        ),
        const SizedBox(height: RkSpace.s2),
        OutlinedButton(onPressed: _build, child: Text(l10n.demoCardRetry)),
      ],
      if (nothing) ..._shared(context, plan.sharedOnly),
      if (result != null) ..._summary(context, result),
    ];

    final card = Container(
      constraints: const BoxConstraints(minHeight: RkSpace.rowMinHeight),
      padding: const EdgeInsets.all(RkSpace.s4),
      decoration: BoxDecoration(
        border: Border.all(color: status.hairline),
        borderRadius: BorderRadius.circular(RkRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: body,
      ),
    );

    if (!idle) return card;
    return Semantics(
      button: true,
      label:
          '${l10n.demoCardBadge}. ${l10n.demoCardTitle(name)}. '
          '${l10n.demoCardBody(name)}',
      excludeSemantics: true,
      child: InkWell(
        onTap: _build,
        borderRadius: BorderRadius.circular(RkRadius.md),
        child: card,
      ),
    );
  }

  Widget _row(TextTheme text, IconData icon, String label) => Padding(
    padding: const EdgeInsets.only(top: RkSpace.s2),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: RkIcon.grid),
        const SizedBox(width: RkSpace.s2),
        Expanded(child: Text(label, style: text.bodyMedium)),
      ],
    ),
  );

  /// The books shared with the person and why they are not made here; empty
  /// when there are none.
  List<Widget> _shared(BuildContext context, List<String> names) {
    if (names.isEmpty) return const [];
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final status = RkStatusColors.of(context);
    return [
      const SizedBox(height: RkSpace.s4),
      Text(l10n.demoCardSharedHeading, style: text.titleSmall),
      for (final n in names) _row(text, Icons.people_outline, n),
      const SizedBox(height: RkSpace.s1),
      Text(
        l10n.demoCardSharedNote,
        style: text.bodySmall?.copyWith(color: status.muted),
      ),
    ];
  }

  List<Widget> _summary(BuildContext context, DemoBuildResult result) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final status = RkStatusColors.of(context);
    return [
      // Never a heading over an empty list (review finding DEMO1-4).
      if (result.built.isNotEmpty || result.alreadyHere.isNotEmpty) ...[
        const SizedBox(height: RkSpace.s4),
        Text(l10n.demoCardBuiltHeading, style: text.titleSmall),
        for (final b in result.built)
          _row(text, Icons.check_circle_outline, b.name),
        for (final n in result.alreadyHere)
          _row(text, Icons.check_circle_outline, l10n.demoCardAlready(n)),
      ],
      ..._shared(context, result.sharedOnly),
      const SizedBox(height: RkSpace.s3),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.cloud_off_outlined, size: RkIcon.grid),
          const SizedBox(width: RkSpace.s2),
          Expanded(
            child: Text(
              l10n.demoCardSyncNote,
              style: text.bodySmall?.copyWith(color: status.muted),
            ),
          ),
        ],
      ),
      const SizedBox(height: RkSpace.s4),
      FilledButton(
        onPressed: () => widget.onContinue(widget.person.name),
        child: Text(l10n.demoCardContinue),
      ),
    ];
  }
}
