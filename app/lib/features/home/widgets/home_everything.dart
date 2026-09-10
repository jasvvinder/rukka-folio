// *Everything* scope (13 §2.2 🔒): "read-only aggregate across every book
// visible to the user" — one card per book, and each card carries a
// **provisional** badge while that book has an author gap (13 §2.2, ADR
// 2026-09-05f §B).
//
// Read-only means read-only: no verb buttons, no drill-downs, no taps that
// post anything. The badge is never inferred here — it is read from
// `BookHealth.isProvisional` (`heldCount > 0 || authorGapCount > 0`,
// local_ledger.dart:324), the projection's own flag; no gap detection is
// invented in the UI.
import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/format/money_format.dart';
import '../../../shared/ledger/local_ledger.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';
import '../home_scope.dart';
import 'home_states.dart';

/// The *Everything* body: one read-only card per book, in switcher order.
class HomeEverythingList extends StatelessWidget {
  /// Creates the list.
  const HomeEverythingList({
    super.key,
    required this.ledger,
    required this.books,
  });

  /// The facade every card reads its own book through.
  final LocalLedger ledger;

  /// Books, already ordered by group (`watchBookRefs`).
  final List<BookRef> books;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final status = RkStatusColors.of(context);
    return ListView(
      padding: const EdgeInsets.only(bottom: RkSpace.s10),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            RkSpace.gutter,
            RkSpace.s4,
            RkSpace.gutter,
            RkSpace.s2,
          ),
          // Colour never alone: the read-only state is said in words and
          // carries the lock icon (07 §1 rule 3).
          child: Row(
            children: [
              Icon(Icons.lock_outline, size: RkSpace.s4, color: status.locked),
              const SizedBox(width: RkSpace.s2),
              Expanded(
                child: Text(
                  l10n.homeEverythingReadOnly,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: status.muted),
                ),
              ),
            ],
          ),
        ),
        if (books.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: RkSpace.gutter,
              vertical: RkSpace.s2,
            ),
            child: Text(l10n.homeEverythingEmpty),
          )
        else
          for (final book in books) HomeBookCard(ledger: ledger, book: book),
      ],
    );
  }
}

/// One book's read-only card in *Everything*: its name, its *Total money you
/// have*, and the provisional badge when the book's own health says so.
class HomeBookCard extends StatelessWidget {
  /// Creates the card.
  const HomeBookCard({super.key, required this.ledger, required this.book});

  /// Facade.
  final LocalLedger ledger;

  /// The book.
  final BookRef book;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final status = RkStatusColors.of(context);
    final locale = Localizations.localeOf(context);
    return RkRuledCard(
      child: Padding(
        padding: const EdgeInsets.all(RkSpace.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(book.name, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: RkSpace.s1),
            Text(
              l10n.homeHeroLabel,
              style: Theme.of(context).textTheme.labelLarge
                  ?.copyWith(color: status.muted),
            ),
            const SizedBox(height: RkSpace.s1),
            StreamBuilder<Position>(
              stream: ledger.watchPosition(book.id),
              builder: (context, snap) {
                final position = snap.data;
                return Text(
                  position == null
                      ? l10n.homeSkeleton
                      : formatPaise(position.totalMoneyPaise, locale: locale),
                  style: position == null
                      ? Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: status.muted)
                      : RkType.amountRow,
                );
              },
            ),
            StreamBuilder<BookHealth>(
              stream: ledger.watchHealth(book.id),
              builder: (context, snap) {
                // No flag, no badge: the absence of health data is not a gap.
                if (!(snap.data?.isProvisional ?? false)) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: RkSpace.s2),
                  child: Row(
                    children: [
                      Icon(
                        Icons.schedule,
                        size: RkSpace.s4,
                        color: status.pending,
                      ),
                      const SizedBox(width: RkSpace.s2),
                      Expanded(
                        child: Text(
                          l10n.homeVerifyProvisional,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
