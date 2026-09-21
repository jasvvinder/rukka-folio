// S17 Help — the hub (13 §3.2 row S17: "search, contact, diagnostics — the
// grouped, searchable FAQ list lives on this hub, S17.1 folded in,
// ADR 2026-09-02"; 07 §22 🔒).
//
// The whole of Help is on the phone: the thirteen answers are ARB strings and
// the search runs over them locally, so this screen has **no loading, no
// error and no offline state** — offline is the default assumption, not an
// error (07 §1 rule 7 🔒, 13 §8). What it does have is the list's four
// states of 13 §4.3: populated, searched-and-populated (with the count),
// searched-and-empty (one next action), and the two doors under *Still
// stuck?*, each of which either opens or says why it cannot.
//
// The screen owns no navigation: every door is a callback the route fills in
// (the `LegalScreen` convention), which keeps it pumpable with no router.
import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';
import '../../../shared/widgets/rk_fit_text.dart';
import '../faq_catalog.dart';
import '../widgets/help_widgets.dart';

/// S17 — Help.
class HelpScreen extends StatefulWidget {
  /// Creates the hub.
  const HelpScreen({
    super.key,
    required this.onOpenArticle,
    required this.onOpenContact,
    required this.onOpenDiagnostics,
  });

  /// Opens S17.2 for an answer id.
  ///
  /// Required, like the two below: all three destinations are built and
  /// mounted by `helpRoutes`, so there is no state in which one of these
  /// doors has nowhere to go. A nullable callback here would invite a
  /// disabled row with a *reason that is not true*, which is the thing
  /// 07 §1 rule 6 🔒 rules out — the Menu's Help row spent a milestone
  /// saying "Help has not been built yet" for exactly that reason.
  final void Function(String id) onOpenArticle;

  /// Opens S17.3.
  final VoidCallback onOpenContact;

  /// Opens S17.4.
  final VoidCallback onOpenDiagnostics;

  @override
  State<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends State<HelpScreen> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _clear() {
    _search.clear();
    setState(() => _query = '');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final status = RkStatusColors.of(context);
    final matches = faqSearch(l10n, _query);
    final searching = _query.trim().isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: RkFitText(l10n.helpTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: RkSpace.s10),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                RkSpace.gutter,
                RkSpace.s4,
                RkSpace.gutter,
                RkSpace.s3,
              ),
              child: RkFitText(l10n.helpIntro, style: text.bodyLarge),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: RkSpace.gutter),
              child: Semantics(
                label: l10n.helpSearchLabel,
                child: TextField(
                  controller: _search,
                  onChanged: (v) => setState(() => _query = v),
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: l10n.helpSearchHint,
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: searching
                        ? IconButton(
                            icon: const Icon(Icons.close),
                            tooltip: l10n.helpSearchClear,
                            onPressed: _clear,
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(RkRadius.md),
                    ),
                  ),
                ),
              ),
            ),
            if (searching)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  RkSpace.gutter,
                  RkSpace.s3,
                  RkSpace.gutter,
                  0,
                ),
                child: RkFitText(
                  l10n.helpSearchCount(matches.length),
                  style: text.bodySmall?.copyWith(color: status.muted),
                ),
              ),
            if (searching && matches.isEmpty)
              _SearchEmpty(onShowAll: _clear)
            else ...[
              HelpSectionHeading(l10n.helpSectionFaq),
              for (final group in FaqGroup.values)
                if (matches.any((a) => a.group == group)) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      RkSpace.gutter,
                      RkSpace.s4,
                      RkSpace.gutter,
                      RkSpace.s1,
                    ),
                    child: RkFitText(
                      faqGroupLabel(l10n, group),
                      style: text.labelLarge?.copyWith(color: status.muted),
                    ),
                  ),
                  for (final a in matches.where((a) => a.group == group))
                    HelpQuestionRow(
                      question: faqText(l10n, a.id)!.question,
                      onOpen: () => widget.onOpenArticle(a.id),
                    ),
                ],
            ],
            HelpSectionHeading(l10n.helpSectionReach),
            // Both doors are live. S17.3 states for itself why its WhatsApp
            // channel will not open yet (`help.contact.reason`); saying so
            // here as well would disable a row whose destination exists.
            HelpDoorRow(
              icon: Icons.chat_outlined,
              title: l10n.helpContactTitle,
              subtitle: l10n.helpContactValue,
              onTap: widget.onOpenContact,
            ),
            HelpDoorRow(
              icon: Icons.assignment_outlined,
              title: l10n.helpDiagnosticsTitle,
              subtitle: l10n.helpDiagnosticsSubtitle,
              onTap: widget.onOpenDiagnostics,
            ),
          ],
        ),
      ),
    );
  }
}

/// The searched-and-empty state: what happened, and the one way on
/// (13 §4.3, 07 §1 rule 6 🔒).
class _SearchEmpty extends StatelessWidget {
  const _SearchEmpty({required this.onShowAll});

  final VoidCallback onShowAll;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final status = RkStatusColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        RkSpace.gutter,
        RkSpace.s6,
        RkSpace.gutter,
        RkSpace.s2,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Icon plus words: the state never rides on the tint alone
              // (07 §1 rule 3).
              Icon(
                Icons.search_off_outlined,
                size: RkIcon.grid,
                color: status.muted,
              ),
              const SizedBox(width: RkSpace.s2),
              Expanded(
                child: RkFitText(
                  l10n.helpSearchEmptyTitle,
                  style: text.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: RkSpace.s2),
          RkFitText(l10n.helpSearchEmptyBody, style: text.bodyLarge),
          const SizedBox(height: RkSpace.s4),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: FilledButton(
              onPressed: onShowAll,
              child: RkFitText(l10n.helpSearchEmptyAction),
            ),
          ),
        ],
      ),
    );
  }
}
