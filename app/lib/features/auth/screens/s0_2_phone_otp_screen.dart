// S0.2 Phone + OTP (13 §3.2, 07 §3.1 step 2, 06 §2). One number per person;
// the OTP is the only sign-in event. States (13 §4.3): default · sending ·
// wrong code (attempts left) · resend cooldown 30 s → 60 s → 5 min (06 §2) ·
// offline (quiet chip, send disabled with reason — 07 §1 rule 7) · min-version
// gate (426 → S19.1 inline, 06 §4.5) · activating · done. Errors are generic
// by rule (06 §2: no "number not registered" oracle). The done step names
// nothing about the family — an OTP-only device sees only itself (ADR
// 2026-09-05d §2). The clock is `RkScope.now` (rule 3); this file never
// logs the number or the code (rule 4).
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/app_scope.dart';
import '../../../shared/seams/auth_client.dart';
import '../../../shared/seams/sync_client.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';
import '../http_auth_client.dart';
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

enum _Step { phone, otp, activating, done }

class PhoneOtpScreen extends StatefulWidget {
  const PhoneOtpScreen({
    super.key,
    this.onDone,
    this.gate,
    this.channel,
    this.onUpdate,
  });

  /// Called with the session once the device is registered (→ S0.3).
  final void Function(AuthSession session)? onDone;

  /// Min-version gate override; defaults to the scope's auth when it is a
  /// [MinVersionGate] (HttpAuthClient).
  final ValueListenable<UpdateRequired?>? gate;

  /// OTP channel override; defaults to the scope's auth when it is an
  /// [OtpChannelSource].
  final ValueListenable<OtpChannel?>? channel;

  /// Passed through to S19.1.
  final Future<void> Function()? onUpdate;

  @override
  State<PhoneOtpScreen> createState() => _PhoneOtpScreenState();
}

class _PhoneOtpScreenState extends State<PhoneOtpScreen> {
  final _phone = TextEditingController();
  final _code = TextEditingController();
  _Step _step = _Step.phone;
  bool _busy = false;
  String? _error;
  int _sends = 0;
  DateTime? _resendAt;
  Timer? _tick;
  AuthSession? _session;

  static final _tenDigits = RegExp(r'^[6-9][0-9]{9}$');

