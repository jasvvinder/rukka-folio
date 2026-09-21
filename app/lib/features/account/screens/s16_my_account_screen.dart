// S16 My account (07 §21 🔒; 13 §3.2 row S16: name, photo, phone, language).
// Reached from Menu (S8); mounted on the root navigator.
//
// The hub shows the identity record 06 §9.1 🔒 lists and hands every change
// to the screen that owns it: the name to S16.1, the number to S16.2 (06 §9.4
// — **another lane's screen**), the language to Settings S13, and the account
// itself to S16.3.
//
// Two rows here are honest about a gap rather than hiding it (07 §1 rule 6).
// **Photo:** the app has no photo pipeline at all — no picker, no camera path,
// no storage — so the row states that the initials stand in, and no control is
// drawn. **Phone:** until S16.2 is mounted the row renders
// disabled-with-reason; hand it `onChangePhone` and the same row becomes a
// door. Neither is removed from the list: a door nobody can find is a dead end
// of its own kind.
import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/app_scope.dart';
import '../../../shared/format/date_format.dart';
import '../../../shared/seams/sync_client.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';
import '../../../shared/widgets/rk_banner.dart';
import '../../../shared/widgets/rk_states.dart';
import '../account_repository.dart';
import '../widgets/account_parts.dart';

/// S16 — the account hub.
class MyAccountScreen extends StatefulWidget {
  /// Creates the screen. A null callback leaves that row
  /// disabled-with-reason rather than dropping it (07 §1 rule 6).
  const MyAccountScreen({
    super.key,
    this.onEditProfile,
    this.onChangePhone,
    this.onOpenLanguage,
    this.onOpenDelete,
  });

  /// → S16.1 Edit profile.
  final VoidCallback? onEditProfile;

  /// → S16.2 Change phone number (06 §9.4) — another lane's screen.
  final VoidCallback? onChangePhone;

  /// → S13 Settings, which owns the language control (01 §1 rule 1).
  final VoidCallback? onOpenLanguage;

  /// → S16.3 Delete account.
  final VoidCallback? onOpenDelete;

  @override
  State<MyAccountScreen> createState() => _MyAccountScreenState();
}

