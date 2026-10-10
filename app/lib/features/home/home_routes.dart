// Home feature routes (features/README "Routes", 13 §3.1/§3.2). Home (S1) is a
// bottom-bar root — `homeRoot` is the [RkTabRoot] the app passes to
// `buildRouter(home: homeRoot, ...)`. S1.1 sits one level below it and mounts
// on the *root* navigator so it covers the tab bar, as S4 does.
//
// S1.2/S1.3 (the scope switcher) now live inside [HomeScreen]: it owns a
// [HomeScopeController] for its own lifetime, so the chip appears by itself
// the moment a second book exists (13 §2.2 🔒) and nothing is routed. The
// shell will pass a controller in when scope persists per tab.
//
// The Close card reads [CloseScope], which `bootstrap.dart` installs above the
// router; with no scope (a preview, a test) no card is drawn and Home is
// otherwise unchanged.
//
// S1.4's producer is `Recompute.watchProgress` (packages/data, E-03-29),
// adapted by [rebuildProgressOf] — null when no ledger is in scope, so a
// preview or a test pumped without data still shows the book. The shipped app
// mounts [homeTabRootWith] with the shell's scope controller; it and
// [homeRoot] build through one function, [homeScreenFor], so there is one
// wiring, not two. S1.1 opens over the book Home has in scope
// (`?book=`, [HomePaths.positionOf]); the solo-book fallback is only for a
// path that names none.
import 'package:core_ledger/core_ledger.dart' show EntryKind;
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../shared/router.dart';
import '../ledger/ledger_paths.dart';
import '../onboarding/onboarding_paths.dart';
import '../reports/reports_paths.dart';
import 'home_paths.dart';
import 'home_rebuild.dart';
import 'home_scope.dart';
import 'screens/s1_1_position_drilldown_screen.dart';
import 'screens/s1_home_screen.dart';
import 'widgets/home_cards.dart' show SetupStep;

export 'home_paths.dart';
export 'widgets/home_cards.dart' show SetupStep;

