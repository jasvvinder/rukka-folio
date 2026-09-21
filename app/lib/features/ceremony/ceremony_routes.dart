// Ceremony feature routes (features/README) — S9.2, S9.3, S9.4, mounted on the
// root navigator: the ceremony covers the tab bar, like entry and detail.
//
// S9.4 is reached only from S9.3, and only by replacing it (`pushReplacement`):
// a mismatch has no way back to the comparison it failed (04 §6.3 🔒).
//
// **Where the repositories come from.** Each builder asks the installed
// [CeremonyScope] to *open* the side it renders, and shows the waiting
// placeholder until it has one. A route never constructs a ceremony itself
// and never passes an id it invented: S9.3's path segment is the subject's
// **user id**, read straight from the URL, and the factory refuses anything
// it cannot back with a real 0007 session.
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/gen/app_localizations.dart';
import '../../shared/app_scope.dart';
import '../../shared/widgets/placeholder_screen.dart';
import 'camera_scanner.dart';
import 'ceremony_paths.dart';
import 'ceremony_repository.dart';
import 'ceremony_scope.dart';
import 'ceremony_sessions.dart';
import 'screens/s9_2_show_my_code_screen.dart';
import 'screens/s9_3_verify_member_screen.dart';
import 'screens/s9_4_mismatch_screen.dart';

export 'camera_scanner.dart';
export 'ceremony_api.dart';
export 'ceremony_paths.dart';
export 'ceremony_repository.dart';
export 'ceremony_scope.dart';
export 'ceremony_sessions.dart';
export 'screens/s9_2_show_my_code_screen.dart';
export 'screens/s9_3_verify_member_screen.dart';
export 'screens/s9_4_mismatch_screen.dart';

final List<RouteBase> ceremonyRoutes = [
  GoRoute(
    path: CeremonyPaths.showMyCode,
    builder: (context, state) => const _ShowMyCodeRoute(),
  ),
  GoRoute(
    path: CeremonyPaths.verifyMember,
    builder: (context, state) => _VerifyMemberRoute(
      // ⚠️ SPEC — the router still spells this parameter `:invite`
      // (`shared/router.dart`), but a ceremony session is keyed by
      // `subject_user` (migration 0007) and three of 04 §6's four uses
      // (guardian activation, device linking, trustee handover) have no
      // invite at all. The VALUE carried here is the subject's user id;
      // renaming the segment belongs to the lane that owns `shared/router`.
      subjectUserId: state.pathParameters[CeremonyPaths.subjectParameter] ?? '',
    ),
  ),
  GoRoute(
    path: CeremonyPaths.mismatch,
    builder: (context, state) => const VerificationMismatchScreen(),
  ),
];

/// S9.2, once the invitee's own side can be opened.
class _ShowMyCodeRoute extends StatelessWidget {
  const _ShowMyCodeRoute();

  @override
  Widget build(BuildContext context) {
    final scope = CeremonyScope.maybeOf(context);
    final l10n = AppLocalizations.of(context);
    return _CeremonyGate<ShowMyCodeRepository>(
      ready: scope?.showMyCode,
      open: () => (scope?.openings ?? const NoCeremonySessions()).showMyCode(),
      waiting: RkPlaceholderScreen(
        title: l10n.ceremonyShowTitle,
        body: l10n.ceremonyShowLoading,
      ),
      builder: (context, repository) => ShowMyCodeScreen(
        repository: repository,
        now: RkScope.of(context).now,
      ),
    );
  }
}

/// S9.3, once the verifier's side can be opened against a real subject.
class _VerifyMemberRoute extends StatelessWidget {
  const _VerifyMemberRoute({required this.subjectUserId});

  final String subjectUserId;

  @override
  Widget build(BuildContext context) {
    final scope = CeremonyScope.maybeOf(context);
    final l10n = AppLocalizations.of(context);
    return _CeremonyGate<VerifyMemberRepository>(
      ready: scope?.verifyMember,
      open: () => (scope?.openings ?? const NoCeremonySessions()).verifyMember(
        subjectUserId,
      ),
      waiting: RkPlaceholderScreen(
        title: l10n.ceremonyVerifyTitle,
        body: l10n.ceremonyVerifyChecking,
      ),
      builder: (context, repository) => VerifyMemberScreen(
        repository: repository,
        scanner: scope?.scanner ?? NoCameraScanner(),
        onMismatch: () => context.pushReplacement(CeremonyPaths.mismatch),
        onVerified: () => context.pop(),
      ),
    );
  }
}

/// Resolves one side of the ceremony exactly once per set of dependencies.
///
/// [ready] short-circuits the factory — a caller that already holds the side
/// hands it straight through. Otherwise [open] runs once; while it is running,
/// and for good if it answers null, [waiting] is what the route renders. There
/// is no error screen here on purpose: opening a side reads seams, not the
/// ceremony itself, and a failure to open is indistinguishable to the user
/// from *not ready yet* — the ceremony's own failures belong to the screens,
/// which state them (04 §6.3 has no silent path).
class _CeremonyGate<T extends Object> extends StatefulWidget {
  const _CeremonyGate({
    required this.ready,
    required this.open,
    required this.waiting,
    required this.builder,
    super.key,
  });

  final T? ready;
  final Future<T?> Function() open;
  final Widget waiting;
  final Widget Function(BuildContext context, T repository) builder;

  @override
  State<_CeremonyGate<T>> createState() => _CeremonyGateState<T>();
}

class _CeremonyGateState<T extends Object> extends State<_CeremonyGate<T>> {
  Future<T?>? _opening;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Once per dependency change — an inherited scope that swaps its factory
    // re-opens, a rebuild that changes nothing does not. A second `open()`
    // would mint a second 0007 session for the same screen.
    _opening ??= widget.ready != null
        ? Future<T?>.value(widget.ready)
        : widget.open();
  }

  @override
  void didUpdateWidget(_CeremonyGate<T> old) {
    super.didUpdateWidget(old);
    if (!identical(widget.ready, old.ready)) {
      _opening = widget.ready != null
          ? Future<T?>.value(widget.ready)
          : widget.open();
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<T?>(
    future: _opening,
    builder: (context, snapshot) {
      final repository = snapshot.data;
      if (repository == null) return widget.waiting;
      return widget.builder(context, repository);
    },
  );
}
