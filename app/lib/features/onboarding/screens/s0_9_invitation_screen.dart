// S0.9 Invitation accept (13 §3.2 row S0.9, design O7a/O7b; entry point: a
// deep link). The joiner's side of 07 §12 🔒 and of the state machine in
// 06 §7 🔒 — the one screen between a working invite and a second phone.
//
// **The happy path** (13 §3.2): accept → OTP → the personal book works
// immediately, shared books greyed with *"Meet Sunita to activate"*. That is
// post-then-review applied to membership: a joiner is never blocked on
// somebody else's phone for their *own* book, because the personal book needs
// nobody's keys (06 §7 `joined_pending_verification`). The ceremony gates the
// shared books and nothing else.
//
// **The refusals are the part this screen exists to get right.**
//
// ADR 2026-09-05d §9 🔒 — *"Invites are phone-bound. An invite is accepted
// only by a device whose OTP-verified number matches `invitee_hmac`; the link
// alone admits nobody."* The route answers a wrong number and a link that does
// not exist with byte-identical bodies (C-05d-9), so it is no oracle for who
// was invited. **This screen must not undo that by being helpful.** There is
// therefore exactly ONE message — `onboarding.invite.not_for_you.*` — for all
// three of:
//   * the server refused with `invite_not_for_you`;
//   * `myInvites()` came back empty;
//   * the link named an invite id this phone was offered none of.
// Never two. A stranger holding a harvested link must not learn from this
// screen whether a number is on the invite. The other two refusals are named
// separately on purpose: the server only ever answers `invite_expired` and
// `invite_not_live` to a device whose number already matched, so neither
// tells an outsider anything.
//
// **The S0.9 variant** (13 §5 flow F11 🔒: *"device certified? no → sees
// nothing of the family, S0.9 variant"*). An uncertified device is shown its
// own user row, its own device row and nothing else — no memberships, no
// names, no roles (ADR 2026-09-05d §2 🔒, 06 §3 step 3, tested as C-06-19).
// So the variant names no tenant, no book and no member, and — the part that
// is easy to get wrong — it does not claim an invitation is waiting either,
// because this device cannot know that. It states why it is empty and offers
// the F11 ladder. ⚠️ SPEC: 13 names the variant but gives it no content; this
// is the conservative reading (say only what an uncertified device may know)
// and the gap is in the lane report.
//
// States (13 §4.3): loading (ruled skeleton) · offer · accepted · each named
// refusal with its way out · offline · error-with-retry. No dead end anywhere
// (07 §1 rule 6): every terminal state offers the joiner their own book.
//
// Nothing here logs; an offer names a tenant and its books (CLAUDE.md rule 4).
import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/app_scope.dart';
import '../../../shared/format/date_format.dart';
import '../../../shared/seams/auth_client.dart';
import '../../../shared/layout.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';
import '../invitation_gateway.dart';

/// Where S0.9 is in its own state machine.
enum InvitationStep {
  /// Asking the server which invites this number may accept.
  checking,

  /// One offer found; waiting for *Accept invitation*.
  offer,

  /// [InvitationGateway.acceptInvite] in flight.
  accepting,

  /// Accepted — 06 §7 `joined_pending_verification`.
  joined,

  /// The one refusal of ADR 2026-09-05d §9 🔒: not this phone's link, **or**
  /// no such link. One state, one message, deliberately.
  notForYou,

  /// The 7-day window closed (06 §7).
  expired,

  /// Used, revoked, or replaced by a newer invite (06 §7).
  notLive,

  /// No session yet — the OTP step of 13 §3.2's happy path.
  needsOtp,

  /// The request never reached a response (07 §1 rule 7).
  offline,

  /// Anything else the server said, with a retry.
  error,

  /// 13 §5 flow F11's *"S0.9 variant"*: this device is not certified, so it
  /// is shown nothing of the family and names nothing.
  uncertifiedDevice,
}

/// S0.9 — the invitation a deep link opened.
class InvitationScreen extends StatefulWidget {
  /// Creates the screen.
  const InvitationScreen({
    super.key,
    this.inviteId,
    this.onOpenMyBook,
    this.onConfirmNumber,
    this.onSetUpPhone,
  });

  /// The invite id the deep link carried, when it carried one. Null means
  /// *"show me whatever is addressed to this number"* — the same outcome
  /// either way, because an id this phone was offered none of is answered
  /// exactly like no offer at all (ADR 2026-09-05d §9 🔒).
  final String? inviteId;

  /// Leaves for S1 Home and the joiner's own book — the way out of **every**
  /// terminal state (07 §1 rule 6).
  final VoidCallback? onOpenMyBook;

  /// Goes to S0.2 phone + OTP when there is no session yet.
  final VoidCallback? onConfirmNumber;

