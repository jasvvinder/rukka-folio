// Help & diagnostics routes (features/README "Routes"). Mounted on the
// **root** navigator: S17 is reached by pushing [HelpPaths.root] from the
// *Help* Menu row (07 §2 🔒, 13 §3.2 row S17), and the three pages sit one
// level under it — nothing deeper than two levels from a bottom-bar root
// (13 §3.1).
//
// The screens own no navigation of their own; every door is a callback the
// route fills in (the `legalRoutes` convention). That keeps each page
// pumpable in a widget test with no router, and keeps the paths in one place.
//
// ⛔ No route here launches a URL. S17.3's `onOpenChannel` and S17.4's
// `sender` are both left **null**: `url_launcher` is not in the app's
// pubspec while ADR 2026-09-19 is unratified, so the WhatsApp door states
// why it will not open and *Copy the report* carries the person forward
// (07 §1 rule 6 🔒). `device` is null for the same reason — the app version
// and the phone's software version need a platform plugin, and a field the
// app cannot read is omitted from the report rather than invented.
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import 'help_paths.dart';
import 'screens/s17_2_faq_article_screen.dart';
import 'screens/s17_3_contact_screen.dart';
import 'screens/s17_4_diagnostics_screen.dart';
import 'screens/s17_help_screen.dart';

export 'diagnostics_report.dart';
export 'diagnostics_seams.dart';
export 'faq_catalog.dart';
export 'help_paths.dart';
export 'screens/s17_2_faq_article_screen.dart';
export 'screens/s17_3_contact_screen.dart';
export 'screens/s17_4_diagnostics_screen.dart';
export 'screens/s17_help_screen.dart';

/// The Help & diagnostics feature's routes.
final List<RouteBase> helpRoutes = [
  GoRoute(
    path: HelpPaths.root,
    builder: (context, state) => HelpScreen(
      // No `extra`: an answer opened from the hub has exactly one page
      // between it and the hub, which is [_ArticleEntry.hub]'s reading and
      // also a deep link's (the match list for `/help/answer/x` is the hub
      // page plus the answer page).
      onOpenArticle: (id) => context.push(HelpPaths.articleOf(id)),
      onOpenContact: () => context.push(HelpPaths.contact),
      onOpenDiagnostics: () => context.push(HelpPaths.diagnostics),
    ),
    routes: [
      GoRoute(
        path: 'answer/:${HelpPaths.articleParam}',
        builder: (context, state) => FaqArticleScreen(
          id: state.pathParameters[HelpPaths.articleParam] ?? '',
          onBackToHub: () => _backToHub(context, _entryOf(state)),
          onOpenContact: () => context.push(HelpPaths.contact),
        ),
      ),
      GoRoute(
        path: 'contact',
        builder: (context, state) => ContactSupportScreen(
          onOpenDiagnostics: () => context.push(HelpPaths.diagnostics),
          // Two pages then stand between the answer and the hub, and
          // *Read the other questions* must clear both of them.
          onOpenArticle: (id) => context.push(
            HelpPaths.articleOf(id),
            extra: _ArticleEntry.contact,
          ),
        ),
      ),
      GoRoute(
        path: 'diagnostics',
        builder: (context, state) => const SendDiagnosticsScreen(),
      ),
    ],
  ),
];

/// How S17.2 was reached — i.e. how many pages stand between the answer and
/// the hub.
///
/// S17.2's *Read the other questions* and its missing-answer *Back to Help*
/// both mean the hub, and the hub is **already on the stack**: an answer is
/// only ever opened from the hub or from Contact support, which is itself a
/// child of the hub, and a deep link into `/help/answer/x` builds the hub's
/// page underneath it. So the way back is to pop, not to navigate.
enum _ArticleEntry {
  /// Hub → answer, and a deep link straight to the answer.
  hub(1),

  /// Hub → Contact support → answer.
  contact(2);

  const _ArticleEntry(this.pagesAboveHub);

  /// Pages sitting above the hub when the answer is on top.
  final int pagesAboveHub;
}

_ArticleEntry _entryOf(GoRouterState state) {
  final extra = state.extra;
  return extra is _ArticleEntry ? extra : _ArticleEntry.hub;
}

/// Back to the hub by popping the pages above it.
///
/// Not `push`, which leaves a second hub on the stack, and **not**
/// `pushReplacement`, which was the defect here: go_router 17.5.0 documents
/// it as replacing *the top-most page of the page stack*
/// (`go_router/lib/src/router.dart`), so `[/help, /help/answer/x]` became
/// `[/help, /help]` — two hubs, and a system Back gesture that appeared to do
/// nothing because it revealed the same page (07 §1 rule 6 🔒).
void _backToHub(BuildContext context, _ArticleEntry entry) {
  final router = GoRouter.of(context);
  if (!router.canPop()) {
    // Nothing above the answer at all — the only reading left is that the
    // hub is not on this stack, so navigate to it rather than stranding the
    // reader on the answer.
    router.go(HelpPaths.root);
    return;
  }
  for (var i = 0; i < entry.pagesAboveHub && router.canPop(); i++) {
    router.pop();
  }
}
