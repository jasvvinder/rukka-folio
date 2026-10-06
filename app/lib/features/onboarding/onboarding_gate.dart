// ADR 2026-10-06b 🔒 — the app never lands on Home until sign-up (13 §5 F1)
// or sign-in (F1b, ADR 2026-10-05c) has handed over to it.
//
// Three pieces, one per ruling:
//   1. [OnboardingGate.redirect] — the router's launch gate. While the install
//      is not onboarded, every location outside the chain (Home, a tab, a deep
//      link, a notification tap, a back stack) goes to the resume target. The
//      *onboarded* flag itself is `AppSettings.onboarded` (per install, kept
//      with the shell's other device-local state) and is written once, by
//      [handOverToHome], at the chain's own last step.
//   2. [OnboardingGate.resumeTarget] — where a cold start resumes (ruling 2).
//   3. [OnboardingBack] — system Back on a step does what that step's own back
//      affordance does (ruling 3).
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../shared/app_settings.dart';
import '../../shared/router.dart' show RkPaths;
import '../../shared/seams/auth_client.dart' show Active, AuthClient;
import '../auth/widgets/sign_in_parts.dart' show AuthBackRow;
import '../devices/pin_vault.dart' show PinNotSet, PinVault;
import '../home/home_paths.dart';
import 'onboarding_flow.dart';
import 'onboarding_paths.dart';
import 'screens/s0_6a_business_name_screen.dart';

/// The launch gate of ADR 2026-10-06b. Built once by the composition root
/// (`bootstrap.dart`) over the live session and PIN vault; `RukkaFolioApp`
/// hands its [redirect] to the router together with the persisted flag.
class OnboardingGate {
  /// [hasAccount] answers whether this device holds a session (S0.2's result);
  /// [pinSet] whether an MPIN exists (S0.8's result). [flow] carries the
  /// in-process answers (S0.3 purpose, S0.4 name) that nothing persists yet.
  OnboardingGate({
    required this.hasAccount,
    required this.pinSet,
    OnboardingFlow? flow,
  }) : flow = flow ?? OnboardingFlow();

  /// The gate over the live seams, exactly as the composition root builds it
  /// (`bootstrap.dart` calls this and nothing else): S0.2's result is an
  /// [Active] session, S0.8's is any [PinVault.status] but [PinNotSet].
  factory OnboardingGate.over({
    required AuthClient auth,
    required PinVault vault,
    required OnboardingFlow flow,
  }) => OnboardingGate(
    hasAccount: () => auth.current is Active,
    pinSet: () async => await vault.status() is! PinNotSet,
    flow: flow,
  );

  /// True when a session is on the device.
  final bool Function() hasAccount;

  /// True when an MPIN has been set (any state but *not set*).
  final Future<bool> Function() pinSet;

  /// The chain's in-process answers.
  final OnboardingFlow flow;

  /// Locations an install that is not yet onboarded may stand on.
  ///
  /// - `/onboarding/**` — the chain itself (S0.0–S0.8, the branch steps, S0.9);
  /// - `/auth/**` — S0.2 (the forgot-PIN door's copy) and S19.1;
  /// - `/recovery/**` — F1b's activation ladder (13 §5 F11), whose end is a
  ///   hand-over in its own right;
  /// - `/lock` — S15 goes over the resumed step once S0.8 has set a PIN;
  /// - the global gates S15.4 suspended and S19.5 modified device;
  /// - `/devices` — the one door S0.9 opens for a phone the invite routes
  ///   refuse as not live (desk 109).
  ///
  /// ⚠️ SPEC: ADR 2026-10-06b ruling 1 names "Home or the tab shell"; every
  /// other feature screen is gated too (conservative reading — a deep link to,
  /// say, S5 over no onboarded ledger would be a dead end, 07 §1 rule 6).
  static bool allowsBeforeOnboarding(String path) {
    bool under(String root) => path == root || path.startsWith('$root/');
    return under('/onboarding') ||
        under('/auth') ||
        under('/recovery') ||
        under('/lock') ||
        under(RkPaths.updateRequired) ||
        under(RkPaths.suspended) ||
        under(RkPaths.modifiedDevice) ||
        under(RkPaths.devices);
  }

