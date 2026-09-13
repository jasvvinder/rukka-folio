// S9 Members (13 §3.2, 07 §12, 06 §1.0/§1.1/§7, 04 §6.4).
//
// One row per person in the tenant: their role **per book** with the auto-post
// limit beside it (tap to edit — admin only, 06 §1.0 verbs table), the
// permanent verification log of 04 §6.4 (who verified whom, by which method,
// on which day), and the 06 §7 state machine as a chip. `+ Invite` opens S9.1.
//
// Two rules this screen exists to keep visible:
//   * **A designation never carries a permission** (06 §1.0 🔒 Option B): the
//     label is always drawn *with* the capability in plain words, never
//     instead of it (13 §2.4).
//   * **A second admin cannot see whom was invited** (ADR 2026-09-05c §4,
//     ADR 2026-09-05f §G 🔒): where this device does not hold the contact the
//     row reads *"Invited by Amrit · awaiting join"* and no number is shown.
//
// States (13 §4.3): loading (ruled skeleton) · populated · empty (just you →
// one action) · error-with-retry · offline chip · the non-admin variant of
// 13 §2.3.1, which states why an action is missing instead of hiding it.
//
// Not built here: **removal**. 02 §7.2.1 🔒 makes removing a member a
// *structural* action needing an owners' quorum, and 07 §12 puts an
// advance-settlement gate (02 §7) in front of it — neither the quorum card
// (S6.3) nor the advances engine is in this lane. ⚠️ SPEC: 13 §2.3.1's
// Members row still lists "invite/remove/roles" for an admin; the quorum rule
// is the later and more specific ruling, so nothing here offers a one-tap
// remove.
import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/app_scope.dart';
import '../../../shared/format/date_format.dart';
import '../../../shared/format/money_format.dart';
import '../../../shared/seams/sync_client.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';
import '../designations.dart';
import '../members_repository.dart';
import '../widgets/membership_state_chip.dart';

class MembersScreen extends StatefulWidget {
  const MembersScreen({super.key, this.onInvite});

  /// Opens S9.1. Null where the host has not wired the route yet.
  final VoidCallback? onInvite;

  @override
  State<MembersScreen> createState() => _MembersScreenState();
}

