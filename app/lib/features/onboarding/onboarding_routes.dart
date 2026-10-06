// Onboarding feature routes (features/README, router.dart contract). Mounted
// on the root navigator via `featureRoutes` — these screens run before the
// tab shell exists, same posture as features/auth's S0.2 (07 §5 flow F1:
// splash → language → welcome → S0.2 → S0.3 purpose → S0.4 name → S0.8 PIN).
import 'dart:async';

import 'package:core_ledger/core_ledger.dart' show LocalDate;
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../shared/app_scope.dart';
import '../../shared/app_settings.dart';
import '../../shared/ledger/ledger_scope.dart';
import '../../shared/router.dart' show RkPaths;
import '../../shared/seams/auth_client.dart' show SignInDoor;

import '../auth/auth_paths.dart';
import '../auth/screens/s0_2_phone_otp_screen.dart' show PhoneOtpScreen;
import '../demo/widgets/demo_build_card.dart' show demoPurposeCard;
import '../devices/devices_paths.dart';
import '../entry/entry_restriction.dart';
import '../home/home_paths.dart';
import 'onboarding_flow.dart';
import 'onboarding_gate.dart';
import 'onboarding_paths.dart';
import 'personal_book.dart';
import 'screens/s0_0_splash_screen.dart';
import 'screens/s0_05_welcome_screen.dart';
import 'screens/s0_06_start_screen.dart';
import 'screens/s0_1_language_screen.dart';
import 'screens/s0_3_purpose_screen.dart';
import 'screens/s0_4_name_photo_screen.dart';
import 'screens/s0_5_books_safe_screen.dart';
import 'screens/s0_5b_recovery_sheet_screen.dart';
import 'screens/s0_6a1_business_owners_screen.dart';
import 'screens/s0_6a_business_name_screen.dart';
import 'screens/s0_6c_add_another_business_screen.dart';
import 'screens/s0_6d_family_name_screen.dart';
import 'screens/s0_6e_family_members_screen.dart';
import 'screens/s0_6g_trust_name_screen.dart';
import 'screens/s0_6h_trust_members_screen.dart';
import 'screens/s0_8_set_pin_screen.dart';
import 'screens/s0_9_invitation_screen.dart';
import 'widgets/business_opening_host.dart';
import 'widgets/family_opening_host.dart';
import 'widgets/personal_opening_host.dart';
import 'widgets/trust_opening_host.dart';

export 'onboarding_flow.dart' show OnboardingFlow, OnboardingFlowScope;
export 'onboarding_gate.dart'
    show
        OnboardingBack,
        OnboardingBackMirror,
        OnboardingGate,
        handOverToHome,
        previousOnboardingStep;
export 'onboarding_paths.dart';
export 'opening_setup_record.dart' show OpeningSetupRecord;
export 'personal_book.dart' show ensurePersonalBook, personalBookIdOf;
export 'screens/s0_6_opening_balances_screen.dart'
    show FirstRunRow, IndianGroupingFormatter, OpeningBalancesScreen;
export 'widgets/personal_opening_host.dart' show PersonalOpeningHost;
export 'screens/s0_06_start_screen.dart' show StartScreen;
export 'screens/s0_3_purpose_screen.dart' show OnboardingPurpose;
export 'screens/s0_6a1_business_owners_screen.dart'
    show BusinessOwnersScreen, OwnerDraft, ShareMode;
export 'screens/s0_6a_business_name_screen.dart'
    show BusinessDraft, BusinessNameScreen, BusinessOwnershipChoice;
export 'screens/s0_5_books_safe_screen.dart'
    show BooksSafeScreen, KeySyncAvailability;
export 'screens/s0_5b_recovery_sheet_screen.dart'
    show RecoverySheetScreen, RecoverySheetStep;
export 'invitation_gateway.dart'
    show
        DelegatedInvitationGateway,
        FakeInvitationGateway,
        InvitationGateway,
        InvitationGatewayScope;
export 'screens/s0_8_set_pin_screen.dart' show SetPinScreen, SetPinStep;
export 'screens/s0_9_invitation_screen.dart'
    show InvitationScreen, InvitationStep;
export 'screens/s0_6b_business_opening_balances_screen.dart'
    show BusinessOpeningBalancesScreen, OpeningGroup, OpeningRow;
