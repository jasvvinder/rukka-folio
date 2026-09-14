// S9 Books (13 §3.2 row S9), reached from Menu → Books — the surface 07 §5.7
// 🔒 names as the entry point for **S9.5 Add a business**, the second and
// third book once onboarding is over.
//
// 13 §3.2's S9 row is wider than this milestone: *roles, limits, verification
// log*. Only the books list and the S9.5 entry point are built here; the rest
// is one disabled-with-reason row (07 §1 rule 6, 13 §4.3) — it explains
// itself rather than vanishing, so the screen is never a dead end and never
// silently drops a promised feature.
//
// States (13 §4.3): working (a sentence, not a bare spinner — 11 §4.5),
// error-with-retry, and the list. There is no empty state: a device that has
// reached S9 owns at least its own book (07 §3.1 step 5 creates it), so an
// empty list is a fault, not a state — it renders as the error.
import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/ledger/ledger_scope.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';

/// One row of the books list, as S9 needs it — id is carried for the
/// member/roles work that lands later; the screen itself only reads name and
/// type.
@immutable
final class BookRow {
  /// Creates a row.
  const BookRow({required this.id, required this.name, required this.type});

  /// Book id (02 §1.1).
  final String id;

  /// Display name.
  final String name;

  /// The wire book type (`personal` · `family` · `joint` · `business` ·
  /// `organization`, 02 §1.1).
  final String type;
}

/// S9 — the books on this device, with *Add a business* (S9.5) on it.
class BooksScreen extends StatefulWidget {
  /// Creates the screen.
  const BooksScreen({super.key, this.onAddBusiness, this.books});

  /// Opens S9.5 (07 §5.7 🔒).
  final VoidCallback? onAddBusiness;

  /// The books to show. Null (the app's case) reads them from the
  /// [LedgerScope]; a test may pass a fixed list instead.
  final List<BookRow>? books;

  @override
  State<BooksScreen> createState() => _BooksScreenState();
}

class _BooksScreenState extends State<BooksScreen> {
  /// Bumped by *Try again* so the [StreamBuilder] resubscribes (07 §1 rule
  /// 12: an error always offers the way on).
  int _attempt = 0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.booksTitle)),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Heading(l10n.booksListHeading),
              _BooksList(
                key: ValueKey(_attempt),
                books: widget.books,
                onRetry: () => setState(() => _attempt++),
              ),
              const Divider(height: 1),
              _ActionRow(
                icon: Icons.add_business_outlined,
                title: l10n.booksAddBusinessRowTitle,
                subtitle: l10n.booksAddBusinessRowSubtitle,
                onTap: widget.onAddBusiness,
              ),
              _DisabledRow(
                title: l10n.booksMembersRowTitle,
                reason: l10n.booksMembersRowReason,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BooksList extends StatelessWidget {
  const _BooksList({super.key, required this.books, required this.onRetry});

  final List<BookRow>? books;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final fixed = books;
    if (fixed != null) return _rows(context, fixed);
    final ledger = LedgerScope.maybeOf(context);
    if (ledger == null) return const SizedBox.shrink();
    return StreamBuilder(
      stream: ledger.watchBooks(),
      builder: (context, snapshot) {
        final l10n = AppLocalizations.of(context);
        if (snapshot.hasError) {
          return _Notice(
            icon: Icons.error_outline,
            message: l10n.booksError,
            action: l10n.booksErrorRetry,
            onAction: onRetry,
          );
        }
        final rows = snapshot.data;
        if (rows == null) {
          return _Notice(
            icon: Icons.hourglass_empty,
            message: l10n.booksLoading,
          );
        }
        return _rows(context, [
          for (final r in rows) BookRow(id: r.id, name: r.name, type: r.type),
        ]);
      },
    );
  }

  Widget _rows(BuildContext context, List<BookRow> rows) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [for (final r in rows) _BookTile(row: r)],
  );
}

class _BookTile extends StatelessWidget {
  const _BookTile({required this.row});

  final BookRow row;