  @override
  void dispose() {
    _tick?.cancel();
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  AuthClient get _auth => RkScope.of(context).auth;

  /// The scope's auth may also implement the gate / channel interfaces
  /// (HttpAuthClient does); the fake does not.
  static T? _as<T>(Object o) => switch (o) {
    final T t => t,
    _ => null,
  };
  DateTime _now() => RkScope.of(context).now();

  String get _e164 => '+91${_phone.text.trim()}';

  void _startCooldown() {
    _sends++;
    _resendAt = _now().add(otpCooldownAfter(_sends));
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {});
      if (_resendSeconds == 0) _tick?.cancel();
    });
  }

  int get _resendSeconds {
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

  Future<void> _send() async {
    final l10n = AppLocalizations.of(context);
    if (!_tenDigits.hasMatch(_phone.text.trim())) {
      setState(() => _error = l10n.authPhoneErrorInvalid);
      return;
    }
    await _run(() async {
      await _auth.requestOtp(_e164);
      _code.clear();
      _startCooldown();
      setState(() => _step = _Step.otp);
    });
  }

  Future<void> _resend() => _run(() async {
    await _auth.requestOtp(_e164);
    _code.clear();
    _startCooldown();
  });

  Future<void> _verify() => _run(() async {
    final ticket = await _auth.verifyOtp(_code.text.trim());
    setState(() => _step = _Step.activating);
    try {
      final session = await _auth.activateDevice(ticket);
      _session = session;
      setState(() => _step = _Step.done);
    } catch (_) {
      setState(() => _step = _Step.otp);
      rethrow;
    }
  });

  void _changeNumber() {
    _tick?.cancel();
    setState(() {
      _step = _Step.phone;
      _error = null;
      _resendAt = null;
      _sends = 0;
    });
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
    final l10n = AppLocalizations.of(context);
    final sync = RkScope.of(context).sync;
    return Scaffold(
      body: SafeArea(
        child: StreamBuilder<SyncStatus>(
          stream: sync.status,
          initialData: sync.current,
          builder: (context, snap) {
            final offline = snap.data is Offline;
            return SingleChildScrollView(
              padding: const EdgeInsets.all(RkSpace.s6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (offline) _OfflineChip(text: l10n.authOfflineChip),
                  switch (_step) {
                    _Step.phone => _phoneStep(context, offline),
                    _Step.otp => _otpStep(context, offline),
                    _Step.activating => _activating(context),
                    _Step.done => _done(context),
                  },
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _errorLine(BuildContext context) {
    final e = _error;
    if (e == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: RkSpace.s3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.error_outline,
            size: RkIcon.grid - RkSpace.s1,
            color: scheme.error,
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

  Widget _phoneStep(BuildContext context, bool offline) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.authPhoneTitle, style: text.headlineMedium),
        const SizedBox(height: RkSpace.s2),
        Text(l10n.authPhoneHint, style: text.bodyLarge),
        const SizedBox(height: RkSpace.s6),
        TextField(
          controller: _phone,
          keyboardType: TextInputType.phone,
          autofillHints: const [AutofillHints.telephoneNumberNational],
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(10),
          ],
          style: text.bodyLarge?.copyWith(fontFeatures: RkType.tabular),
          decoration: InputDecoration(
            labelText: l10n.authPhoneFieldLabel,
            prefixText: '${l10n.authPhoneCountryCode} ',
          ),
          enabled: !_busy,
          onSubmitted: (_) => offline ? null : _send(),
        ),
        _errorLine(context),
        const SizedBox(height: RkSpace.s6),
        FilledButton(
          onPressed: _busy || offline ? null : _send,
          child: Text(_busy ? l10n.authPhoneSending : l10n.authPhoneSend),
        ),
      ],
    );
  }

  Widget _otpStep(BuildContext context, bool offline) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final auth = _auth;
    final channel = widget.channel ?? _as<OtpChannelSource>(auth)?.otpChannel;
    final wait = _resendSeconds;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.authOtpTitle, style: text.headlineMedium),
        const SizedBox(height: RkSpace.s2),
        Text(l10n.authOtpSentTo(_e164), style: text.bodyLarge),
        if (channel != null)
          ValueListenableBuilder<OtpChannel?>(
            valueListenable: channel,
            builder: (context, c, _) => c == OtpChannel.sms
                ? Padding(
                    padding: const EdgeInsets.only(top: RkSpace.s2),
                    child: Text(l10n.authOtpChannelSms, style: text.bodySmall),
                  )
                : const SizedBox.shrink(),
          ),
        const SizedBox(height: RkSpace.s6),
        TextField(
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
          decoration: InputDecoration(labelText: l10n.authOtpFieldLabel),
          enabled: !_busy,
          onSubmitted: (_) => _verify(),
        ),
        _errorLine(context),
        const SizedBox(height: RkSpace.s6),
        FilledButton(
          onPressed: _busy ? null : _verify,
          child: Text(_busy ? l10n.authOtpVerifying : l10n.authOtpVerify),
        ),
        const SizedBox(height: RkSpace.s3),
        TextButton(
          onPressed: _busy || offline || wait > 0 ? null : _resend,
          child: Text(
            wait > 0 ? l10n.authOtpResendWait(wait) : l10n.authOtpResend,
          ),
        ),
        TextButton(
          onPressed: _busy ? null : _changeNumber,
          child: Text(l10n.authOtpChangeNumber),
        ),
      ],
    );
  }

  Widget _activating(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final status = RkStatusColors.of(context);
    return Padding(
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
    );
  }

  Widget _done(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(
          Icons.check_circle_outline,
          size: RkSpace.s12,
          color: scheme.primary,
        ),
        const SizedBox(height: RkSpace.s4),
        Text(l10n.authDeviceDoneTitle, style: text.headlineMedium),
        const SizedBox(height: RkSpace.s8),
        FilledButton(
          onPressed: () {
            final s = _session;
            if (s != null) widget.onDone?.call(s);
          },
          child: Text(l10n.authDeviceContinue),
        ),
      ],
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
      margin: const EdgeInsets.only(bottom: RkSpace.s4),
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
