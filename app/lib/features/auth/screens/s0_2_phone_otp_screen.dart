// S0.2 Phone + OTP (13 §3.2, 07 §3.1 step 2, 06 §2), drawn to canvas 1 O2a/O2b
// (the *I'm new* door) and canvas 1b L2–L4 (its sign-in state, ADR 2026-10-05c
// §1 🔒). One number per person; the OTP is the only sign-in event. The code
// goes by SMS only (ADR 2026-09-25 §1; ADR 2026-10-05c §2): no WhatsApp copy
// and no fallback line (C-25-1).
//
// The door (S0.06) sets only the heading — *Sign in*, with *Set up instead*
// for a wrong tap — and what happens when the number surprises us **after**
// the code (ADR 2026-10-05c §2 🔒). Before the code every number gets the same
// answer (06 §2: no registered-number oracle). After it:
//   * this install's own account → activate (06 §3) → done → S0.3;
//   * books under another account → S0.2a on the *I'm new* door, S0.2b
//     straight away on the sign-in door (13 §5 F1b) — no second code;
//   * no account (sign-in door) → S0.2e; *Set up new books* adopts the signup
//     ticket (no second code) → activate → S0.3.
//
// States (13 §4.3): default · sending · verifying · wrong code (tries left,
// boxes edged) · third miss (boxes clear, a new code goes by itself within
// the 06 §2 backoff — never a lockout, ADR 2026-10-05c §2) · resend cooldown
// 30 s → 60 s → 5 min (06 §2) · offline (quiet chip, send disabled with the
// chip as its reason — 07 §1 rule 7) · min-version gate (426 → S19.1 inline,
// 06 §4.5) · activating · done · S0.2a / S0.2b / S0.2e. Errors are generic by
// rule. The done step names nothing about the family — an OTP-only device
// sees only itself (ADR 2026-09-05d §2). The clock is `RkScope.now` (rule 3);
// this file never logs the number, the code or a ticket (rule 4); the signup
// ticket lives in this state only, never in a route.
//
// Input is the in-app keypad the canvas draws under the number and the boxes
// (the shared [PinKeypad], as S0.8 and the lock use). The six boxes are also
// a system text field, drawn invisibly over them: tapping the boxes raises
// the platform keyboard with its SMS one-time-code suggestion (iOS
// `oneTimeCode`, Android SMS autofill) and long-press offers Paste, so the
// code never has to be transcribed by hand (design-system §3.1 🔒 WCAG 2.2
// AA, SC 3.3.8). The canvas decides the look; it cannot take that away (ADR
// 2026-10-05 §1). ⚠️ SPEC: the field does not take focus by itself — that
// would raise the system keyboard over the drawn keypad on arrival — so the
// iOS suggestion appears once the boxes are tapped; an Android SMS
// User-Consent read that fills without the keyboard needs a plugin this
// build does not carry. Owner to rule if either should change.
//
// The resend row (countdown, then *Didn't get it? · Send again*) is never
// hidden by an error (07 §3.1 step 2 🔒 "resend with visible countdown";
// design-system §3.1 rule 2 🔒: nothing expires without a way back). Only
// the wrong-code state the canvas draws (c1b L4, tries left) shows its words
// alone, and the next key clears them.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/app_scope.dart';
import '../../../shared/router.dart';
import '../../../shared/seams/auth_client.dart';
import '../../../shared/seams/sync_client.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';
import '../../../shared/widgets/rk_fit_text.dart';
import '../http_auth_client.dart';
import '../phone_shape.dart';
import '../widgets/sign_in_parts.dart';
import 's0_2a_has_books_screen.dart';
import 's0_2b_found_you_screen.dart';
import 's0_2e_no_books_screen.dart';
import 's19_1_update_required_screen.dart';

/// Resend backoff after the 1st, 2nd and later sends (06 §2).
const List<Duration> otpResendBackoff = [
  Duration(seconds: 30),
  Duration(seconds: 60),
  Duration(minutes: 5),
];