class _MyAccountScreenState extends State<MyAccountScreen> {
  bool _loading = false;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final repo = AccountRepositoryScope.of(context);
    final scope = RkScope.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.accountTitle)),
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
              return RkSkeleton(label: l10n.accountSkeletonLabel, rows: 5);
            }
            return StreamBuilder<SyncStatus>(
              stream: scope.sync.status,
              initialData: scope.sync.current,
              builder: (context, ss) => _body(
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

  Widget _body(
    BuildContext context,
    AccountSnapshot s, {
    required bool offline,
    required DateTime now,
  }) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final status = RkStatusColors.of(context);
    final p = s.profile;
    final window = s.window;
    final request = s.request;
    final open = window != null && !window.cancelled;

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.only(bottom: RkSpace.s8),
        children: [
          if (offline) _Chip(icon: Icons.wifi_off, text: l10n.accountOffline),
          if (_error)
            _Chip(
              icon: Icons.error_outline,
              text: l10n.accountError,
              action: l10n.accountRetry,
              onAction: _refresh,
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              RkSpace.gutter,
              RkSpace.s4,
              RkSpace.gutter,
              RkSpace.s4,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                AccountAvatar(
                  initials: p.initials,
                  nameLang: p.nameLang,
                  semanticLabel: l10n.accountAvatarLabel(p.name),
                ),
                const SizedBox(width: RkSpace.s4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Localizations.override(
                        context: context,
                        locale: Locale(p.nameLang),
                        child: Builder(
                          builder: (context) =>
                              Text(p.name, style: text.titleLarge),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (s.readOnly)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                RkSpace.gutter,
                0,
                RkSpace.gutter,
                RkSpace.s3,
              ),
              child: RkBannerSurface(
                tone: RkBannerTone.info,
                icon: Icons.lock_outline,
                title: l10n.accountReadonlyTitle,
                body: l10n.accountReadonlyBody,
              ),
            ),
          if (open)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                RkSpace.gutter,
                0,
                RkSpace.gutter,
                RkSpace.s3,
              ),
              child: RkBannerSurface(
                tone: RkBannerTone.danger,
                icon: Icons.timer_outlined,
                title: window.isComplete(now)
                    ? l10n.accountDeleteCompleteHeading
                    : l10n.accountDeletionBannerTitle,
                body: window.isComplete(now)
                    ? l10n.accountDeleteCompleteBody
                    : l10n.accountDeletionBannerBody(
                        formatLedgerDate(
                          localDateOf(window.completesAt),
                          strings: l10n,
                        ),
                      ),
                actions: [
                  if (!window.isComplete(now))
                    Text(
                      l10n.accountDeletionDaysLeft(window.daysLeft(now)),
                      style: text.bodyMedium?.copyWith(
                        fontFeatures: RkType.tabular,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  if (widget.onOpenDelete != null)
                    TextButton(
                      onPressed: widget.onOpenDelete,
                      child: Text(l10n.accountDeletionBannerAction),
                    ),
                ],
              ),
            ),
          if (request != null && !open)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                RkSpace.gutter,
                0,
                RkSpace.gutter,
                RkSpace.s3,
              ),
              child: RkBannerSurface(
                tone: RkBannerTone.warning,
                icon: Icons.support_agent,
                title: l10n.accountRequestCardTitle,
                body: l10n.accountRequestCardBody,
                actions: [
                  Text(
                    l10n.accountRequestCardAskedOn(
                      formatLedgerDate(
                        localDateOf(request.requestedAt),
                        strings: l10n,
                      ),
                    ),
                    style: text.bodySmall?.copyWith(color: status.muted),
                  ),
                  if (widget.onOpenDelete != null)
                    TextButton(
                      onPressed: widget.onOpenDelete,
                      child: Text(l10n.accountRequestCardAction),
                    ),
                ],
              ),
            ),
          _SectionHeader(l10n.accountSectionYou),
          AccountRow(
            key: const Key('account.row.name'),
            title: l10n.accountNameRowTitle,
            value: p.name,
            onTap: widget.onEditProfile,
          ),
          AccountDisabledRow(
            key: const Key('account.row.photo'),
            title: l10n.accountPhotoRowTitle,
            value: l10n.accountPhotoRowValue,
            reason: l10n.accountPhotoRowReason,
          ),
          if (widget.onChangePhone == null)
            AccountDisabledRow(
              key: const Key('account.row.phone'),
              title: l10n.accountPhoneRowTitle,
              value: p.phone,
              reason: l10n.accountPhoneRowReason,
            )
          else
            AccountRow(
              key: const Key('account.row.phone'),
              title: l10n.accountPhoneRowTitle,
              value: p.phone,
              onTap: widget.onChangePhone,
            ),
          AccountRow(
            key: const Key('account.row.language'),
            title: l10n.accountLanguageRowTitle,
            value: _languageLabel(l10n, p.languageCode),
            subtitle: l10n.accountLanguageRowSubtitle,
            onTap: widget.onOpenLanguage,
          ),
          Divider(height: 1, color: status.hairline),
          _SectionHeader(l10n.accountSectionAccount),
          AccountRow(
            key: const Key('account.row.delete'),
            title: l10n.accountDeleteRowTitle,
            subtitle: l10n.accountDeleteRowSubtitle,
            onTap: widget.onOpenDelete,
          ),
        ],
      ),
    );
  }

  /// Language names always render in their own script, in every locale
  /// (design-system §3.1 rule 1) — the same rule S0.1 and S13 follow.
  String _languageLabel(AppLocalizations l10n, String code) => switch (code) {
    'pa' => l10n.accountLanguageValuePa,
    'hi' => l10n.accountLanguageValueHi,
    _ => l10n.accountLanguageValueEn,
  };
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      RkSpace.gutter,
      RkSpace.s5,
      RkSpace.gutter,
      RkSpace.s2,
    ),
    child: Semantics(
      header: true,
      child: Text(
        label,
        style: Theme.of(context).textTheme.titleLarge
            ?.copyWith(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    ),
  );
}

/// The quiet one-line state chip — offline, or a refresh that failed over
/// content that is still perfectly readable (07 §1 rule 7: never blocking).
class _Chip extends StatelessWidget {
  const _Chip({
    required this.icon,
    required this.text,
    this.action,
    this.onAction,
  });

  final IconData icon;
  final String text;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final status = RkStatusColors.of(context);
    final style = Theme.of(context).textTheme.bodySmall;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        RkSpace.gutter,
        RkSpace.s3,
        RkSpace.gutter,
        0,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 16, color: status.muted),
          ),
          const SizedBox(width: RkSpace.s2),
          Expanded(
            child: Text(text, style: style?.copyWith(color: status.muted)),
          ),
          if (action != null && onAction != null)
            TextButton(onPressed: onAction, child: Text(action!)),
        ],
      ),
    );
  }
}
