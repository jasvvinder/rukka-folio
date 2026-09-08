// In-memory book keys (unwrapped, 03 §3.1 "unwrapped only in memory"),
// serving `packages/data`'s `KeySource` so Recompute opens payloads, and the
// engine's re-seal step (05 §3). Every version is retained (re-seal needs the
// old one); `dispose` zeroises.
import 'package:core_crypto/core_crypto.dart';
import 'package:data/data.dart';

/// Book keys by `(book, version)` plus the book → tenant map.
final class BookKeyStore implements KeySource {
  /// Creates a store for one tenant.
  BookKeyStore({required this.tenantId});

  /// The tenant every book here belongs to.
  final String tenantId;

  final Map<BookKeyRef, BookKey> _keys = {};
  final Set<String> _books = {};

  /// Books with at least one key.
  Set<String> get books => Set.unmodifiable(_books);

  /// Adds (or replaces) a key.
  void put(BookKey key) {
    _keys[key.ref]?.dispose();
    _keys[key.ref] = key;
    _books.add(key.ref.bookId);
  }

  /// Whether `(book, version)` is held.
  bool has(String bookId, int keyVersion) =>
      _keys.containsKey(BookKeyRef(bookId: bookId, keyVersion: keyVersion));

  /// Highest version held for [bookId], or null.
  int? highestVersion(String bookId) {
    int? best;
    for (final ref in _keys.keys) {
      if (ref.bookId == bookId && (best == null || ref.keyVersion > best)) {
        best = ref.keyVersion;
      }
    }
    return best;
  }

  @override
  BookKey? bookKey(BookKeyRef ref) => _keys[ref];

  @override
  String? tenantIdOf(String bookId) => tenantId;

  /// Drops every key of [bookId] (membership removed, 05 §5).
  void dropBook(String bookId) {
    _keys.removeWhere((ref, key) {
      if (ref.bookId != bookId) return false;
      key.dispose();
      return true;
    });
    _books.remove(bookId);
  }

  /// Drops everything (own-device revocation verified, 05 §5).
  void clear() {
    for (final k in _keys.values) {
      k.dispose();
    }
    _keys.clear();
    _books.clear();
  }
}
