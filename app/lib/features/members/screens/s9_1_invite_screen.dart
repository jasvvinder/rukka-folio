// S9.1 Invite member (13 §3.2, 07 §12, 06 §7).
//
// Three steps, in the order 07 §12 sets them: **phone → per-book role + limit
// grid → designation (optional)**, then send.
//
//   * The phone is the claim: one number = one human = one account (06 §1).
//     It leaves this device once, to be sent — the server keeps only an HMAC
//     of it (ADR 2026-09-05c §4), so nothing here stores or logs the number
//     (CLAUDE.md rule 4).
//   * A role is granted **per book**, never globally (06 §1.1), and the role
//     plus its auto-post limit is the whole of what the person may do
//     (06 §1.0 🔒). Limits are integer paise — no float touches money.
//   * The designation is a **display label**, and the one muted line
//     06 §1.0 🔒 fixes says so word for word: *"A name, not a permission —
//     what they can do is set above."* Suggestions come from the 01 §2 table
//     for this tenant type, or the label is typed free.
//
// States (13 §4.3): default · sending · error-with-retry (the form stays
// filled, 13 §8 Interruption) · disabled-with-reason when offline — the link
// is sent by the server (06 §7), so this one action needs a connection.
// ⚠️ SPEC: neither 06 §7 nor 05 says an invite may be queued in the outbox and
// sent later, so the screen states the restriction rather than promising a
// send it cannot guarantee.
import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/app_scope.dart';
import '../../../shared/format/money_format.dart';
import '../../../shared/seams/sync_client.dart';
import '../../../shared/tokens.dart';
import '../designations.dart';
import '../members_repository.dart';
import 's9_members_screen.dart' show parseRupeeLimitToPaise;

class InviteScreen extends StatefulWidget {
  const InviteScreen({super.key, this.onSent});

  /// Called once the invite is away; the host pops back to S9. Null → this
  /// screen pops itself.
  final VoidCallback? onSent;

  @override
  State<InviteScreen> createState() => _InviteScreenState();
}

class _InviteScreenState extends State<InviteScreen> {
  final _phone = TextEditingController();
  final _freeLabel = TextEditingController();
  final _limits = <String, TextEditingController>{};
  final _roles = <String, BookRole>{};

  Designation? _designation;
  bool _sending = false;

  /// The last refusal, or null. Named rather than a bare bool so the form can
  /// offer the right way out of each one (07 §1 rule 6 — no dead ends).
  MembersRefusal? _failure;
  bool _phoneInvalid = false;
  bool _rolesInvalid = false;
  bool _limitInvalid = false;