  /// Ruling 2: where the chain resumes.
  ///
  /// - No account on the device → S0.0 splash.
  /// - Otherwise the step after the last one whose result is saved, in 13 §5
  ///   F1 order (S0.2 → S0.3 → S0.4 → S0.8 → S0.5 …).
  ///
  /// ⚠️ SPEC (ADR 2026-10-06b ruling 2's own conservative reading): S0.2's
  /// session and S0.8's PIN are persisted; S0.3's purpose and S0.4's name live
  /// only in [flow], so they count within a process (a deep link, a tab, a
  /// relaunch the OS served from the same process) and are asked again after
  /// a cold start that lost them — never the other way round. A PIN that
  /// exists puts the resume at S0.5, whatever was lost before it; with no
  /// purpose recorded the chain then hands over through `afterSetPin`, and
  /// Home's S0.7 checklist carries what was skipped (07 §3.1 step 7).
  Future<String> resumeTarget() async {
    if (!hasAccount()) return OnboardingPaths.splash;
    if (await pinSet()) return OnboardingPaths.booksSafe;
    if (flow.yourName.isNotEmpty) return OnboardingPaths.setPin;
    if (flow.purpose != null) return OnboardingPaths.namePhoto;
    return OnboardingPaths.purpose;
  }

  /// The GoRouter `redirect`: null (stay) once [onboarded], or for a location
  /// the chain may stand on; the resume target otherwise.
  FutureOr<String?> redirect(GoRouterState state, {required bool onboarded}) {
    if (onboarded) return null;
    if (allowsBeforeOnboarding(state.uri.path)) return null;
    return resumeTarget();
  }

  /// The end of F1b through the activation ladder (13 §5 F11: S11.5 silent
  /// restore, S11.3 sheet, S11.8 *Continue and set up this phone*).
  ///
  /// A hand-over to Home — and so the *onboarded* record — only when the
  /// phone is actually set up: a session (S0.2's result) **and** a PIN
  /// (S0.8's). Otherwise the chain resumes where ruling 2 puts it, and the
  /// install stays not-onboarded, so a later launch resumes it too
  /// (ADR 2026-10-06b ruling 1: the record is made at the hand-over, never
  /// for a phone with no account).
  ///
  /// ⚠️ SPEC: S11.8 is reached on F1b with no device activated (S0.2b's *No,
  /// it's lost or reset* never calls `activateDevice`), and neither 13 §5 F11
  /// nor ADR 2026-10-06b says what *set up this phone* does then. The
  /// conservative reading is the gate's own: no account → S0.0. An install
  /// that is already onboarded goes to Home as before.
  Future<void> handOverIfReady(BuildContext context) async {
    final settings = AppSettingsScope.read(context);
    if (settings?.onboarded ?? false) {
      context.go(HomePaths.home);
      return;
    }
    final ready = hasAccount() && await pinSet();
    if (!context.mounted) return;
    if (ready) {
      handOverToHome(context);
      return;
    }
    final target = await resumeTarget();
    if (context.mounted) context.go(target);
  }
}

/// The chain's hand-over to Home (ADR 2026-10-06b ruling 1): records the
/// install as onboarded — once, before the navigation, so the gate already
/// reads it — and goes to Home. Every last step of F1/F1b calls this and
/// nothing else writes the flag.
void handOverToHome(BuildContext context) {
  AppSettingsScope.read(context)?.markOnboarded();
  context.go(HomePaths.home);
}

/// Navigates a chain step forward to [path]; when [path] is Home that is the
/// hand-over, so it goes through [handOverToHome].
void goOnboarding(BuildContext context, String path) {
  if (path == HomePaths.home) {
    handOverToHome(context);
  } else {
    context.go(path);
  }
}

/// System Back on an onboarding step (ADR 2026-10-06b ruling 3).
///
/// Every step navigates with `context.go`, so the navigator holds one page and
/// a bare system Back would close the app. This intercepts it and does what
/// the step's own back affordance does:
/// - [onBack] non-null → that (the previous step of the chain);
/// - [onBack] null → the step holds its place (mid-operation, or a step with
///   no meaningful previous one);
/// - [exits] → Back may leave the app (the chain's first screen only).
///
/// Why `PopScope` and not a pushed stack: a resumed chain (ruling 2) starts
/// mid-way with nothing beneath it, so a pushed stack would still exit there.
/// An explicit previous step is the same on every path into the step.
class OnboardingBack extends StatelessWidget {
  /// Wraps [child].
  const OnboardingBack({
    super.key,
    required this.onBack,
    this.exits = false,
    required this.child,
  });

  /// What Back does; null holds the place.
  final VoidCallback? onBack;

  /// True only on the chain's first screen.
  final bool exits;

  /// The step.
  final Widget child;

  @override
  Widget build(BuildContext context) => PopScope<Object?>(
    canPop: exits,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) onBack?.call();
    },
    child: child,
  );
}