/// Cooldown that follows send number [sends] (1-based).
Duration otpCooldownAfter(int sends) =>
    otpResendBackoff[(sends - 1).clamp(0, otpResendBackoff.length - 1)];

/// `0:24` / `5:00` — the canvas's countdown (c1 O2b). Latin digits.
String otpCountdown(int seconds) =>
    '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';

/// National digits in an Indian mobile number.
const _nationalLength = 10;

/// The F1 chain's place of S0.2 on canvas 1's step bar (c1 O2a/O2b: two of
/// six segments filled). ⚠️ SPEC: the canvas draws the bar on the F1 screens;
/// only S0.2 draws it in this build — the shared stepper is 13 §4.1's.
const _f1Step = 2;
const _f1Steps = 6;

/// Where S0.2 stands. Public only so a design capture can open a state.
enum PhoneOtpStep {
  phone,
  otp,
  activating,
  done,

  /// S0.2a — books under another account, *I'm new* door.
  hasBooks,

  /// S0.2b — is your old phone with you?
  foundYou,

  /// S0.2e — no account, sign-in door.
  noBooks,
}

class PhoneOtpScreen extends StatefulWidget {
  const PhoneOtpScreen({
    super.key,
    this.door = SignInDoor.newBooks,
    this.onboardingStep = false,
    this.onDone,
    this.onBack,
    this.gate,
    this.onUpdate,
    this.onNoOldPhone,
    this.debugStep,
    this.debugPhone = '',
    this.debugCode = '',
    this.debugWrongTriesLeft,
    this.debugResendSeconds,
  });

  /// The S0.06 door this screen opened on (ADR 2026-10-05c §1). *Set up
  /// instead* switches it in place.
  final SignInDoor door;

  /// Inside the F1 onboarding chain: the *I'm new* door draws canvas 1's step
  /// bar (c1 O2a/O2b).
  final bool onboardingStep;

  /// Called with the session once the device is registered (→ S0.3).
  final void Function(AuthSession session)? onDone;

  /// The back chevron on the number step (→ S0.06). Null ⇒ the route's own
  /// pop when there is one, else no chevron.
  final VoidCallback? onBack;

  /// S0.2b *No, it's lost or reset* (ADR 2026-10-05c §3). Null ⇒ the screen
  /// opens S11.6, the fork ([RkPaths.recoveryFork], 13 §5 F11), itself — so
  /// every route that mounts S0.2 offers it and no route can forget to.
  final VoidCallback? onNoOldPhone;

  /// Min-version gate override; defaults to the scope's auth when it is a
  /// [MinVersionGate] (HttpAuthClient).
  final ValueListenable<UpdateRequired?>? gate;

  /// Passed through to S19.1.
  final Future<void> Function()? onUpdate;

  /// Design captures only (ADR 2026-10-05 §2): open on this step with these
  /// digits typed, as the canvas frames draw them.
  @visibleForTesting
  final PhoneOtpStep? debugStep;
  @visibleForTesting
  final String debugPhone;
  @visibleForTesting
  final String debugCode;
  @visibleForTesting
  final int? debugWrongTriesLeft;
  @visibleForTesting
  final int? debugResendSeconds;

  @override
  State<PhoneOtpScreen> createState() => _PhoneOtpScreenState();
}

class _PhoneOtpScreenState extends State<PhoneOtpScreen> {
  late SignInDoor _door = widget.door;
  late PhoneOtpStep _step = widget.debugStep ?? PhoneOtpStep.phone;
  late String _digits = widget.debugPhone;
  late String _code = widget.debugCode;
  bool _busy = false;
  String? _error;

  /// The boxes show the rejected code edged until the next key (c1b L4).
  late bool _wrong = widget.debugWrongTriesLeft != null;
  int? _lastTriesLeft;

  /// The third miss fell inside the resend wait: send when it ends.
  bool _autoResendDue = false;
  int _sends = 0;
  DateTime? _resendAt;
  Timer? _tick;
  AuthSession? _session;
  SignupTicket? _signup;

  /// S0.2b's back goes where it came from (S0.2a or the number).
  PhoneOtpStep _beforeFoundYou = PhoneOtpStep.phone;