export 'screens/s0_6c_add_another_business_screen.dart'
    show AddAnotherBusinessScreen, AddedBusiness;
export 'screens/s0_6d_family_name_screen.dart'
    show FamilyDraft, FamilyNameScreen;
export 'screens/s0_6e_family_members_screen.dart'
    show FamilyMemberDraft, FamilyMembersScreen;
export 'screens/s0_6f_family_accounts_screen.dart'
    show FamilySharedAccountsScreen;
export 'screens/s0_6g_trust_name_screen.dart' show TrustDraft, TrustNameScreen;
export 'screens/s0_6h_trust_members_screen.dart'
    show TrustMemberDraft, TrustMembersScreen, TrustRole;
export 'screens/s0_6i_trust_accounts_screen.dart' show TrustAccountsScreen;
export 'widgets/business_opening_host.dart' show BusinessOpeningHost;
export 'widgets/family_opening_host.dart' show FamilyOpeningHost;
export 'widgets/trust_opening_host.dart' show TrustOpeningHost;

/// S0.0 at [OnboardingPaths.splash]; S0.1 at [OnboardingPaths.language]; S0.05
/// at [OnboardingPaths.welcome]; S0.3 at [OnboardingPaths.purpose]; S0.4 at
/// [OnboardingPaths.namePhoto]. The splash's `onFinished`, the language
/// screen's `onSelected` and S0.3's `onSelected` all push forward; welcome's
/// `onDone` hands off to S0.2 at [OnboardingPaths.signIn] (auth's screen),
/// wired by main.dart.
///
/// The answers are carried between steps by [onboardingFlow] — S0.4's name is
/// needed again as the first owner row on S0.6a1 (ADR 2026-09-09 §1) and the
/// S0.6a / S0.6a1 answers are needed together at the committing step, where
/// `createBook` runs ([BusinessOpeningHost]).
///
/// S0.4's Continue records the name and goes to **S0.8 set PIN** (13 §5
/// flow F1). S0.8's Continue now goes to **S0.5 keeping your books safe** and on to
/// **S0.5b the recovery sheet** (07 §3.1 steps 5–6, 13's onboarding flow
/// line), and only then takes the branch the purpose card chose. Both steps
/// are skippable and resumable (07 §3.1.1): S0.5's skip and S0.5b's skip land
/// on the same branch step Continue would, and the verified-storage nag
/// (04 §7.4 🔒) is what brings the sheet back.
///
/// The chosen [OnboardingPurpose] is recorded on the flow: the business
/// branch (O6a/O6a1/O6b), the family branch (O6d/O6e/O6f) and the trust
/// branch (O6g/O6h/O6i) all have screens now (U1e, M5).
final OnboardingFlow onboardingFlow = OnboardingFlow();

