// S16.1 Edit profile — **name and photo only** (13 §3.2 row S16.1, 07 §21 🔒).
//
// The photo half is a statement, not a control. There is no photo pipeline in
// the app — no picker, no camera path, no storage, no dependency — so this
// screen shows the initials that stand in for one and says why, instead of
// drawing a button that leads nowhere (07 §1 rule 6). When a picker lands, it
// replaces this block; nothing else on the screen changes.
//
// The name is a user-typed string, so it carries its own script tag
// (01 §1 rule 9 🔒): the tag rides with the value to the seam, and the name is
// drawn under that locale so the right family of the Mukta superfamily is
// picked (11 §4.4).
import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';
import '../../../shared/widgets/rk_states.dart';
import '../account_repository.dart';
import '../widgets/account_parts.dart';

/// S16.1 — name and photo.
class EditProfileScreen extends StatefulWidget {
  /// Creates the screen. [onDone] is called after a successful save (the
  /// router pops); null leaves the confirmation on screen instead.
  const EditProfileScreen({super.key, this.onDone});

  /// Called once the new name has reached the seam.
  final VoidCallback? onDone;

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _controller = TextEditingController();
  String _original = '';
  bool _seeded = false;
  bool _loading = false;
  bool _error = false;
  bool _saving = false;
  bool _saveError = false;
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final repo = AccountRepositoryScope.of(context);
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

  /// Seeds the field from the first snapshot, once. Re-seeding on every
  /// snapshot would throw away what the user is halfway through typing — the
  /// interruption rule of 13 §8 in miniature.
  void _seed(AccountProfile p) {
    if (_seeded) return;
    _seeded = true;
    _original = p.name;
    _controller.text = p.name;
  }

  Future<void> _save(AccountRepository repo) async {
    final name = _controller.text.trim();
    setState(() {
      _saving = true;
      _saveError = false;
      _saved = false;
    });
    try {
      await repo.setName(name, lang: accountScriptOf(name));
      if (!mounted) return;
      setState(() {
        _original = name;
        _saved = true;
      });
      widget.onDone?.call();
    } on Exception {
      if (mounted) setState(() => _saveError = true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final repo = AccountRepositoryScope.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.accountEditTitle)),
      body: SafeArea(
        child: StreamBuilder<AccountSnapshot>(
          stream: repo.watch(),
          initialData: repo.current,
          builder: (context, snap) {
            final s = snap.data;
            if (s == null) {
              if (_error && !_loading) {
                return RkErrorState(
                  text: l10n.accountError,
                  retryLabel: l10n.accountRetry,
                  onRetry: _refresh,
                );
              }
              return RkSkeleton(label: l10n.accountSkeletonLabel, rows: 3);
            }
            _seed(s.profile);
            return _form(context, s, repo);
          },
        ),
      ),
    );
  }

  Widget _form(
    BuildContext context,
    AccountSnapshot s,
    AccountRepository repo,
  ) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final status = RkStatusColors.of(context);
    final typed = _controller.text.trim();
    final shown = typed.isEmpty ? s.profile.name : typed;
    final lang = accountScriptOf(shown);

    final String? blockedBecause = switch (true) {
      _ when s.readOnly => l10n.accountEditSaveReasonReadonly,
      _ when typed.isEmpty => l10n.accountEditSaveReasonEmpty,
      _ when typed == _original => l10n.accountEditSaveReasonUnchanged,
      _ => null,
    };
    final canSave = blockedBecause == null && !_saving;

    return ListView(
      padding: const EdgeInsets.all(RkSpace.gutter),
      children: [
        Row(
          children: [
            AccountAvatar(
              initials: accountInitialsOf(shown),
              nameLang: lang,
              semanticLabel: l10n.accountAvatarLabel(shown),
            ),
            const SizedBox(width: RkSpace.s4),
            Expanded(
              child: Semantics(
                header: true,
                child: Text(l10n.accountEditPhotoTitle, style: text.titleLarge),
              ),
            ),
          ],
        ),
        const SizedBox(height: RkSpace.s2),
        // Disabled-with-reason, with no control to disable: the icon carries
        // the state beside the words, never colour alone (07 §1 rule 3). It
        // runs the full width — beside the disc it has ~180 px at 200 % on a
        // 360 px phone, and "initials" alone needs 195 px.
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(Icons.schedule, size: 14, color: status.muted),
            ),
            const SizedBox(width: RkSpace.s1),
            Expanded(
              child: Text(
                l10n.accountEditPhotoBody,
                style: text.bodySmall?.copyWith(color: status.muted),
              ),
            ),
          ],
        ),
        const SizedBox(height: RkSpace.s6),
        TextField(
          key: const Key('account.edit.name'),
          controller: _controller,
          enabled: !s.readOnly && !_saving,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.done,
          onChanged: (_) => setState(() => _saved = false),
          onSubmitted: (_) => canSave ? _save(repo) : null,
          decoration: InputDecoration(
            labelText: l10n.accountEditNameLabel,
            helperText: l10n.accountEditNameHint,
            helperMaxLines: 3,
            errorText: typed.isEmpty && _seeded && _controller.text.isNotEmpty
                ? l10n.accountEditNameEmpty
                : null,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: RkSpace.s4),
        if (_saveError)
          Padding(
            padding: const EdgeInsets.only(bottom: RkSpace.s3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(
                    Icons.error_outline,
                    size: 16,
                    color: status.danger,
                  ),
                ),
                const SizedBox(width: RkSpace.s2),
                Expanded(
                  child: Text(
                    l10n.accountEditError,
                    style: text.bodySmall?.copyWith(color: status.danger),
                  ),
                ),
              ],
            ),
          ),
        if (_saved && !_saveError)
          Padding(
            padding: const EdgeInsets.only(bottom: RkSpace.s3),
            child: Row(
              children: [
                Icon(Icons.check_circle, size: 16, color: status.success),
                const SizedBox(width: RkSpace.s2),
                Text(
                  l10n.accountEditSaved,
                  style: text.bodySmall?.copyWith(color: status.success),
                ),
              ],
            ),
          ),
        FilledButton(
          key: const Key('account.edit.save'),
          onPressed: canSave ? () => _save(repo) : null,
          child: Text(_saving ? l10n.accountEditSaving : l10n.accountEditSave),
        ),
        if (blockedBecause != null && !_saving)
          Padding(
            padding: const EdgeInsets.only(top: RkSpace.s2),
            child: Text(
              blockedBecause,
              textAlign: TextAlign.center,
              style: text.bodySmall?.copyWith(color: status.muted),
            ),
          ),
      ],
    );
  }
}
