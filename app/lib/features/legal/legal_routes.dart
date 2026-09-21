// Legal & trust routes (features/README "Routes"). Mounted on the **root**
// navigator: S18 is reached by pushing [LegalPaths.root] from the last Menu
// row under *This app* (07 §2, ADR 2026-09-03 ruling 3), and the four pages
// sit one level under it — nothing deeper than two levels from a bottom-bar
// root (13 §3.1).
//
// The screens own no navigation of their own; every door is a callback the
// route fills in. That keeps each page pumpable in a widget test with no
// router, and keeps the paths in one place (features/README: never re-type
// a path).
import 'package:go_router/go_router.dart';

import 'legal_paths.dart';
import 'screens/s18_1_terms_screen.dart';
import 'screens/s18_2_privacy_screen.dart';
import 'screens/s18_3_what_we_see_screen.dart';
import 'screens/s18_4_licences_screen.dart';
import 'screens/s18_legal_screen.dart';

export 'legal_paths.dart';
export 'screens/s18_1_terms_screen.dart';
export 'screens/s18_2_privacy_screen.dart';
export 'screens/s18_3_what_we_see_screen.dart';
export 'screens/s18_4_licences_screen.dart';
export 'screens/s18_legal_screen.dart';

/// The Legal & trust feature's routes.
final List<RouteBase> legalRoutes = [
  GoRoute(
    path: LegalPaths.root,
    builder: (context, state) => LegalScreen(
      onOpenWhatWeSee: () => context.push(LegalPaths.whatWeSee),
      onOpenPrivacy: () => context.push(LegalPaths.privacy),
      onOpenTerms: () => context.push(LegalPaths.terms),
      onOpenLicences: () => context.push(LegalPaths.licences),
    ),
    routes: [
      GoRoute(
        path: 'what-we-see',
        builder: (context, state) => const WhatWeSeeScreen(),
      ),
      GoRoute(
        path: 'terms',
        builder: (context, state) => TermsScreen(
          // The terms are unpublished, so the page's way on is the page that
          // is published (07 §1 rule 6). `pushReplacement`, not `push`: the
          // reader should not end up with an empty page behind them.
          onOpenWhatWeSee: () => context.pushReplacement(LegalPaths.whatWeSee),
        ),
      ),
      GoRoute(
        path: 'privacy',
        builder: (context, state) => PrivacyScreen(
          onOpenWhatWeSee: () => context.pushReplacement(LegalPaths.whatWeSee),
        ),
      ),
      GoRoute(
        path: 'licences',
        builder: (context, state) => LicencesScreen(
          onBack: () {
            if (context.canPop()) context.pop();
          },
        ),
      ),
    ],
  ),
];