  /// Goes to the F11 ladder (link a device · guardians · paper sheet) from the
  /// uncertified-device variant.
  final VoidCallback? onSetUpPhone;

  @override
  State<InvitationScreen> createState() => _InvitationScreenState();
}

class _InvitationScreenState extends State<InvitationScreen> {
  InvitationStep _step = InvitationStep.checking;
  InviteOffer? _offer;
  List<PendingBook> _pending = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  /// True only when identity says this device holds a certificate under the
  /// user's UMK (06 §3 step 3). [SignedOut] and [OtpSent] are *not* the
  /// variant — they are the OTP step of the happy path.
  bool get _certified {
    final state = RkScope.of(context).auth.current;
    return state is! Active || state.deviceCertified;
  }

  bool get _signedIn => RkScope.of(context).auth.current is Active;

  Future<void> _load() async {
    setState(() => _step = InvitationStep.checking);
    if (!_signedIn) {
      setState(() => _step = InvitationStep.needsOtp);
      return;
    }
    if (!_certified) {
      // 13 §5 F11 🔒 — do not even ask. An uncertified device is shown
      // nothing of the family, and asking would only invite a refusal this
      // screen would then have to explain in family terms.
      setState(() => _step = InvitationStep.uncertifiedDevice);
      return;
    }
    final gateway = InvitationGatewayScope.of(context);
    try {
      final offers = await gateway.myInvites();
      if (!mounted) return;
      final wanted = widget.inviteId;
      final match = _pick(offers, wanted);
      setState(() {
        _offer = match;
        // An empty list, and a link naming an invite this phone was offered
        // none of, land in the SAME state as a refused accept — the whole of
        // ADR 2026-09-05d §9 🔒.
        _step = match == null ? InvitationStep.notForYou : InvitationStep.offer;
      });
    } on MembersFailure catch (f) {
      if (mounted) setState(() => _step = _stepFor(f.reason));
    }
  }

  static InviteOffer? _pick(List<InviteOffer> offers, String? wanted) {
    for (final o in offers) {
      if (wanted == null || o.inviteId == wanted) return o;
    }
    return null;
  }

  Future<void> _accept() async {
    final offer = _offer;
    if (offer == null) return;
    setState(() => _step = InvitationStep.accepting);
    final gateway = InvitationGatewayScope.of(context);
    try {
      await gateway.acceptInvite(offer.inviteId);
      // The greyed shared books of 07 §12 arrive with the meta pull, which may
      // not have run yet. Their absence never blocks the success state: the
      // count from the offer stands in, and no name is invented.
      List<PendingBook> pending = const [];
      try {
        pending = await gateway.pendingBooks();
      } on MembersFailure {
        pending = const [];
      }
      if (!mounted) return;
      setState(() {
        _pending = pending;
        _step = InvitationStep.joined;
      });
    } on MembersFailure catch (f) {
      if (mounted) setState(() => _step = _stepFor(f.reason));
    }
  }