class _MembersScreenState extends State<MembersScreen> {
  bool _loading = false;
  bool _error = false;
  String? _reinviting;
  bool _reinviteError = false;
  bool _limitError = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && MembersRepositoryScope.of(context).current == null) {
        _refresh();
      }
    });
  }

  Future<void> _refresh() async {
    final repo = MembersRepositoryScope.of(context);
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      await repo.refresh();
    } on Exception {
      if (mounted) setState(() => _error = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _reinvite(Member m) async {
    final repo = MembersRepositoryScope.of(context);
    setState(() {
      _reinviting = m.id;
      _reinviteError = false;
    });
    try {
      await repo.reinvite(m.id);
    } on Exception {
      if (mounted) setState(() => _reinviteError = true);
    } finally {
      if (mounted) setState(() => _reinviting = null);
    }
  }

  Future<void> _editLimit(Member m, TenantBook book, BookGrant grant) async {
    final repo = MembersRepositoryScope.of(context);
    final l10n = AppLocalizations.of(context);
    final result = await showModalBottomSheet<_LimitResult>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => _LimitSheet(
        name: m.displayName ?? l10n.membersInvitedByUnknown,
        book: book.name,
        paise: grant.autoPostLimitPaise,
      ),
    );
    if (result == null || !mounted) return;
    setState(() => _limitError = false);
    try {
      await repo.setAutoPostLimit(
        memberId: m.id,
        bookId: book.id,
        paise: result.paise,
      );
    } on Exception {
      if (mounted) setState(() => _limitError = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final repo = MembersRepositoryScope.of(context);
    final scope = RkScope.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.membersTitle)),
      body: SafeArea(
        child: StreamBuilder<MembersSnapshot>(
          stream: repo.watch(),
          initialData: repo.current,
          builder: (context, snap) {
            final s = snap.data;
            if (s == null) {
              if (_error && !_loading) {
                return _ErrorState(
                  text: l10n.membersListError,
                  retry: l10n.membersListRetry,
                  onRetry: _refresh,
                );
              }
              return _Skeleton(label: l10n.membersListSkeleton);
            }
            return StreamBuilder<SyncStatus>(
              stream: scope.sync.status,
              initialData: scope.sync.current,
              builder: (context, ss) => _list(
                context,
                s,
                offline: ss.data is Offline,
                now: scope.now(),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _list(
    BuildContext context,
    MembersSnapshot s, {
    required bool offline,
    required DateTime now,
  }) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final canInvite = s.youAreAdminSomewhere && !s.readOnly;
    final others = s.members.where((m) => !m.isYou).toList();
    final you = s.members.where((m) => m.isYou).toList();

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.all(RkSpace.gutter),
        children: [
          if (offline)
            _Chip(icon: Icons.wifi_off, text: l10n.membersListOffline),
          if (_error)
            _Chip(
              icon: Icons.error_outline,
              text: l10n.membersListError,
              color: scheme.error,
              action: l10n.membersListRetry,
              onAction: _refresh,
            ),
          if (s.pendingBooks.isNotEmpty) ...[
            _Header(l10n.membersPendingBooksSection),
            for (final b in s.pendingBooks) _PendingBookRow(book: b),
            Padding(
              padding: const EdgeInsets.only(top: RkSpace.s2),
              child: Text(l10n.membersPendingBooksHelp, style: text.bodySmall),
            ),
          ],
          _Header(l10n.membersSectionPeople),
          if (canInvite)
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: widget.onInvite,
                icon: const Icon(Icons.person_add_alt),
                label: Text(l10n.membersInviteAction),
              ),
            )
          else
            // 13 §2.3 🔒 — never hide a capability silently; say why it is
            // not there.
            _Chip(icon: Icons.lock_outline, text: l10n.membersInviteBlocked),
          for (final m in you)
            _MemberRow(
              member: m,
              snapshot: s,
              now: now,
              adminSomewhere: canInvite,
              busy: _reinviting == m.id,
              onReinvite: () => _reinvite(m),
              onEditLimit: (book, grant) => _editLimit(m, book, grant),
            ),
          if (others.isEmpty)
            _Empty(
              text: l10n.membersListEmpty,
              action: l10n.membersListEmptyAction,
              onAction: canInvite ? widget.onInvite : null,
            )
          else
            for (final m in others)
              _MemberRow(
                member: m,
                snapshot: s,
                now: now,
                adminSomewhere: canInvite,
                busy: _reinviting == m.id,
                onReinvite: () => _reinvite(m),
                onEditLimit: (book, grant) => _editLimit(m, book, grant),
              ),
          if (_reinviteError)
            Padding(
              padding: const EdgeInsets.only(top: RkSpace.s2),
              child: Text(
                l10n.membersReinviteError,
                style: text.bodyMedium?.copyWith(color: scheme.error),
              ),
            ),
          if (_limitError)
            Padding(
              padding: const EdgeInsets.only(top: RkSpace.s2),
              child: Text(
                l10n.membersLimitEditError,
                style: text.bodyMedium?.copyWith(color: scheme.error),
              ),
            ),
        ],
      ),
    );
  }
}

/// One person: who they are, what they may do in each book, how they were
/// verified, and where they are in the 06 §7 state machine.
class _MemberRow extends StatelessWidget {
  const _MemberRow({
    required this.member,
    required this.snapshot,
    required this.now,
    required this.adminSomewhere,
    required this.busy,
    required this.onReinvite,
    required this.onEditLimit,
  });

  final Member member;
  final MembersSnapshot snapshot;
  final DateTime now;
  final bool adminSomewhere;
  final bool busy;
  final VoidCallback onReinvite;
  final void Function(TenantBook book, BookGrant grant) onEditLimit;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final status = RkStatusColors.of(context);
    final scheme = Theme.of(context).colorScheme;

    // ADR 2026-09-05c §4 / 05f §G 🔒: with no contact on this device there is
    // no name to draw — and never the number.
    final name = member.displayName;
    final anonymous = name == null;
    final headline = anonymous
        ? (member.invitedByName == null
              ? l10n.membersInvitedByUnknown
              : l10n.membersInvitedBy(member.invitedByName!))
        : name;

    final grants = [
      for (final g in member.grants)
        if (_bookOf(g.bookId) case final TenantBook b) (book: b, grant: g),
    ];
    final anyLocked =
        adminSomewhere && grants.any((g) => !snapshot.adminOf(g.book.id));

    return Container(
      padding: const EdgeInsets.symmetric(vertical: RkSpace.s3),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: status.hairline)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: RkSpace.s2,
            runSpacing: RkSpace.s1,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Icon(
                anonymous ? Icons.mail_outline : Icons.person_outline,
                color: scheme.onSurface,
              ),
              Text(headline, style: text.bodyLarge),
              if (member.isYou)
                _Badge(
                  text: l10n.membersYou,
                  colour: scheme.primary,
                  icon: Icons.person,
                ),
              MembershipStateChip(
                state: member.state,
                now: now,
                expiresOn: member.expiresOn,
              ),
            ],
          ),
          const SizedBox(height: RkSpace.s1),
          // 06 §1.0 🔒 / 13 §2.4: the label never travels without the
          // capability in plain words.
          if (_primaryRole() case final BookRole role)
            Text(
              member.designationLabel == null
                  ? rolePlainWords(l10n, role)
                  : l10n.membersRowDesignation(
                      member.designationLabel!,
                      rolePlainWords(l10n, role),
                    ),
              style: text.bodySmall,
            ),
          const SizedBox(height: RkSpace.s2),
          for (final g in grants)
            _GrantRow(
              book: g.book,
              grant: g.grant,
              editable:
                  snapshot.adminOf(g.book.id) &&
                  !snapshot.readOnly &&
                  member.state != MembershipState.blocked,
              onEdit: () => onEditLimit(g.book, g.grant),
            ),
          if (anyLocked)
            Padding(
              padding: const EdgeInsets.only(top: RkSpace.s1),
              child: Text(l10n.membersLimitLocked, style: text.bodySmall),
            ),
          const SizedBox(height: RkSpace.s2),
          _verification(context),
          if (member.state == MembershipState.expired && adminSomewhere)
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: busy ? null : onReinvite,
                icon: const Icon(Icons.refresh),
                label: Text(
                  busy
                      ? l10n.membersReinviteWorking
                      : l10n.membersReinviteAction,
                ),
              ),
            ),
          if (member.state == MembershipState.blocked)
            Padding(
              padding: const EdgeInsets.only(top: RkSpace.s1),
              child: Text(
                l10n.membersStateBlockedHelp,
                style: text.bodySmall?.copyWith(color: status.danger),
              ),
            ),
        ],
      ),
    );
  }

  /// The role whose plain words sit beside the designation: the strongest the
  /// person holds anywhere in the tenant, so a title is never paired with a
  /// weaker capability than they actually have.
  BookRole? _primaryRole() {
    BookRole? best;
    for (final g in member.grants) {
      if (best == null || g.role.index < best.index) best = g.role;
    }
    return best;
  }

  TenantBook? _bookOf(String id) {
    for (final b in snapshot.books) {
      if (b.id == id) return b;
    }
    return null;
  }

  Widget _verification(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final status = RkStatusColors.of(context);
    final v = member.verification;
    final verified = v != null;
    final date = verified
        ? formatLedgerDate(localDateOf(v.on), strings: l10n)
        : '';
    final line = switch (v?.method) {
      VerificationMethod.qrInPerson => l10n.membersVerifiedQr(
        v!.verifiedByName,
        date,
      ),
      VerificationMethod.codeRemote => l10n.membersVerifiedRemote(
        v!.verifiedByName,
        date,
      ),
      null => l10n.membersVerifiedPending,
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          verified ? Icons.verified_outlined : Icons.hourglass_empty,
          size: RkIcon.grid - RkSpace.s2,
          color: verified ? status.success : status.pending,
        ),
        const SizedBox(width: RkSpace.s1),
        Expanded(child: Text(line, style: text.bodySmall)),
      ],
    );
  }
}

