// S11.1 Guardian setup — the mutual-ceremony screen behind the S11 *Trusted
// members* row (13 §3.2, 07 §15, 04 §7.3 🔒, DESIGN-PACK canvas 2b R3.2).
//
// What it does: choose people from the book's members, show where the mutual
// ceremony stands with each (04 §6, both directions), and record the set.
// Default 2-of-3; n = 2..5 with k = ⌈(n+1)/2⌉ — stated as a **sentence**
// ("Any 2 of the 3 you choose can help you get back in"), never as a formula.
//
// 🔒 Two rules this screen exists to keep:
//
//   1. **2-of-2 only behind a typed confirmation** (ADR 2026-09-06 checklist 4
//      🔒). The panel below is an inline, permanent part of the page: there is
//      no dialog, no dismiss button and no "I understand" — the only thing
//      that enables Save at n = 2 is the typed phrase, and clearing it
//      disables Save again. A warning you can wave away would be exactly the
//      shape the ADR forbids.
//   2. **No key material is rendered.** No share, no QR, no Base32 group — the
//      S0.5b precedent for the 04 §7.4 / 07 §5.6 reason. The screen cannot
//      render one even by mistake, because `shared/seams/guardians.dart`
//      carries no bytes to render; the split, seal and upload happen behind
//      [GuardiansRepository.save].
//
// The ceremony itself is `features/ceremony` (S9.2/S9.3/S9.4) and is consumed
// read-only: this screen raises [GuardianSetupScreen.onMeet] and the route
// pushes S9.3 for that member's invite. Nothing here verifies anything.
//
// States (13 §4.3): loading (ruled skeleton) · populated · empty with its one
// next action · error-with-retry · offline (a line, never a block) · read-only
// (the S12.5 pattern) · every control disabled **with its reason**.
import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/app_scope.dart';
import '../../../shared/seams/guardians.dart';
import '../../../shared/seams/sync_client.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';
import '../../../shared/widgets/rk_states.dart';

/// S11.1.
class GuardianSetupScreen extends StatefulWidget {
  /// Creates the screen. [repository] overrides the [GuardiansScope] one.
  const GuardianSetupScreen({
    super.key,
    this.repository,
    this.onMeet,
    this.onAddMember,
    this.onDone,
  });

  /// The seam, when not handed down by a [GuardiansScope].
  final GuardiansRepository? repository;

  /// Opens the mutual ceremony (S9.3) for this member. Null → the action is
  /// disabled with its reason, never silently absent.
  final void Function(TrustedMemberCandidate candidate)? onMeet;

  /// The one next action of the empty state — S9 Members.
  final VoidCallback? onAddMember;

  /// Called once the set is saved, so the caller can leave.
  final VoidCallback? onDone;

  @override
  State<GuardianSetupScreen> createState() => _GuardianSetupScreenState();
}

class _GuardianSetupScreenState extends State<GuardianSetupScreen> {
  static final _fallback = FakeGuardians(initial: const GuardianSetup());

  final _phrase = TextEditingController();
  List<String>? _chosen;
  bool _loading = false;
  bool _loadError = false;
  bool _saveError = false;
  bool _saved = false;

