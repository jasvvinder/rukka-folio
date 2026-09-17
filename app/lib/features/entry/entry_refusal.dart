// A refused inter-book movement, in words (07 §1 rule 6 🔒 — no dead ends:
// "every blocked action explains why and offers the path").
//
// [InterBookRefused] is typed precisely so a screen never prints an engine
// symbol at a shopkeeper: `InterBookRefusal.notAMoneyAccount` is a name for
// this file to translate, not a sentence. Every branch is covered, so a
// refusal added to the engine breaks this switch at compile time rather than
// reaching a user as a raw enum.
//
// The draft is never touched on a refusal: nothing was appended (02 §6 — the
// facade refuses before it authors), so the amount and both slots stay
// exactly as they were and the member fixes the one thing that was wrong.
import '../../l10n/gen/app_localizations.dart';
import '../../shared/ledger/local_ledger.dart';

/// The sentence for [refusal] — consumer vocabulary (02 §10 🔒).
String interBookRefusalMessage(
  AppLocalizations l10n,
  InterBookRefusal refusal,
) => switch (refusal) {
  InterBookRefusal.sameBook => l10n.entryMoveRefusedSameBook,
  InterBookRefusal.bookNotHeld => l10n.entryMoveRefusedBookNotHeld,
  InterBookRefusal.notAMoneyAccount => l10n.entryMoveRefusedNotMoney,
  InterBookRefusal.notAnExpenseCategory => l10n.entryMoveRefusedNotExpense,
  InterBookRefusal.amountNotPositive => l10n.entryMoveRefusedAmount,
};
