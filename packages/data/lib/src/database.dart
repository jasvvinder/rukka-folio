// The local database (03 §3): schema, migrations that fail closed (03 §5),
// SQLCipher key hand-off and the `quick_check` every open runs (ADR 2026-09-05c §6).
import 'package:drift/drift.dart';
import 'package:sqlite3/common.dart' show CommonDatabase;

import 'tables.dart';

part 'database.g.dart';

/// Current client schema version (03 §5: tested upgrade paths from every
/// shipped version; a failed migration fails closed).
/// v2 (ADR 2026-09-09d §4): `books_p.start_date`.
const int ledgerSchemaVersion = 2;

/// The client database: Layer 1 mirror + outbox and Layer 2 projections.
@DriftDatabase(
  tables: [
    EnvelopesLocal,
    Outbox,
    AuthorSeqLocal,
    AuthorGaps,
    AuthorDuplicates,
    SignedRecordsLocal,
    StoreEpoch,
    SyncCursors,
    KeyCache,
    AttachmentCache,
    BooksP,
    AccountsP,
    EntriesP,
    EntryLinesP,
    PeriodsP,
    CashCountsP,
    YearCloseP,
    ImportLinesP,
    RulesP,
    Balances,
    DailySnapshots,
  ],
)
class LedgerDatabase extends _$LedgerDatabase {
  /// Wraps an executor. Prefer [openLedgerDatabase], which also runs the
  /// integrity check and turns migration failures into a typed outcome.
  LedgerDatabase(super.executor);

