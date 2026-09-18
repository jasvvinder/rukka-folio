// S7.0b and S7.0c — confirm the columns, then the duplicates summary
// (07 §11 item 1 🔒, 13 §3.3 design rows S7.0b · S7.0c).
//
// Two phases on one screen because they are one decision with one Back: the
// user confirms how the file was read, and is immediately told what that
// produced — *12 lines already imported — skipped*, stated **before anything
// else is shown** (07 §11 item 1 🔒).
//
// Corrections are remembered per bank (07 §11 item 1 🔒): confirming calls
// `rememberMapping(bankKey, …)` whether or not anything was corrected, which
// is what makes the second statement from that bank need no checking.
//
// Bank vocabulary throughout — *Money in* / *Money out*, never Dr/Cr
// (02 §10 🔒). Nothing here posts anything: parsed lines land in an inbox,
// never the ledger, and the screen says so.
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
import '../parse/statement_parser.dart';
import '../widgets/import_parts.dart';
import '../widgets/mapping_parts.dart';

/// Which half of the step is showing.
enum MappingPhase {
  /// S7.0b — the columns, for confirmation.
  columns,

  /// S7.0c — duplicates skipped, and the door onward.
  duplicates,
}

/// S7.0b–c — confirm the mapping, then see what came through.
class ImportMappingScreen extends StatefulWidget {
  /// Creates the screen for a statement S7 has already read.
  const ImportMappingScreen({
    super.key,
    required this.statement,
    required this.account,
    required this.bytes,
    required this.onContinue,
    this.source,
    this.onAnotherFile,
  });

  /// What S7 read.
  final ParsedStatement statement;

  /// The bank A/C it was read into.
  final ImportAccount account;

  /// The file's bytes, kept so a correction can re-read them on-device — the
  /// file is never re-picked and never leaves the phone.
  final Uint8List bytes;

  /// The door onward to S7.1, the import inbox.
  final void Function(ParsedStatement statement) onContinue;

  /// The ledger door; read from [ImportScope] when absent.
  final ImportSource? source;

  /// Back to S7 to pick a different file — the path out when every line in
  /// this one is already imported.
  final VoidCallback? onAnotherFile;

  @override
  State<ImportMappingScreen> createState() => _ImportMappingScreenState();
}

class _ImportMappingScreenState extends State<ImportMappingScreen> {
  late ColumnMapping _mapping = widget.statement.mapping;
  late ParsedStatement _statement = widget.statement;
  MappingPhase _phase = MappingPhase.columns;
  bool _saving = false;

  List<List<String>>? _rows;

  List<List<String>> get _fileRows =>
      _rows ??= statementRows(widget.bytes, delimiter: _mapping.delimiter);

  /// The first line the current mapping reads, for the sample card.
  ParsedLine? get _sample {
    final read = readLines(_fileRows, _mapping);
    return read.lines.isEmpty ? null : read.lines.first;
  }

  void _correct(StatementColumn role, int? column) {
    setState(() => _mapping = _mapping.withColumn(role, column));
  }