/// `Book · Role` with the auto-post limit beside it; tappable for an admin of
/// that book (07 §12: *auto-post limits, tap to edit, admin only*).
class _GrantRow extends StatelessWidget {
  const _GrantRow({
    required this.book,
    required this.grant,
    required this.editable,
    required this.onEdit,
  });

  final TenantBook book;
  final BookGrant grant;
  final bool editable;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final limit = grant.autoPostLimitPaise;
    final limitText = limit == null
        ? l10n.membersLimitNone
        : l10n.membersLimitValue(
            formatPaise(limit, locale: Localizations.localeOf(context)),
          );
    final chip = Padding(
      padding: const EdgeInsets.symmetric(vertical: RkSpace.s1),
      child: Wrap(
        spacing: RkSpace.s2,
        runSpacing: RkSpace.s1,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Icon(
            Icons.menu_book_outlined,
            size: RkIcon.grid - RkSpace.s2,
            color: scheme.onSurface,
          ),
          Text(
            l10n.membersRowBookRole(book.name, roleLabel(l10n, grant.role)),
            style: text.bodyMedium,
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                editable ? Icons.edit_outlined : Icons.lock_outline,
                size: RkIcon.grid - RkSpace.s2,
                color: scheme.primary,
              ),
              const SizedBox(width: RkSpace.s1),
              Text(limitText, style: text.bodySmall),
            ],
          ),
        ],
      ),
    );
    if (!editable) return chip;
    return Semantics(
      button: true,
      label: '${l10n.membersLimitLabel} · ${book.name}',
      child: InkWell(
        onTap: onEdit,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: RkSpace.rowMinHeight),
          child: chip,
        ),
      ),
    );
  }
}