final List<RouteBase> onboardingRoutes = [
  GoRoute(
    path: OnboardingPaths.splash,
    builder: (context, state) => OnboardingBack(
      onBack: null,
      exits: true,
      child: SplashScreen(
        onFinished: () => context.go(OnboardingPaths.language),
      ),
    ),
  ),
  GoRoute(
    path: OnboardingPaths.language,
    // ⚠️ SPEC (ADR 2026-10-06b ruling 3, "only the first screen may exit"):
    // S0.0 is a launch animation with no input that hands straight on to
    // S0.1, so S0.1 is the first step a person acts on and Back may leave the
    // app from either. Back from S0.1 to S0.0 would only replay the mark and
    // land on S0.1 again — a loop, not a previous step.
    builder: (context, state) => OnboardingBack(
      onBack: null,
      exits: true,
      child: LanguagePickerScreen(
        onSelected: (locale) => context.go(OnboardingPaths.welcome),
      ),
    ),
  ),
  GoRoute(
    path: OnboardingPaths.welcome,
    builder: (context, state) => _chainStep(
      context,
      state,
      WelcomeScreen(onDone: () => context.go(OnboardingPaths.start)),
    ),
  ),
  // ADR 2026-10-05c §1: the front door after the slides. Both doors open the
  // same S0.2; the door rides as a query parameter (never the number, never
  // a ticket — those stay in S0.2's memory).
  GoRoute(
    path: OnboardingPaths.start,
    builder: (context, state) => _chainStep(
      context,
      state,
      StartScreen(
        onNew: () => context.go(OnboardingPaths.signIn),
        onSignIn: () => context.go(OnboardingPaths.signInReturning),
      ),
    ),
  ),
  // 13 §5 flows F1 / F1b: S0.06 → S0.2 → S0.3 (or S0.2a/S0.2b/S0.2e after the
  // code, inside S0.2). Auth's own S0.2 route lands on Home (it is also the
  // forgot-PIN door), so the signup chain mounts the same screen here and
  // carries on to the purpose cards.
  GoRoute(
    path: OnboardingPaths.signIn,
    // System Back presses the back row of whichever S0.2 sub-step is on
    // screen (ADR 2026-10-06b ruling 3): the number step → S0.06, the code
    // step → the number step, *found you* → where it came from, and a step
    // mid-operation (verifying, activating) holds — see
    // [OnboardingBackMirror].
    builder: (context, state) => OnboardingBackMirror(
      child: PhoneOtpScreen(
        key: ValueKey(state.uri.toString()),
        door:
            state.uri.queryParameters[OnboardingPaths.signInDoorParam] ==
                OnboardingPaths.signInDoorReturning
            ? SignInDoor.signIn
            : SignInDoor.newBooks,
        onboardingStep: true,
        onBack: () => context.go(OnboardingPaths.start),
        onDone: (_) => context.go(OnboardingPaths.purpose),
        // F1b's *No, it's lost or reset* (13 §5: S0.2b → S11.6 fork) is
        // **pushed** over this step, so system Back on the fork returns to
        // S0.2b with its answers in place (ruling 3: only the chain's first
        // screen may exit) — `go` would leave the fork alone on the stack.
        onNoOldPhone: () => context.push(RkPaths.recoveryFork),
      ),
    ),
  ),
  GoRoute(
    path: OnboardingPaths.purpose,
    builder: (context, state) => _chainStep(
      context,
      state,
      PurposeScreen(
        // DEBUG ONLY (owner-directed, 4 Oct 2026): null in every release build
        // and whenever the signed-in phone is not on the demo roster. Continue
        // carries on exactly as a purpose choice would — S0.4 name (prefilled
        // with the roster name), S0.8 PIN, S0.5/S0.5b — and, with no purpose
        // recorded, [afterSetPin] then lands on Home rather than a branch
        // wizard that would make another book.
        debugDemoCard: demoPurposeCard(
          onContinue: (name) {
            onboardingFlow.setYourName(name);
            context.go(OnboardingPaths.namePhoto);
          },
        ),
        onSelected: (purpose) {
          onboardingFlow.setPurpose(purpose);
          context.go(OnboardingPaths.namePhoto);
        },
      ),
    ),
  ),
  GoRoute(
    path: OnboardingPaths.namePhoto,
    builder: (context, state) => _chainStep(
      context,
      state,
      NamePhotoScreen(
        initialName: onboardingFlow.yourName,
        // 07 §3.1 step 4's answer is carried forward, not dropped: S0.6a1 tags
        // the first owner row with it (ADR 2026-09-09 §1).
        //
        // Desk 164: the person's personal book is made here, the moment its
        // name is known (13 §2.1; canvas 1 "One private book is already
        // made") — see `personal_book.dart` for why here. Started, not
        // awaited: S0.8 does not need it, and S0.6's host finds it (or the
        // creation still in flight) before it fills the book's Cash A/c.
        onSubmit: (name, photo) {
          onboardingFlow.setYourName(name);
          unawaited(_makePersonalBook(context, onboardingFlow.yourName));
          context.go(OnboardingPaths.setPin);
        },
      ),
    ),
  ),
  GoRoute(
    path: OnboardingPaths.setPin,
    // System Back is the screen's own (it mirrors its back button: the
    // confirm step starts over, the choose step goes back to S0.4, a save in
    // flight holds) — see SetPinScreen.build.
    builder: (context, state) => SetPinScreen(
      onDone: () => context.go(OnboardingPaths.booksSafe),
      onBack: () => context.go(OnboardingPaths.namePhoto),
    ),
  ),
  // 07 §3.1 step 5 🔒 — backup is configured here, at signup. Continue and
  // the sheet action both lead to S0.5b; the skip (shown when key sync is
  // unavailable, where the sheet is the primary action) goes to the branch.
  //
  // ⚠️ SPEC: whether iCloud Keychain / Block Store is available is a platform
  // question no seam answers in this build, so no `keySyncAvailable` callback
  // is wired here and the screen takes 04 §7.0's default (on). Same for the
  // destination: naming the wrong cloud would be worse than the generic line.
  GoRoute(
    path: OnboardingPaths.booksSafe,
    builder: (context, state) => _chainStep(
      context,
      state,
      BooksSafeScreen(
        onContinue: () => context.go(OnboardingPaths.recoverySheet),
        onSheet: () => context.go(OnboardingPaths.recoverySheet),
        onSkip: () => goOnboarding(context, afterSetPin(onboardingFlow)),
      ),
    ),
  ),
  // 07 §3.1 step 6 / 04 §7.4 🔒. Generation, print/save and the scan-back
  // check are seams with no implementation in this build, so none is wired:
  // the screen shows its intro with *Make the sheet* disabled **and its
  // reason** (13 §4.3; desk 171) rather than pretending a sheet was made.
  //
  // ⚠️ SPEC / open (P1A, desk 171) — the cause, from the code, not GATE1 and
  // not a missing printing dependency (`pdf` and `printing` are both in
  // app/pubspec.yaml). Nothing in the build makes a sheet: (1) `core_crypto`
  // seals the UMK under RK (`sealUmkUnderRecoveryKey`) but defines no byte
  // framing for `SealedRecoveryBlob`, and `POST /sync-meta/recovery/sheet`
  // (`RecoveryApi.publishSheet`) stores one opaque byte string — choosing the
  // layout is core_crypto behaviour (bootstrap.dart's rung-3 note says the
  // same), and a sheet published under a guessed framing would be a printed
  // key nobody can open later; (2) no sheet PDF layout (04 §7.4: QR +
  // Crockford fallback, EN + the user's language) and no scan-back verifier
  // exist. The UMK itself is reachable (`LocalLedger.keyMaterial.umk`), so
  // (1) is the blocker. Both are outside onboarding.
  GoRoute(
    path: OnboardingPaths.recoverySheet,
    builder: (context, state) => _chainStep(
      context,
      state,
      RecoverySheetScreen(
        onVerifiedChanged: onboardingFlow.setRecoverySheetVerified,
        onDone: () => goOnboarding(context, afterSetPin(onboardingFlow)),
        onSkip: () => goOnboarding(context, afterSetPin(onboardingFlow)),
      ),
    ),
  ),
  // The business branch (07 §3.1.1 O6a → O6b). S0.6a's ownership answer is
  // what forks it: *Shared with others* goes through S0.6a1 first (ADR
  // 2026-09-09 §1), *Just me* straight to S0.6b. The answers live on
  // [onboardingFlow] rather than in `extra`, because the committing step
  // needs S0.6a *and* S0.6a1 together and a resumed step (07 §3.1.1) must not
  // create a second book.
  //
  // ⚠️ SPEC: the S0.6a1 **share weights** are collected and shown but have
  // nowhere to persist — `BookConfig` (packages/data) carries `ownership` but
  // no partner ratio, and `PartnerShare` takes its weight per call at
  // distribution time. They stay on [onboardingFlow] for this build; giving
  // them a home is a `packages/data` change and is in the lane report.
  GoRoute(
    path: OnboardingPaths.business,
    builder: (context, state) => _chainStep(
      context,
      state,
      BusinessNameScreen(
        startDate: bookStartDateOf(context),
        initial: onboardingFlow.business,
        onSubmit: (draft) {
          onboardingFlow.setBusiness(draft);
          context.go(
            draft.ownership == BusinessOwnershipChoice.shared
                ? OnboardingPaths.businessOwners
                : OnboardingPaths.businessOpening,
          );
        },
      ),
    ),
  ),
  GoRoute(
    path: OnboardingPaths.businessOwners,
    builder: (context, state) => _chainStep(
      context,
      state,
      BusinessOwnersScreen(
        yourName: onboardingFlow.yourName,
        initialOwners: onboardingFlow.owners.isEmpty
            ? null
            : onboardingFlow.owners,
        onSubmit: (owners) {
          onboardingFlow.setOwners(owners);
          context.go(OnboardingPaths.businessOpening);
        },
        // ADR 2026-09-09 §3: not a skip — back to S0.6a on the *Just me* branch.
        onJustMeAfterAll: () {
          final draft = onboardingFlow.business;
          if (draft != null) {
            onboardingFlow.setBusiness(
              BusinessDraft(
                name: draft.name,
                ownership: BusinessOwnershipChoice.justMe,
                fyStartMonth: draft.fyStartMonth,
              ),
            );
          }
          context.go(OnboardingPaths.business);
        },
      ),
    ),
  ),
  GoRoute(
    path: OnboardingPaths.businessOpening,
    builder: (context, state) => BusinessOpeningHost(
      flow: onboardingFlow,
      startDate: bookStartDateOf(context),
      // Skipped or saved, the *My business* card goes on to S0.6c (07 §3.1.1,
      // ADR 2026-10-04c §1) — see [afterBusinessOpening].
      onDone: () => goOnboarding(context, afterBusinessOpening(onboardingFlow)),
      onBack: _backFrom(context, state),
    ),
  ),
  // S0.6c — the loop control of the multi-business branch (07 §3.1.1 O6c,
  // 13 §3.2). *Add another* rewinds the branch to S0.6a for a fresh business:
  // the flow's cursor moves past the finished one, so the S0.6a screen opens
  // blank and the committing step creates a second book rather than reusing
  // the first (07 §3.1.1 — resumable, never duplicated).
  GoRoute(
    path: OnboardingPaths.businessAnother,
    builder: (context, state) => _chainStep(
      context,
      state,
      AddAnotherBusinessScreen(
        businesses: [
          for (final entry in onboardingFlow.businesses)
            if (entry.draft case final draft?)
              AddedBusiness(name: draft.name, fyStartMonth: draft.fyStartMonth),
        ],
        onAddAnother: () {
          onboardingFlow.addAnotherBusiness();
          context.go(OnboardingPaths.business);
        },
        // 07 §3.1.1 🔒 *My business* row: O6c → **O6** your own → checklist.
        // *No, that's all* and the skip both go on to S0.6 (desk 172), since
        // 07 §3.1.1 makes every branch step skippable.
        onDone: () => context.go(OnboardingPaths.openingBalances),
        onSkip: () => context.go(OnboardingPaths.openingBalances),
      ),
    ),
  ),
  // The family branch (07 §3.1.1 O6d → O6e → O6f). Every step is skippable
  // and resumable; S0.6e's *Skip for now* is always visible (🔒) and simply
  // carries an empty (or partial) member list forward rather than blocking.
  GoRoute(
    path: OnboardingPaths.family,
    builder: (context, state) => _chainStep(
      context,
      state,
      FamilyNameScreen(
        startDate: bookStartDateOf(context),
        initial: onboardingFlow.family,
        onSubmit: (draft) {
          onboardingFlow.setFamily(draft);
          context.go(OnboardingPaths.familyMembers);
        },
      ),
    ),
  ),
  GoRoute(
    path: OnboardingPaths.familyMembers,
    builder: (context, state) => _chainStep(
      context,
      state,
      FamilyMembersScreen(
        yourName: onboardingFlow.yourName,
        initialMembers: onboardingFlow.familyMembers.isEmpty
            ? null
            : onboardingFlow.familyMembers,
        onSubmit: (members) {
          onboardingFlow.setFamilyMembers(members);
          context.go(OnboardingPaths.familyAccounts);
        },
        onSkip: () => context.go(OnboardingPaths.familyAccounts),
      ),
    ),
  ),
  GoRoute(
    path: OnboardingPaths.familyAccounts,
    builder: (context, state) => FamilyOpeningHost(
      flow: onboardingFlow,
      startDate: bookStartDateOf(context),
      // Skipped or saved, the next stop is S0.6 (07 §3.1.1 🔒 *My family*
      // row: O6f → O6 your own → checklist; desk 172).
      onDone: () => context.go(OnboardingPaths.openingBalances),
      onBack: _backFrom(context, state),
    ),
  ),
  // The trust branch (07 §3.1.1 O6g → O6h → O6i). Every step is skippable
  // and resumable; S0.6h's *Skip for now* is always visible (🔒) and simply
  // carries an empty (or partial) committee list forward rather than
  // blocking — the same shape as the family branch's S0.6e.
  GoRoute(
    path: OnboardingPaths.trust,
    builder: (context, state) => _chainStep(
      context,
      state,
      TrustNameScreen(
        startDate: bookStartDateOf(context),
        initial: onboardingFlow.trust,
        onSubmit: (draft) {
          onboardingFlow.setTrust(draft);
          context.go(OnboardingPaths.trustMembers);
        },
      ),
    ),
  ),
  GoRoute(
    path: OnboardingPaths.trustMembers,
    builder: (context, state) => _chainStep(
      context,
      state,
      TrustMembersScreen(
        yourName: onboardingFlow.yourName,
        initialMembers: onboardingFlow.trustMembers.isEmpty
            ? null
            : onboardingFlow.trustMembers,
        onSubmit: (members) {
          onboardingFlow.setTrustMembers(members);
          context.go(OnboardingPaths.trustAccounts);
        },
        onSkip: () => context.go(OnboardingPaths.trustAccounts),
      ),
    ),
  ),
  GoRoute(
    path: OnboardingPaths.trustAccounts,
    builder: (context, state) => TrustOpeningHost(
      flow: onboardingFlow,
      startDate: bookStartDateOf(context),
      // Skipped or saved, the next stop is S0.6 (desk 172: shown once after
      // the branch steps on every path, canvas 1 "All five paths converge
      // here").
      //
      // ⚠️ SPEC (owner, open P1A): 07 §3.1.1 🔒's *Our trust* row still
      // reads O6i → checklist with no O6, while 13 §5 F1 and canvas 1 put
      // S0.6 after every branch. Desk 172 (owner-ruled 6 Oct, PLAN.md) rules
      // S0.6 "once in the chain, after the branch steps" on every path, and
      // this follows it; but the ruling is recorded only in PLAN.md — no ADR
      // amends the 🔒 row and no ⟦tests⟧ marker names F1-1006c-*. This lane
      // may not write docs/, so the amendment is the orchestrator's (open
      // P1A). S0.6 is skippable, so a trust treasurer with no personal
      // figures loses one tap.
      onDone: () => context.go(OnboardingPaths.openingBalances),
      onBack: _backFrom(context, state),
    ),
  ),
  // S0.6 Opening balances · first run (desk 172). Once in the chain, after
  // the branch steps; *Finish* and *Skip for now* both hand over to Home with
  // the S0.7 checklist (ADR 2026-10-06b ruling 1: this is the chain's last
  // step). Reopened later from the checklist's *Opening balances* row, when
  // the install is already onboarded: Back then returns to Home.
  GoRoute(
    path: OnboardingPaths.openingBalances,
    builder: (context, state) {
      final chainBack = _backFrom(context, state);
      return PersonalOpeningHost(
        flow: onboardingFlow,
        startDate: bookStartDateOf(context),
        onDone: () => handOverToHome(context),
        onBack: () {
          if (AppSettingsScope.read(context)?.onboarded ?? false) {
            context.go(HomePaths.home);
          } else {
            chainBack();
          }
        },
      );
    },
  ),
  // S0.9 Invitation accept — 13 §3.2's deep-link entry. It is a root route,
  // not a step of flow F1: a joiner arrives here from a WhatsApp/SMS link,
  // possibly before any of S0.1–S0.8 has run.
  //
  // ⚠️ WIRE — three things belong to the orchestrator's router.dart, not here:
  //   1. the **deep-link mapping**: the external `https://…/join/<id>` (or
  //      custom-scheme) URL onto [OnboardingPaths.invitation] with the id in
  //      the `invite` query parameter;
  //   2. an **[InvitationGatewayScope]** above the router (bootstrap.dart
  //      mounts it), bound with [DelegatedInvitationGateway]: `offers` to
  //      `MembersRepository.myInvites`, `accept` to
  //      `InviteNonceRelay.acceptInvite` — not `MembersRepository
  //      .acceptInvite`, which would drop the relayed nonce S9.2 pairs by
  //      `invite_id` (ADR 2026-09-25b §3) — and `pending` to
  //      `MembersSnapshot.pendingBooks`. Without the scope S0.9 falls back to
  //      an empty fake, which is the safe state but never a real invitation;
  //   3. `onConfirmNumber` currently goes straight to S0.2, which **loses the
  //      link**. The return hop (come back to this path with the same invite
  //      id after the OTP) needs a redirect in router.dart; ⚠️ SPEC: neither
  //      13 nor 07 says where a joiner lands after the OTP step of 13 §3.2's
  //      `accept → OTP → …`, and this lane does not invent it.
  GoRoute(
    path: OnboardingPaths.invitation,
    builder: (context, state) => InvitationScreen(
      inviteId: state.uri.queryParameters[OnboardingPaths.invitationIdParam],
      // ⚠️ SPEC (ADR 2026-10-06b ruling 1): S0.9 is not a step of F1 or F1b,
      // so *Open my book* is not a hand-over. On an onboarded install it is
      // Home as before; on one that is not, the gate resumes the chain (an
      // invitee still sets a name and a PIN before Home).
      onOpenMyBook: () => context.go(HomePaths.home),
      onConfirmNumber: () => context.go(AuthPaths.phoneOtp),
      // The F11 ladder (13 §5) is features/devices' and features/auth's, not
      // this lane's; until router.dart names its entry the action is absent
      // rather than wrong — a disabled button with its reason on screen, not
      // a door to nowhere (07 §1 rule 6).
      onSetUpPhone: null,
      // Desk 109: a phone the invite routes refuse as not live can still open
      // S11 locally — the same push S15.4 and the menu make.
      onOpenDevices: () => context.push(DevicesPaths.devices),
    ),
  ),
];

