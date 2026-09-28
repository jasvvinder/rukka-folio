// The phone's dialer, behind a seam (ADR 2026-09-19 ruling 2 🔒).
//
// R2.2's per-row *Call* link (S11.2) and R2.3's *Call {name}* button (S11.7)
// hand a number to the phone app. This file is the whole of that door, and
// three sentences of the ruling are kept here rather than remembered:
//
//   * **`tel:` and nothing else.** [Dialer.dial] takes a number, not a URI;
//     [UrlLauncherDialer] builds `Uri(scheme: 'tel', path: number)` itself, so
//     no caller can reach any other scheme through it.
//   * **`launchUrl`, never `canLaunchUrl`.** Only `canLaunchUrl` needs an
//     `LSApplicationQueriesSchemes` entry or an Android `<queries>` block, so
//     **neither is added** — and must not be "fixed" back in. The plugin's own
//     README: *"it is better to use `launchUrl` directly and handle failure,
//     rather than disabling the button"* (07 §1 rule 6 🔒).
//   * **The bytes the book holds are the bytes dialled.** The number is never
//     parsed, trimmed, normalised or reformatted here.
//
// A failed dial — no SIM, a tablet, the iOS Simulator — is `false`, never a
// throw: the screen then shows the number, *Copy the number* and one line
// saying why (ruling 3). Screens import this file, never
// `package:url_launcher` (the `features/help/support_mailer.dart` precedent).
library;

import 'package:flutter/widgets.dart';
import 'package:url_launcher/url_launcher.dart';

/// Places a call. A seam, so widget tests drive a fake.
abstract interface class Dialer {
  /// Hands [number] to the phone app. `true` when the platform took it;
  /// `false` when nothing would (no SIM, a tablet). Never throws.
  Future<bool> dial(String number);
}

/// What [UrlLauncherDialer] hands the URI to. Production is `launchUrl`; a
/// test passes a recorder to pin the exact URI.
typedef DialUriLauncher = Future<bool> Function(Uri uri);

Future<bool> _launchUrl(Uri uri) => launchUrl(uri);

/// The `tel:` URI for [number], its bytes unaltered.
Uri telUriOf(String number) => Uri(scheme: 'tel', path: number);

/// The production dialer: `tel:<number>` through `launchUrl`, and nothing
/// else.
final class UrlLauncherDialer implements Dialer {
  /// Creates the dialer. [launch] defaults to `url_launcher`'s `launchUrl`.
  const UrlLauncherDialer({this.launch = _launchUrl});

  /// Where the `tel:` URI is handed. It is never given any other scheme.
  final DialUriLauncher launch;

  @override
  Future<bool> dial(String number) async {
    try {
      return await launch(telUriOf(number));
    } on Object {
      // `launchUrl` throws a PlatformException on some platforms when no
      // handler exists; to the screen that is the same failed dial.
      return false;
    }
  }
}

/// Installs the [Dialer] above the app. With none, a *Call* control is not
/// drawn and the number is shown as text — nothing is drawn that would do
/// nothing (07 §1 rule 6 🔒).
class DialerScope extends InheritedWidget {
  /// Installs [dialer].
  const DialerScope({super.key, required this.dialer, required super.child});

  /// The dialer.
  final Dialer dialer;

  /// The nearest dialer, or null.
  static Dialer? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DialerScope>()?.dialer;

  @override
  bool updateShouldNotify(DialerScope old) => dialer != old.dialer;
}