/// S1 Home, wired — the one place S1's doors are spelled. A position row
/// pushes S1.1 on the root navigator; a verb button pushes the S2 entry flow
/// with the verb pre-chosen (07 §4, 07 §5).
///
/// Both tab roots below build through this, so the production root
/// ([homeTabRootWith], which the shell gives its scope holder) and the
/// preview/test root ([homeRoot]) cannot drift apart: a door added here is a
/// door in the shipped app.
Widget homeScreenFor(
  BuildContext context, {
  HomeScopeController? scopeController,
}) => HomeScreen(
  scopeController: scopeController,
  // S1.4's producer (07 §28 🔒).
  rebuildProgress: rebuildProgressOf(context),
  // S1.1 opens over the book in scope, so its total is the row's (02 §9).
  onOpenPosition: (line, bookId) =>
      context.push(HomePaths.positionOf(line, bookId: bookId)),
  onOpenAccount: (accountId) =>
      context.push(LedgerPaths.statementOf(accountId)),
  // S21 Search (07 §25 🔒; 13 §3.2: reached from S3 and S1) — the route the
  // ledger feature owns, over the book S1 has in scope.
  onOpenSearch: (bookId) => context.push(LedgerPaths.searchIn(bookId)),
  onVerb: (kind) => context.push('${RkPaths.entry}?verb=${kind.wire}'),
  // 07 §10 🔒 names the destination ("the Family Reconciliation screen
  // (Menu → Reports)") — the path constant is read from the feature that
  // owns S8.3, never re-spelled here.
  onOpenReconciliation: () => context.push(ReportsPaths.reconciliationLocation),
  // The verification card's door (07 §4 🔒: "tapping through to the full
  // trial balance (S8.2 report viewer)"; desk 193 (c)).
  // ⚠️ SPEC (lane F193H open): the app has no trial-balance surface yet — S8.2
  // renders the Day Book only and S8.1 keeps *Trial Balance* disabled-with-
  // reason until its report lands (ADR 2026-09-12 Consequences: M12). Until
  // then the door opens S8.1 Reports, where the Trial Balance row stands with
  // its reason, rather than leaving the card a dead end or pointing it at the
  // Day Book. When the trial balance gets a location, it replaces this one.
  onOpenTrialBalance: () => context.push(_trialBalanceDoor),
  // The Home *Close card* (07 §13 🔒 bullet 1). The path is S10's or
  // S10.2's, built by the card from `ClosePaths` — the feature that owns
  // the route spells it, never this file. The push is awaited so the card
  // re-reads its state when the closer comes back.
  onOpenClose: (path) async {
    await context.push<void>(path);
  },
  // The S0.7 checklist's doors (07 §3.1 step 7; desk 172; ADR 2026-10-07
  // ruling 3). *Opening balances* reopens S0.6 alone — never the chain; S0.6
  // fills the personal book, so [HomeScreen] offers this door only while that
  // book is in scope (P1A review, finding 6). *Finish <book>* resumes the
  // skipped invite step — S0.6e for the joint fund, S0.6h for a trust — with
  // what was saved kept; on an onboarded install those routes come back to
  // Home. *Write your first entry* is the S2 entry flow on *Money out*, the
  // canvas's "whatever you spent this morning". *Check your recovery sheet*
  // opens S0.5b, which returns Home once onboarded (until RUNG3B it says why
  // the sheet cannot be made yet — a door with its reason, ADR 2026-10-06d).
  // ⚠️ SPEC / open: *Add your family* stays information — the members screen
  // (S9, Menu → Members) is another feature's, and no doc says which book it
  // should open from here.
  setupDoors: const {
    SetupStep.openingBalances,
    SetupStep.finishFamily,
    SetupStep.finishTrust,
    SetupStep.firstEntry,
    SetupStep.recoverySheet,
  },
  onSetupStep: (step) => switch (step) {
    SetupStep.openingBalances => context.push(OnboardingPaths.openingBalances),
    SetupStep.finishFamily => context.push(OnboardingPaths.familyMembers),
    SetupStep.finishTrust => context.push(OnboardingPaths.trustMembers),
    SetupStep.firstEntry => context.push(
      '${RkPaths.entry}?verb=${EntryKind.moneyOut.wire}',
    ),
    SetupStep.recoverySheet => context.push(OnboardingPaths.recoverySheet),
    SetupStep.addFamily => null,
  },
);

/// Where S1's verification card goes: S8.1 Reports, under the Menu tab — see
/// the ⚠️ SPEC note at [homeScreenFor]'s `onOpenTrialBalance`.
const _trialBalanceDoor = '${RkPaths.menu}/${ReportsPaths.root}';

/// S1 as the shipped app mounts it: [homeScreenFor] with the shell's scope
/// holder, so scope outlives the screen (13 §2.2). `bootstrap.dart` passes
/// this as `homeTabRoot`.
RkTabRoot homeTabRootWith(HomeScopeController scopeController) => RkTabRoot(
  builder: (context) =>
      homeScreenFor(context, scopeController: scopeController),
);

/// S1 with a scope holder of its own lifetime — for tests and previews; the
/// same wiring as [homeTabRootWith].
final RkTabRoot homeRoot = RkTabRoot(
  builder: (context) => homeScreenFor(context),
);

/// Root-navigator routes this feature owns beyond its tab root.
final List<RouteBase> homeRoutes = [
  GoRoute(
    path: HomePaths.position,
    builder: (context, state) => PositionDrilldownScreen(
      line:
          PositionLine.parse(state.pathParameters['line']!) ??
          PositionLine.cash,
      accountId: state.uri.queryParameters['account'],
      // The book Home had in scope; absent only on a hand-typed path, where
      // the screen falls back to the solo book.
      bookId: state.uri.queryParameters[HomePaths.bookQuery],
      onOpenAccount: (accountId) =>
          context.push(LedgerPaths.statementOf(accountId)),
    ),
  ),
];