  @override
  void dispose() {
    _phone.dispose();
    _freeLabel.dispose();
    for (final c in _limits.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _limitFor(String bookId) =>
      _limits.putIfAbsent(bookId, TextEditingController.new);

  /// E.164 as 06 §1 states it: a country code and 8–15 digits in all.
  static bool isE164(String input) {
    final s = input.replaceAll(' ', '').replaceAll('-', '');
    return RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(s);
  }

  static String normalisePhone(String input) =>
      input.replaceAll(' ', '').replaceAll('-', '');

  Future<void> _send(MembersSnapshot s) async {
    final phoneOk = isE164(_phone.text);
    final grants = <BookGrant>[];
    var limitOk = true;
    for (final book in s.books) {
      final role = _roles[book.id];
      if (role == null) continue;
      int? paise;
      final typed = _limitFor(book.id).text.trim();
      if (typed.isNotEmpty && _rolePosts(role)) {
        paise = parseRupeeLimitToPaise(typed);
        if (paise == null) limitOk = false;
      }
      grants.add(
        BookGrant(bookId: book.id, role: role, autoPostLimitPaise: paise),
      );
    }
    setState(() {
      _phoneInvalid = !phoneOk;
      _rolesInvalid = grants.isEmpty;
      _limitInvalid = !limitOk;
    });
    if (!phoneOk || grants.isEmpty || !limitOk) return;

    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final repo = MembersRepositoryScope.of(context);
    final label = _designation == null
        ? (_freeLabel.text.trim().isEmpty ? null : _freeLabel.text.trim())
        : designationLabel(l10n, _designation!);
    setState(() {
      _sending = true;
      _failure = null;
    });
    try {
      await repo.invite(
        InviteRequest(
          phoneE164: normalisePhone(_phone.text),
          grants: grants,
          designationLabel: label,
        ),
      );
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(l10n.inviteSent)));
      if (widget.onSent != null) {
        widget.onSent!();
      } else {
        Navigator.of(context).maybePop();
      }
    } on MembersFailure catch (e) {
      if (mounted) setState(() => _failure = e.reason);
    } on Exception {
      if (mounted) setState(() => _failure = MembersRefusal.server);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// What to say about a refusal, in the words the form already owns: the
  /// number, the permission, the connection — and a plain retry for the rest.
  static String _failureMessage(AppLocalizations l10n, MembersRefusal reason) =>
      switch (reason) {
        MembersRefusal.offline => l10n.inviteOffline,
        MembersRefusal.badPhone => l10n.invitePhoneInvalid,
        MembersRefusal.notAdmin => l10n.membersInviteBlocked,
        _ => l10n.inviteError,
      };

  /// A viewer cannot post, so an auto-post limit means nothing for them
  /// (06 §1.0 verbs table).
  static bool _rolePosts(BookRole role) => role != BookRole.viewer;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final repo = MembersRepositoryScope.of(context);
    final scope = RkScope.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.inviteTitle)),
      body: SafeArea(
        child: StreamBuilder<MembersSnapshot>(
          stream: repo.watch(),
          initialData: repo.current,
          builder: (context, snap) {
            final s = snap.data ?? const MembersSnapshot();
            return StreamBuilder<SyncStatus>(
              stream: scope.sync.status,
              initialData: scope.sync.current,
              builder: (context, ss) =>
                  _form(context, s, offline: ss.data is Offline),
            );
          },
        ),
      ),
    );
  }

  Widget _form(
    BuildContext context,
    MembersSnapshot s, {
    required bool offline,
  }) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final suggestions = designationsFor(s.tenantType);
    final blocked = offline || s.readOnly;

    return ListView(
      padding: const EdgeInsets.all(RkSpace.gutter),
      children: [
        _Step(l10n.inviteStepPhone),
        TextField(
          controller: _phone,
          keyboardType: TextInputType.phone,
          autofillHints: const [AutofillHints.telephoneNumber],
          decoration: InputDecoration(
            hintText: l10n.invitePhoneHint,
            errorText: _phoneInvalid ? l10n.invitePhoneInvalid : null,
          ),
          onChanged: (_) {
            if (_phoneInvalid) setState(() => _phoneInvalid = false);
          },
        ),
        const SizedBox(height: RkSpace.s2),
        Text(l10n.invitePhoneHelp, style: text.bodySmall),

        _Step(l10n.inviteStepRoles),
        Text(l10n.inviteRolesHelp, style: text.bodySmall),
        const SizedBox(height: RkSpace.s2),
        for (final book in s.books) _bookGrant(context, book),
        if (_rolesInvalid)
          Padding(
            padding: const EdgeInsets.only(top: RkSpace.s2),
            child: Text(
              l10n.inviteRolesRequired,
              style: text.bodyMedium?.copyWith(color: scheme.error),
            ),
          ),

        _Step(l10n.inviteStepDesignation),
        Text(l10n.inviteDesignationOptional, style: text.bodySmall),
        const SizedBox(height: RkSpace.s2),
        if (suggestions.isEmpty)
          Text(l10n.inviteDesignationNoTable, style: text.bodySmall)
        else
          Wrap(
            spacing: RkSpace.s2,
            runSpacing: RkSpace.s2,
            children: [
              ChoiceChip(
                label: Text(l10n.inviteDesignationNone),
                selected: _designation == null,
                onSelected: (_) => setState(() => _designation = null),
              ),
              for (final d in suggestions)
                ChoiceChip(
                  label: Text(designationLabel(l10n, d)),
                  selected: _designation == d,
                  onSelected: (on) => setState(() {
                    _designation = on ? d : null;
                    if (on) _freeLabel.clear();
                  }),
                ),
            ],
          ),
        const SizedBox(height: RkSpace.s3),
        TextField(
          controller: _freeLabel,
          decoration: InputDecoration(
            labelText: suggestions.isEmpty
                ? l10n.inviteDesignationHint
                : l10n.inviteDesignationFree,
          ),
          onChanged: (v) {
            if (v.trim().isNotEmpty && _designation != null) {
              setState(() => _designation = null);
            }
          },
        ),
        const SizedBox(height: RkSpace.s2),
        // 07 §12 / 06 §1.0 🔒 Option B — word for word, never reworded.
        Text(l10n.inviteDesignationNote, style: text.bodySmall),

        const SizedBox(height: RkSpace.s6),
        Text(l10n.inviteExpiryNote, style: text.bodySmall),
        const SizedBox(height: RkSpace.s3),
        if (offline)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.wifi_off,
                size: RkIcon.grid - RkSpace.s1,
                color: scheme.onSurface,
              ),
              const SizedBox(width: RkSpace.s2),
              Expanded(child: Text(l10n.inviteOffline, style: text.bodySmall)),
            ],
          ),
        if (_failure != null)
          Padding(
            padding: const EdgeInsets.only(bottom: RkSpace.s2),
            child: Text(
              _failureMessage(l10n, _failure!),
              style: text.bodyMedium?.copyWith(color: scheme.error),
            ),
          ),
        const SizedBox(height: RkSpace.s2),
        FilledButton.icon(
          onPressed: _sending || blocked ? null : () => _send(s),
          icon: const Icon(Icons.send_outlined),
          label: Text(_sending ? l10n.inviteSending : l10n.inviteSend),
        ),
      ],
    );
  }

  Widget _bookGrant(BuildContext context, TenantBook book) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final role = _roles[book.id];
    return Padding(
      padding: const EdgeInsets.only(bottom: RkSpace.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.inviteBookRole(book.name), style: text.bodyLarge),
          const SizedBox(height: RkSpace.s2),
          Wrap(
            spacing: RkSpace.s2,
            runSpacing: RkSpace.s2,
            children: [
              ChoiceChip(
                label: Text(l10n.inviteBookNone),
                selected: role == null,
                onSelected: (_) => setState(() {
                  _roles.remove(book.id);
                  _rolesInvalid = false;
                }),
              ),
              for (final r in BookRole.values)
                ChoiceChip(
                  label: Text(roleLabel(l10n, r)),
                  selected: role == r,
                  onSelected: (on) => setState(() {
                    if (on) {
                      _roles[book.id] = r;
                    } else {
                      _roles.remove(book.id);
                    }
                    _rolesInvalid = false;
                  }),
                ),
            ],
          ),
          if (role != null) ...[
            const SizedBox(height: RkSpace.s2),
            // 13 §2.4 🔒 — the capability is always stated in plain words.
            Text(rolePlainWords(l10n, role), style: text.bodySmall),
          ],
          if (role != null && _rolePosts(role)) ...[
            const SizedBox(height: RkSpace.s2),
            TextField(
              controller: _limitFor(book.id),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: l10n.inviteLimitHint,
                prefixText: rupeeSign,
                errorText: _limitInvalid ? l10n.membersLimitEditInvalid : null,
              ),
              onChanged: (_) {
                if (_limitInvalid) setState(() => _limitInvalid = false);
              },
            ),
            const SizedBox(height: RkSpace.s1),
            Text(
              l10n.membersLimitHelp,
              style: text.bodySmall?.copyWith(color: scheme.onSurface),
            ),
          ],
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: RkSpace.s6, bottom: RkSpace.s2),
    child: Text(text, style: Theme.of(context).textTheme.titleLarge),
  );
}