  /// The server's refusal → this screen's state. Note what is *missing*:
  /// there is no state that distinguishes "wrong number" from "no such
  /// invite", because there is no such distinction to draw
  /// (ADR 2026-09-05d §9 🔒).
  static InvitationStep _stepFor(MembersRefusal reason) => switch (reason) {
    MembersRefusal.inviteNotForYou => InvitationStep.notForYou,
    MembersRefusal.inviteExpired => InvitationStep.expired,
    MembersRefusal.inviteNotLive ||
    MembersRefusal.recordReplayed => InvitationStep.notLive,
    MembersRefusal.offline => InvitationStep.offline,
    MembersRefusal.unauthorized => InvitationStep.needsOtp,
    _ => InvitationStep.error,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.onboardingInviteTitle)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(RkSpace.gutter),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: RkLayout.readableMeasure,
            ),
            child: switch (_step) {
              InvitationStep.checking => _Skeleton(
                label: l10n.onboardingInviteChecking,
              ),
              InvitationStep.offer ||
              InvitationStep.accepting => _offerBody(context),
              InvitationStep.joined => _joinedBody(context),
              InvitationStep.notForYou => _Outcome(
                icon: Icons.link_off_outlined,
                tone: _Tone.warning,
                title: l10n.onboardingInviteNotForYouTitle,
                body: l10n.onboardingInviteNotForYouBody,
                actionLabel: l10n.onboardingInviteNotForYouAction,
                onAction: widget.onOpenMyBook,
              ),
              InvitationStep.expired => _Outcome(
                icon: Icons.hourglass_disabled_outlined,
                tone: _Tone.warning,
                title: l10n.onboardingInviteExpiredTitle,
                body: l10n.onboardingInviteExpiredBody,
                actionLabel: l10n.onboardingInviteNotForYouAction,
                onAction: widget.onOpenMyBook,
              ),
              InvitationStep.notLive => _Outcome(
                icon: Icons.history_toggle_off_outlined,
                tone: _Tone.warning,
                title: l10n.onboardingInviteNotLiveTitle,
                body: l10n.onboardingInviteNotLiveBody,
                actionLabel: l10n.onboardingInviteNotForYouAction,
                onAction: widget.onOpenMyBook,
              ),
              InvitationStep.needsOtp => _Outcome(
                icon: Icons.phone_iphone_outlined,
                tone: _Tone.info,
                title: l10n.onboardingInviteSignInTitle,
                body: l10n.onboardingInviteSignInBody,
                actionLabel: l10n.onboardingInviteSignInAction,
                onAction: widget.onConfirmNumber,
              ),
              InvitationStep.offline => _Outcome(
                icon: Icons.cloud_off_outlined,
                tone: _Tone.info,
                title: l10n.onboardingInviteOfflineTitle,
                body: l10n.onboardingInviteOfflineBody,
                actionLabel: l10n.onboardingInviteErrorRetry,
                onAction: _load,
                secondaryLabel: l10n.onboardingInviteNotForYouAction,
                onSecondary: widget.onOpenMyBook,
              ),
              InvitationStep.error => _Outcome(
                icon: Icons.error_outline,
                tone: _Tone.danger,
                title: l10n.onboardingInviteErrorTitle,
                body: l10n.onboardingInviteErrorBody,
                actionLabel: l10n.onboardingInviteErrorRetry,
                onAction: _load,
                secondaryLabel: l10n.onboardingInviteNotForYouAction,
                onSecondary: widget.onOpenMyBook,
              ),
              // 13 §5 F11 🔒 — names no tenant, no book, no member, and does
              // not say whether an invitation exists.
              InvitationStep.uncertifiedDevice => _Outcome(
                icon: Icons.lock_outline,
                tone: _Tone.info,
                title: l10n.onboardingInviteUnsetTitle,
                body: l10n.onboardingInviteUnsetBody,
                actionLabel: l10n.onboardingInviteUnsetAction,
                onAction: widget.onSetUpPhone,
              ),
            },
          ),
        ),
      ),
    );
  }

  Widget _offerBody(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final status = Theme.of(context).extension<RkStatusColors>()!;
    final offer = _offer!;
    final busy = _step == InvitationStep.accepting;
    final expiry = localDateOf(offer.expiresAt);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.onboardingInviteOfferHeading, style: text.headlineSmall),
        const SizedBox(height: RkSpace.s4),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.menu_book_outlined,
                    size: RkIcon.grid,
                    color: status.muted,
                  ),
                  const SizedBox(width: RkSpace.s3),
                  Expanded(
                    child: Text(
                      l10n.onboardingInviteOfferBooks(offer.roles.length),
                      style: text.titleMedium,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: RkSpace.s3),
              Text(
                l10n.onboardingInviteOfferHidden,
                style: text.bodySmall?.copyWith(color: status.muted),
              ),
              const SizedBox(height: RkSpace.s3),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.schedule_outlined,
                    size: RkIcon.grid,
                    color: status.muted,
                  ),
                  const SizedBox(width: RkSpace.s3),
                  Expanded(
                    child: Text(
                      l10n.onboardingInviteOfferExpires(
                        formatLedgerDate(expiry, strings: l10n),
                      ),
                      style: text.bodySmall?.copyWith(color: status.muted),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: RkSpace.s6),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: busy ? null : _accept,
            child: Text(
              busy
                  ? l10n.onboardingInviteOfferAccepting
                  : l10n.onboardingInviteOfferAccept,
            ),
          ),
        ),
        const SizedBox(height: RkSpace.s2),
        SizedBox(
          width: double.infinity,
          child: TextButton(
            onPressed: busy ? null : widget.onOpenMyBook,
            child: Text(l10n.onboardingInviteOfferNotNow),
          ),
        ),
      ],
    );
  }

  Widget _joinedBody(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final status = Theme.of(context).extension<RkStatusColors>()!;
    // The offer's role rows are one per book, so their count is the number of
    // shared books — the honest stand-in until the meta pull names them.
    final waiting = _pending.isNotEmpty
        ? _pending.length
        : (_offer?.roles.length ?? 0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.check_circle_outline,
              size: RkIcon.grid,
              color: status.success,
            ),
            const SizedBox(width: RkSpace.s3),
            Expanded(
              child: Text(
                l10n.onboardingInviteJoinedHeading,
                style: text.headlineSmall,
              ),
            ),
          ],
        ),
        const SizedBox(height: RkSpace.s4),
        _Card(
          child: Text(l10n.onboardingInviteJoinedOwn, style: text.bodyMedium),
        ),
        if (waiting > 0) ...[
          const SizedBox(height: RkSpace.s5),
          Text(l10n.membersPendingBooksSection, style: text.titleMedium),
          const SizedBox(height: RkSpace.s2),
          if (_pending.isEmpty)
            _Card(
              child: _GreyedRow(
                label: l10n.onboardingInviteJoinedWaiting(waiting),
                // No name is invented: 07 §12's line keeps its shape with the
                // *"someone already in this book"* slot 🔒.
                locked: l10n.membersPendingBooksLocked(
                  l10n.membersPendingBooksSomeone,
                ),
              ),
            )
          else
            _Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final b in _pending) ...[
                    if (b != _pending.first) const SizedBox(height: RkSpace.s4),
                    _GreyedRow(
                      label: b.name,
                      // 07 §12 🔒 — *"Meet Sunita to activate"*, the exact
                      // line S9 uses, from the same key.
                      locked: l10n.membersPendingBooksLocked(
                        b.activateWithName,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          const SizedBox(height: RkSpace.s3),
          Text(
            l10n.membersPendingBooksHelp,
            style: text.bodySmall?.copyWith(color: status.muted),
          ),
        ],
        const SizedBox(height: RkSpace.s6),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: widget.onOpenMyBook,
            child: Text(l10n.onboardingInviteJoinedOpen),
          ),
        ),
      ],
    );
  }
}

