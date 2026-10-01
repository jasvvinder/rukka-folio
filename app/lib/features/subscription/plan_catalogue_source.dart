// The catalogue seam: where S12.1 gets the plans it draws (ADR 2026-09-25 §6
// 🔒 — *"The app downloads the catalogue on the meta channel (05 §5) and
// renders S12.1 from it"*).
//
// ⚠️ WIRE — `GET sync-meta/plans` (`server/supabase/functions/sync-meta/
// index.ts`, `plans()` and `planToWire`), authenticated like every meta
// route: a bearer JWT (06 §4) and the client-version header. 200 carries
// `{plans:[…], catalogue_updated_at}`; parsed by [RkPlanCatalogue.fromJson].
//
// Three implementations, each honest about what it is:
//   • [HttpPlanCatalogueSource] — production, over the app's one HTTP door
//     (`shared/seams/http_transport.dart`). It keeps the last catalogue the
//     server gave it and hands that back when a later request never reaches
//     a response (S19.3: offline is not an error), but it **never** falls
//     back to the offline mirror: a phone that has never reached the server
//     is told so, with a retry.
//   • [OfflinePlanCatalogueSource] — the labelled fallback for a build where
//     nothing mounts a [PlanCatalogueScope] yet. Its answer carries
//     `offline: true`.
//   • [FakePlanCatalogueSource] — tests.
//
// Nothing here logs: a request carries a bearer token (CLAUDE.md rule 4).
import 'dart:convert';

import 'package:flutter/widgets.dart';

import '../../shared/seams/http_transport.dart';
import 'tier_catalogue.dart';

/// Reads the plan catalogue.
abstract interface class PlanCatalogueSource {
  /// The catalogue. Throws [PlanCatalogueFailure] when there is none to give.
  Future<RkPlanCatalogue> read();
}

/// Why no catalogue came back.
enum PlanCatalogueRefusal {
  /// The request never reached a response, and nothing had been read before.
  offline,

  /// No session, or the server refused the token (401/403).
  unauthorized,

  /// The server answered with something other than a catalogue.
  server,

  /// A 200 whose body is not a catalogue.
  malformed,
}

/// The one failure [PlanCatalogueSource.read] throws.
final class PlanCatalogueFailure implements Exception {
  /// Creates the failure.
  const PlanCatalogueFailure(this.reason, [this.status]);

  /// Why.
  final PlanCatalogueRefusal reason;

  /// The HTTP status, when there was one.
  final int? status;

  @override
  String toString() => 'PlanCatalogueFailure(${reason.name}, $status)';
}

/// `GET sync-meta/plans` over the app's HTTP door.
///
/// **Binding (not made here):** `bootstrap.dart` / the shell mounts
/// `PlanCatalogueScope(source: HttpPlanCatalogueSource(transport: httpDoor,
/// functionsRoot: …, accessToken: auth.accessToken, clientVersion: …))`
/// beside `EntitlementScope`. Until it does, S12.1 draws the offline mirror.
final class HttpPlanCatalogueSource implements PlanCatalogueSource {
  /// Creates the source. [functionsRoot] is the edge-functions root
  /// (`…/functions/v1/`); [accessToken] yields the 15-minute JWT of 06 §4.
  HttpPlanCatalogueSource({
    required RkHttpTransport transport,
    required Uri functionsRoot,
    required Future<String?> Function() accessToken,
    String? clientVersion,
  }) : _http = transport,
       _url = _plansUrl(functionsRoot),
       _token = accessToken,
       _version = clientVersion;

  final RkHttpTransport _http;
  final Uri _url;
  final Future<String?> Function() _token;
  final String? _version;
  RkPlanCatalogue? _lastGood;

  /// ⚠️ WIRE `_shared/http.ts` CLIENT_VERSION_HEADER.
  static const String clientVersionHeader = 'x-rukka-client-version';

  static Uri _plansUrl(Uri root) {
    final base = root.path.endsWith('/')
        ? root
        : root.replace(path: '${root.path}/');
    return base.resolve('sync-meta/plans');
  }

  @override
  Future<RkPlanCatalogue> read() async {
    final token = await _token();
    if (token == null || token.isEmpty) {
      throw const PlanCatalogueFailure(PlanCatalogueRefusal.unauthorized);
    }
    final RkHttpResponse res;
    try {
      res = await _http.get(
        _url,
        headers: {
          'authorization': 'Bearer $token',
          if (_version != null) clientVersionHeader: _version,
        },
      );
    } on RkHttpFailure {
      // Display data the phone already holds is still true enough to show
      // offline (S19.3 is non-blocking); a phone that holds none says so.
      final last = _lastGood;
      if (last != null) return last;
      throw const PlanCatalogueFailure(PlanCatalogueRefusal.offline);
    }
    if (res.statusCode == 401 || res.statusCode == 403) {
      throw PlanCatalogueFailure(
        PlanCatalogueRefusal.unauthorized,
        res.statusCode,
      );
    }
    if (res.statusCode != 200) {
      throw PlanCatalogueFailure(PlanCatalogueRefusal.server, res.statusCode);
    }
    final RkPlanCatalogue catalogue;
    try {
      final body = jsonDecode(res.body);
      if (body is! Map) throw const FormatException('not an object');
      catalogue = RkPlanCatalogue.fromJson(body.cast<String, Object?>());
    } on FormatException {
      throw const PlanCatalogueFailure(PlanCatalogueRefusal.malformed, 200);
    }
    return _lastGood = catalogue;
  }
}

/// ⚠️ **OFFLINE FALLBACK.** Hands back [rkOfflineCatalogue] — 0018's seed,
/// mirrored — for a build where no [PlanCatalogueScope] is mounted. Its
/// answer is marked `offline: true`. Never used once the HTTP source is bound.
final class OfflinePlanCatalogueSource implements PlanCatalogueSource {
  /// Creates the source.
  const OfflinePlanCatalogueSource();

  @override
  Future<RkPlanCatalogue> read() async => rkOfflineCatalogue;
}

/// Test double: hands back what it was built with, or throws.
class FakePlanCatalogueSource implements PlanCatalogueSource {
  /// Creates the fake.
  FakePlanCatalogueSource({RkPlanCatalogue? catalogue, this.failure})
    : catalogue = catalogue ?? rkOfflineCatalogue;

  /// What [read] returns.
  RkPlanCatalogue catalogue;

  /// When set, [read] throws this instead.
  Object? failure;

  /// How many times [read] was called.
  int reads = 0;

  @override
  Future<RkPlanCatalogue> read() async {
    reads++;
    final failure = this.failure;
    if (failure != null) throw failure;
    return catalogue;
  }
}

/// Hands a [PlanCatalogueSource] down the tree. Mount it where
/// `EntitlementScope` is mounted — above the router, so a sheet sees it too.
class PlanCatalogueScope extends InheritedWidget {
  /// Creates the scope.
  const PlanCatalogueScope({
    super.key,
    required this.source,
    required super.child,
  });

  /// The source S12.1 reads.
  final PlanCatalogueSource source;

  /// The nearest scope, or null.
  static PlanCatalogueScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PlanCatalogueScope>();

  @override
  bool updateShouldNotify(PlanCatalogueScope oldWidget) =>
      oldWidget.source != source;
}

/// The mounted source, or the labelled offline fallback when none is.
PlanCatalogueSource planCatalogueSourceOf(BuildContext context) =>
    PlanCatalogueScope.maybeOf(context)?.source ??
    const OfflinePlanCatalogueSource();
