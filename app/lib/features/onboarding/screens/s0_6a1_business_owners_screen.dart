// S0.6a1 Who owns this business? (13 §3.2 row S0.6a1, ADR 2026-09-09 §1–§3) —
// the *Shared with others* branch of S0.6a, and only that branch: a *Just me*
// business never sees this screen.
//
// Three rulings shape it:
//  §1 owners are invited **by phone**, reusing the S0.6e row unchanged — name,
//     number and the *to invite* tag. A phone number alone adds nobody: the
//     invitation waits for the in-person verification ceremony, which the
//     screen says in words so nothing here implies a verified key.
//  §2 shares are **whole-number weights**, never percentages. Equal shares
//     holds real weights (1:1:1), not 33/33/34; under *Different shares* each
//     owner has a stepper and the percentage is **computed and shown beneath,
//     never typed**. There is therefore no "must add to 100" validation and no
//     error state — any set of positive whole numbers is a valid ratio, and
//     the stepper floors at one share (removing an owner is a row action).
//  §3 the step is **not skippable**; the secondary returns to *Just me*, so it
//     is escapable without becoming a dead end (07 §1 rule 6).
//
// Percentages are integer arithmetic on the weights — no float ever touches a
// ratio the engine divides by (02 §7.1).
import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';

/// How the weights are being set (ADR 2026-09-09 §2).
enum ShareMode {
  /// Every owner holds one share — real weights, not 33/33/34.
  equal,

  /// Per-owner stepper in whole shares.
  different,
}

/// One owner of a shared business: a name, the phone the invitation goes to,
/// and a whole-number share weight (02 §7.1 divides by weight).
@immutable
final class OwnerDraft {
  /// Creates an owner row.
  const OwnerDraft({
    required this.name,
    this.phone = '',
    this.shares = 1,
    this.isYou = false,
  });

  /// Display name.
  final String name;

  /// The number the invitation goes to; empty for [isYou], who is already here.
  final String phone;

  /// Whole-number weight, at least 1.
  final int shares;

  /// True for the creating user — the first row, tagged *you*.
  final bool isYou;

  /// Copy with fields replaced.
  OwnerDraft copyWith({String? name, String? phone, int? shares}) => OwnerDraft(
    name: name ?? this.name,
    phone: phone ?? this.phone,
    shares: shares ?? this.shares,
    isYou: isYou,
  );
}

/// `shares ÷ total` as a percentage string with at most one decimal, computed
/// in integers (paise-style discipline: no float touches a ratio).
String sharePercentLabel(int shares, int total) {
  if (total <= 0) return '0';
  final tenths = (shares * 1000 + total ~/ 2) ~/ total;
  final whole = tenths ~/ 10;
  final rest = tenths % 10;
  return rest == 0 ? '$whole' : '$whole.$rest';
}

/// S0.6a1 — owners by phone, whole-number shares, computed percentages.
class BusinessOwnersScreen extends StatefulWidget {
  /// Creates the screen.
  const BusinessOwnersScreen({
    super.key,
    required this.yourName,
    this.onSubmit,
    this.onJustMeAfterAll,
    this.initialOwners,
  });

  /// The creating user's name (S0.4) — the first row, tagged *you*.
  final String yourName;

  /// Called with every owner, weights included, when Continue is pressed.
  final void Function(List<OwnerDraft> owners)? onSubmit;

  /// ADR 2026-09-09 §3: the secondary action, in place of *Skip for now* —
  /// it returns to S0.6a's *Just me* branch.
  final VoidCallback? onJustMeAfterAll;

  /// Pre-fills the rows when the step is resumed (07 §3.1.1).
  final List<OwnerDraft>? initialOwners;

  @override
  State<BusinessOwnersScreen> createState() => _BusinessOwnersScreenState();
}

class _OwnerRow {
  _OwnerRow(this.draft)
    : name = TextEditingController(text: draft.name),
      phone = TextEditingController(text: draft.phone);

  OwnerDraft draft;
  final TextEditingController name;
  final TextEditingController phone;

  void dispose() {
    name.dispose();
    phone.dispose();
  }
}

class _BusinessOwnersScreenState extends State<BusinessOwnersScreen> {
  late final List<_OwnerRow> _rows = _initialRows();
  late ShareMode _mode =
      _rows.every((r) => r.draft.shares == _rows.first.draft.shares)
      ? ShareMode.equal
      : ShareMode.different;

