// S1.2 / S1.3 — the scope switcher, in its two ruled forms (07 §5.7 🔒).
//
//   • exactly two books (Me + one business) → the inline two-chip toggle in
//     the top bar (S1.2). Never the sheet.
//   • three or more books                   → the grouped bottom sheet (S1.3):
//     Me / Family / Businesses / Organizations / Everything, empty groups
//     omitted.
//   • one book                              → no control at all (13 §2.2).
//
// Tokens only; the selected chip is marked by a tick as well as by colour, so
// colour is never alone (07 §1 rule 3). Switching notifies the controller and
// nothing else — the same screen re-renders in the new scope (13 §2.2).
import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';
import '../home_scope.dart';

/// The scope control for the top bar: nothing, the S1.2 toggle, or the S1.3
/// sheet opener, decided by how many books the user has.
class HomeScopeControl extends StatelessWidget {
  /// Creates the control.
  const HomeScopeControl({
    super.key,
    required this.controller,
    required this.scope,
  });

  /// Books and selection.
  final HomeScopeController controller;

  /// The scope Home is showing right now.
  final HomeScope scope;

  @override
  Widget build(BuildContext context) {
    if (!controller.showsControl) return const SizedBox.shrink();
    return controller.isGrouped
        ? HomeScopeSheetButton(controller: controller, scope: scope)
        : HomeScopeToggle(controller: controller, scope: scope);
  }
}

/// S1.2 — the two-chip inline toggle. One chip per book; no *Everything* row,
/// because with two books the aggregate is the sheet's affordance (07 §5.7).
class HomeScopeToggle extends StatelessWidget {
  /// Creates the toggle.
  const HomeScopeToggle({
    super.key,
    required this.controller,
    required this.scope,
  });

  /// Books and selection.
  final HomeScopeController controller;

  /// Current scope.
  final HomeScope scope;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Semantics(
      container: true,
      label: l10n.homeScopeLabel,
      // Scrollable, not a Row that must fit: two Gurmukhi book names at 200%
      // do not fit 360 px (07 §1 rule 11).
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: RkSpace.gutter,
          vertical: RkSpace.s2,
        ),
        child: Row(
          children: [
            for (final book in controller.books)
              Padding(
                padding: const EdgeInsets.only(right: RkSpace.s2),
                child: _ScopeChip(
                  label: book.name,
                  selected: scope.bookId == book.id,
                  onTap: () => controller.select(HomeScope.book(book.id)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// S1.3 — the opener for the grouped sheet: it names the current scope and
/// says it can be changed.
class HomeScopeSheetButton extends StatelessWidget {
  /// Creates the opener.
  const HomeScopeSheetButton({
    super.key,
    required this.controller,
    required this.scope,
  });

  /// Books and selection.
  final HomeScopeController controller;

  /// Current scope.
  final HomeScope scope;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final named = controller.books.where((b) => b.id == scope.bookId);
    final label = scope.isEverything
        ? l10n.homeScopeEverything
        : named.isEmpty
        ? l10n.homeScopeLabel
        : named.first.name;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: RkSpace.gutter,
        vertical: RkSpace.s2,
      ),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: ActionChip(
          avatar: const Icon(Icons.menu_book_outlined, size: RkSpace.s4),
          label: Text(label),
          tooltip: l10n.homeScopeChange,
          onPressed: () => showHomeScopeSheet(context, controller, scope),
        ),
      ),
    );
  }
}

/// Opens the S1.3 grouped sheet. 🔒 07 §5.7: only ever called when the user
/// has **three or more** books.
Future<void> showHomeScopeSheet(
  BuildContext context,
  HomeScopeController controller,
  HomeScope scope,
) async {
  final chosen = await showModalBottomSheet<HomeScope>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => HomeScopeSheet(books: controller.books, scope: scope),
  );
  if (chosen != null) controller.select(chosen);
}

/// The grouped sheet's body (S1.3): Me / Family / Businesses / Organizations,
/// empty groups omitted, then *Everything* as the read-only aggregate.
class HomeScopeSheet extends StatelessWidget {
  /// Creates the sheet body.
  const HomeScopeSheet({super.key, required this.books, required this.scope});

  /// Every book, already ordered by group (see `watchBookRefs`).
  final List<BookRef> books;

  /// Current scope.
  final HomeScope scope;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final status = RkStatusColors.of(context);
    String groupLabel(HomeScopeGroup g) => switch (g) {
      HomeScopeGroup.me => l10n.homeScopeGroupMe,
      HomeScopeGroup.family => l10n.homeScopeGroupFamily,
      HomeScopeGroup.businesses => l10n.homeScopeGroupBusinesses,
      HomeScopeGroup.organizations => l10n.homeScopeGroupOrganizations,
    };
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: RkSpace.s6),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              RkSpace.gutter,
              0,
              RkSpace.gutter,
              RkSpace.s2,
            ),
            child: Semantics(
              header: true,
              child: Text(
                l10n.homeScopeSheetTitle,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ),
          for (final group in HomeScopeGroup.values)
            // Empty groups are omitted (13 §3.2 row S1.3).
            if (books.any((b) => b.group == group)) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  RkSpace.gutter,
                  RkSpace.s3,
                  RkSpace.gutter,
                  RkSpace.s1,
                ),
                child: Semantics(
                  header: true,
                  child: Text(
                    groupLabel(group),
                    style: Theme.of(context).textTheme.labelLarge
                        ?.copyWith(color: status.muted),
                  ),
                ),
              ),
              for (final book in books.where((b) => b.group == group))
                _ScopeTile(
                  label: book.name,
                  selected: scope.bookId == book.id,
                  onTap: () =>
                      Navigator.of(context).pop(HomeScope.book(book.id)),
                ),
            ],
          Divider(color: status.hairline, height: RkSpace.s6),
          _ScopeTile(
            label: l10n.homeScopeEverything,
            meta: l10n.homeScopeEverythingMeta,
            selected: scope.isEverything,
            onTap: () =>
                Navigator.of(context).pop(const HomeScope.everything()),
          ),
        ],
      ),
    );
  }
}

class _ScopeChip extends StatelessWidget {
  const _ScopeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ChoiceChip(
    selected: selected,
    // The tick is the point: selection is never carried by colour alone
    // (07 §1 rule 3).
    avatar: selected ? const Icon(Icons.check, size: RkSpace.s4) : null,
    showCheckmark: false,
    label: Text(label),
    onSelected: (_) => onTap(),
  );
}

class _ScopeTile extends StatelessWidget {
  const _ScopeTile({
    required this.label,
    required this.selected,
    required this.onTap,
    this.meta,
  });

  final String label;
  final String? meta;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final status = RkStatusColors.of(context);
    return Semantics(
      selected: selected,
      button: true,
      child: ListTile(
        title: Text(label),
        subtitle: meta == null
            ? null
            : Text(
                meta!,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: status.muted),
              ),
        trailing: selected ? const Icon(Icons.check) : null,
        onTap: onTap,
      ),
    );
  }
}
