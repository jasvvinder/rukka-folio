// The platform share sheet for plain text, behind a seam (ADR 2026-09-25 §2;
// the ADR 2026-09-19 precedent — a platform door lives here, never in a
// screen).
//
// S9.1 *Send invite* creates the invite on the server and then hands the
// inviter's own phone a prefilled message with the link; the inviter sends it
// by whatever app they choose. **The server sends nothing** (ADR 2026-09-25
// §2, amending 06 §7 and ADR 2026-09-05c §4). This file is the whole of that
// door.
//
//   * **Text only.** [ShareSheet.shareText] takes the message and nothing
//     else: no file, no recipient, no number. The caller decides the words;
//     the message carries no amount, no book figure and no invitee number
//     (CLAUDE.md rule 4) — this seam never adds any.
//   * **Three outcomes, never a throw.** Which one happened decides the words
//     on the screen, as `ReportDelivery` does for S8.2: a raised sheet is its
//     own confirmation and the platform reports neither send nor cancel, so
//     nothing is claimed after it (07 §1 rule 12); a copy to the clipboard is
//     a fact the screen may state; and *unavailable* means the screen shows the
//     link with its own *Copy* so the invite is never a dead end (07 §1 rules 2
//     and 6).
//
// ⚠️ SPEC (M11-INV2): no package in `app/pubspec.yaml` raises a platform share
// sheet for plain text. `printing` (5.15.0) offers `Printing.sharePdf` — a PDF
// file with an optional body — and nothing for text alone; `url_launcher` is
// ruled to `tel:` (dialer.dart) and `mailto:` (S17.3) only. So the live
// binding in `bootstrap.dart` is [ClipboardShareSheet] — Flutter's own
// `Clipboard`, no new package — until a dependency ADR admits a text share
// sheet (e.g. `share_plus`). Screens import this file and never a package.
library;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// What became of a [ShareSheet.shareText] call.
sealed class ShareOutcome {
  /// Creates an outcome.
  const ShareOutcome();
}

/// The platform share sheet is up; the person chooses where it goes.
///
/// **No confirmation follows this.** The sheet covers the screen and the
/// platform reports neither completion nor cancellation, so any sentence
/// written after it would be a guess (07 §1 rule 12).
final class ShareSheetRaised extends ShareOutcome {
  /// Creates the raised outcome.
  const ShareSheetRaised();
}

/// The text is on the clipboard — a fact the screen may say, with where to
/// paste it.
final class ShareCopied extends ShareOutcome {
  /// Creates the copied outcome.
  const ShareCopied();
}

/// Nothing could be raised. The screen shows the text with its own *Copy*
/// (07 §1 rule 6 — no dead end).
final class ShareUnavailable extends ShareOutcome {
  /// Creates the unavailable outcome.
  const ShareUnavailable();
}

/// Hands plain text to the phone. A seam, so widget tests drive a fake.
abstract interface class ShareSheet {
  /// Offers [text] to the person's own apps. Never throws.
  Future<ShareOutcome> shareText(String text);
}

/// What [ClipboardShareSheet] writes through. Production is
/// `Clipboard.setData`; a test passes a recorder.
typedef ClipboardWriter = Future<void> Function(String text);

Future<void> _setClipboard(String text) =>
    Clipboard.setData(ClipboardData(text: text));

/// The live binding until a text share sheet is admitted by a dependency ADR:
/// the message goes onto the clipboard and the screen says to paste it.
final class ClipboardShareSheet implements ShareSheet {
  /// Creates the binding. [write] defaults to Flutter's `Clipboard.setData`.
  const ClipboardShareSheet({this.write = _setClipboard});

  /// Where the text goes.
  final ClipboardWriter write;

  @override
  Future<ShareOutcome> shareText(String text) async {
    try {
      await write(text);
      return const ShareCopied();
    } on Object {
      // A platform without a clipboard channel is, to the screen, a sheet
      // that could not be raised — it then shows the text and its *Copy*.
      return const ShareUnavailable();
    }
  }
}

/// A recording fake for widget tests.
final class FakeShareSheet implements ShareSheet {
  /// Creates the fake; every call returns [outcome].
  FakeShareSheet({this.outcome = const ShareSheetRaised()});

  /// What the next calls return.
  ShareOutcome outcome;

  /// Every text offered, oldest first.
  final shared = <String>[];

  @override
  Future<ShareOutcome> shareText(String text) async {
    shared.add(text);
    return outcome;
  }
}

/// Installs the [ShareSheet] above the app. With none, a screen treats the
/// share as [ShareUnavailable] and shows the text with *Copy*.
class ShareSheetScope extends InheritedWidget {
  /// Installs [sheet].
  const ShareSheetScope({super.key, required this.sheet, required super.child});

  /// The share sheet.
  final ShareSheet sheet;

  /// The nearest share sheet, or null.
  static ShareSheet? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ShareSheetScope>()?.sheet;

  @override
  bool updateShouldNotify(ShareSheetScope old) => sheet != old.sheet;
}