  List<_OwnerRow> _initialRows() {
    final initial =
        widget.initialOwners ??
        [
          OwnerDraft(name: widget.yourName, isYou: true),
          const OwnerDraft(name: ''),
        ];
    return [for (final o in initial) _OwnerRow(o)];
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  int get _totalShares => _rows.fold(0, (sum, r) => sum + r.draft.shares);

  /// Every invited row needs a name and a number; the creating user needs a
  /// name. Nothing here validates the ratio — any positive weights are valid.
  bool get _ready => _rows.every(
    (r) =>
        r.name.text.trim().isNotEmpty &&
        (r.draft.isYou || r.phone.text.trim().isNotEmpty),
  );

  void _setMode(ShareMode mode) {
    setState(() {
      _mode = mode;
      if (mode == ShareMode.equal) {
        for (final r in _rows) {
          r.draft = r.draft.copyWith(shares: 1);
        }
      }
    });
  }

  void _step(_OwnerRow row, int delta) {
    final next = row.draft.shares + delta;
    if (next < 1) return; // ADR 2026-09-09 §2: an owner cannot hold zero.
    setState(() => row.draft = row.draft.copyWith(shares: next));
  }

  void _addOwner() => setState(
    () => _rows.add(
      _OwnerRow(OwnerDraft(name: '', shares: _mode == ShareMode.equal ? 1 : 1)),
    ),
  );

  void _remove(_OwnerRow row) {
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
    final total = _totalShares;
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
                      l10n.onboardingBusinessOwnersTitle,
                      style: text.headlineMedium,
                    ),
                    const SizedBox(height: RkSpace.s2),
                    Text(
                      l10n.onboardingBusinessOwnersSubtitle,
                      style: text.bodyLarge,
                    ),
                    const SizedBox(height: RkSpace.s4),
                    _Note(
                      icon: Icons.info_outline,
                      text: l10n.onboardingBusinessOwnersUnverifiedNote,
                    ),
                    const SizedBox(height: RkSpace.s4),
                    // Weights, never percentages (ADR 2026-09-09 §2).
                    Wrap(
                      spacing: RkSpace.s2,
                      runSpacing: RkSpace.s2,
                      children: [
                        _ModeChip(
                          label: l10n.onboardingBusinessOwnersModeEqual,
                          selected: _mode == ShareMode.equal,
                          onTap: () => _setMode(ShareMode.equal),
                        ),
                        _ModeChip(
                          label: l10n.onboardingBusinessOwnersModeDifferent,
                          selected: _mode == ShareMode.different,
                          onTap: () => _setMode(ShareMode.different),
                        ),
                      ],
                    ),
                    const SizedBox(height: RkSpace.s4),
                    for (final row in _rows) ...[
                      _OwnerCard(
                        row: row,
                        mode: _mode,
                        total: total,
                        canRemove: !row.draft.isYou && _rows.length > 2,
                        onChanged: () => setState(() {}),
                        onStep: (delta) => _step(row, delta),
                        onRemove: () => _remove(row),
                      ),
                      const SizedBox(height: RkSpace.s3),
                    ],
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: TextButton.icon(
                        onPressed: _addOwner,
                        icon: const Icon(Icons.person_add_alt_outlined),
                        label: Text(l10n.onboardingBusinessOwnersAddOwner),
                      ),
                    ),
                    const SizedBox(height: RkSpace.s2),
                    Text(
                      l10n.onboardingBusinessOwnersTotalNote(total),
                      style: text.titleSmall,
                    ),
                    const SizedBox(height: RkSpace.s4),
                    _Note(
                      icon: Icons.lock_outline,
                      text: l10n.onboardingBusinessOwnersFixedNote,
                    ),
                  ],
                ),
              ),
              FilledButton(
                onPressed: _ready ? _submit : null,
                child: Text(l10n.onboardingBusinessOwnersContinueLabel),
              ),
              const SizedBox(height: RkSpace.s2),
              // ADR 2026-09-09 §3: not *Skip for now* — back to *Just me*.
              TextButton(
                onPressed: widget.onJustMeAfterAll,
                child: Text(l10n.onboardingBusinessOwnersJustMe),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OwnerCard extends StatelessWidget {
  const _OwnerCard({
    required this.row,
    required this.mode,
    required this.total,
    required this.canRemove,
    required this.onChanged,
    required this.onStep,
    required this.onRemove,
  });

  final _OwnerRow row;
  final ShareMode mode;
  final int total;
  final bool canRemove;
  final VoidCallback onChanged;
  final void Function(int delta) onStep;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final status = RkStatusColors.of(context);
    final text = Theme.of(context).textTheme;
    final draft = row.draft;
    final label = row.name.text.trim().isEmpty
        ? l10n.onboardingBusinessOwnersNameLabel
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
                    ? l10n.onboardingBusinessOwnersYouTag
                    : l10n.onboardingBusinessOwnersInviteTag,
              ),
              if (canRemove)
                TextButton.icon(
                  onPressed: onRemove,
                  icon: const Icon(Icons.remove_circle_outline),
                  label: Text(l10n.onboardingBusinessOwnersRemove(label)),
                ),
            ],
          ),
          const SizedBox(height: RkSpace.s2),
          TextField(
            controller: row.name,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: l10n.onboardingBusinessOwnersNameLabel,
            ),
            onChanged: (_) => onChanged(),
          ),
          if (!draft.isYou) ...[
            const SizedBox(height: RkSpace.s2),
            TextField(
              controller: row.phone,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: l10n.onboardingBusinessOwnersPhoneLabel,
              ),
              onChanged: (_) => onChanged(),
            ),
          ],
          const SizedBox(height: RkSpace.s3),
          Wrap(
            spacing: RkSpace.s2,
            runSpacing: RkSpace.s1,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (mode == ShareMode.different) ...[
                IconButton(
                  onPressed: draft.shares > 1 ? () => onStep(-1) : null,
                  icon: const Icon(Icons.remove),
                  tooltip: l10n.onboardingBusinessOwnersDecrease(label),
                ),
                IconButton(
                  onPressed: () => onStep(1),
                  icon: const Icon(Icons.add),
                  tooltip: l10n.onboardingBusinessOwnersIncrease(label),
                ),
              ],
              Text(
                l10n.onboardingBusinessOwnersSharesCount(draft.shares),
                style: text.titleMedium,
              ),
            ],
          ),
          const SizedBox(height: RkSpace.s1),
          // Computed, shown beneath, never typed (ADR 2026-09-09 §2).
          Text(
            l10n.onboardingBusinessOwnersPercentNote(
              sharePercentLabel(draft.shares, total),
            ),
            style: text.bodySmall?.copyWith(color: status.muted),
          ),
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

class _ModeChip extends StatelessWidget {
  const _ModeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      selected: selected,
      onSelected: (_) => onTap(),
      avatar: Icon(
        selected ? Icons.check : Icons.circle_outlined,
        size: RkIcon.grid,
      ),
      label: Text(label),
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