  GuardiansRepository get _repo =>
      widget.repository ?? GuardiansScope.maybeOf(context) ?? _fallback;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _repo.current == null) _refresh();
    });
  }

  @override
  void dispose() {
    _phrase.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _loadError = false;
    });
    try {
      await _repo.refresh();
    } on Exception {
      if (mounted) setState(() => _loadError = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toggle(GuardianSetup s, String id) {
    if (s.readOnly) return;
    final chosen = [...(_chosen ?? s.chosenIds)];
    if (chosen.remove(id)) {
      setState(() {
        _chosen = chosen;
        _saved = false;
      });
      return;
    }
    // The upper bound of 04 §7.3 is enforced here rather than announced after
    // the fact: a sixth tap does nothing and the max line is already on screen.
    if (chosen.length >= guardianMaxCount) return;
    setState(() {
      _chosen = [...chosen, id];
      _saved = false;
    });
  }

  Future<void> _save(List<String> chosen) async {
    setState(() {
      _saveError = false;
      _saved = false;
    });
    try {
      await _repo.save(chosen);
      if (mounted) {
        setState(() => _saved = true);
        widget.onDone?.call();
      }
    } on Exception {
      if (mounted) setState(() => _saveError = true);
    }
  }

  /// Why Save is off, or null when it is on. Never returns null for a reason
  /// the user cannot see (13 §4.3 disabled-with-reason).
  ///
  /// Read-only is not one of the reasons: the S12.5 note already carries it at
  /// the top of the page, and printing the same sentence twice reads as two
  /// different problems.
  String? _blockedReason(
    AppLocalizations l10n,
    GuardianSetup s,
    List<String> chosen,
  ) {
    if (chosen.length < guardianMinCount) return l10n.guardiansSaveBlockedFew;
    final byId = {for (final c in s.candidates) c.memberId: c};
    final unmet = chosen.any(
      (id) => byId[id]?.ceremony != GuardianCeremony.done,
    );
    if (unmet) return l10n.guardiansSaveBlockedMeet;
    if (guardianNeedsTypedConfirmation(chosen.length) &&
        _phrase.text.trim().toLowerCase() !=
            l10n.guardiansTwoPhrase.trim().toLowerCase()) {
      // 🔒 ADR 2026-09-06 checklist 4: the phrase, and only the phrase.
      //
      // ⚠️ SPEC: the ADR says "a typed confirmation" and names no words, so
      // the phrase itself is this lane's copy — short, plain, and localised
      // per language (`guardians.two.phrase`) rather than a Latin word a
      // Gurmukhi or Devanagari keyboard makes hard to type. The comparison is
      // trimmed and case-insensitive so a capital letter is not a puzzle; it
      // is never fuzzy, because "close enough" would be the dismissible
      // warning the ADR forbids, wearing a text field. Reported to the owner:
      // the words want native review with the rest of the PA/HI copy.
      return l10n.guardiansTwoPrompt(l10n.guardiansTwoPhrase);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.guardiansTitle)),
      body: SafeArea(
        child: StreamBuilder<GuardianSetup>(
          stream: _repo.watch(),
          initialData: _repo.current,
          builder: (context, snap) {
            if (_loadError) {
              return RkErrorState(
                text: l10n.guardiansError,
                retryLabel: l10n.guardiansRetry,
                onRetry: _refresh,
              );
            }
            final s = snap.data;
            if (s == null || _loading) {
              return RkSkeleton(label: l10n.guardiansLoading);
            }
            if (s.candidates.isEmpty) {
              return _Empty(onAddMember: widget.onAddMember);
            }
            return _Body(
              setup: s,
              chosen: _chosen ?? s.chosenIds,
              phrase: _phrase,
              saved: _saved,
              saveError: _saveError,
              onToggle: (id) => _toggle(s, id),
              onMeet: widget.onMeet,
              onPhraseChanged: () => setState(() {}),
            );
          },
        ),
      ),
      bottomNavigationBar: StreamBuilder<GuardianSetup>(
        stream: _repo.watch(),
        initialData: _repo.current,
        builder: (context, snap) {
          final s = snap.data;
          if (s == null || _loadError || s.candidates.isEmpty) {
            return const SizedBox.shrink();
          }
          final chosen = _chosen ?? s.chosenIds;
          final reason = s.readOnly ? null : _blockedReason(l10n, s, chosen);
          return _Footer(
            reason: reason,
            label: l10n.guardiansSave,
            onSave: s.readOnly || reason != null ? null : () => _save(chosen),
          );
        },
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.setup,
    required this.chosen,
    required this.phrase,
    required this.saved,
    required this.saveError,
    required this.onToggle,
    required this.onMeet,
    required this.onPhraseChanged,
  });

  final GuardianSetup setup;
  final List<String> chosen;
  final TextEditingController phrase;
  final bool saved;
  final bool saveError;
  final void Function(String memberId) onToggle;
  final void Function(TrustedMemberCandidate)? onMeet;
  final VoidCallback onPhraseChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final status = RkStatusColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    final sync = RkScope.of(context).sync;
    final n = chosen.length;
    return StreamBuilder<SyncStatus>(
      stream: sync.status,
      initialData: sync.current,
      builder: (context, ss) {
        final offline = ss.data is Offline;
        return ListView(
          padding: const EdgeInsets.all(RkSpace.gutter),
          children: [
            Text(l10n.guardiansIntro, style: text.bodyLarge),
            const SizedBox(height: RkSpace.s3),
            _Note(icon: Icons.lock_outline, text: l10n.guardiansNokey),
            if (setup.isConfigured) ...[
              const SizedBox(height: RkSpace.s2),
              _Note(
                icon: Icons.verified_user_outlined,
                text: l10n.guardiansCurrent(
                  guardianThreshold(setup.chosenIds.length),
                  setup.chosenIds.length,
                ),
              ),
            ],
            if (setup.readOnly) ...[
              const SizedBox(height: RkSpace.s2),
              _Note(
                icon: Icons.visibility_outlined,
                text: l10n.guardiansReadonly,
                color: status.locked,
              ),
            ],
            if (offline) ...[
              const SizedBox(height: RkSpace.s2),
              _Note(icon: Icons.phone_android, text: l10n.guardiansOffline),
            ],
            if (saved) ...[
              const SizedBox(height: RkSpace.s2),
              _Note(
                icon: Icons.check_circle_outline,
                text: l10n.guardiansSaved,
                color: status.success,
              ),
            ],
            if (saveError) ...[
              const SizedBox(height: RkSpace.s2),
              _Note(
                icon: Icons.error_outline,
                text: l10n.guardiansSaveError,
                color: scheme.error,
              ),
            ],
            const SizedBox(height: RkSpace.s4),
            Text(
              n >= guardianMinCount
                  ? l10n.guardiansRule(guardianThreshold(n), n)
                  : l10n.guardiansRulePick,
              style: text.titleMedium,
            ),
            if (n >= guardianMaxCount) ...[
              const SizedBox(height: RkSpace.s1),
              Text(
                l10n.guardiansRuleMax,
                style: text.bodySmall?.copyWith(color: status.muted),
              ),
            ],
            const SizedBox(height: RkSpace.s3),
            for (final c in setup.candidates)
              _MemberRow(
                candidate: c,
                chosen: chosen.contains(c.memberId),
                // A row that cannot be chosen because the set is full still
                // reacts (to un-choose), so no tap is a dead end.
                enabled: !setup.readOnly,
                onToggle: () => onToggle(c.memberId),
                onMeet: c.inviteId == null || onMeet == null
                    ? null
                    : () => onMeet!(c),
              ),
            if (guardianNeedsTypedConfirmation(n)) ...[
              const SizedBox(height: RkSpace.s4),
              _TwoOfTwoPanel(
                controller: phrase,
                enabled: !setup.readOnly,
                onChanged: onPhraseChanged,
              ),
            ],
            const SizedBox(height: RkSpace.s6),
          ],
        );
      },
    );
  }
}