/// One greyed shared book: the locked icon and the word carry the state, never
/// the colour alone (07 §1 rule 3).
class _GreyedRow extends StatelessWidget {
  const _GreyedRow({required this.label, required this.locked});

  final String label;
  final String locked;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final status = Theme.of(context).extension<RkStatusColors>()!;
    return Semantics(
      label: '$label, $locked',
      excludeSemantics: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_outline, size: RkIcon.grid, color: status.locked),
          const SizedBox(width: RkSpace.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: text.bodyMedium?.copyWith(color: status.locked),
                ),
                const SizedBox(height: RkSpace.s1),
                Text(
                  locked,
                  style: text.bodySmall?.copyWith(color: status.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum _Tone { info, warning, danger }

/// Every terminal state: an icon, a named cause, plain words, and a way out
/// (07 §1 rules 6 and 12).
class _Outcome extends StatelessWidget {
  const _Outcome({
    required this.icon,
    required this.tone,
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.onAction,
    this.secondaryLabel,
    this.onSecondary,
  });

  final IconData icon;
  final _Tone tone;
  final String title;
  final String body;
  final String actionLabel;
  final VoidCallback? onAction;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final status = Theme.of(context).extension<RkStatusColors>()!;
    final tint = switch (tone) {
      _Tone.info => status.info,
      _Tone.warning => status.warning,
      _Tone.danger => status.danger,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, size: RkIcon.grid, color: tint),
                  const SizedBox(width: RkSpace.s3),
                  Expanded(child: Text(title, style: text.titleMedium)),
                ],
              ),
              const SizedBox(height: RkSpace.s3),
              Text(body, style: text.bodyMedium?.copyWith(color: status.muted)),
            ],
          ),
        ),
        const SizedBox(height: RkSpace.s6),
        SizedBox(
          width: double.infinity,
          child: FilledButton(onPressed: onAction, child: Text(actionLabel)),
        ),
        if (secondaryLabel case final label?) ...[
          const SizedBox(height: RkSpace.s2),
          SizedBox(
            width: double.infinity,
            child: TextButton(onPressed: onSecondary, child: Text(label)),
          ),
        ],
      ],
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final status = Theme.of(context).extension<RkStatusColors>()!;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(RkSpace.s4),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(RkRadius.lg),
        border: Border.all(color: status.hairline),
      ),
      child: child,
    );
  }
}

/// The ruled skeleton of 11 §4.5 / 13 §4.2 — two bars, no spinner.
class _Skeleton extends StatelessWidget {
  const _Skeleton({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final status = Theme.of(context).extension<RkStatusColors>()!;
    final text = Theme.of(context).textTheme;
    return Semantics(
      label: label,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: text.bodyMedium?.copyWith(color: status.muted)),
          const SizedBox(height: RkSpace.s4),
          for (var i = 0; i < 3; i++) ...[
            Container(
              height: RkSpace.s5,
              decoration: BoxDecoration(
                color: i == 0 ? status.skeletonAmount : status.skeletonLabel,
                borderRadius: BorderRadius.circular(RkRadius.sm),
              ),
            ),
            const SizedBox(height: RkSpace.s3),
          ],
        ],
      ),
    );
  }
}