  /// The system text field over the boxes (autofill and paste). It mirrors
  /// [_code], except while the boxes show a rejected code edged (c1b L4):
  /// then it is empty, so the next typed digit starts afresh.
  late final _codeField = TextEditingController(text: widget.debugCode);
  final _codeFocus = FocusNode(debugLabel: 'S0.2 code');

  @override
  void initState() {
    super.initState();
    final wait = widget.debugResendSeconds;
    if (wait != null) {
      _sends = 1;
      _resendAt = DateTime.fromMillisecondsSinceEpoch(0);
      _debugWait = wait;
    }
  }

  int? _debugWait;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final left = widget.debugWrongTriesLeft;
    if (left != null && _wrong && _error == null) {
      _error = AppLocalizations.of(context).authOtpErrorInvalid(left);
      _lastTriesLeft = left;
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    _codeField.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  AuthClient get _auth => RkScope.of(context).auth;

  /// The scope's auth may also implement the gate interface
  /// (HttpAuthClient does); the fake does not.
  static T? _as<T>(Object o) => switch (o) {
    final T t => t,
    _ => null,
  };
  DateTime _now() => RkScope.of(context).now();

  String get _e164 => '+91$_digits';

  void _startCooldown() {
    _sends++;
    _debugWait = null;
    _resendAt = _now().add(otpCooldownAfter(_sends));
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {});
      if (_resendSeconds == 0) {
        _tick?.cancel();
        if (_autoResendDue) {
          _autoResendDue = false;
          unawaited(_resend(auto: true));
        }
      }
    });
  }

  int get _resendSeconds {
    final w = _debugWait;
    if (w != null) return w;
    final at = _resendAt;
    if (at == null) return 0;
    final left = at.difference(_now()).inSeconds;
    return left < 0 ? 0 : left;
  }

  String _message(AppLocalizations l10n, Object e) => switch (e) {
    AuthFailure(kind: AuthFailureKind.invalidCode, :final attemptsLeft) =>
      l10n.authOtpErrorInvalid(attemptsLeft ?? 0),
    AuthFailure(kind: AuthFailureKind.codeExpired) => l10n.authOtpErrorExpired,
    AuthFailure(kind: AuthFailureKind.noPendingCode) =>
      l10n.authOtpErrorExpired,
    AuthFailure(kind: AuthFailureKind.rateLimited) =>
      l10n.authOtpErrorRateLimited,
    AuthFailure(kind: AuthFailureKind.unavailable) =>
      l10n.authOtpErrorUnavailable,
    AuthFailure(kind: AuthFailureKind.signupTicketInvalid) =>
      l10n.authSignupExpired,
    _ => l10n.authOtpErrorGeneric,
  };

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on UpdateRequired {
      // The gate listenable now shows S19.1; nothing else to say here.
    } catch (e) {
      if (mounted) {
        setState(() => _error = _message(AppLocalizations.of(context), e));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // --- the number --------------------------------------------------------

  void _phoneDigit(String d) {
    if (_digits.length >= _nationalLength) return;
    setState(() {
      _digits += d;
      _error = null;
    });
  }

  void _phoneDelete() {
    if (_digits.isEmpty) return;
    setState(() {
      _digits = _digits.substring(0, _digits.length - 1);
      _error = null;
    });
  }

  Future<void> _send() async {
    final l10n = AppLocalizations.of(context);
    if (!isNationalPhoneShape(_digits)) {
      setState(() => _error = l10n.authPhoneErrorInvalid);
      return;
    }
    await _run(() async {
      // The same request for every number, on either door (06 §2).
      await _auth.requestOtp(_e164, door: _door);
      _code = '';
      _wrong = false;
      _lastTriesLeft = null;
      _startCooldown();
      setState(() => _step = PhoneOtpStep.otp);
    });
  }

  Future<void> _resend({bool auto = false}) async {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    await _run(() async {
      await _auth.requestOtp(_e164, door: _door);
      _code = '';
      _wrong = false;
      _lastTriesLeft = null;
      _startCooldown();
      if (auto) setState(() => _error = l10n.authOtpErrorResent);
    });
  }

  // --- the code ------------------------------------------------------------

  void _codeDigit(String d) {
    if (_busy) return;
    setState(() {
      if (_wrong) {
        _code = '';
        _wrong = false;
      }
      _error = null;
      if (_code.length < otpLength) _code += d;
    });
    if (_code.length == otpLength) unawaited(_verify());
  }

  void _codeDelete() {
    setState(() {
      _error = null;
      if (_wrong) {
        _code = '';
        _wrong = false;
      } else if (_code.isNotEmpty) {
        _code = _code.substring(0, _code.length - 1);
      }
    });
  }

  /// The system field changed: typed, pasted or autofilled (already cut to
  /// six digits by [OtpCodeFormatter]).
  void _codeTyped(String value) {
    if (_busy) return;
    setState(() {
      _code = value;
      _wrong = false;
      _error = null;
    });
    if (_code.length == otpLength) unawaited(_verify());
  }

  /// Keeps the system field equal to what the boxes mean, after the frame
  /// (never while building).
  void _syncCodeField() {
    final shown = _wrong ? '' : _code;
    if (_codeField.text == shown) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final now = _wrong ? '' : _code;
      if (_codeField.text == now) return;
      _codeField.value = TextEditingValue(
        text: now,
        selection: TextSelection.collapsed(offset: now.length),
      );
    });
  }

  Future<void> _verify() async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    OtpOutcome? outcome;
    try {
      outcome = await _auth.checkOtp(_code);
    } on AuthFailure catch (e) {
      if (!mounted) return;
      if (e.kind == AuthFailureKind.existingAccount) {
        outcome = const OtpHasBooks();
      } else if (e.kind == AuthFailureKind.codeExpired && _lastTriesLeft == 1) {
        // ADR 2026-10-05c §2: the third miss. The boxes clear and a new code
        // goes by itself — now if the 06 §2 wait is over, else when it ends.
        setState(() {
          _busy = false;
          _code = '';
          _wrong = false;
          _lastTriesLeft = null;
        });
        if (_resendSeconds == 0) {
          await _resend(auto: true);
        } else {
          setState(() {
            _autoResendDue = true;
            _error = l10n.authOtpErrorResendSoon;
          });
        }
        return;
      } else {
        setState(() {
          _busy = false;
          _wrong = e.kind == AuthFailureKind.invalidCode;
          _lastTriesLeft = e.attemptsLeft;
          if (e.kind == AuthFailureKind.codeExpired) _code = '';
          _error = _message(l10n, e);
        });
        return;
      }
    } on UpdateRequired {
      if (mounted) setState(() => _busy = false);
      return;
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = _message(l10n, e);
        });
      }
      return;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    _tick?.cancel();
    _autoResendDue = false;
    switch (outcome) {
      case OtpThisPhone(:final ticket):
        await _activate(ticket);
      case OtpHasBooks():
        // ⚠️ SPEC: ADR 2026-10-05c §3 / 13 §3.2 S0.2b — when platform key sync
        // restores the keys (04 §7.0, S11.5) this goes straight to silent
        // restore with no question. S11.5 is not built
        // (recovery_ladder_source.dart, the platform rung is unavailable), so
        // [_silentRestoreAvailable] is false and S0.2b always shows. The
        // branch point stays here; it is not faked.
        if (_silentRestoreAvailable) return;
        setState(() {
          _code = '';
          _step = _door == SignInDoor.newBooks
              ? PhoneOtpStep.hasBooks
              : _toFoundYou(PhoneOtpStep.phone);
        });
      case OtpNoBooks(:final signupTicket):
        if (_door == SignInDoor.signIn) {
          setState(() {
            _code = '';
            _signup = signupTicket;
            _step = PhoneOtpStep.noBooks;
          });
        } else {
          // The *I'm new* door already chose the signup (ADR 2026-10-05c §2);
          // the server answered `none` anyway — adopt it, no second question.
          _signup = signupTicket;
          await _adopt();
        }
    }
  }

  /// See the ⚠️ SPEC at the call site: S11.5 silent restore is not built.
  bool get _silentRestoreAvailable => false;

  PhoneOtpStep _toFoundYou(PhoneOtpStep from) {
    _beforeFoundYou = from;
    return PhoneOtpStep.foundYou;
  }

  Future<void> _activate(ActivationTicket ticket) async {
    setState(() => _step = PhoneOtpStep.activating);
    try {
      final session = await _auth.activateDevice(ticket);
      _session = session;
      if (mounted) setState(() => _step = PhoneOtpStep.done);
    } on UpdateRequired {
      // S19.1 is showing.
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _step = PhoneOtpStep.otp;
        _code = '';
        _error = _message(AppLocalizations.of(context), e);
      });
    }
  }

  /// S0.2e *Set up new books*: the signup from the code already accepted —
  /// no second code (ADR 2026-10-05c §2).
  Future<void> _adopt() async {
    final signup = _signup;
    if (signup == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final ActivationTicket ticket;
    try {
      ticket = await _auth.adoptSignup(signup);
    } on AuthFailure catch (e) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      if (e.kind == AuthFailureKind.signupTicketInvalid) {
        // Spent or expired: start again from the number, plainly.
        _signup = null;
        _changeNumber();
        setState(() => _error = l10n.authSignupExpired);
      } else {
        setState(() {
          _busy = false;
          _error = _message(l10n, e);
        });
      }
      return;
    } on UpdateRequired {
      if (mounted) setState(() => _busy = false);
      return;
    } catch (e) {
      // Anything else (a key-store write, no device identity): say so
      // plainly and give every way out back (07 §1 rule 6 — no dead end).
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _message(AppLocalizations.of(context), e);
      });
      return;
    }
    _signup = null;
    if (!mounted) return;
    setState(() => _busy = false);
    await _activate(ticket);
  }

  void _changeNumber() {
    _tick?.cancel();
    setState(() {
      _step = PhoneOtpStep.phone;
      _code = '';
      _wrong = false;
      _busy = false;
      _error = null;
      _resendAt = null;
      _debugWait = null;
      _autoResendDue = false;
      _lastTriesLeft = null;
      _sends = 0;
    });
  }

  VoidCallback? _backFromPhone(BuildContext context) {
    final back = widget.onBack;
    if (back != null) return back;
    final nav = Navigator.maybeOf(context);
    return nav != null && nav.canPop() ? () => nav.maybePop() : null;
  }

  @override
  Widget build(BuildContext context) {
    final auth = _auth;
    final gate = widget.gate ?? _as<MinVersionGate>(auth)?.updateRequired;
    if (gate == null) return _body(context);
    return ValueListenableBuilder<UpdateRequired?>(
      valueListenable: gate,
      builder: (context, g, _) => g == null
          ? _body(context)
          : UpdateRequiredScreen(gate: g, onUpdate: widget.onUpdate),
    );
  }

  Widget _body(BuildContext context) {
    final sync = RkScope.of(context).sync;
    return StreamBuilder<SyncStatus>(
      stream: sync.status,
      initialData: sync.current,
      builder: (context, snap) {
        final offline = snap.data is Offline;
        return switch (_step) {
          PhoneOtpStep.phone => _phoneStep(context, offline),
          PhoneOtpStep.otp => _otpStep(context, offline),
          PhoneOtpStep.activating => _activating(context),
          PhoneOtpStep.done => _done(context),
          PhoneOtpStep.hasBooks => HasBooksScreen(
            phone: _e164,
            onBack: _changeNumber,
            onOtherNumber: _changeNumber,
            onSignIn: () =>
                setState(() => _step = _toFoundYou(PhoneOtpStep.hasBooks)),
          ),
          PhoneOtpStep.foundYou => FoundYouScreen(
            phone: _e164,
            onBack: () => _beforeFoundYou == PhoneOtpStep.hasBooks
                ? setState(() => _step = PhoneOtpStep.hasBooks)
                : _changeNumber(),
            onNoOldPhone:
                widget.onNoOldPhone ?? () => context.go(RkPaths.recoveryFork),
          ),
          PhoneOtpStep.noBooks => NoBooksScreen(
            phone: _e164,
            busy: _busy,
            error: _error,
            onBack: _changeNumber,
            onOtherNumber: _changeNumber,
            onSetUp: _adopt,
          ),
        };
      },
    );
  }

  Widget? _offlineChip(BuildContext context, bool offline) => offline
      ? Padding(
          padding: const EdgeInsets.fromLTRB(authSide, RkSpace.s2, authSide, 0),
          child: _OfflineChip(
            text: AppLocalizations.of(context).authOfflineChip,
          ),
        )
      : null;

  Widget? _stepBar() => widget.onboardingStep && _door == SignInDoor.newBooks
      ? const _StepBar(filled: _f1Step, total: _f1Steps)
      : null;

  Widget _heading(BuildContext context, String title) => Semantics(
    header: true,
    child: RkFitText(title, style: Theme.of(context).textTheme.headlineMedium),
  );

  Widget _phoneStep(BuildContext context, bool offline) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final status = RkStatusColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    final signIn = _door == SignInDoor.signIn;
    final e = _error;
    final complete = _digits.length == _nationalLength;
    return _Shell(
      top: _offlineChip(context, offline),
      onBack: _busy ? null : _backFromPhone(context),
      bar: _stepBar(),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _heading(
            context,
            signIn ? l10n.authSignInTitle : l10n.authPhoneTitle,
          ),
          const SizedBox(height: RkSpace.s3),
          Text(
            signIn
                ? l10n.authSignInHint(l10n.appName)
                : '${l10n.authPhoneWhy} ${l10n.authPhoneHint}',
            style: text.bodyLarge?.copyWith(color: status.muted),
          ),
          const SizedBox(height: RkSpace.s8),
          PhoneNumberLine(
            digits: _digits,
            focused: !complete,
            error: e != null,
          ),
          if (e != null) ...[
            const SizedBox(height: RkSpace.s4),
            AuthErrorLine(text: e),
          ],
        ],
      ),
      actions: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AuthPrimaryAction(
            label: _busy ? l10n.authPhoneSending : l10n.authPhoneSend,
            onPressed: _busy || offline || !complete ? null : _send,
          ),
          if (signIn)
            Padding(
              padding: const EdgeInsets.only(top: RkSpace.s2),
              child: Wrap(
                spacing: RkSpace.s1,
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    l10n.authSignInNewHere,
                    style: text.bodyMedium?.copyWith(color: status.muted),
                  ),
                  _LinkButton(
                    label: l10n.authSignInSetUpInstead,
                    color: scheme.primary,
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                            _door = SignInDoor.newBooks;
                            _error = null;
                          }),
                  ),
                ],
              ),
            ),
        ],
      ),
      keypad: AuthKeypadDock(
        onDigit: _busy ? null : _phoneDigit,
        onDelete: _busy || _digits.isEmpty ? null : _phoneDelete,
      ),
    );
  }

  Widget _otpStep(BuildContext context, bool offline) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final status = RkStatusColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    final wait = _resendSeconds;
    final e = _error;
    final small = text.bodyMedium?.copyWith(color: status.muted);
    _syncCodeField();
    // The resend row is always drawn (07 §3.1 step 2 🔒): a countdown with
    // a clock (c1 O2b), then *Didn't get it? · Send again* (c1b L3).
    final Widget resend = wait > 0
        ? Row(
            children: [
              Icon(
                Icons.schedule,
                size: text.bodyMedium?.fontSize,
                color: status.muted,
              ),
              const SizedBox(width: RkSpace.s2),
              Expanded(
                child: Text(
                  l10n.authOtpResendCountdown(otpCountdown(wait)),
                  style: small?.copyWith(fontFeatures: RkType.tabular),
                ),
              ),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.authOtpDidntGet, style: small),
              _LinkButton(
                label: l10n.authOtpResend,
                color: scheme.primary,
                onPressed: offline ? null : _resend,
              ),
            ],
          );
    final Widget below;
    if (_busy && e == null) {
      below = Text(l10n.authOtpVerifying, style: small);
    } else if (e != null && _wrong) {
      // c1b L4: the tries-left words alone; the next key brings the row back.
      below = AuthErrorLine(text: e);
    } else if (e != null) {
      below = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AuthErrorLine(text: e),
          const SizedBox(height: RkSpace.s3),
          resend,
        ],
      );
    } else {
      below = resend;
    }
    return _Shell(
      top: _offlineChip(context, offline),
      onBack: _busy ? null : _changeNumber,
      bar: _stepBar(),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _heading(context, l10n.authOtpTitle),
          // The sentence row is as tall as *Change*'s 44 dp target; the gaps
          // around it give that height back so the boxes sit where c1b L3
          // draws them.
          const SizedBox(height: RkSpace.s1),
          Wrap(
            spacing: RkSpace.s1,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                l10n.authOtpSentTo(displayPhone(_e164)),
                style: text.bodyLarge?.copyWith(color: status.muted),
              ),
              _LinkButton(
                label: l10n.authOtpChangeNumber,
                color: scheme.primary,
                // Part of the body sentence (c1b L3), so its size.
                style: text.bodyLarge,
                onPressed: _busy ? null : _changeNumber,
              ),
            ],
          ),
          const SizedBox(height: RkSpace.s4),
          Stack(
            children: [
              ExcludeSemantics(
                child: OtpBoxes(code: _code, error: _wrong),
              ),
              Positioned.fill(
                child: Opacity(
                  opacity: 0,
                  alwaysIncludeSemantics: true,
                  child: Semantics(
                    label: l10n.authOtpBoxesLabel(_code.length),
                    child: TextField(
                      controller: _codeField,
                      focusNode: _codeFocus,
                      readOnly: _busy,
                      autofillHints: const [AutofillHints.oneTimeCode],
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.done,
                      inputFormatters: const [OtpCodeFormatter()],
                      autocorrect: false,
                      enableSuggestions: false,
                      showCursor: false,
                      decoration: const InputDecoration.collapsed(
                        hintText: null,
                      ),
                      onChanged: _codeTyped,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: RkSpace.s5),
          below,
          if (_door == SignInDoor.newBooks && e == null) ...[
            const SizedBox(height: RkSpace.s8),
            Text(
              l10n.authOtpOnlyNewPhone,
              style: text.bodyMedium?.copyWith(color: status.muted),
            ),
          ],
        ],
      ),
      keypad: AuthKeypadDock(
        onDigit: _busy ? null : _codeDigit,
        onDelete: _busy || (_code.isEmpty && !_wrong) ? null : _codeDelete,
      ),
    );
  }

  Widget _activating(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final status = RkStatusColors.of(context);
    return AuthPage(
      body: Padding(
        padding: const EdgeInsets.symmetric(vertical: RkSpace.s12),
        child: Column(
          children: [
            Semantics(
              label: l10n.authDeviceActivating,
              child: LinearProgressIndicator(
                minHeight: RkMotion.loaderTrackHeight,
                backgroundColor: status.loaderTrack,
                color: status.loaderSegment,
              ),
            ),
            const SizedBox(height: RkSpace.s4),
            Text(
              l10n.authDeviceActivating,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ],
        ),
      ),
    );
  }

  Widget _done(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return AuthPage(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: RkSpace.s8),
          Icon(
            Icons.check_circle_outline,
            size: RkSpace.s12,
            color: scheme.primary,
          ),
          const SizedBox(height: RkSpace.s4),
          Semantics(
            header: true,
            child: RkFitText(
              l10n.authDeviceDoneTitle,
              style: text.headlineMedium,
            ),
          ),
        ],
      ),
      footer: AuthPrimaryAction(
        label: l10n.authDeviceContinue,
        onPressed: () {
          final s = _session;
          if (s != null) widget.onDone?.call(s);
        },
      ),
    );
  }
}