  Future<void> _confirm() async {
    // Both doors are read before the first await: nothing reaches for
    // `context` across an async gap.
    final scope = ImportScope.maybeOf(context);
    final source = widget.source ?? scope?.source;
    final bookId = scope?.bookId;
    setState(() => _saving = true);
    // Remembered for the bank, not the A/C: a second A/C at the same bank
    // exports the same columns (07 §11 item 1 🔒).
    await source?.rememberMapping(widget.account.bankKey, _mapping);

    // Re-read under the confirmed mapping, against the same already-imported
    // set, so the duplicates count is the one the confirmed columns produce.
    final already = source == null || bookId == null
        ? const <LineIdentity>{}
        : await source.alreadyImported(bookId);
    if (!mounted) return;
    final result = parseStatement(
      bytes: widget.bytes,
      fileName: widget.statement.fileName,
      accountId: widget.account.id,
      mapping: _mapping.confirmed,
      alreadyImported: already,
    );
    setState(() {
      _saving = false;
      if (result is ParsedStatement) _statement = result;
      _phase = MappingPhase.duplicates;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: RkFitText(
          _phase == MappingPhase.columns
              ? l.importMapTitle
              : l.importDupesTitle,
          maxLines: 1,
        ),
        leading: _phase == MappingPhase.duplicates
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() => _phase = MappingPhase.columns),
              )
            : null,
      ),
      body: SafeArea(
        child: _saving
            ? RkSkeleton(label: l.importSkeleton, rows: 3)
            : switch (_phase) {
                MappingPhase.columns => _columns(l),
                MappingPhase.duplicates => _duplicates(l),
              },
      ),
    );
  }

  Widget _columns(AppLocalizations l) {
    final headers = _statement.headers;
    final split = _mapping.hasSplitColumns;
    final theme = Theme.of(context);
    final status = RkStatusColors.of(context);
    return ListView(
      // Each phase carries its own scroll position. Without distinct keys the
      // two lists share one, and the duplicates summary would open part-way
      // down — where the count *stated up front* (07 §11 item 1 🔒) is the
      // line already scrolled off.
      key: const ValueKey('import.columns'),
      children: [
        ImportStepTitle(
          l.importMapHelp,
          help: _statement.mapping.confidence == MappingConfidence.confirmed
              ? l.importMapRemembered(widget.account.bankKey)
              : l.importMapRemember(widget.account.bankKey),
        ),
        if (_statement.mapping.confidence == MappingConfidence.guessed)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: RkSpace.gutter),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.help_outline,
                  size: RkIcon.grid,
                  color: status.warning,
                ),
                const SizedBox(width: RkSpace.s2),
                Expanded(
                  child: RkFitText(
                    l.importMapGuessed,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        MappingRow(
          role: StatementColumn.date,
          headers: headers,
          value: _mapping.date,
          required: true,
          onChanged: (c) => _correct(StatementColumn.date, c),
        ),
        MappingRow(
          role: StatementColumn.description,
          headers: headers,
          value: _mapping.description,
          onChanged: (c) => _correct(StatementColumn.description, c),
        ),
        if (split) ...[
          MappingRow(
            role: StatementColumn.moneyOut,
            headers: headers,
            value: _mapping.moneyOut,
            onChanged: (c) => _correct(StatementColumn.moneyOut, c),
          ),
          MappingRow(
            role: StatementColumn.moneyIn,
            headers: headers,
            value: _mapping.moneyIn,
            onChanged: (c) => _correct(StatementColumn.moneyIn, c),
          ),
        ] else ...[
          MappingRow(
            role: StatementColumn.amount,
            headers: headers,
            value: _mapping.amount,
            onChanged: (c) => _correct(StatementColumn.amount, c),
          ),
          MappingRow(
            role: StatementColumn.direction,
            headers: headers,
            value: _mapping.direction,
            onChanged: (c) => _correct(StatementColumn.direction, c),
          ),
        ],
        MappingRow(
          role: StatementColumn.balance,
          headers: headers,
          value: _mapping.balance,
          onChanged: (c) => _correct(StatementColumn.balance, c),
        ),
        SampleLineCard(line: _sample),
        Padding(
          padding: const EdgeInsets.all(RkSpace.gutter),
          child: FilledButton(
            onPressed: _sample == null ? null : _confirm,
            child: RkFitText(l.importMapConfirm),
          ),
        ),
        const SizedBox(height: RkSpace.s8),
      ],
    );
  }

  Widget _duplicates(AppLocalizations l) {
    final theme = Theme.of(context);
    final status = RkStatusColors.of(context);
    final nothingLeft = _statement.lines.isEmpty;
    return ListView(
      key: const ValueKey('import.duplicates'),
      padding: const EdgeInsets.all(RkSpace.gutter),
      children: [
        // Stated up front, before anything else about the file
        // (07 §11 item 1 🔒).
        RkFitText(
          _statement.duplicatesSkipped == 0
              ? l.importDupesNone
              : l.importDupesSkipped(_statement.duplicatesSkipped),
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: RkSpace.s3),
        RkFitText(
          nothingLeft
              ? l.importDupesNothing
              : l.importDupesReady(_statement.lines.length),
          style: theme.textTheme.bodyLarge,
        ),
        if (_statement.unreadableRows > 0) ...[
          const SizedBox(height: RkSpace.s2),
          RkFitText(
            l.importDupesIgnored(_statement.unreadableRows),
            style: theme.textTheme.bodySmall?.copyWith(color: status.muted),
          ),
        ],
        const SizedBox(height: RkSpace.s4),
        RkFitText(
          l.importDupesNotposted,
          style: theme.textTheme.bodySmall?.copyWith(color: status.muted),
        ),
        const SizedBox(height: RkSpace.s6),
        if (nothingLeft)
          // Not a failure, and not a dead end: the path out is another file
          // (07 §1 rule 6).
          FilledButton(
            onPressed: widget.onAnotherFile,
            child: RkFitText(l.importFailAnother),
          )
        else
          FilledButton(
            onPressed: () => widget.onContinue(_statement),
            child: RkFitText(l.importDupesContinue),
          ),
      ],
    );
  }
}