/// The invitee's greyed shared book — *"Meet Sunita to activate"* (07 §12 🔒).
class _PendingBookRow extends StatelessWidget {
  const _PendingBookRow({required this.book});

  final PendingBook book;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final status = RkStatusColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: RkSpace.s3),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: status.hairline)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_outline, color: status.locked),
          const SizedBox(width: RkSpace.s2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  book.name,
                  style: text.bodyLarge?.copyWith(color: status.locked),
                ),
                Text(
                  l10n.membersPendingBooksLocked(book.activateWithName),
                  style: text.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// What [_LimitSheet] returns: the new limit in integer paise, or null for
/// *no limit*.
@immutable
final class _LimitResult {
  const _LimitResult(this.paise);

  final int? paise;
}

/// Tap-to-edit auto-post limit (07 §12). Whole rupees in, integer paise out —
/// no float ever touches money (CLAUDE.md rule 1).
class _LimitSheet extends StatefulWidget {
  const _LimitSheet({
    required this.name,
    required this.book,
    required this.paise,
  });

  final String name;
  final String book;
  final int? paise;

  @override
  State<_LimitSheet> createState() => _LimitSheetState();
}

class _LimitSheetState extends State<_LimitSheet> {
  late final TextEditingController _field = TextEditingController(
    text: widget.paise == null ? '' : (widget.paise! ~/ 100).toString(),
  );
  bool _invalid = false;

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  void _save() {
    final paise = parseRupeeLimitToPaise(_field.text);
    if (paise == null) {
      setState(() => _invalid = true);
      return;
    }
    Navigator.of(context).pop(_LimitResult(paise));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(
        left: RkSpace.gutter,
        right: RkSpace.gutter,
        top: RkSpace.s2,
        bottom: RkSpace.s6 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.membersLimitEditTitle, style: text.titleLarge),
          Text(
            l10n.membersLimitEditSubtitle(widget.name, widget.book),
            style: text.bodySmall,
          ),
          const SizedBox(height: RkSpace.s3),
          TextField(
            controller: _field,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: l10n.membersLimitEditField,
              prefixText: rupeeSign,
              errorText: _invalid ? l10n.membersLimitEditInvalid : null,
            ),
            onChanged: (_) {
              if (_invalid) setState(() => _invalid = false);
            },
          ),
          const SizedBox(height: RkSpace.s2),
          Text(l10n.membersLimitHelp, style: text.bodySmall),
          const SizedBox(height: RkSpace.s4),
          Wrap(
            spacing: RkSpace.s2,
            runSpacing: RkSpace.s2,
            children: [
              FilledButton(
                onPressed: _save,
                child: Text(l10n.membersLimitEditSave),
              ),
              TextButton(
                onPressed: () =>
                    Navigator.of(context).pop(const _LimitResult(null)),
                child: Text(l10n.membersLimitEditClear),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                style: TextButton.styleFrom(foregroundColor: scheme.onSurface),
                child: Text(l10n.membersCancel),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Parses a typed rupee limit into integer paise. Empty is **not** zero here —
/// a blank field is a mistake, not "no limit": *no limit* has its own button
/// (13 §4.3 disabled-with-reason beats a silent default). Returns null when
/// the text is not a rupee amount.
int? parseRupeeLimitToPaise(String input) {
  final s = input.trim();
  if (s.isEmpty) return null;
  final m = RegExp(r'^(\d+)(?:\.(\d{1,2}))?$').firstMatch(s);
  if (m == null) return null;
  final rupees = int.parse(m.group(1)!);
  final fraction = (m.group(2) ?? '').padRight(2, '0');
  return rupees * 100 + int.parse(fraction);
}

class _Header extends StatelessWidget {
  const _Header(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: RkSpace.s6, bottom: RkSpace.s2),
    child: Text(text, style: Theme.of(context).textTheme.titleLarge),
  );
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text, required this.colour, required this.icon});

  final String text;
  final Color colour;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: RkSpace.s2,
      vertical: RkSpace.s1,
    ),
    decoration: BoxDecoration(
      border: Border.all(color: colour),
      borderRadius: BorderRadius.circular(RkRadius.sm),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: RkIcon.grid - RkSpace.s2, color: colour),
        const SizedBox(width: RkSpace.s1),
        Text(
          text,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colour),
        ),
      ],
    ),
  );
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.icon,
    required this.text,
    this.color,
    this.action,
    this.onAction,
  });

  final IconData icon;
  final String text;
  final Color? color;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final status = RkStatusColors.of(context);
    final c = color ?? status.muted;
    return Container(
      margin: const EdgeInsets.only(bottom: RkSpace.s3),
      padding: const EdgeInsets.symmetric(
        horizontal: RkSpace.s3,
        vertical: RkSpace.s2,
      ),
      decoration: BoxDecoration(
        color: status.sunk,
        borderRadius: BorderRadius.circular(RkRadius.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: RkIcon.grid - RkSpace.s1, color: c),
          const SizedBox(width: RkSpace.s2),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: c),
            ),
          ),
          if (action != null)
            TextButton(onPressed: onAction, child: Text(action!)),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.text, required this.action, this.onAction});

  final String text;
  final String action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: RkSpace.s4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(text, style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: RkSpace.s2),
        OutlinedButton.icon(
          onPressed: onAction,
          icon: const Icon(Icons.person_add_alt),
          label: Text(action),
        ),
      ],
    ),
  );
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({
    required this.text,
    required this.retry,
    required this.onRetry,
  });

  final String text;
  final String retry;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(RkSpace.s6),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error),
        const SizedBox(height: RkSpace.s3),
        Text(
          text,
          style: Theme.of(context).textTheme.bodyLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: RkSpace.s4),
        FilledButton(onPressed: onRetry, child: Text(retry)),
      ],
    ),
  );
}

/// Ruled skeleton rows (11 §4.5, ADR 2026-09-05f §D): static bars, no text.
class _Skeleton extends StatelessWidget {
  const _Skeleton({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final status = RkStatusColors.of(context);
    return Semantics(
      label: label,
      child: ListView.builder(
        padding: const EdgeInsets.all(RkSpace.gutter),
        itemCount: 4,
        itemBuilder: (context, i) => Container(
          height: RkSpace.rowMinHeight,
          padding: const EdgeInsets.symmetric(vertical: RkSpace.s3),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: status.hairline)),
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: i.isEven
                  ? RkMotion.skeletonLabelWidthMax
                  : RkMotion.skeletonLabelWidthMin,
              child: Container(
                height: RkSpace.s3,
                decoration: BoxDecoration(
                  color: status.skeletonLabel,
                  borderRadius: BorderRadius.circular(RkRadius.sm),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