/// System Back on S0.2 (ADR 2026-10-06b ruling 3), whose sub-steps — number,
/// code, *found you*, *no books*, verifying, activating — all live inside
/// `features/auth`'s one screen. Back presses the back row the step on screen
/// draws ([AuthBackRow]) — so it goes wherever that row goes (the code step
/// to the number step, *found you* to where it came from, the number step to
/// S0.06) — and holds when the row has no action, which is how the screen
/// draws a step mid-operation (verifying, activating, a send in flight).
///
/// ⚠️ SPEC / open (lane ONB1): the natural home of this is a `PopScope` inside
/// `PhoneOtpScreen` (features/auth, not this lane's). Until that lands the
/// route mirrors the screen's own affordance rather than guessing its step;
/// once it does, this wrapper is dropped from the route, or Back runs twice.
class OnboardingBackMirror extends StatelessWidget {
  /// Wraps [child].
  const OnboardingBackMirror({super.key, required this.child});

  /// The screen whose back row Back presses.
  final Widget child;

  /// The action of the first [AuthBackRow] under [context], or null.
  static VoidCallback? onScreenBack(BuildContext context) {
    VoidCallback? action;
    var found = false;
    void visit(Element e) {
      if (found) return;
      final w = e.widget;
      if (w is AuthBackRow) {
        found = true;
        action = w.onBack;
        return;
      }
      e.visitChildren(visit);
    }

    context.visitChildElements(visit);
    return action;
  }

  @override
  Widget build(BuildContext context) => PopScope<Object?>(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) onScreenBack(context)?.call();
    },
    child: child,
  );
}

/// Where system Back goes from a chain step that has no on-screen back of its
/// own (ADR 2026-10-06b ruling 3: the previous step of 13 §5 F1). Null holds
/// the place.
///
/// ⚠️ SPEC (conservative readings, owner may refine):
/// - S0.3 holds: its previous step, S0.2, has already activated this device —
///   going back would ask for a number and code that can no longer be used,
///   which is not a meaningful previous step (ruling 3, "hold its place").
/// - S0.5 holds: its previous step, S0.8, has saved the PIN; asking for it
///   again is what ruling 2 says not to do.
/// - The branch's first step (S0.6a / S0.6d / S0.6g) goes back to S0.5b, the
///   step before it in 13 §5 F1 — or, on a second pass round the *My
///   business* loop, to S0.6c, which sent it there.
/// - A committing step (S0.6b, S0.6f, S0.6i) goes back to its answer steps
///   only while its book does not exist yet (the creation failed or was
///   refused). Once `createBook` has run, the answers are fixed into the book
///   — the ownership ratio *at creation* (02 §7.1 🔒, ADR 2026-09-09 §2) — so
///   reopening S0.6a/S0.6a1, S0.6d/S0.6e or S0.6g/S0.6h would accept edits the
///   book never takes. The step holds; Save and *Skip for now* lead on.
/// - S0.6c holds: its previous step, S0.6b, has posted (or skipped) that
///   business's opening balances, and reopening it would offer to post them
///   a second time to the same book.
///
/// Read at the moment Back is pressed, so a book created while the step was
/// on screen is seen.
String? previousOnboardingStep(String path, OnboardingFlow flow) =>
    switch (path) {
      OnboardingPaths.welcome => OnboardingPaths.language,
      OnboardingPaths.start => OnboardingPaths.welcome,
      OnboardingPaths.purpose => null,
      OnboardingPaths.namePhoto => OnboardingPaths.purpose,
      OnboardingPaths.booksSafe => null,
      OnboardingPaths.recoverySheet => OnboardingPaths.booksSafe,
      OnboardingPaths.business =>
        flow.loopingBusinesses
            ? OnboardingPaths.businessAnother
            : OnboardingPaths.recoverySheet,
      OnboardingPaths.businessOwners => OnboardingPaths.business,
      OnboardingPaths.businessOpening =>
        flow.businessBookId != null
            ? null
            : flow.business?.ownership == BusinessOwnershipChoice.shared
            ? OnboardingPaths.businessOwners
            : OnboardingPaths.business,
      OnboardingPaths.businessAnother => null,
      OnboardingPaths.family => OnboardingPaths.recoverySheet,
      OnboardingPaths.familyMembers => OnboardingPaths.family,
      OnboardingPaths.familyAccounts =>
        flow.familyBookId != null ? null : OnboardingPaths.familyMembers,
      OnboardingPaths.trust => OnboardingPaths.recoverySheet,
      OnboardingPaths.trustMembers => OnboardingPaths.trust,
      OnboardingPaths.trustAccounts =>
        flow.trustBookId != null ? null : OnboardingPaths.trustMembers,
      _ => null,
    };
