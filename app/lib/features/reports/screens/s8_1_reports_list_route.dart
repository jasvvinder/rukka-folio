// The one thing S8.1 has to *know* rather than merely list: whether this book
// is a shared business, because that decides whether the Partner positions row
// exists at all (07 §14 🔒, 02 §7.1 🔒, ADR 2026-09-09b 🔒).
//
// [ReportsListScreen] stays a pure list of doors; this wrapper does the read
// and hands it a boolean. The read is **`LocalLedger.configOf(bookId)`**, not
// `PartnersScope`:
//
//   • `book_config` is where ownership is *recorded* (03 §2.3; `BookConfig`
//     carries `type`, `ownership` and the 02 §7.1 🔒 `partner_shares`), so it
//     answers the question directly and without a live subscription.
//   • `PartnersPort.watch` is S14's own stream. It is optional — the shell may
//     not have mounted a `PartnersScope` at all — and depending on it here
//     would make the Reports list need the partner seam merely to decide *not*
//     to mention partners, which is backwards.
//
// Conservative by construction (CLAUDE.md, ambiguity → the safe reading):
// anything other than a recorded *business + shared* is treated as Just me —
// a missing config, an unreadable one, a book still resolving, or a business
// whose ownership was never recorded (an absent `partner_shares` map is *not
// recorded*, never *equal shares*; a book with no partner accounts is Just
// me). The row is then absent, and with it every partner word (ADR
// 2026-09-09b 🔒).
import 'package:core_ledger/core_ledger.dart' show BookType;
import 'package:data/data.dart' show BookOwnership;
import 'package:flutter/material.dart';

import '../../../shared/ledger/ledger_scope.dart';
import '../../../shared/ledger/local_ledger.dart';
import '../../ledger/ledger_book.dart';
import 's8_1_reports_list_screen.dart';

/// S8.1 with its book resolved: the Reports list, plus the one ledger read it
/// needs (the book's ownership).
class ReportsListRoute extends StatefulWidget {
  /// Creates the route wrapper.
  const ReportsListRoute({
    super.key,
    this.bookId,
    this.onOpenDayBook,
    this.onOpenReconciliation,
    this.onOpenPartnerPositions,
  });

  /// The book whose reports these are; null resolves the solo book
  /// ([soloBookId]), exactly as S3/S4 do until the scope switcher lands.
  final String? bookId;

  /// Opens S8.2 for the Day Book.
  final VoidCallback? onOpenDayBook;

  /// Opens S8.3 Family reconciliation.
  final VoidCallback? onOpenReconciliation;

  /// Opens S14 Partner positions for the resolved book id.
  final void Function(String bookId)? onOpenPartnerPositions;

  @override
  State<ReportsListRoute> createState() => _ReportsListRouteState();
}

class _ReportsListRouteState extends State<ReportsListRoute> {
  String? _bookId;
  bool _sharedBusiness = false;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The scope is an InheritedWidget: read it from here, never in initState.
    if (_started) return;
    _started = true;
    _resolve();
  }

  Future<void> _resolve() async {
    final ledger = LedgerScope.of(context);
    try {
      final id = widget.bookId ?? await soloBookId(ledger);
      final config = await ledger.configOf(id);
      if (!mounted) return;
      setState(() {
        _bookId = id;
        _sharedBusiness =
            config != null &&
            config.type == BookType.business &&
            config.ownership == BookOwnership.shared;
      });
    } catch (_) {
      // The list itself needs no ledger data, so a failed ownership read is
      // not an error state for the screen — it is simply *not a shared
      // business*, which is the reading that says nothing about partners.
      if (mounted) setState(() => _sharedBusiness = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bookId = _bookId;
    final open = widget.onOpenPartnerPositions;
    return ReportsListScreen(
      onOpenDayBook: widget.onOpenDayBook,
      onOpenReconciliation: widget.onOpenReconciliation,
      showPartnerPositions: _sharedBusiness,
      onOpenPartnerPositions: _sharedBusiness && bookId != null && open != null
          ? () => open(bookId)
          : null,
    );
  }
}
