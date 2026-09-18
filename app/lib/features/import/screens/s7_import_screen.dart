// S7 — Import: pick the bank A/C, then the file (13 §3.2 row S7, design
// S7.0a; 07 §11 item 1 🔒).
//
// The order is the spec's: **pick account → pick file → confirm mapping →
// duplicates skipped**. The account comes first because a statement is one
// A/C's, and because the per-bank remembered mapping is looked up from it —
// by the time the file is read, the app already knows how this bank writes.
//
// **Offline says nothing here.** Every step is on-device (07 §11 item 1 🔒,
// 04), so there is no network state to report and no connection chip: a
// statement imports in a basement.
//
// States (13 §4.3): the ruled skeleton while the A/Cs load · error-with-retry
// · empty (no bank A/C, with the one next action) · ready · reading a file ·
// parse failure. None of them is a dead end (07 §1 rule 6).
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';
import '../../../shared/widgets/rk_fit_text.dart';
import '../../../shared/widgets/rk_states.dart';
import '../import_source.dart';
import '../parse/column_mapping.dart';
import '../parse/parsed_statement.dart';
import '../widgets/import_parts.dart';

/// S7 — pick account & file.
class ImportScreen extends StatefulWidget {
  /// Creates the screen.
  const ImportScreen({
    super.key,
    this.bookId,
    this.source,
    this.filePort,
    required this.onParsed,
  });

  /// The book to import into; read from [ImportScope] when absent.
  final String? bookId;

  /// The ledger door; read from [ImportScope] when absent.
  final ImportSource? source;

  /// The device door; read from [ImportScope] when absent.
  final StatementFilePort? filePort;

  /// Where a read statement goes next — S7.0b, the mapping step. The bytes
  /// travel with it so a correction can re-read the file **on this phone**
  /// without asking for it again.
  final void Function(
    ParsedStatement statement,
    ImportAccount account,
    Uint8List bytes,
  )
  onParsed;

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  ImportSource? _source;
  StatementFilePort? _filePort;
  String? _bookId;

  List<ImportAccount>? _accounts;
  String? _selectedId;
  Object? _error;
  bool _started = false;