/// One candidate: a checkbox, the name, where the ceremony stands (icon **and**
/// word — colour never alone, 07 §1 rule 3) and the way to finish it.
class _MemberRow extends StatelessWidget {
  const _MemberRow({
    required this.candidate,
    required this.chosen,
    required this.enabled,
    required this.onToggle,
    required this.onMeet,
  });

  final TrustedMemberCandidate candidate;
  final bool chosen;
  final bool enabled;
  final VoidCallback onToggle;
  final VoidCallback? onMeet;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final status = RkStatusColors.of(context);
    final (icon, word, color) = switch (candidate.ceremony) {
      GuardianCeremony.done => (
        Icons.check_circle_outline,
        l10n.guardiansCeremonyDone,
        status.success,
      ),
      GuardianCeremony.started => (
        Icons.hourglass_empty,
        l10n.guardiansCeremonyStarted,
        status.pending,
      ),
      GuardianCeremony.notStarted => (
        Icons.person_outline,
        l10n.guardiansCeremonyNotStarted,
        status.muted,
      ),
    };
    return Semantics(
      checked: chosen,
      label: candidate.name,
      child: InkWell(
        key: Key('guardians.member.${candidate.memberId}'),
        onTap: enabled ? onToggle : null,
        child: Container(
          constraints: const BoxConstraints(minHeight: RkSpace.rowMinHeight),
          padding: const EdgeInsets.symmetric(vertical: RkSpace.s3),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: status.hairline)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ExcludeSemantics(
                child: Checkbox(
                  value: chosen,
                  onChanged: enabled ? (_) => onToggle() : null,
                ),
              ),
              const SizedBox(width: RkSpace.s2),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(candidate.name, style: text.bodyLarge),
                    const SizedBox(height: RkSpace.s1),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          icon,
                          size: RkIcon.grid - RkSpace.s2,
                          color: color,
                        ),
                        const SizedBox(width: RkSpace.s1),
                        Expanded(
                          child: Text(
                            word,
                            style: text.bodySmall?.copyWith(color: color),
                          ),
                        ),
                      ],
                    ),
                    if (candidate.ceremony != GuardianCeremony.done) ...[
                      const SizedBox(height: RkSpace.s1),
                      Text(
                        l10n.guardiansMeetWhy(candidate.name),
                        style: text.bodySmall?.copyWith(color: status.muted),
                      ),
                      const SizedBox(height: RkSpace.s2),
                      OutlinedButton(
                        key: Key('guardians.meet.${candidate.memberId}'),
                        onPressed: enabled ? onMeet : null,
                        child: Text(l10n.guardiansMeet),
                      ),
                      if (onMeet == null) ...[
                        const SizedBox(height: RkSpace.s1),
                        Text(
                          l10n.guardiansMeetUnavailable(candidate.name),
                          style: text.bodySmall?.copyWith(color: status.muted),
                        ),
                      ],
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

/// 🔒 ADR 2026-09-06 checklist 4: 2-of-2 behind a **typed** confirmation.
///
/// Inline and permanent — deliberately not a dialog, a sheet or anything with
/// a dismiss affordance. There is no control in this panel that enables Save.
class _TwoOfTwoPanel extends StatelessWidget {
  const _TwoOfTwoPanel({
    required this.controller,
    required this.enabled,
    required this.onChanged,
  });

  final TextEditingController controller;
  final bool enabled;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final status = RkStatusColors.of(context);
    return Container(
      padding: const EdgeInsets.all(RkSpace.cardPadding),
      decoration: BoxDecoration(
        color: status.sunk,
        borderRadius: BorderRadius.circular(RkRadius.lg),
        border: Border.all(color: status.pending),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.warning_amber_outlined,
                size: RkIcon.grid,
                color: status.pending,
              ),
              const SizedBox(width: RkSpace.s2),
              Expanded(
                child: Text(
                  l10n.guardiansTwoTitle,
                  style: text.titleMedium?.copyWith(color: status.pending),
                ),
              ),
            ],
          ),
          const SizedBox(height: RkSpace.s2),
          Text(l10n.guardiansTwoBody, style: text.bodyMedium),
          const SizedBox(height: RkSpace.s3),
          Text(
            l10n.guardiansTwoPrompt(l10n.guardiansTwoPhrase),
            style: text.bodyMedium,
          ),
          const SizedBox(height: RkSpace.s2),
          TextField(
            key: const Key('guardians.two.field'),
            controller: controller,
            enabled: enabled,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: l10n.guardiansTwoField,
              border: const OutlineInputBorder(),
            ),
            onChanged: (_) => onChanged(),
          ),
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.reason,
    required this.label,
    required this.onSave,
  });

  final String? reason;
  final String label;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final status = RkStatusColors.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(RkSpace.gutter),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (reason != null) ...[
              Text(
                reason!,
                style: text.bodySmall?.copyWith(color: status.muted),
              ),
              const SizedBox(height: RkSpace.s2),
            ],
            FilledButton(
              key: const Key('guardians.save'),
              onPressed: onSave,
              child: Text(label),
            ),
          ],
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.onAddMember});

  final VoidCallback? onAddMember;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.all(RkSpace.gutter),
      children: [
        const SizedBox(height: RkSpace.s8),
        Text(l10n.guardiansEmptyTitle, style: text.titleLarge),
        const SizedBox(height: RkSpace.s2),
        Text(l10n.guardiansEmptyBody, style: text.bodyLarge),
        const SizedBox(height: RkSpace.s4),
        FilledButton(
          onPressed: onAddMember,
          child: Text(l10n.guardiansEmptyAction),
        ),
      ],
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.text, this.color});

  final IconData icon;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;
    final c = color ?? RkStatusColors.of(context).muted;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: RkIcon.grid - RkSpace.s2, color: c),
        const SizedBox(width: RkSpace.s1),
        Expanded(
          child: Text(text, style: style?.copyWith(color: c)),
        ),
      ],
    );
  }
}
