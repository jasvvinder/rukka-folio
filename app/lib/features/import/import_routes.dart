// Statement import routes (features/README "Routes").
//
// S7 is a **root-navigator** destination: it is opened from the S2 header,
// top right (ADR 2026-09-03 🔒), and covers the tab bar until the lines reach
// the inbox or the import is abandoned. The door itself is `features/entry`'s
// file; this feature publishes the destination and [ImportPaths.root].
//
// S7.0b–c is pushed, not routed: the mapping step carries the parsed
// statement and the file's bytes in memory, and a path cannot. Nothing is
// written to disk to make a URL possible — the file stays where the user put
// it (07 §11 item 1 🔒, 04).
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'import_paths.dart';
import 'screens/s7_0_mapping_screen.dart';
import 'screens/s7_1_inbox_screen.dart';
import 'screens/s7_import_screen.dart';

export 'balance_check.dart';
export 'import_fake.dart';
export 'import_lines.dart';
export 'import_paths.dart';
export 'import_source.dart';
export 'ledger_import_source.dart';
export 'parse/column_mapping.dart';
export 'parse/parsed_statement.dart';
export 'parse/statement_parser.dart';
export 'screens/s7_0_mapping_screen.dart';
export 'screens/s7_1_inbox_screen.dart';
export 'screens/s7_2_balance_check_screen.dart';
export 'screens/s7_import_screen.dart';
export 'widgets/inbox_parts.dart';

/// Root-navigator routes this feature owns: S7, and the S7.1 placeholder the
/// mapping step opens onto.
final List<RouteBase> importRoutes = [
  GoRoute(
    path: ImportPaths.root,
    builder: (context, state) => ImportScreen(
      onParsed: (statement, account, bytes) => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ImportMappingScreen(
            statement: statement,
            account: account,
            bytes: bytes,
            onContinue: (sorted) => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ImportInboxScreen(statement: sorted),
              ),
            ),
            onAnotherFile: () => Navigator.of(context).pop(),
          ),
        ),
      ),
    ),
  ),
];
