// S0.6e Who else is in the family? (13 §3.2 row S0.6e, 07 §3.1.1 branch O6e)
// — invite the other heads by phone; **Skip for now** is always visible 🔒.
//
// This is the archetype row 13 §3.2 names for S0.6a1 (ADR 2026-09-09 §1: "…
// reusing the S0.6e row"): a name, a phone number to invite on, and a tag
// showing whether the row is *you* or someone waiting on the in-person
// verification ceremony. Nobody is added by a phone number alone — the
// invitation waits for that ceremony, same as S0.6a1, so the screen says so
// in words.
//
// Unlike S0.6a1 there are **no share weights** here: a family member is not
// a business partner, so nothing is divided. That is the one respect in
// which S0.6a1 specializes this row rather than the reverse, and S0.6a1's own
// file is left untouched by this lane.
import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';

/// One member of the family: a name, the phone the invitation goes to, and
/// whether this is the creating user (already here, no invitation needed).
@immutable
final class FamilyMemberDraft {
  /// Creates a member row.
  const FamilyMemberDraft({
    required this.name,
    this.phone = '',
    this.isYou = false,
  });

  /// Display name.
  final String name;

  /// The number the invitation goes to; empty for [isYou].
  final String phone;

  /// True for the creating user — the first row, tagged *you*.
  final bool isYou;

  /// Copy with fields replaced.
  FamilyMemberDraft copyWith({String? name, String? phone}) =>
      FamilyMemberDraft(
        name: name ?? this.name,
        phone: phone ?? this.phone,
        isYou: isYou,
      );
}

/// S0.6e — invite the other family heads by phone; Skip for now always shown.
class FamilyMembersScreen extends StatefulWidget {
  /// Creates the screen.
  const FamilyMembersScreen({
    super.key,
    required this.yourName,
    this.onSubmit,
    this.onSkip,
    this.initialMembers,
  });

  /// The creating user's name (S0.4) — the first row, tagged *you*.
  final String yourName;

  /// Called with every member, invited rows included, when Continue is
  /// pressed.
  final void Function(List<FamilyMemberDraft> members)? onSubmit;

  /// *Skip for now* — 🔒 always visible on this screen (07 §3.1.1, 13 §3.2).
  final VoidCallback? onSkip;

  /// Pre-fills the rows when the step is resumed (07 §3.1.1).
  final List<FamilyMemberDraft>? initialMembers;

  @override
  State<FamilyMembersScreen> createState() => _FamilyMembersScreenState();
}

class _MemberRow {
  _MemberRow(this.draft)
    : name = TextEditingController(text: draft.name),
      phone = TextEditingController(text: draft.phone);

  FamilyMemberDraft draft;
  final TextEditingController name;
  final TextEditingController phone;

  void dispose() {
    name.dispose();
    phone.dispose();
  }
}

class _FamilyMembersScreenState extends State<FamilyMembersScreen> {
  late final List<_MemberRow> _rows = _initialRows();