  @override
  int get schemaVersion => ledgerSchemaVersion;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      for (final sql in schemaStatements) {
        await customStatement(sql);
      }
    },
    onUpgrade: (m, from, to) async {
      if (from > to) {
        // 03 §5: never run on a ledger written by a newer schema.
        throw MigrationFailedException(
          from: from,
          to: to,
          reason: 'database schema $from is newer than this app ($to)',
        );
      }
      // Forward migrations land here, version by version, each with a test.
      if (from < 2) {
        // v2 — ADR 2026-09-09d §4: the book's start date, projected from
        // book_config. Nullable, so existing rows need no backfill; the next
        // Recompute fills it for books whose config carries one.
        await m.addColumn(booksP, booksP.startDate);
      }
      for (final sql in schemaStatements) {
        await customStatement(sql);
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  /// SQLite's `PRAGMA quick_check` (SQLCipher runs the same pragma over the
  /// decrypted pages). Returns the messages; `['ok']` means healthy.
  Future<List<String>> quickCheck() async {
    final rows = await customSelect('PRAGMA quick_check').get();
    return [for (final r in rows) r.data.values.first.toString()];
  }

  /// Dumps one table as deterministic text — every row, every column, ordered
  /// by all columns — so two databases can be compared byte for byte (03 §3.3
  /// rule 2, 03 §7 *Determinism*).
  Future<String> dumpTable(String table) async {
    final cols = await customSelect('PRAGMA table_info("$table")').get();
    final names = [for (final c in cols) c.data['name'] as String];
    final order = names.map((n) => '"$n"').join(', ');
    final rows = await customSelect('SELECT * FROM "$table" ORDER BY $order')
        .get();
    final b = StringBuffer()..writeln('# $table (${names.join(', ')})');
    for (final r in rows) {
      b.writeln(
        names
            .map((n) {
              final v = r.data[n];
              return v is Uint8List ? 'x${_hex(v)}' : '$v';
            })
            .join('\t'),
      );
    }
    return b.toString();
  }

  /// [dumpTable] over every projection table, in [layer2Tables] order.
  Future<String> dumpProjections() async {
    final b = StringBuffer();
    for (final t in layer2Tables) {
      b.write(await dumpTable(t));
    }
    return b.toString();
  }
}

/// Thrown from the migration strategy when the stored schema cannot be brought
/// to [ledgerSchemaVersion] safely; surfaced as [MigrationFailed].
final class MigrationFailedException implements Exception {
  /// Creates the exception.
  const MigrationFailedException({
    required this.from,
    required this.to,
    required this.reason,
  });

  /// Stored schema version.
  final int from;

  /// This app's schema version.
  final int to;

  /// Why.
  final String reason;

  @override
  String toString() => 'MigrationFailedException($from → $to: $reason)';
}

/// What opening the database produced (ADR 2026-09-05c §6; 03 §5).
sealed class OpenResult {
  const OpenResult();
}

/// Open, migrated and `quick_check` clean.
final class Opened extends OpenResult {
  /// Creates the outcome.
  const Opened(this.db);

  /// The database.
  final LedgerDatabase db;
}

/// Migration failed closed — the app blocks with the support screen (03 §5).
/// The database is closed; nothing was run on a half-migrated ledger.
final class MigrationFailed extends OpenResult {
  /// Creates the outcome.
  const MigrationFailed(this.from, this.to, this.reason);

  /// Stored version.
  final int from;

  /// App version.
  final int to;

  /// Why.
  final String reason;
}

/// `quick_check` reported damage. The database is open so the caller can run
/// the corruption path (drop + Recompute, or re-bootstrap — ADR 05c §6).
final class QuickCheckFailed extends OpenResult {
  /// Creates the outcome.
  const QuickCheckFailed(this.db, this.messages);

  /// The database.
  final LedgerDatabase db;

  /// What SQLite reported.
  final List<String> messages;
}

/// The file could not be read at all — wrong key, not a database, I/O error.
final class OpenFailed extends OpenResult {
  /// Creates the outcome.
  const OpenFailed(this.error);

  /// The underlying error.
  final Object error;
}

/// Opens the ledger database over [executor]: applies migrations (failing
/// closed), then runs `PRAGMA quick_check` (ADR 2026-09-05c §6).
///
/// **SQLCipher key.** The key must reach the connection before drift reads
/// `user_version`, which only the executor's own setup hook can do — so the app
/// builds `NativeDatabase(file, setup: sqlcipherSetup(key))` and passes the
/// executor here. Passing [cipherKey] as well makes this function verify the
/// key actually unlocked the file (an unreadable header surfaces as
/// [OpenFailed]) and **zeroises** the buffer afterwards (CLAUDE.md rule 7).
Future<OpenResult> openLedgerDatabase(
  QueryExecutor executor, {
  Uint8List? cipherKey,
}) async {
  final db = LedgerDatabase(executor);
  try {
    // Forces the executor open, which runs the migration strategy.
    await db.customSelect('SELECT 1').get();
  } on MigrationFailedException catch (e) {
    await db.close();
    return MigrationFailed(e.from, e.to, e.reason);
  } on Object catch (e) {
    final cause = _unwrap(e);
    if (cause is MigrationFailedException) {
      await db.close();
      return MigrationFailed(cause.from, cause.to, cause.reason);
    }
    await db.close();
    return OpenFailed(e);
  } finally {
    if (cipherKey != null) cipherKey.fillRange(0, cipherKey.length, 0);
  }
  final check = await db.quickCheck();
  if (check.length != 1 || check.first != 'ok') {
    return QuickCheckFailed(db, check);
  }
  return Opened(db);
}

/// A `NativeDatabase(setup:)` hook that hands SQLCipher its key as **raw bytes**
/// (`PRAGMA key = "x'…'"`), never as a passphrase string, then verifies the
/// page header is readable. On a plain SQLite build the pragma is a no-op, so
/// tests and the desktop dev loop use the same code path.
void Function(CommonDatabase) sqlcipherSetup(Uint8List key) {
  if (key.length != 32) {
    throw ArgumentError.value(
      key.length,
      'key',
      'SQLCipher raw key is 32 bytes',
    );
  }
  final hex = _hex(key);
  return (db) {
    db.execute('PRAGMA key = "x\'$hex\'"');
    db.execute('PRAGMA cipher_memory_security = ON');
    // Touching the schema is how SQLCipher reports a wrong key.
    db.select('SELECT count(*) FROM sqlite_master');
  };
}

String _hex(Uint8List bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

Object _unwrap(Object e) {
  var cur = e;
  for (var i = 0; i < 4; i++) {
    if (cur is MigrationFailedException) return cur;
    final s = cur.toString();
    if (cur is DriftWrappedException) {
      cur = cur.cause ?? cur;
      if (cur is DriftWrappedException) break;
      continue;
    }
    if (s.contains('MigrationFailedException')) return cur;
    break;
  }
  return e;
}
