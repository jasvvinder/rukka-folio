// S17.3's one door out of the app: *Email support* (ADR 2026-09-25 §4).
//
// ADR 2026-09-19 ruling 2 🔒 adopted `url_launcher` for `tel:` only, behind a
// seam, with `canLaunchUrl` never called. ADR 2026-09-25 §4 amends it by one
// scheme: `mailto:` to **the one support address**, behind the same kind of
// seam. "No other URL is opened." This file is how that sentence is kept:
//
//   * [SupportMailer] takes **no argument**. There is no address, subject,
//     body or scheme for a caller to pass, so nothing but [supportMailtoUri]
//     can be reached through it — not by a screen, not by a later lane.
//   * [UrlLauncherSupportMailer] calls `launchUrl` and never `canLaunchUrl`
//     (ADR 2026-09-19 §4: `launchUrl` needs no `LSApplicationQueriesSchemes`
//     or `<queries>` entry; only `canLaunchUrl` does, and none is added).
//   * Screens import this file, never `package:url_launcher`.
//
// A failed launch is an answer (`false`), not a throw: S17.3 then names the
// address in words and offers *Copy the address* (07 §1 rule 6 🔒, the shape
// ADR 2026-09-19 ruling 3 gives a failed `dial`).
library;

import 'package:url_launcher/url_launcher.dart';

/// The one support address (ADR 2026-09-25 §4). Shown on S17.3 as it is and
/// never translated — it is an address, not prose.
const String supportEmailAddress = 'support@rukkafolio.com';

/// The one URI this app may hand `url_launcher` for support:
/// `mailto:support@rukkafolio.com`, with no query — no subject and no body,
/// so nothing the app knows travels in it.
final Uri supportMailtoUri = Uri(scheme: 'mailto', path: supportEmailAddress);

/// Opens the phone's email app addressed to [supportEmailAddress]. A seam,
/// so widget tests drive a fake.
abstract interface class SupportMailer {
  /// Opens it. `true` when the platform took the URI; `false` when no email
  /// app would (no mail account, a locked-down phone). Never throws.
  Future<bool> openSupportEmail();
}

/// What [UrlLauncherSupportMailer] hands the URI to. Production is
/// `launchUrl`; a test passes a recorder to pin the exact URI.
typedef SupportUriLauncher = Future<bool> Function(Uri uri);

Future<bool> _launchUrl(Uri uri) => launchUrl(uri);

/// The production mailer: [supportMailtoUri] through `launchUrl`, and
/// nothing else.
final class UrlLauncherSupportMailer implements SupportMailer {
  /// Creates the mailer. [launch] defaults to `url_launcher`'s `launchUrl`.
  const UrlLauncherSupportMailer({this.launch = _launchUrl});

  /// Where [supportMailtoUri] is handed. It is never given any other URI.
  final SupportUriLauncher launch;

  @override
  Future<bool> openSupportEmail() async {
    try {
      return await launch(supportMailtoUri);
    } on Object {
      // `launchUrl` throws a PlatformException on some platforms when no
      // handler exists; to the screen that is the same failed launch.
      return false;
    }
  }
}
