// S16.2 Change phone number (06 §9.4 🔒, 07 §21 🔒, 13 §3.2 row S16.2,
// ADR 2026-09-05d §1 🔒, ADR 2026-09-05f §6).
//
// 06 §9.4 🔒 in one line: *OTP on old number (or, if lost, guardian approval
// k-of-n) + OTP on new number → identity record updates; UMK, keys,
// memberships untouched.*
//
// **Why this is a screen and not a settings row.** The lost-number case is the
// whole reason S16.2 exists: somebody whose SIM is gone cannot receive the
// code that proves the number is theirs, and the app's answer is the same
// k-of-n ask the recovery ladder already makes. So the screen carries two
// routes to one outcome with very different trust, and it says which is which
// rather than hiding the weaker one behind the stronger.
//
// **What never bends.** The *new* number's code is required on both routes
// (06 §9.4 🔒 is an `and`, not an `or`): the guardian branch replaces the old
// number's proof and nothing else. [PhoneChangeStage] has no path to
// [PhoneChangeStage.done] that skips [PhoneChangeStage.codeSentToNew], and
// F1-07-368 holds the guardian route to it.
//
// **One vocabulary.** The ask is drawn in the ladder's own words — *trusted
// members*, said yes / no answer yet, counted from named rows — because it is
// the same act, and a second vocabulary for it would teach the reader that
// two different things were happening. "Guardian" and "share" are engineering
// words and stay off the screen (01 §1.3).
//
// ⚠️ SPEC — **does the requesting device count as "an active device"?**
// ADR 2026-09-05d §1 🔒 delays a guardian-approved change 24 h "if any active
// device exists", and puts a one-tap Cancel on "every existing device". In
// recovery the asker is a *new, uncertified* phone, so the two sets are
// disjoint; here the asker reached S16.2 from S16 and is itself a certified
// device the user holds. Neither 06 §9.4 nor the ADR says whether that
// device counts. The conservative reading is taken: it does — the wait
// applies, and the Cancel is drawn here too, because "every existing device"
// includes this one. Nothing is made faster by the user being the asker.
// Reported as an open item.
//
// ⚠️ SPEC — **the old number's notice.** 06 §9.4 🔒 says the old number
// receives a plain notice that a change was requested, but does not say on
// which route or at which moment. The screen promises it once, on the first
// step, for both routes — the earliest honest place, and the conservative one:
// a reader who is *not* the account holder learns their number will be told
// before they get any further.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/app_scope.dart';
import '../../../shared/format/date_format.dart';
import '../../../shared/seams/sync_client.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';
import '../../../shared/widgets/rk_banner.dart';
import '../../../shared/widgets/rk_fit_text.dart';
import '../../../shared/widgets/rk_states.dart';
import '../phone_change.dart';
import '../widgets/phone_change_parts.dart';

/// S16.2 — change the number on the identity record.
class ChangePhoneScreen extends StatefulWidget {
  /// Creates the screen. A null callback leaves the control it would have
  /// driven out of the tree rather than drawing one that does nothing
  /// (07 §1 rule 6 🔒).
  const ChangePhoneScreen({
    super.key,
    this.phoneChange,
    this.onDone,
    this.onSetUpTrustedMembers,
    this.onCall,
  });

  /// The seam; defaults to [PhoneChangeScope]'s.
  final PhoneChange? phoneChange;

  /// Back to S16 once the number has changed.
  final VoidCallback? onDone;

  /// → S11.1 Trusted members (04 §7.3 🔒). The way out of the lost-number
  /// route's disabled-with-reason state.
  final VoidCallback? onSetUpTrustedMembers;

  /// Places a call to one trusted member. Null when nothing on this build can
  /// dial; the row then draws no control rather than a dead one.
  final void Function(TrustedApprover approver)? onCall;

  @override
  State<ChangePhoneScreen> createState() => _ChangePhoneScreenState();
}

