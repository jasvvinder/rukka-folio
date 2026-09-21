// The thirteen answers S17 lists and S17.2 draws (13 §3.2 rows S17/S17.2;
// ADR 2026-09-02 folded the separate FAQ list S17.1 into the hub, so the
// grouped, searchable list *is* the hub).
//
// The catalogue is ids and grouping only — every word is an ARB string, so
// the list reads in EN, PA and HI with no per-language code (CLAUDE.md
// rule 8). [faqText] is the one place an id turns into strings; an id with no
// entry there returns null, which is the state S17.2 draws as
// `help.article.missing.*` rather than an empty page.
library;

import '../../l10n/gen/app_localizations.dart';

/// The five headings the list is grouped under, in reading order.
enum FaqGroup {
  /// Getting started.
  start,

  /// Writing entries.
  entries,

  /// Family, staff and partners.
  people,

  /// Safety and privacy.
  safety,

  /// When something looks wrong.
  trouble,
}

/// One answer: its stable id (the route parameter, and the ARB key's middle
/// segment) and the heading it sits under.
final class FaqArticle {
  /// Creates the entry.
  const FaqArticle(this.id, this.group);

  /// The id — `money_in_out`, `new_phone`, …. Stable: it is in the URL.
  final String id;

  /// Which heading it is listed under.
  final FaqGroup group;
}

/// Every answer, in the order the hub lists them within their group.
const faqArticles = <FaqArticle>[
  FaqArticle('money_in_out', FaqGroup.start),
  FaqArticle('offline', FaqGroup.start),
  FaqArticle('fix_entry', FaqGroup.entries),
  FaqArticle('locked_date', FaqGroup.entries),
  FaqArticle('meet_in_person', FaqGroup.people),
  FaqArticle('review_flag', FaqGroup.people),
  FaqArticle('no_password', FaqGroup.safety),
  FaqArticle('paper_sheet', FaqGroup.safety),
  FaqArticle('new_phone', FaqGroup.safety),
  FaqArticle('support_powers', FaqGroup.safety),
  FaqArticle('diagnostics', FaqGroup.safety),
  FaqArticle('needs_attention', FaqGroup.trouble),
  FaqArticle('waiting_for', FaqGroup.trouble),
];

/// One answer's words, in the reader's language.
final class FaqText {
  /// Creates the text.
  const FaqText({required this.question, required this.paragraphs});

  /// The question, as the hub lists it and S17.2 heads the page with.
  final String question;

  /// The answer, one paragraph per element — plain language, no jargon
  /// (01 §1.3).
  final List<String> paragraphs;

  /// Question and answer as one lowercase haystack for the hub's search.
  String get searchable => '$question ${paragraphs.join(' ')}'.toLowerCase();
}

/// The heading [group] is listed under.
String faqGroupLabel(AppLocalizations l10n, FaqGroup group) => switch (group) {
  FaqGroup.start => l10n.faqGroupStart,
  FaqGroup.entries => l10n.faqGroupEntries,
  FaqGroup.people => l10n.faqGroupPeople,
  FaqGroup.safety => l10n.faqGroupSafety,
  FaqGroup.trouble => l10n.faqGroupTrouble,
};

/// The words of the answer [id], or null when no such answer exists — the
/// S17.2 missing state (13 §4.3).
FaqText? faqText(AppLocalizations l10n, String id) => switch (id) {
  'money_in_out' => FaqText(
    question: l10n.faqMoneyInOutQ,
    paragraphs: [l10n.faqMoneyInOutA1, l10n.faqMoneyInOutA2],
  ),
  'offline' => FaqText(
    question: l10n.faqOfflineQ,
    paragraphs: [l10n.faqOfflineA1, l10n.faqOfflineA2],
  ),
  'fix_entry' => FaqText(
    question: l10n.faqFixEntryQ,
    paragraphs: [l10n.faqFixEntryA1, l10n.faqFixEntryA2],
  ),
  'locked_date' => FaqText(
    question: l10n.faqLockedDateQ,
    paragraphs: [l10n.faqLockedDateA1, l10n.faqLockedDateA2],
  ),
  'meet_in_person' => FaqText(
    question: l10n.faqMeetInPersonQ,
    paragraphs: [l10n.faqMeetInPersonA1, l10n.faqMeetInPersonA2],
  ),
  'review_flag' => FaqText(
    question: l10n.faqReviewFlagQ,
    paragraphs: [l10n.faqReviewFlagA1, l10n.faqReviewFlagA2],
  ),
  'no_password' => FaqText(
    question: l10n.faqNoPasswordQ,
    paragraphs: [l10n.faqNoPasswordA1, l10n.faqNoPasswordA2],
  ),
  'paper_sheet' => FaqText(
    question: l10n.faqPaperSheetQ,
    paragraphs: [l10n.faqPaperSheetA1, l10n.faqPaperSheetA2],
  ),
  'new_phone' => FaqText(
    question: l10n.faqNewPhoneQ,
    paragraphs: [l10n.faqNewPhoneA1, l10n.faqNewPhoneA2],
  ),
  'support_powers' => FaqText(
    question: l10n.faqSupportPowersQ,
    paragraphs: [
      l10n.faqSupportPowersA1,
      l10n.faqSupportPowersA2,
      l10n.faqSupportPowersA3,
    ],
  ),
  'diagnostics' => FaqText(
    question: l10n.faqDiagnosticsQ,
    paragraphs: [
      l10n.faqDiagnosticsA1,
      l10n.faqDiagnosticsA2,
      l10n.faqDiagnosticsA3,
    ],
  ),
  'needs_attention' => FaqText(
    question: l10n.faqNeedsAttentionQ,
    paragraphs: [l10n.faqNeedsAttentionA1, l10n.faqNeedsAttentionA2],
  ),
  'waiting_for' => FaqText(
    question: l10n.faqWaitingForQ,
    paragraphs: [l10n.faqWaitingForA1, l10n.faqWaitingForA2],
  ),
  _ => null,
};

/// One group's matching answers, for the hub's list.
///
/// [query] is matched, case-folded, against the question *and* the answer —
/// a reader searching "paper" should reach the answer whose question says
/// "sheet". An empty query matches everything, so the unsearched hub is the
/// whole list.
List<FaqArticle> faqSearch(AppLocalizations l10n, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return faqArticles;
  return [
    for (final a in faqArticles)
      if (faqText(l10n, a.id)?.searchable.contains(q) ?? false) a,
  ];
}
