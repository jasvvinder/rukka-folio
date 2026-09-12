// S0.6h Who runs the trust? (13 §3.2 row S0.6h, 07 §3.1.1 branch O6h) —
// invite the committee by phone, tagged with the role they hold; **Skip for
// now** is always visible 🔒.
//
// This reuses the archetype 13 §3.2 names for S0.6a1 and, before that, for
// S0.6e (ADR 2026-09-09 §1: "… reusing the S0.6e row"): a name, a phone
// number to invite on, and a tag showing whether the row is *you* or someone
// waiting on the in-person verification ceremony. Nobody is added by a phone
// number alone — the invitation waits for that ceremony, same as S0.6e, so
// the screen says so in words.
//
// What specializes this row for the trust branch: 07 §3.1.1 names the roles
// explicitly — **Chairman, President, Trustee, Sevadar** — the trustee role
// labels that `tenant.type = organization` turns on (06 §1.0's organization
// column: admin → Chairman, head → President, member → Trustee, operator →
// Sevadar). Each row therefore carries a [TrustRole] alongside its name and
// phone; S0.6e's family row carries no such thing, because a family member
// is not given a committee title at invite time.
//
// As on S0.6e, there are **no share weights** here — a trustee is not a
// business partner, so nothing is divided.
import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';

/// The four committee roles 07 §3.1.1 / 06 §1.0 name for an organization
/// book. A *designation* (06 §1.0) — display only; the capability an admin
/// grants afterwards is a separate thing this screen does not decide.
enum TrustRole {
  /// Runs the book day to day; the admin default (06 §1.0).
  chairman,

  /// The head default (ਪ੍ਰਧਾਨ, 06 §1.0).
  president,

  /// The member default.
  trustee,

  /// The operator default (ਸੇਵਾਦਾਰ, 06 §1.0).
  sevadar,
}

/// One member of the trust committee: a name, the phone the invitation goes
/// to, the role/designation they hold, and whether this is the creating user
/// (already here, no invitation needed).
@immutable
final class TrustMemberDraft {
  /// Creates a member row.
  const TrustMemberDraft({
    required this.name,
    this.phone = '',
    this.isYou = false,
    this.role = TrustRole.chairman,
  });

  /// Display name.
  final String name;

  /// The number the invitation goes to; empty for [isYou].
  final String phone;

  /// True for the creating user — the first row, tagged *you*.
  final bool isYou;

  /// The designation this row is tagged with (06 §1.0).
  final TrustRole role;

  /// Copy with fields replaced.
  TrustMemberDraft copyWith({String? name, String? phone, TrustRole? role}) =>
      TrustMemberDraft(
        name: name ?? this.name,
        phone: phone ?? this.phone,
        isYou: isYou,
        role: role ?? this.role,
      );
}