  /// The localised name of a wire book type (02 §1.1). An unknown wire value
  /// (a book from a newer build, 03 §3.3.4) reads as a business rather than
  /// crashing — the conservative reading, and what Home's grouping does too.
  static String typeLabel(AppLocalizations l10n, String wire) => switch (wire) {
    'personal' => l10n.booksTypePersonal,
    'family' => l10n.booksTypeFamily,
    'joint' => l10n.booksTypeJoint,
    'organization' => l10n.booksTypeOrganization,
    _ => l10n.booksTypeBusiness,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final status = RkStatusColors.of(context);
    final label = typeLabel(l10n, row.type);
    return Semantics(
      label: '${row.name}. $label',
      child: ExcludeSemantics(
        child: Container(
          constraints: const BoxConstraints(minHeight: RkSpace.rowMinHeight),
          padding: const EdgeInsets.symmetric(
            horizontal: RkSpace.gutter,
            vertical: RkSpace.s3,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // The book's own name is user-typed: tag it so a screen reader
              // in another locale still says it correctly (07 §1).
              Text(row.name, style: text.bodyLarge),
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  label,
                  style: text.bodySmall?.copyWith(color: status.muted),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A navigable row — the shape of `features/menu`'s `MenuRow`, kept local
/// because neither feature owns the other.
class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final status = RkStatusColors.of(context);
    return Semantics(
      button: onTap != null,
      label: '$title. $subtitle',
      child: ExcludeSemantics(
        child: InkWell(
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: RkSpace.rowMinHeight),
            padding: const EdgeInsets.symmetric(
              horizontal: RkSpace.gutter,
              vertical: RkSpace.s3,
            ),
            child: Row(
              children: [
                Icon(icon, color: status.muted, size: 22),
                const SizedBox(width: RkSpace.s3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(title, style: text.bodyLarge),
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          subtitle,
                          style: text.bodySmall?.copyWith(color: status.muted),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: RkSpace.s2),
                Icon(Icons.chevron_right, color: status.muted, size: 22),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A row whose destination has not been built (07 §1 rule 6, 13 §4.3): the
/// clock icon is paired with the reason, so the state never rides on colour.
class _DisabledRow extends StatelessWidget {
  const _DisabledRow({required this.title, required this.reason});

  final String title;
  final String reason;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final status = RkStatusColors.of(context);
    return Semantics(
      enabled: false,
      label: '$title. $reason',
      child: ExcludeSemantics(
        child: Container(
          constraints: const BoxConstraints(minHeight: RkSpace.rowMinHeight),
          padding: const EdgeInsets.symmetric(
            horizontal: RkSpace.gutter,
            vertical: RkSpace.s3,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: text.bodyLarge?.copyWith(color: status.muted)),
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.schedule, size: 14, color: status.muted),
                    const SizedBox(width: RkSpace.s1),
                    Expanded(
                      child: Text(
                        reason,
                        style: text.bodySmall?.copyWith(color: status.muted),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelLarge;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        RkSpace.gutter,
        RkSpace.s4,
        RkSpace.gutter,
        RkSpace.s2,
      ),
      child: Semantics(header: true, child: Text(text, style: style)),
    );
  }
}

/// The working / error line — a sentence with an icon beside it (11 §4.5:
/// never a bare spinner; 07 §1 rule 3: colour never alone).
class _Notice extends StatelessWidget {
  const _Notice({
    required this.icon,
    required this.message,
    this.action,
    this.onAction,
  });

  final IconData icon;
  final String message;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final status = RkStatusColors.of(context);
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: RkSpace.gutter,
        vertical: RkSpace.s3,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: status.muted),
          const SizedBox(width: RkSpace.s2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Semantics(
                  liveRegion: true,
                  child: Text(message, style: text.bodyMedium),
                ),
                if (action != null)
                  Padding(
                    padding: const EdgeInsets.only(top: RkSpace.s2),
                    child: FilledButton(
                      onPressed: onAction,
                      child: Text(action!),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
