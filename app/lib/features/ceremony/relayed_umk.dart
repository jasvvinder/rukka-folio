// The keys the **server** relayed for the person being verified — the other
// side of 04 §6.3's 🔒 byte-for-byte comparison.
//
// Where they come from. `umk_public_keys` (migration 0001, `pub_x` added by
// 0012) reaches this device on the ordinary meta pull: sync-meta's
// `shapeRow('umk_public_keys')` relays `{user_id, key_version, pub_ed, pub_x,
// superseded_at, updated_at}`, bytes as unpadded base64url and `pub_x` null
// where no x half was ever offered (`server/supabase/functions/sync-meta/
// index.ts`, the `umk_public_keys` case). The sync engine carries the table
// through untouched in `MetaResponse.extra` (rule 6), so this file reads it
// there, the way `ServerMembersRepository` reads `invites`.
//
// **Three answers, never two** (ADR 2026-09-24b §2). A row with both halves
// is [RelayedUmkComplete]. A row with `pub_ed` and no `pub_x` is
// [RelayedUmkEdOnly] — a real, named state, because every device installed
// before the re-offer shipped holds exactly that row until its owner opens
// the app once, and S9.3 must *say so* rather than fall silent. Anything else
// — no row, a malformed row, a pull that failed — is null: this device has
// nothing to compare against, and no half of anything is ever compared
// (`Ceremony.verifyQr` compares both halves, 04 §6.3 🔒).
//
// Nothing here logs: a row names a user (CLAUDE.md rule 4).
import 'dart:typed_data';

import 'package:core_crypto/core_crypto.dart' show Bytes, UmkPublic;
import 'package:flutter/foundation.dart' show immutable;
import 'package:sync_engine/sync_engine.dart' show MetaResponse;

/// What the server relayed for one user's UMK.
@immutable
sealed class RelayedUmk {
  const RelayedUmk();
}

/// Both public halves — what 04 §6.3 🔒 compares.
final class RelayedUmkComplete extends RelayedUmk {
  /// Wraps the relayed pair.
  const RelayedUmkComplete(this.umk);

  /// The server's copy of the person's UMK public halves.
  final UmkPublic umk;
}

/// The Ed25519 half only: the person's phone has not offered its X25519 half
/// yet (ADR 2026-09-24b §2). The ceremony fails closed **and says so** — it
/// never compares the one half it has.
final class RelayedUmkEdOnly extends RelayedUmk {
  /// The one value.
  const RelayedUmkEdOnly();
}

/// The public-key length both halves must have (04 §3.1). 0012's CHECK and
/// `certifyWith` refuse anything else; a row that somehow carries another
/// length is malformed here too, never "close enough".
const int _umkHalfBytes = 32;

/// Picks [userId]'s current UMK from `umk_public_keys` rows as the meta pull
/// relays them. Pure, so the decision is testable without a server.
///
/// Rows arrive oldest first across pages, and a row the server updated (the
/// re-offer filling `pub_x`) arrives again later — so the **last** row per
/// `key_version` wins. A superseded version is never current; of the rest,
/// the highest `key_version` is.
RelayedUmk? relayedUmkFromRows(
  Iterable<Map<String, Object?>> rows,
  String userId,
) {
  final byVersion = <int, Map<String, Object?>>{};
  for (final row in rows) {
    if (row['user_id'] != userId) continue;
    final version = row['key_version'];
    if (version is! int) continue;
    byVersion[version] = row;
  }
  Map<String, Object?>? current;
  var best = -1;
  for (final MapEntry(key: version, value: row) in byVersion.entries) {
    if (row['superseded_at'] != null) continue;
    if (version > best) {
      best = version;
      current = row;
    }
  }
  if (current == null) return null;
  final ed = _half(current['pub_ed']);
  if (ed == null) return null;
  final rawX = current['pub_x'];
  if (rawX == null) return const RelayedUmkEdOnly();
  final x = _half(rawX);
  if (x == null) return null; // present but malformed: not a key at all
  return RelayedUmkComplete(UmkPublic(x25519: x, ed25519: ed));
}

Uint8List? _half(Object? v) {
  if (v is! String || v.isEmpty) return null;
  try {
    final bytes = Bytes.fromBase64Url(v);
    return bytes.length == _umkHalfBytes ? bytes : null;
  } on FormatException {
    return null;
  } on ArgumentError {
    return null;
  }
}

/// One page of the meta pull (`MembersApi.pullMeta` in production).
typedef MetaPageReader = Future<MetaResponse> Function({String? after});

/// A `RelayedUmkSource` over the meta pull.
///
/// Every call reads the feed **from the beginning**, for the reason
/// `ServerMembersRepository.refresh` does: the cursor is the sync engine's to
/// keep, and a partial read could miss the very row the subject's re-offer
/// just updated. [pageCap] bounds a runaway feed.
final class MetaRelayedUmkSource {
  /// Creates the source over [pullMeta].
  const MetaRelayedUmkSource(this.pullMeta, {this.pageCap = 50});

  /// Reads one page.
  final MetaPageReader pullMeta;

  /// The most pages one lookup reads.
  final int pageCap;

  /// The meta table this reads.
  static const String table = 'umk_public_keys';

  /// [userId]'s relayed UMK, or null when this device cannot obtain one —
  /// offline, refused, or no row. A failure is null, never a guess.
  Future<RelayedUmk?> call(String userId) async {
    final rows = <Map<String, Object?>>[];
    try {
      String? after;
      for (var i = 0; i < pageCap; i++) {
        final page = await pullMeta(after: after);
        final list = page.extra[table];
        if (list is List) {
          for (final row in list) {
            if (row is Map) rows.add(row.cast<String, Object?>());
          }
        }
        if (!page.hasMore || page.next == null || page.next == after) break;
        after = page.next;
      }
    } on Object {
      return null;
    }
    return relayedUmkFromRows(rows, userId);
  }
}