/// The number and code steps: back row (with canvas 1's step bar on the F1
/// chain), body, the actions, then the keypad dock flush to the foot.
class _Shell extends StatelessWidget {
  const _Shell({
    required this.body,
    required this.keypad,
    this.actions,
    this.top,
    this.onBack,
    this.bar,
  });

  final Widget body;
  final Widget keypad;
  final Widget? actions;
  final Widget? top;
  final VoidCallback? onBack;
  final Widget? bar;

  @override
  Widget build(BuildContext context) {
    final act = actions;
    final b = bar;
    // The dock runs under the home indicator as the canvas draws it, so the
    // bottom inset is added inside the dock rather than left as page colour.
    final inset = MediaQuery.paddingOf(context).bottom;
    final status = RkStatusColors.of(context);
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, viewport) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: viewport.maxHeight),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ?top,
                      Stack(
                        alignment: Alignment.centerRight,
                        children: [
                          AuthBackRow(onBack: onBack),
                          if (b != null)
                            Padding(
                              padding: const EdgeInsets.only(
                                right: RkSpace.s4,
                                bottom: RkSpace.s2,
                              ),
                              child: b,
                            ),
                        ],
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          authSide,
                          RkSpace.s4,
                          authSide,
                          0,
                        ),
                        child: body,
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (act != null)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                            RkSpace.s4,
                            RkSpace.s6,
                            RkSpace.s4,
                            RkSpace.s2,
                          ),
                          child: act,
                        )
                      else
                        const SizedBox(height: RkSpace.s6),
                      keypad,
                      ColoredBox(
                        color: status.sunk,
                        child: SizedBox(height: inset),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Canvas 1's step bar (c1 O2a/O2b): [total] short rules, the first [filled]
/// in `primary`, the rest in `hairline`. Read as "step 2 of 6" by nothing
/// else — it is decoration beside the heading, so it is excluded from
/// semantics.
class _StepBar extends StatelessWidget {
  const _StepBar({required this.filled, required this.total});

  final int filled;
  final int total;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final status = RkStatusColors.of(context);
    return ExcludeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < total; i++)
            Container(
              width: RkSpace.s5 + RkSpace.s1 / 2,
              height: RkSpace.s1,
              margin: const EdgeInsets.only(left: RkSpace.s1),
              decoration: BoxDecoration(
                color: i < filled ? scheme.primary : status.hairline,
                borderRadius: BorderRadius.circular(RkSpace.s1),
              ),
            ),
        ],
      ),
    );
  }
}

