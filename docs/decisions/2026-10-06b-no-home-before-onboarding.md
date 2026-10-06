# ADR 2026-10-06b — The app never lands on Home until sign-up or sign-in is finished

On 6 Oct 2026 the owner ran a fresh install on the Android emulator. At any onboarding step, the system Back button
closed the app, and reopening it showed Home with *"Couldn't load your position"*. Reproduced the same day on `rf_min`.
There were two causes:
- `main.dart:167` builds the router with no start location, so it falls back to `RkPaths.home` (`router.dart:167`). The
  first-run chain (13 §5 F1) was reached only because `DEMO=1 scripts/run_dev.sh` injects `--route /onboarding/splash`.
  Any other launch of an install with no account opened Home. A store install would never have seen sign-up.
- Every onboarding step navigates with `context.go(…)` (`onboarding_routes.dart:108-267`), which replaces the stack, so
  system Back had nothing to pop and closed the activity.

**Owner ruled, 6 Oct 2026:** *"Until the onboarding/signup/signin it should not land technically on Home."*

## Rulings 🔒 ⟦tests: n/a — container heading; each ruling below carries its own marker⟧

### 1. Home is unreachable until onboarding is finished 🔒 ⟦tests: F1-1006b-1 @M13⟧
- An install is **onboarded** only once its sign-up chain (13 §5 F1) or its sign-in path (F1b, ADR 2026-10-05c) has
  handed over to Home through the chain's own last step. This is recorded once, on the device, at that hand-over.
- Until then, **every** route to Home or the tab shell is redirected into the chain. That covers a cold start, a launch
  from the launcher or recents, a deep link, a notification tap and a back stack. No launch-time argument is needed.
- After onboarding, a launch goes through the lock (S15, 07 §5.6) to Home as today.

### 2. A cold start resumes the chain, never restarts it from scratch without need 🔒 ⟦tests: F1-1006b-2 @M13⟧
- With no account on the device, the app starts at S0.0 Splash.
- With an account but onboarding unfinished, it resumes at the **first step not yet completed** in the order of 13 §5
  F1/F1b. Steps that leave nothing on the device (language, welcome) may simply be shown again.
- ⚠️ SPEC (conservative reading, owner may refine): steps whose result is saved (S0.2 account, S0.4 name, S0.8 PIN,
  the purpose choice) are not asked again. The step after the last saved one is shown.

### 3. System Back follows the chain 🔒 ⟦tests: F1-1006b-3 @M13⟧
- On every onboarding step, Android system Back (and the iOS edge swipe, where the screen allows it) does exactly what
  that step's own back affordance does: it returns to the previous step of the chain.
- Only on the **first** screen of the chain may Back leave the app. A step without a meaningful previous step must hold
  its place rather than exit, for example while a code is being verified.
- Leaving the app mid-chain and coming back resumes per ruling 2. It never lands on Home.

## Consequences
- **Code (lane ONB1):** a launch gate in the router (redirect) driven by an *onboarded* flag kept with the app's other
  per-install state; the chain records that flag at its hand-over to Home; resume logic per ruling 2; system Back wired
  per step (the steps' existing `onBack` callbacks are the authority).
- **Tests:**
  - F1-1006b-1: Home, tabs and deep links redirect while not onboarded.
  - F1-1006b-2: cold start with no account → S0.0; with an account mid-chain → the right step.
  - F1-1006b-3: Back on each step → the previous step; Back on the first screen → exit allowed.
  Plus an emulator check: Back mid-chain, reopen from the launcher, and land in the chain, not on Home.
- **Docs:** 07 §3.1 and 13 §5 F1 carry the cross-reference. Desk 164 (Home with no book) is no longer reachable in the
  normal flow, but stays open for robustness.