class _ChangePhoneScreenState extends State<ChangePhoneScreen> {
  final _code = TextEditingController();
  final _newPhone = TextEditingController();

  PhoneChangeAttempt? _attempt;
  StreamSubscription<PhoneChangeAttempt>? _sub;
  bool _started = false;
  bool _refreshFailed = false;
  bool _busy = false;
  String? _error;

  PhoneChange? get _seam =>
      widget.phoneChange ?? PhoneChangeScope.maybeOf(context);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      unawaited(_listen());
    }
  }

  @override
  void didUpdateWidget(ChangePhoneScreen old) {
    super.didUpdateWidget(old);
    if (widget.phoneChange != old.phoneChange) unawaited(_listen());
  }

  @override
  void dispose() {
    _sub?.cancel();
    _code.dispose();
    _newPhone.dispose();
    super.dispose();
  }

  /// Subscribes to the attempt and reads it once.
  ///
  /// The result is held in plain fields rather than handed to a
  /// `FutureBuilder`: a seam that fails synchronously would otherwise complete
  /// before any builder subscribed and surface as an unhandled framework error
  /// over a screen that is behaving correctly — the same reason S11.2 does it
  /// this way.
  Future<void> _listen() async {
    final seam = _seam;
    setState(() {
      _refreshFailed = false;
      _attempt = seam?.current;
    });
    if (seam == null) {
      setState(() => _refreshFailed = true);
      return;
    }
    await _sub?.cancel();
    _sub = seam.watch().listen((a) {
      if (mounted) setState(() => _attempt = a);
    });
    try {
      await seam.refresh();
      if (!mounted) return;
      setState(() => _attempt = seam.current ?? _attempt);
    } on Object {
      if (!mounted) return;
      setState(() => _refreshFailed = true);
    }
  }

  /// Runs one seam call with the busy flag and the error line, so no call site
  /// has to remember either.
  Future<void> _run(Future<void> Function() call) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await call();
      if (mounted) _code.clear();
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _error = _message(AppLocalizations.of(context), e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _message(AppLocalizations l10n, Object e) => switch (e) {
    PhoneChangeFailure(
      kind: PhoneChangeFailureKind.invalidCode,
      :final attemptsLeft,
    ) =>
      l10n.accountChangeErrorInvalid(attemptsLeft ?? 0),
    PhoneChangeFailure(kind: PhoneChangeFailureKind.codeExpired) =>
      l10n.accountChangeErrorExpired,
    PhoneChangeFailure(kind: PhoneChangeFailureKind.rateLimited) =>
      l10n.accountChangeErrorRate,
    PhoneChangeFailure(kind: PhoneChangeFailureKind.badNumber) =>
      l10n.accountChangeErrorBadnumber,
    PhoneChangeFailure(kind: PhoneChangeFailureKind.sameNumber) =>
      l10n.accountChangeErrorSame,
    PhoneChangeFailure(kind: PhoneChangeFailureKind.noTrustedMembers) =>
      l10n.accountChangeLostReason,
    _ => l10n.accountChangeErrorNetwork,
  };

  /// Digits only, so `+91 98765 43210` and `+919876543210` are one number.
  static String _digits(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scope = RkScope.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.accountChangeTitle)),
      body: SafeArea(
        child: Builder(
          builder: (context) {
            final a = _attempt;
            if (a == null) {
              if (_refreshFailed) {
                return RkErrorState(
                  text: l10n.accountChangeError,
                  retryLabel: l10n.accountRetry,
                  onRetry: _listen,
                );
              }
              return RkSkeleton(
                label: l10n.accountChangeSkeletonLabel,
                rows: 4,
              );
            }
            return StreamBuilder<SyncStatus>(
              stream: scope.sync.status,
              initialData: scope.sync.current,
              builder: (context, ss) => _body(
                context,
                a,
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
    PhoneChangeAttempt a, {
    required bool offline,
    required DateTime now,
  }) {
    final l10n = AppLocalizations.of(context);
    return ListView(
      padding: const EdgeInsets.only(bottom: RkSpace.s8),
      children: [
        if (offline)
          PhoneChangeChip(
            icon: Icons.wifi_off,
            text: l10n.accountChangeOffline,
          ),
        if (_refreshFailed)
          PhoneChangeChip(
            icon: Icons.error_outline,
            text: l10n.accountChangeError,
            action: l10n.accountRetry,
            onAction: _listen,
          ),
        _stepLine(context, a),
        ...switch (a.stage) {
          PhoneChangeStage.start => _start(context, a, offline: offline),
          PhoneChangeStage.codeSentToOld => _codeStep(
            context,
            heading: l10n.accountChangeOldTitle(a.currentNumber),
            offline: offline,
            onVerify: (code) => _seam!.verifyOldNumberCode(code),
            onResend: () => _seam!.sendCodeToOldNumber(),
            onBack: () => _seam!.cancel(),
          ),
          PhoneChangeStage.askingTrustedMembers => _members(
            context,
            a,
            offline: offline,
            now: now,
          ),
          PhoneChangeStage.oldNumberProved => _newNumber(
            context,
            a,
            offline: offline,
          ),
          PhoneChangeStage.codeSentToNew => _codeStep(
            context,
            heading: l10n.accountChangeOldTitle(a.newNumber ?? a.currentNumber),
            offline: offline,
            onVerify: (code) => _seam!.verifyNewNumberCode(code),
            onResend: () =>
                _seam!.sendCodeToNewNumber(a.newNumber ?? a.currentNumber),
            onBack: () => _seam!.cancel(),
          ),
          PhoneChangeStage.done => _done(context, a),
        },
        // DESIGN-PACK §S16.2 (canvas 10) fixes this line and says it runs
        // *throughout* — so it sits under every step, not only the first. It
        // is the one thing a reader of this screen is actually afraid of.
        _calmLine(context),
      ],
    );
  }

  /// *Your books, keys and family stay exactly as they are — only the number
  /// changes.* 06 §9.4 🔒 in the pack's own words.
  Widget _calmLine(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final status = RkStatusColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        RkSpace.gutter,
        RkSpace.s6,
        RkSpace.gutter,
        0,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_outline, size: 16, color: status.muted),
          const SizedBox(width: RkSpace.s2),
          Expanded(
            child: Text(
              l10n.accountChangeIntro,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: status.muted),
            ),
          ),
        ],
      ),
    );
  }

  /// *Step 2 of 3* — the reader should never wonder how far in they are on a
  /// flow that can pause for days.
  Widget _stepLine(BuildContext context, PhoneChangeAttempt a) {
    final l10n = AppLocalizations.of(context);
    final status = RkStatusColors.of(context);
    final step = switch (a.stage) {
      PhoneChangeStage.start ||
      PhoneChangeStage.codeSentToOld ||
      PhoneChangeStage.askingTrustedMembers => 1,
      PhoneChangeStage.oldNumberProved || PhoneChangeStage.codeSentToNew => 2,
      PhoneChangeStage.done => 3,
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        RkSpace.gutter,
        RkSpace.s4,
        RkSpace.gutter,
        0,
      ),
      child: Text(
        l10n.accountChangeStep(step, 3),
        style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: status.muted),
      ),
    );
  }

  // ---------------------------------------------------------------- step 1

  List<Widget> _start(
    BuildContext context,
    PhoneChangeAttempt a, {
    required bool offline,
  }) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final status = RkStatusColors.of(context);
    final canAsk = a.trustedMemberCount > 0;
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(
          RkSpace.gutter,
          RkSpace.s3,
          RkSpace.gutter,
          RkSpace.s4,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.accountChangeCurrentLabel,
              style: text.bodySmall?.copyWith(color: status.muted),
            ),
            const SizedBox(height: 2),
            RkFitText(
              a.currentNumber,
              style: text.titleLarge?.copyWith(fontFeatures: RkType.tabular),
            ),
            const SizedBox(height: RkSpace.s5),
            Semantics(
              header: true,
              child: Text(
                l10n.accountChangeProveHeading,
                style: text.titleLarge?.copyWith(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
      PhoneChangeRouteCard(
        key: const Key('account.change.otp'),
        icon: Icons.sms_outlined,
        title: l10n.accountChangeOtpAction,
        onTap: _busy || offline
            ? null
            : () => _run(() => _seam!.sendCodeToOldNumber()),
      ),
      PhoneChangeRouteCard(
        key: const Key('account.change.lost'),
        icon: Icons.group_outlined,
        title: l10n.accountChangeLostTitle,
        body: l10n.accountChangeLostBody,
        reason: canAsk ? null : l10n.accountChangeLostReason,
        fixLabel: l10n.accountChangeLostSetup,
        onFix: widget.onSetUpTrustedMembers,
        onTap: _busy || offline || !canAsk
            ? null
            : () => _run(() => _seam!.askTrustedMembers()),
      ),
      _errorLine(context),
      Padding(
        padding: const EdgeInsets.fromLTRB(
          RkSpace.gutter,
          RkSpace.s4,
          RkSpace.gutter,
          0,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.mail_outline, size: 16, color: status.muted),
            const SizedBox(width: RkSpace.s2),
            Expanded(
              child: Text(
                l10n.accountChangeNotice,
                style: text.bodySmall?.copyWith(color: status.muted),
              ),
            ),
          ],
        ),
      ),
    ];
  }

  // ------------------------------------------------------- either code step

  List<Widget> _codeStep(
    BuildContext context, {
    required String heading,
    required bool offline,
    required Future<void> Function(String code) onVerify,
    required Future<void> Function() onResend,
    required Future<void> Function() onBack,
  }) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(
          RkSpace.gutter,
          RkSpace.s3,
          RkSpace.gutter,
          0,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            RkFitText(heading, style: text.headlineMedium),
            const SizedBox(height: RkSpace.s6),
            TextField(
              key: const Key('account.change.code'),
              controller: _code,
              keyboardType: TextInputType.number,
              autofillHints: const [AutofillHints.oneTimeCode],
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6),
              ],
              style: text.headlineMedium?.copyWith(
                fontFeatures: RkType.tabular,
                letterSpacing: RkSpace.s1,
              ),
              decoration: InputDecoration(
                labelText: l10n.accountChangeCodeLabel,
              ),
              enabled: !_busy,
            ),
          ],
        ),
      ),
      _errorLine(context),
      Padding(
        padding: const EdgeInsets.fromLTRB(
          RkSpace.gutter,
          RkSpace.s6,
          RkSpace.gutter,
          0,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton(
              key: const Key('account.change.verify'),
              onPressed: _busy ? null : () => _run(() => onVerify(_code.text)),
              child: Text(
                _busy ? l10n.accountChangeVerifying : l10n.accountChangeVerify,
              ),
            ),
            const SizedBox(height: RkSpace.s3),
            TextButton(
              key: const Key('account.change.resend'),
              onPressed: _busy || offline ? null : () => _run(onResend),
              child: Text(l10n.accountChangeResend),
            ),
            TextButton(
              key: const Key('account.change.back'),
              onPressed: _busy ? null : () => _run(onBack),
              child: Text(l10n.accountChangeBack),
            ),
          ],
        ),
      ),
    ];
  }

  // ----------------------------------------------- step 1, lost-number route

  List<Widget> _members(
    BuildContext context,
    PhoneChangeAttempt a, {
    required bool offline,
    required DateTime now,
  }) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final status = RkStatusColors.of(context);
    final r = a.request;
    if (r == null) {
      return [
        RkErrorState(
          text: l10n.accountChangeError,
          retryLabel: l10n.accountRetry,
          onRetry: _listen,
        ),
      ];
    }

    // Closed, either way. 03 §2.2 has no `denied`, so a refused ask and a
    // lapsed one are the same value and this copy claims neither — it states
    // that nothing changed and offers the way to start again.
    if (r.isClosed) {
      return [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            RkSpace.gutter,
            RkSpace.s4,
            RkSpace.gutter,
            0,
          ),
          child: RkBannerSurface(
            tone: RkBannerTone.info,
            icon: Icons.history_toggle_off,
            title: r.state == RecoveryAttemptState.cancelled
                ? l10n.accountChangeMembersCancelled
                : l10n.accountChangeMembersClosed,
            actions: [
              TextButton(
                key: const Key('account.change.back'),
                onPressed: _busy ? null : () => _run(() => _seam!.cancel()),
                child: Text(l10n.accountChangeBack),
              ),
            ],
          ),
        ),
      ];
    }

    final waiting = r.state == RecoveryAttemptState.waiting24h;
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(
          RkSpace.gutter,
          RkSpace.s3,
          RkSpace.gutter,
          0,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            RkFitText(
              l10n.accountChangeMembersTitle,
              style: text.headlineMedium,
            ),
            const SizedBox(height: RkSpace.s2),
            Text(l10n.accountChangeMembersBody, style: text.bodyLarge),
            const SizedBox(height: RkSpace.s5),
            PhoneChangeRule(
              key: const Key('account.change.rule'),
              value: r.fraction,
              countText: l10n.accountChangeMembersCount(r.approvals, r.k),
              semanticsLabel: l10n.accountChangeMembersRuleLabel(
                r.approvals,
                r.k,
              ),
            ),
            if (r.expiresAt != null) ...[
              const SizedBox(height: RkSpace.s3),
              Text(
                l10n.accountChangeMembersExpires(
                  formatLedgerDate(localDateOf(r.expiresAt!), strings: l10n),
                ),
                style: text.bodySmall?.copyWith(color: status.muted),
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: RkSpace.s4),
      for (final m in r.approvers)
        TrustedMemberRow(
          key: Key('account.change.member.${m.memberId}'),
          approver: m,
          stateLabel: switch (m.state) {
            TrustedApproverState.approved =>
              l10n.accountChangeMembersStateApproved,
            TrustedApproverState.waiting =>
              l10n.accountChangeMembersStateWaiting,
            TrustedApproverState.notAsked =>
              l10n.accountChangeMembersStateNotasked,
            TrustedApproverState.declined =>
              l10n.accountChangeMembersStateDeclined,
          },
          callLabel: m.phone == null || widget.onCall == null
              ? null
              : l10n.accountChangeMembersCall,
          onCall: m.phone == null || widget.onCall == null
              ? null
              : () => widget.onCall!(m),
        ),
      // ADR 2026-09-05d §1 🔒 — the 24 h window, stated as protection.
      if (waiting)
        Padding(
          padding: const EdgeInsets.fromLTRB(
            RkSpace.gutter,
            RkSpace.s4,
            RkSpace.gutter,
            0,
          ),
          child: RkBannerSurface(
            tone: RkBannerTone.info,
            icon: Icons.shield_outlined,
            title: l10n.accountChangeWaitTitle,
            body: l10n.accountChangeWaitBody,
            actions: [
              Text(
                l10n.accountChangeWaitHours(r.hoursLeft(now)),
                style: text.bodyMedium?.copyWith(
                  fontFeatures: RkType.tabular,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      _errorLine(context),
      Padding(
        padding: const EdgeInsets.fromLTRB(
          RkSpace.gutter,
          RkSpace.s4,
          RkSpace.gutter,
          0,
        ),
        child: OutlinedButton(
          key: const Key('account.change.cancel'),
          onPressed: _busy ? null : () => _run(() => _seam!.cancel()),
          child: Text(l10n.accountChangeCancel),
        ),
      ),
    ];
  }

  // ---------------------------------------------------------------- step 2

  List<Widget> _newNumber(
    BuildContext context,
    PhoneChangeAttempt a, {
    required bool offline,
  }) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(
          RkSpace.gutter,
          RkSpace.s3,
          RkSpace.gutter,
          0,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            RkFitText(l10n.accountChangeNewTitle, style: text.headlineMedium),
            const SizedBox(height: RkSpace.s2),
            Text(l10n.accountChangeNewBody, style: text.bodyLarge),
            const SizedBox(height: RkSpace.s6),
            TextField(
              key: const Key('account.change.newnumber'),
              controller: _newPhone,
              keyboardType: TextInputType.phone,
              autofillHints: const [AutofillHints.telephoneNumberNational],
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(10),
              ],
              style: text.bodyLarge?.copyWith(fontFeatures: RkType.tabular),
              decoration: InputDecoration(
                labelText: l10n.accountChangeNewLabel,
                prefixText: '${l10n.accountChangeNewCountry} ',
              ),
              enabled: !_busy,
            ),
          ],
        ),
      ),
      _errorLine(context),
      Padding(
        padding: const EdgeInsets.fromLTRB(
          RkSpace.gutter,
          RkSpace.s6,
          RkSpace.gutter,
          0,
        ),
        child: FilledButton(
          key: const Key('account.change.send'),
          onPressed: _busy || offline ? null : () => _sendToNew(a),
          child: Text(
            _busy ? l10n.accountChangeNewSending : l10n.accountChangeNewSend,
          ),
        ),
      ),
    ];
  }

  /// Validates before the seam is troubled, so a mistyped number is answered
  /// in the same second rather than after a round trip.
  Future<void> _sendToNew(PhoneChangeAttempt a) {
    final typed = _newPhone.text.trim();
    if (!phoneNationalShape.hasMatch(typed)) {
      setState(
        () => _error = AppLocalizations.of(context).accountChangeErrorBadnumber,
      );
      return Future.value();
    }
    if (_digits(typed) == _digits(a.currentNumber) ||
        _digits(phoneE164(typed)) == _digits(a.currentNumber)) {
      setState(
        () => _error = AppLocalizations.of(context).accountChangeErrorSame,
      );
      return Future.value();
    }
    return _run(() => _seam!.sendCodeToNewNumber(phoneE164(typed)));
  }

  // ---------------------------------------------------------------- step 3

  List<Widget> _done(BuildContext context, PhoneChangeAttempt a) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(
          RkSpace.gutter,
          RkSpace.s4,
          RkSpace.gutter,
          0,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(
              Icons.check_circle_outline,
              size: RkSpace.s12,
              color: scheme.primary,
            ),
            const SizedBox(height: RkSpace.s4),
            RkFitText(l10n.accountChangeDoneTitle, style: text.headlineMedium),
            const SizedBox(height: RkSpace.s3),
            // The number gets its own line. Inside a sentence it is one
            // unbreakable word wider than a 360 px phone at 200 % — the copy
            // says "this number" and the figure stands above it, tabular.
            RkFitText(
              a.currentNumber,
              style: text.titleLarge?.copyWith(fontFeatures: RkType.tabular),
            ),
            const SizedBox(height: RkSpace.s2),
            Text(l10n.accountChangeDoneBody, style: text.bodyLarge),
            const SizedBox(height: RkSpace.s8),
            FilledButton(
              key: const Key('account.change.done'),
              onPressed: widget.onDone,
              child: Text(l10n.accountChangeDoneAction),
            ),
          ],
        ),
      ),
    ];
  }

  /// The one error line every step shares. A live region, so a screen reader
  /// hears a refused code without hunting for it.
  Widget _errorLine(BuildContext context) {
    final e = _error;
    if (e == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
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
            child: Icon(Icons.error_outline, size: 16, color: scheme.error),
          ),
          const SizedBox(width: RkSpace.s2),
          Expanded(
            child: Semantics(
              liveRegion: true,
              child: Text(
                e,
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: scheme.error),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