  List<_MemberRow> _initialRows() {
    final initial =
        widget.initialMembers ??
        [FamilyMemberDraft(name: widget.yourName, isYou: true)];
    return [for (final m in initial) _MemberRow(m)];
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  /// Every invited row needs a name and a number; the creating user only
  /// needs a name. A row added and left blank blocks Continue — *Skip for
  /// now* is the way past that, not a half-filled row.
  bool get _ready => _rows.every(
    (r) =>
        r.name.text.trim().isNotEmpty &&
        (r.draft.isYou || r.phone.text.trim().isNotEmpty),
  );

  void _addMember() =>
      setState(() => _rows.add(_MemberRow(const FamilyMemberDraft(name: ''))));

  void _remove(_MemberRow row) {
    setState(() {
      _rows.remove(row);
      row.dispose();
    });
  }

  void _submit() {
    if (!_ready) return;
    widget.onSubmit?.call([
      for (final r in _rows)
        r.draft.copyWith(name: r.name.text.trim(), phone: r.phone.text.trim()),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(RkSpace.s6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ListView(
                  children: [
                    Text(
                      l10n.onboardingFamilyMembersTitle,
                      style: text.headlineMedium,
                    ),
                    const SizedBox(height: RkSpace.s2),
                    Text(
                      l10n.onboardingFamilyMembersSubtitle,
                      style: text.bodyLarge,
                    ),
                    const SizedBox(height: RkSpace.s4),
                    _Note(
                      icon: Icons.info_outline,
                      text: l10n.onboardingFamilyMembersUnverifiedNote,
                    ),
                    const SizedBox(height: RkSpace.s4),
                    for (final row in _rows) ...[
                      _MemberCard(
                        row: row,
                        canRemove: !row.draft.isYou,
                        onChanged: () => setState(() {}),
                        onRemove: () => _remove(row),
                      ),
                      const SizedBox(height: RkSpace.s3),
                    ],
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: TextButton.icon(
                        onPressed: _addMember,
                        icon: const Icon(Icons.person_add_alt_outlined),
                        label: Text(l10n.onboardingFamilyMembersAddMember),
                      ),
                    ),
                  ],
                ),
              ),
              FilledButton(
                onPressed: _ready ? _submit : null,
                child: Text(l10n.onboardingFamilyMembersContinueLabel),
              ),
              const SizedBox(height: RkSpace.s2),
              // 🔒 07 §3.1.1 / 13 §3.2: always visible, not conditioned on
              // readiness — never a dead end for a head who wants to invite
              // nobody yet.
              TextButton(
                onPressed: widget.onSkip,
                child: Text(l10n.onboardingFamilyMembersSkip),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MemberCard extends StatelessWidget {
  const _MemberCard({
    required this.row,
    required this.canRemove,
    required this.onChanged,
    required this.onRemove,
  });

  final _MemberRow row;
  final bool canRemove;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final status = RkStatusColors.of(context);
    final draft = row.draft;
    final label = row.name.text.trim().isEmpty
        ? l10n.onboardingFamilyMembersNameLabel
        : row.name.text.trim();
    return Container(
      padding: const EdgeInsets.all(RkSpace.s4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(RkRadius.lg),
        border: Border.all(color: status.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: RkSpace.s2,
            runSpacing: RkSpace.s1,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              // Tag, with an icon beside it — colour never alone (07 §1).
              _Tag(
                icon: draft.isYou
                    ? Icons.person_outline
                    : Icons.schedule_outlined,
                label: draft.isYou
                    ? l10n.onboardingFamilyMembersYouTag
                    : l10n.onboardingFamilyMembersInviteTag,
              ),
              if (canRemove)
                TextButton.icon(
                  onPressed: onRemove,
                  icon: const Icon(Icons.remove_circle_outline),
                  label: Text(l10n.onboardingFamilyMembersRemove(label)),
                ),
            ],
          ),
          const SizedBox(height: RkSpace.s2),
          TextField(
            controller: row.name,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: l10n.onboardingFamilyMembersNameLabel,
            ),
            onChanged: (_) => onChanged(),
          ),
          if (!draft.isYou) ...[
            const SizedBox(height: RkSpace.s2),
            TextField(
              controller: row.phone,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: l10n.onboardingFamilyMembersPhoneLabel,
              ),
              onChanged: (_) => onChanged(),
            ),
          ],
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final status = RkStatusColors.of(context);
    final text = Theme.of(context).textTheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: RkIcon.grid, color: status.muted),
        const SizedBox(width: RkSpace.s1),
        Text(label, style: text.bodySmall?.copyWith(color: status.muted)),
      ],
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final status = RkStatusColors.of(context);
    final style = Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: status.muted);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: RkIcon.grid, color: status.muted),
        const SizedBox(width: RkSpace.s2),
        Expanded(child: Text(text, style: style)),
      ],
    );
  }
}