/// S0.6h — invite the trust's committee by phone, tagged with a role; Skip
/// for now always shown.
class TrustMembersScreen extends StatefulWidget {
  /// Creates the screen.
  const TrustMembersScreen({
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
  final void Function(List<TrustMemberDraft> members)? onSubmit;

  /// *Skip for now* — 🔒 always visible on this screen (07 §3.1.1, 13 §3.2).
  final VoidCallback? onSkip;

  /// Pre-fills the rows when the step is resumed (07 §3.1.1).
  final List<TrustMemberDraft>? initialMembers;

  @override
  State<TrustMembersScreen> createState() => _TrustMembersScreenState();
}

class _MemberRow {
  _MemberRow(this.draft)
    : name = TextEditingController(text: draft.name),
      phone = TextEditingController(text: draft.phone);

  TrustMemberDraft draft;
  final TextEditingController name;
  final TextEditingController phone;

  void dispose() {
    name.dispose();
    phone.dispose();
  }
}

class _TrustMembersScreenState extends State<TrustMembersScreen> {
  late final List<_MemberRow> _rows = _initialRows();

  List<_MemberRow> _initialRows() {
    final initial =
        widget.initialMembers ??
        [
          TrustMemberDraft(
            name: widget.yourName,
            isYou: true,
            role: TrustRole.chairman,
          ),
        ];
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

  void _addMember() => setState(
    () => _rows.add(
      _MemberRow(const TrustMemberDraft(name: '', role: TrustRole.trustee)),
    ),
  );

  void _remove(_MemberRow row) {
    setState(() {
      _rows.remove(row);
      row.dispose();
    });
  }

  void _setRole(_MemberRow row, TrustRole role) {
    setState(() => row.draft = row.draft.copyWith(role: role));
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
                      l10n.onboardingTrustMembersTitle,
                      style: text.headlineMedium,
                    ),
                    const SizedBox(height: RkSpace.s2),
                    Text(
                      l10n.onboardingTrustMembersSubtitle,
                      style: text.bodyLarge,
                    ),
                    const SizedBox(height: RkSpace.s4),
                    _Note(
                      icon: Icons.info_outline,
                      text: l10n.onboardingTrustMembersUnverifiedNote,
                    ),
                    const SizedBox(height: RkSpace.s4),
                    for (final row in _rows) ...[
                      _MemberCard(
                        row: row,
                        canRemove: !row.draft.isYou,
                        onChanged: () => setState(() {}),
                        onRemove: () => _remove(row),
                        onRoleChanged: (r) => _setRole(row, r),
                      ),
                      const SizedBox(height: RkSpace.s3),
                    ],
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: TextButton.icon(
                        onPressed: _addMember,
                        icon: const Icon(Icons.person_add_alt_outlined),
                        label: Text(l10n.onboardingTrustMembersAddMember),
                      ),
                    ),
                  ],
                ),
              ),
              FilledButton(
                onPressed: _ready ? _submit : null,
                child: Text(l10n.onboardingTrustMembersContinueLabel),
              ),
              const SizedBox(height: RkSpace.s2),
              // 🔒 07 §3.1.1 / 13 §3.2: always visible, not conditioned on
              // readiness — never a dead end for a committee that wants to
              // invite nobody yet.
              TextButton(
                onPressed: widget.onSkip,
                child: Text(l10n.onboardingTrustMembersSkip),
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
    required this.onRoleChanged,
  });

  final _MemberRow row;
  final bool canRemove;
  final VoidCallback onChanged;
  final VoidCallback onRemove;
  final void Function(TrustRole) onRoleChanged;

  String _roleLabel(AppLocalizations l10n, TrustRole r) => switch (r) {
    TrustRole.chairman => l10n.onboardingTrustRoleChairman,
    TrustRole.president => l10n.onboardingTrustRolePresident,
    TrustRole.trustee => l10n.onboardingTrustRoleTrustee,
    TrustRole.sevadar => l10n.onboardingTrustRoleSevadar,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final status = RkStatusColors.of(context);
    final draft = row.draft;
    final label = row.name.text.trim().isEmpty
        ? l10n.onboardingTrustMembersNameLabel
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
                    ? l10n.onboardingTrustMembersYouTag
                    : l10n.onboardingTrustMembersInviteTag,
              ),
              if (canRemove)
                TextButton.icon(
                  onPressed: onRemove,
                  icon: const Icon(Icons.remove_circle_outline),
                  label: Text(l10n.onboardingTrustMembersRemove(label)),
                ),
            ],
          ),
          const SizedBox(height: RkSpace.s2),
          TextField(
            controller: row.name,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: l10n.onboardingTrustMembersNameLabel,
            ),
            onChanged: (_) => onChanged(),
          ),
          const SizedBox(height: RkSpace.s2),
          DropdownButtonFormField<TrustRole>(
            initialValue: draft.role,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: l10n.onboardingTrustMembersRoleLabel,
            ),
            items: [
              for (final r in TrustRole.values)
                DropdownMenuItem(value: r, child: Text(_roleLabel(l10n, r))),
            ],
            onChanged: (r) => onRoleChanged(r ?? draft.role),
          ),
          if (!draft.isYou) ...[
            const SizedBox(height: RkSpace.s2),
            TextField(
              controller: row.phone,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: l10n.onboardingTrustMembersPhoneLabel,
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