/// The day a book created now would begin (ADR 2026-09-09d §4) — read from the
/// app's injected clock, never `DateTime.now()`.
LocalDate bookStartDateOf(BuildContext context) {
  final now = RkScope.of(context).now();
  return LocalDate(now.year, now.month, now.day);
}

/// Where S0.8's chain (through S0.5 and S0.5b) goes next: the branch step the
/// purpose card chose (07 §3.1.1), or S0.6 for *Myself*.
/// Where the business branch goes after S0.6b (07 §3.1.1 🔒 branch table, as
/// amended by ADR 2026-10-04c §1): the one **My business** card reads O6a →
/// O6b → **O6c** *Add another business?* every time — one business or many.
/// A one-business person answers *No, that's all* there (one tap) and goes on
/// exactly as the retired *My shop* card did. Any other purpose reaching here
/// (none does today) falls through to Home's checklist.
String afterBusinessOpening(OnboardingFlow flow) =>
    flow.purpose == OnboardingPurpose.businesses
    ? OnboardingPaths.businessAnother
    : OnboardingPaths.openingBalances;

String afterSetPin(OnboardingFlow flow) => switch (flow.purpose) {
  OnboardingPurpose.businesses => OnboardingPaths.business,
  OnboardingPurpose.family => OnboardingPaths.family,
  OnboardingPurpose.trust => OnboardingPaths.trust,
  // *Myself* — and a chain whose purpose a cold start lost, or the debug demo
  // card's — goes straight on to S0.6 (07 §3.1.1 🔒 *Myself* row: O6 your
  // own → checklist; desk 172).
  _ => OnboardingPaths.openingBalances,
};