  String? _reading;
  StatementParseFailure? _failure;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = ImportScope.maybeOf(context);
    final source = widget.source ?? scope?.source;
    final port = widget.filePort ?? scope?.filePort;
    final bookId = widget.bookId ?? scope?.bookId;
    if (source == null || port == null || bookId == null) {
      // No scope, no door: the error state, not a thrown red screen
      // (07 §1 rule 6).
      if (_error == null && !_started) {
        setState(() => _error = StateError('no ImportScope'));
      }
      return;
    }
    if (identical(source, _source) && _started) return;
    _source = source;
    _filePort = port;
    _bookId = bookId;
    _started = true;
    _load();
  }

  Future<void> _load() async {
    final source = _source;
    final bookId = _bookId;
    if (source == null || bookId == null) return;
    setState(() {
      _error = null;
      _accounts = null;
      _failure = null;
    });
    try {
      final accounts = await source.pickAccount(bookId);
      if (!mounted) return;
      setState(() {
        _accounts = accounts;
        // One A/C, or the first of several, is pre-selected: the 8-second
        // rule says defaults are prefilled (07 §1 rule 1), and it keeps the
        // file action from opening disabled.
        _selectedId = accounts.isEmpty ? null : accounts.first.id;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    }
  }

  ImportAccount? get _selected {
    final accounts = _accounts;
    if (accounts == null) return null;
    for (final a in accounts) {
      if (a.id == _selectedId) return a;
    }
    return null;
  }

  Future<void> _pickFile() async {
    final source = _source;
    final port = _filePort;
    final bookId = _bookId;
    final account = _selected;
    if (source == null || port == null || bookId == null || account == null) {
      return;
    }
    setState(() => _failure = null);
    final picked = await port.pickStatementFile();
    // A cancel is not an error and shows none.
    if (picked == null || !mounted) return;
    setState(() => _reading = picked.name);
    try {
      final ColumnMapping? remembered = await source.rememberedMapping(
        account.bankKey,
      );
      final already = await source.alreadyImported(bookId);
      final result = await source.parse(
        bytes: picked.bytes,
        fileName: picked.name,
        accountId: account.id,
        mapping: remembered,
        alreadyImported: already,
      );
      if (!mounted) return;
      setState(() => _reading = null);
      switch (result) {
        case ParsedStatement():
          widget.onParsed(result, account, picked.bytes);
        case StatementParseFailure():
          setState(() => _failure = result);
      }
    } on Object catch (_) {
      if (!mounted) return;
      // A door that threw is still a file the app could not read — the
      // stated failure, never a crash (07 §11 item 4 🔒).
      setState(() {
        _reading = null;
        _failure = StatementParseFailure(
          ParseFailureReason.unreadable,
          fileName: picked.name,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final accounts = _accounts;
    return Scaffold(
      appBar: AppBar(title: RkFitText(l.importTitle, maxLines: 1)),
      body: SafeArea(
        child: switch ((accounts, _error)) {
          (_, final Object _) => RkErrorState(
            text: l.importError,
            retryLabel: l.importRetry,
            onRetry: _load,
          ),
          (null, _) => RkSkeleton(label: l.importSkeleton, rows: 4),
          (final List<ImportAccount> list, _) => _body(l, list),
        },
      ),
    );
  }

  Widget _body(AppLocalizations l, List<ImportAccount> accounts) {
    final failure = _failure;
    if (failure != null) {
      return ListView(
        children: [
          ParseFailurePanel(
            failure: failure,
            onAnother: () {
              setState(() => _failure = null);
              _pickFile();
            },
          ),
        ],
      );
    }
    return ListView(
      children: [
        ImportStepTitle(l.importStepAccount, help: l.importAccountHelp),
        if (accounts.isEmpty)
          _EmptyAccounts(l: l)
        else
          for (final a in accounts)
            _AccountRow(
              account: a,
              selected: a.id == _selectedId,
              onTap: () => setState(() => _selectedId = a.id),
            ),
        if (accounts.isNotEmpty) ...[
          ImportStepTitle(l.importStepFile),
          ImportDropZone(
            onPick: _pickFile,
            busyWith: _reading,
            enabled: _selected != null,
          ),
          const SizedBox(height: RkSpace.s8),
        ],
      ],
    );
  }
}

/// The empty state: no bank A/C in this book, and the one next action in
/// words (07 §1 rule 12; the Ledger tab is another lane's screen, so the path
/// is stated rather than pushed).
class _EmptyAccounts extends StatelessWidget {
  const _EmptyAccounts({required this.l});

  final AppLocalizations l;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = RkStatusColors.of(context);
    return Padding(
      padding: const EdgeInsets.all(RkSpace.gutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RkFitText(l.importAccountEmpty, style: theme.textTheme.bodyLarge),
          const SizedBox(height: RkSpace.s2),
          RkFitText(
            l.importAccountEmptyNext,
            style: theme.textTheme.bodyMedium?.copyWith(color: status.muted),
          ),
        ],
      ),
    );
  }
}

/// One bank A/C in the S7 list.
///
/// The selection is carried by an icon *and* the row's own state, never by a
/// tint alone (07 §1 rule 3), and announced to a screen reader as selected.
class _AccountRow extends StatelessWidget {
  const _AccountRow({
    required this.account,
    required this.selected,
    required this.onTap,
  });

  final ImportAccount account;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final status = RkStatusColors.of(context);
    return Semantics(
      selected: selected,
      button: true,
      child: ListTile(
        onTap: onTap,
        selected: selected,
        minTileHeight: RkSpace.rowMinHeight,
        leading: Icon(
          selected ? Icons.check_circle : Icons.circle_outlined,
          color: selected
              ? Theme.of(context).colorScheme.primary
              : status.muted,
        ),
        title: RkFitText(account.name),
        subtitle: account.subtitle == null
            ? null
            : RkFitText(account.subtitle!),
      ),
    );
  }
}