/// An inline text link in `primary` (c1b L2 *Set up instead*, L3 *Change* /
/// *Send again*): a [TextButton] so focus and the disabled state come from the
/// theme, with the canvas's zero padding around the words. The canvas sets
/// these links at 13.5–14 px (the body-small role) unless they sit inside a
/// body sentence ([style]); the hit area is at least [authMinTarget] either
/// way (design-system §3.1 rule 9) — a way out is never a 32 dp sliver.
class _LinkButton extends StatelessWidget {
  const _LinkButton({
    required this.label,
    required this.color,
    this.onPressed,
    this.style,
  });

  final String label;
  final Color color;
  final VoidCallback? onPressed;

  /// Null ⇒ the body-small role.
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: color,
        padding: EdgeInsets.zero,
        minimumSize: const Size(authMinTarget, authMinTarget),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: (style ?? text.bodyMedium)?.copyWith(
          fontWeight: FontWeight.w500,
        ),
      ),
      child: Text(label),
    );
  }
}

class _OfflineChip extends StatelessWidget {
  const _OfflineChip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final status = RkStatusColors.of(context);
    final style = Theme.of(context).textTheme.bodySmall;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: RkSpace.s3,
        vertical: RkSpace.s2,
      ),
      decoration: BoxDecoration(
        color: status.sunk,
        borderRadius: BorderRadius.circular(RkRadius.md),
      ),
      child: Row(
        children: [
          Icon(
            Icons.wifi_off,
            size: RkIcon.grid - RkSpace.s1,
            color: status.muted,
          ),
          const SizedBox(width: RkSpace.s2),
          Expanded(child: Text(text, style: style)),
        ],
      ),
    );
  }
}