/// Wraps a chain step whose screen has no back affordance of its own: system
/// Back goes to [previousOnboardingStep] (ADR 2026-10-06b ruling 3).
Widget _chainStep(BuildContext context, GoRouterState state, Widget step) =>
    OnboardingBack(onBack: _backFrom(context, state), child: step);

/// System Back on [state]'s step: the chain's previous step
/// ([previousOnboardingStep]), resolved **at the press** — a committing step
/// whose book was created while it was on screen holds from then on. Never
/// null, so a step that holds still keeps Back from closing the app.
VoidCallback _backFrom(BuildContext context, GoRouterState state) {
  final path = state.uri.path;
  return () {
    final previous = previousOnboardingStep(path, onboardingFlow);
    if (previous != null) context.go(previous);
  };
}

/// Desk 164: makes the person's personal book at S0.4 ([ensurePersonalBook]).
/// Everything it needs is read from [context] before the first await. A
/// read-only install (S12.5, ADR 2026-09-24b §13) or a failure makes nothing
/// here — S0.6's host tries again in the open, with its sheet and its retry.
Future<void> _makePersonalBook(BuildContext context, String name) async {
  final ledger = LedgerScope.maybeOf(context);
  if (ledger == null || name.isEmpty) return;
  final sources = entryRestrictionSourcesOf(context);
  final startDate = bookStartDateOf(context);
  try {
    if (await entryRestrictionFor(sources, const <String>[]) != null) return;
    await ensurePersonalBook(ledger, name: name, startDate: startDate);
  } on Object {
    // Nothing logged (rule 4); S0.6 carries the retry.
  }
}
