// The draft-activity registry (07 §5.6 🔒, ADR 2026-09-05 §7): the idle lock
// is "suppressed while a draft has digits typed", so the shell — which owns
// the timers — needs a signal out of whichever screen is holding a half-typed
// entry. This is that seam, and it lives on the shell side on purpose: the
// entry flow reports into it, the shell reads it, and neither imports the
// other.
//
// A screen reports under its own `owner` token (usually `this`), so two
// screens cannot clear each other's flag, and clears it in `dispose`. Nothing
// here knows what was typed — only that something was.
import 'package:flutter/widgets.dart';

/// Who is currently holding a draft with digits in it.
class DraftActivity extends ChangeNotifier {
  final Set<Object> _typing = <Object>{};

  /// True while at least one screen reports digits in its draft.
  bool get hasDigits => _typing.isNotEmpty;

  /// Reports whether [owner]'s draft has digits in it right now.
  void report(Object owner, {required bool hasDigits}) {
    final before = _typing.length;
    if (hasDigits) {
      _typing.add(owner);
    } else {
      _typing.remove(owner);
    }
    if (_typing.length != before) notifyListeners();
  }

  /// Forgets [owner] — called from a screen's `dispose`.
  void clear(Object owner) => report(owner, hasDigits: false);
}

/// Hands the registry down the tree. A screen reads it with [maybeOf] and
/// carries on normally when the shell mounted none (widget tests, previews).
class DraftActivityScope extends InheritedNotifier<DraftActivity> {
  /// Wraps [child] with [activity].
  const DraftActivityScope({
    super.key,
    required DraftActivity activity,
    required super.child,
  }) : super(notifier: activity);

  /// The nearest registry, or null.
  static DraftActivity? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<DraftActivityScope>()
      ?.notifier;
}
