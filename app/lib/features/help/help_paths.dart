// Paths of the Help & diagnostics feature (features/README "Routes": a path
// is declared once and never re-typed).
//
// S17 is a root-navigator hub reached from the *Help* Menu row (07 §2 🔒,
// 13 §3.2 row S17), and the three pages sit one level under it.
//
// ⚠️ SPEC — these are literals, not `RkPaths` aliases. Every other feature
// aliases the single declaration in `shared/router.dart`, but that file
// belongs to the shell lane and no lane may edit another's directory this
// round. `features/account` carried its own literals for exactly the same
// reason until the orchestrator hoisted them. The lane report names the
// `RkPaths` block to add.
//
// ⚠️ SPEC — 13 §3.2 names **S17.3** as S17.4's parent, while 13 §3.1 caps a
// screen at two levels from a bottom-bar root. `/help/contact/diagnostics`
// would be three. The conservative reading keeps the depth rule and mounts
// S17.4 flat at `/help/diagnostics`, reachable from S17.3 (its spec parent,
// which draws the row) *and* from the hub, which the drafted string
// `help.diagnostics.title` ("S17 hub row opening S17.4") already assumes.
library;

abstract final class HelpPaths {
  /// S17 Help — the searchable FAQ hub.
  static const root = '/help';

  /// S17.2 FAQ article, by [FaqArticle.id].
  static const articlePattern = '/help/answer/:id';

  /// The route parameter carrying the answer's id.
  static const articleParam = 'id';

  /// S17.2 for one answer.
  static String articleOf(String id) => '/help/answer/$id';

  /// S17.3 Contact support.
  static const contact = '/help/contact';

  /// S17.4 Send diagnostics.
  static const diagnostics = '/help/diagnostics';
}
