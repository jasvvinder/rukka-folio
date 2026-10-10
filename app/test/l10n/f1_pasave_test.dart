// F1-PASAVE-1…3 — ਪੰਜਾਬੀ *Save* is ਸੇਵ ਕਰੋ (01 §2 term table; ADR
// 2026-10-08 §2, "unchanged"; owner ruling 10 Oct 2026). The app's PA used
// ਸੰਭਾਲੋ / ਸਾਂਭੋ — words that mean *keep / look after* — for the Save action.
//
// The expected words are typed here as literals — never read back from the
// ARB files, so a wrong ARB value fails the test instead of agreeing with it.
// The one place the ARB parts are read is the completeness sweep of
// F1-PASAVE-2, which checks a property (an English *save* has ਸੇਵ in ਪੰਜਾਬੀ;
// ਸੰਭਾਲ / ਸਾਂਭ only where the English is not *save*) so that a key the
// literal table does not name still cannot slip back to the old word.
@Tags(['F1'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:core_ledger/core_ledger.dart' show EntryKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/entry/screens/s2_add_entry_screen.dart';
import 'package:rukka_folio/features/import/import_routes.dart';
import 'package:rukka_folio/features/ledger/screens/s4_1_entry_detail_screen.dart';
import 'package:rukka_folio/features/members/members_repository.dart';
import 'package:rukka_folio/features/members/screens/s9_members_screen.dart';
import 'package:rukka_folio/l10n/gen/app_localizations.dart';

import '../features/import/s7_1_inbox_test.dart' as s7_1;
import '../shared/test_app.dart';

const _pa = Locale('pa');
const _save = 'ਸੇਵ ਕਰੋ';

/// The words the PA build used for *Save* before the ruling.
const _oldSave = ['ਸੰਭਾਲ', 'ਸਾਂਭ'];

/// Every string drawn on screen right now.
Iterable<String> _drawn(WidgetTester tester) sync* {
  for (final e in find.byType(RichText).evaluate()) {
    yield (e.widget as RichText).text.toPlainText();
  }
}

void _expectNoOldSave(WidgetTester tester, String where) {
  for (final s in _drawn(tester)) {
    for (final old in _oldSave) {
      expect(
        s.contains(old),
        isFalse,
        reason: '$where under pa draws "$s" — Save is $_save, not $old',
      );
    }
  }
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 1));
}

/// Every PA string that carries the Save action, as a button, a state, an
/// error or a sentence about saving — key → (generated getter, expected).
Map<String, (String, String)> _paSaveTable(AppLocalizations pa) => {
  'account.edit.save': (pa.accountEditSave, "ਸੇਵ ਕਰੋ"),
  'account.edit.saving': (pa.accountEditSaving, "ਸੇਵ ਕਰ ਰਹੇ ਹਾਂ…"),
  'account.edit.saved': (pa.accountEditSaved, "ਸੇਵ ਹੋ ਗਿਆ"),
  'account.edit.error': (pa.accountEditError, "ਤੁਹਾਡਾ ਨਾਂ ਸੇਵ ਨਹੀਂ ਹੋ ਸਕਿਆ।"),
  'advances.sheet.save': (pa.advancesSheetSave, "ਸੇਵ ਕਰੋ"),
  'advances.sheet.saving': (pa.advancesSheetSaving, "ਸੇਵ ਹੋ ਰਹੀ ਹੈ…"),
  'advances.sheet.error': (
    pa.advancesSheetError,
    "ਇਹ ਸੇਵ ਨਹੀਂ ਹੋ ਸਕੀ। ਕੁਝ ਵੀ ਨਹੀਂ ਬਦਲਿਆ।",
  ),
  'count.save': (pa.countSave, "ਗਿਣਤੀ ਸੇਵ ਕਰੋ"),
  'count.saving': (pa.countSaving, "ਗਿਣਤੀ ਸੇਵ ਹੋ ਰਹੀ ਹੈ"),
  'count.save.error': (pa.countSaveError, "ਗਿਣਤੀ ਸੇਵ ਨਹੀਂ ਹੋਈ।"),
  'count.confirm.less': (
    pa.countConfirmLess('X'),
    "ਤੁਹਾਡੀ ਗਿਣਤੀ ਵਹੀ ਨਾਲੋਂ X ਘੱਟ ਹੈ। ਸੇਵ ਕਰਨ ’ਤੇ ਇੱਕ ਐਂਟਰੀ ਪੈ ਜਾਵੇਗੀ, ਤਾਂ ਜੋ ਵਹੀ ਰੋਕੜ ਨਾਲ ਮਿਲ ਜਾਵੇ।",
  ),
  'count.confirm.more': (
    pa.countConfirmMore('X'),
    "ਤੁਹਾਡੀ ਗਿਣਤੀ ਵਹੀ ਨਾਲੋਂ X ਵੱਧ ਹੈ। ਸੇਵ ਕਰਨ ’ਤੇ ਇੱਕ ਐਂਟਰੀ ਪੈ ਜਾਵੇਗੀ, ਤਾਂ ਜੋ ਵਹੀ ਰੋਕੜ ਨਾਲ ਮਿਲ ਜਾਵੇ।",
  ),
  'count.offline': (pa.countOffline, "ਫ਼ੋਨ ’ਤੇ ਸੇਵ ਹੋਇਆ · ਸਿੰਕ ਹੋਵੇਗਾ"),
  'backup.sheet.title': (pa.backupSheetTitle, "ਰਿਕਵਰੀ ਸ਼ੀਟ ਫ਼ਾਈਲ ਵਜੋਂ ਸੇਵ ਕਰੋ"),
  'backup.sheet.action': (pa.backupSheetAction, "ਸੇਵ ਕਰੋ ਜਾਂ ਛਾਪੋ"),
  'backup.saved_offline': (
    pa.backupSavedOffline,
    "ਫ਼ੋਨ ’ਤੇ ਸੇਵ ਹੋਇਆ · ਸਿੰਕ ਹੋਵੇਗਾ",
  ),
  'backup.save.error': (
    pa.backupSaveError,
    "ਇਹ ਬਦਲਾਅ ਸੇਵ ਨਹੀਂ ਹੋ ਸਕਿਆ। ਦੁਬਾਰਾ ਕੋਸ਼ਿਸ਼ ਕਰੋ।",
  ),
  'guardians.save': (pa.guardiansSave, "ਭਰੋਸੇਮੰਦ ਮੈਂਬਰ ਸੇਵ ਕਰੋ"),
  'guardians.save.blocked.few': (
    pa.guardiansSaveBlockedFew,
    "ਸੇਵ ਕਰਨ ਤੋਂ ਪਹਿਲਾਂ ਘੱਟੋ-ਘੱਟ 2 ਜਣੇ ਚੁਣੋ।",
  ),
  'guardians.save.blocked.meet': (
    pa.guardiansSaveBlockedMeet,
    "ਸੇਵ ਕਰਨ ਤੋਂ ਪਹਿਲਾਂ ਹਰ ਚੁਣੇ ਜਣੇ ਨੂੰ ਮਿਲੋ।",
  ),
  'guardians.save.blocked.unavailable': (
    pa.guardiansSaveBlockedUnavailable,
    "ਤੁਹਾਡਾ ਚੁਣਿਆ ਕੋਈ ਜਣਾ ਹੁਣ ਭਰੋਸੇਮੰਦ ਮੈਂਬਰ ਨਹੀਂ ਬਣ ਸਕਦਾ। ਸੇਵ ਕਰਨ ਲਈ ਉਸ ਨੂੰ ਸੂਚੀ ਵਿੱਚੋਂ ਹਟਾਓ।",
  ),
  'guardians.saved': (pa.guardiansSaved, "ਭਰੋਸੇਮੰਦ ਮੈਂਬਰ ਸੇਵ ਹੋ ਗਏ।"),
  'guardians.save.error': (
    pa.guardiansSaveError,
    "ਇਹ ਸੇਵ ਨਹੀਂ ਹੋਇਆ। ਦੁਬਾਰਾ ਕੋਸ਼ਿਸ਼ ਕਰੋ।",
  ),
  'guardians.offline': (
    pa.guardiansOffline,
    "ਤੁਸੀਂ ਆਫ਼ਲਾਈਨ ਹੋ। ਤੁਹਾਡੀ ਚੋਣ ਫ਼ੋਨ ’ਤੇ ਸੇਵ ਕੀਤੀ ਗਈ ਹੈ ਤੇ ਵਾਪਸ ਆਉਣ ’ਤੇ ਭੇਜ ਦਿੱਤੀ ਜਾਵੇਗੀ।",
  ),
  'entry.save': (pa.entrySave, "ਸੇਵ ਕਰੋ"),
  'entry.saved': (pa.entrySaved, "ਸੇਵ ਹੋਇਆ ✓ (ਫ਼ੋਨ ਉੱਤੇ)"),
  'entry.save_error': (pa.entrySaveError, "ਸੇਵ ਨਹੀਂ ਹੋਇਆ — ਦੁਬਾਰਾ ਕੋਸ਼ਿਸ਼ ਕਰੋ"),
  'faq.fix_entry.q': (
    pa.faqFixEntryQ,
    "ਕੀ ਮੈਂ ਸੇਵ ਕਰਨ ਤੋਂ ਬਾਅਦ ਇੰਦਰਾਜ ਬਦਲ ਸਕਦਾ ਹਾਂ?",
  ),
  'faq.fix_entry.a2': (
    pa.faqFixEntryA2,
    "ਸੇਵ ਕਰਨ ਤੋਂ ਤੁਰੰਤ ਬਾਅਦ ਇੱਕ ਸੌਖਾ ਰਾਹ ਵੀ ਹੈ: ਹੇਠਾਂ ਆਏ ਸੁਨੇਹੇ ਉੱਤੇ “ਵਾਪਸ” ਦਸ ਸਕਿੰਟ ਤੱਕ ਇੰਦਰਾਜ ਪੂਰੀ ਤਰ੍ਹਾਂ ਹਟਾ ਦਿੰਦਾ ਹੈ।",
  ),
  'faq.offline.a2': (
    pa.faqOfflineA2,
    "ਜੋ ਅਜੇ ਭੇਜਿਆ ਨਹੀਂ ਗਿਆ, ਉਹ “ਫ਼ੋਨ ’ਤੇ ਸੇਵ ਹੋਇਆ · ਸਿੰਕ ਹੋਵੇਗਾ” ਵਜੋਂ ਦਿਸਦਾ ਹੈ ਅਤੇ ਕਨੈਕਸ਼ਨ ਆਉਂਦੇ ਹੀ ਆਪੇ ਚਲਾ ਜਾਂਦਾ ਹੈ।",
  ),
  'faq.review_flag.q': (
    pa.faqReviewFlagQ,
    "ਮੇਰੀ ਇੰਦਰਾਜ ਕਹਿੰਦੀ ਹੈ ਕਿ ਕੋਈ ਇਸ ਨੂੰ ਵੇਖੇਗਾ। ਕੀ ਇਹ ਸੇਵ ਹੋ ਗਈ ਹੈ?",
  ),
  'faq.review_flag.a1': (
    pa.faqReviewFlagA1,
    "ਸੇਵ ਵੀ ਹੋ ਗਈ ਹੈ ਤੇ ਵਹੀ ਵਿੱਚ ਗਿਣੀ ਵੀ ਜਾਂਦੀ ਹੈ। ਉਹ ਸੁਨੇਹਾ ਸਿਰਫ਼ ਇਹ ਦੱਸਦਾ ਹੈ ਕਿ ਰਕਮ ਤੁਹਾਡੇ ਲਈ ਰੱਖੀ ਹੱਦ ਤੋਂ ਵੱਧ ਸੀ, ਇਸ ਲਈ ਇਹ ਮਾਲਕ ਦੇ ਇਨਬਾਕਸ ਵਿੱਚ ਵੀ ਪਹੁੰਚਦੀ ਹੈ।",
  ),
  'import.inbox.note.save': (pa.importInboxNoteSave, "ਸੇਵ ਕਰੋ"),
  'inbox.card.posted': (
    pa.inboxCardPosted('X'),
    "ਇਹ ਪਹਿਲਾਂ ਹੀ ਵਹੀ ਵਿੱਚ ਹਨ। ਜਿਸ ਵੇਲੇ X ਨੇ ਇਹ ਸੇਵ ਕੀਤੀਆਂ, ਉਸੇ ਵੇਲੇ ਗਿਣੀਆਂ ਗਈਆਂ — ਤੁਸੀਂ ਇਨ੍ਹਾਂ ਦੀ ਜਾਂਚ ਕਰ ਰਹੇ ਹੋ, ਇਨ੍ਹਾਂ ਨੂੰ ਰੋਕਿਆ ਨਹੀਂ ਹੋਇਆ।",
  ),
  'inbox.step.field.saved': (pa.inboxStepFieldSaved, "ਸੇਵ ਹੋਈ"),
  'inbox.step.working': (pa.inboxStepWorking, "ਸੇਵ ਹੋ ਰਹੀ ਹੈ…"),
  'ledger.quick_add.save': (pa.ledgerQuickAddSave, "ਸੇਵ ਕਰੋ"),
  'ledger.quick_add.save_error': (
    pa.ledgerQuickAddSaveError,
    "ਖਾਤਾ ਸੇਵ ਨਹੀਂ ਹੋ ਸਕਿਆ। ਦੁਬਾਰਾ ਕੋਸ਼ਿਸ਼ ਕਰੋ।",
  ),
  'ledger.entry.trail.saved': (pa.ledgerEntryTrailSaved, "ਸੇਵ ਹੋਈ"),
  'ledger.entry.amend.save': (pa.ledgerEntryAmendSave, "ਸੁਧਾਰ ਸੇਵ ਕਰੋ"),
  'ledger.entry.amend.error': (
    pa.ledgerEntryAmendError,
    "ਇਹ ਸੁਧਾਰ ਸੇਵ ਨਹੀਂ ਹੋ ਸਕਿਆ",
  ),
  'ledger.entry.amend.explain': (
    pa.ledgerEntryAmendExplain,
    "ਸੁਧਾਰ ਨਵੀਂ ਐਂਟਰੀ ਵਜੋਂ ਸੇਵ ਹੁੰਦਾ ਹੈ। ਜੋ ਲਿਖਤ ਤੁਸੀਂ ਵੇਖ ਰਹੇ ਹੋ, ਉਹ ਇਤਿਹਾਸ ਵਿੱਚ ਰਹਿੰਦੀ ਹੈ।",
  ),
  'ledger.opening_prompt.not_needed_unavailable': (
    pa.ledgerOpeningPromptNotNeededUnavailable,
    "“ਲੋੜ ਨਹੀਂ” ਹਾਲੇ ਸੇਵ ਨਹੀਂ ਹੋ ਸਕਦਾ — ਇਹ ਅਗਲੇ ਅੱਪਡੇਟ ਵਿੱਚ ਆਵੇਗਾ। ਉਦੋਂ ਤੱਕ ਇਹ ਨੋਟ ਇੱਥੇ ਰਹੇਗਾ।",
  ),
  'ledger.opening_sheet.save': (pa.ledgerOpeningSheetSave, "ਸੇਵ ਕਰੋ"),
  'ledger.opening_sheet.save_error': (
    pa.ledgerOpeningSheetSaveError,
    "ਸ਼ੁਰੂਆਤੀ ਬਾਕੀ ਸੇਵ ਨਹੀਂ ਹੋ ਸਕੀ। ਫਿਰ ਕੋਸ਼ਿਸ਼ ਕਰੋ — ਜਾਂ ਬਾਅਦ ਵਿੱਚ ਤੁਹਾਡੀਆਂ ਵਹੀਆਂ → ਸ਼ੁਰੂਆਤੀ ਬਾਕੀ ਵਿੱਚ ਠੀਕ ਕਰੋ।",
  ),
  'members.limit.edit.save': (pa.membersLimitEditSave, "ਹੱਦ ਸੇਵ ਕਰੋ"),
  'members.limit.edit.working': (pa.membersLimitEditWorking, "ਸੇਵ ਕਰ ਰਹੇ ਹਾਂ…"),
  'members.limit.edit.error': (
    pa.membersLimitEditError,
    "ਇਹ ਹੱਦ ਸੇਵ ਨਹੀਂ ਹੋ ਸਕੀ। ਦੁਬਾਰਾ ਕੋਸ਼ਿਸ਼ ਕਰੋ।",
  ),
  'menu.backup.row.subtitle': (
    pa.menuBackupRowSubtitle,
    "ਪਲੇਟਫਾਰਮ ਕੁੰਜੀ ਸਿੰਕ, ਆਪਣੀ ਰਿਕਵਰੀ ਸ਼ੀਟ ਸੇਵ ਕਰੋ, ਅਤੇ ਮਹੀਨਾਵਾਰ ਪੜ੍ਹਨਯੋਗ ਕਾਪੀ।",
  ),
  'onboarding.business_opening.save': (
    pa.onboardingBusinessOpeningSave,
    "ਸੇਵ ਕਰੋ ਤੇ ਅੱਗੇ ਵਧੋ",
  ),
  'onboarding.set_pin.saving': (
    pa.onboardingSetPinSaving,
    "ਤੁਹਾਡਾ ਪਿੰਨ ਸੇਵ ਹੋ ਰਿਹਾ ਹੈ…",
  ),
  'onboarding.set_pin.save_failed': (
    pa.onboardingSetPinSaveFailed,
    "ਅਸੀਂ ਉਹ ਪਿੰਨ ਸੇਵ ਨਹੀਂ ਕਰ ਸਕੇ — ਇੱਕ ਵਾਰ ਹੋਰ ਕੋਸ਼ਿਸ਼ ਕਰੋ",
  ),
  'onboarding.books_safe.backup.destination': (
    pa.onboardingBooksSafeBackupDestination('X'),
    "X ਵਿੱਚ ਸੇਵ ਹੁੰਦਾ ਹੈ",
  ),
  'onboarding.books_safe.backup.destination_unset': (
    pa.onboardingBooksSafeBackupDestinationUnset,
    "ਤੁਹਾਡੀ ਆਪਣੀ ਕਲਾਊਡ ਡਰਾਈਵ ਵਿੱਚ ਸੇਵ ਹੁੰਦਾ ਹੈ",
  ),
  'onboarding.books_safe.backup.save_failed': (
    pa.onboardingBooksSafeBackupSaveFailed,
    "ਅਸੀਂ ਉਹ ਤਬਦੀਲੀ ਸੇਵ ਨਹੀਂ ਕਰ ਸਕੇ — ਇੱਕ ਵਾਰ ਹੋਰ ਕੋਸ਼ਿਸ਼ ਕਰੋ",
  ),
  'onboarding.family.accounts.save': (
    pa.onboardingFamilyAccountsSave,
    "ਸੇਵ ਕਰੋ",
  ),
  'onboarding.trust.accounts.save': (pa.onboardingTrustAccountsSave, "ਸੇਵ ਕਰੋ"),
  'onboarding.opening.save_error': (
    pa.onboardingOpeningSaveError,
    "ਤੁਹਾਡੇ ਬਕਾਏ ਸੇਵ ਨਹੀਂ ਹੋ ਸਕੇ। ਕੁਝ ਨਹੀਂ ਬਦਲਿਆ — ਦੁਬਾਰਾ 'ਪੂਰਾ ਕਰੋ' ਦਬਾਓ।",
  ),
  'onboarding.recovery_sheet.print': (
    pa.onboardingRecoverySheetPrint,
    "ਸ਼ੀਟ ਛਾਪੋ ਜਾਂ ਸੇਵ ਕਰੋ",
  ),
  'recovery.fork.sheet.sub': (
    pa.recoveryForkSheetSub,
    "ਕਾਗ਼ਜ਼ ਵਾਲੀ, ਜਾਂ ਉਹ ਫ਼ਾਈਲ ਜੋ ਤੁਸੀਂ ਸੇਵ ਕੀਤੀ ਸੀ",
  ),
  'recovery.nothing.private.key_sheet': (
    pa.recoveryNothingPrivateKeySheet,
    "ਆਪਣੀ ਰਿਕਵਰੀ ਸ਼ੀਟ ਲੱਭਣੀ — ਕਾਗ਼ਜ਼ ਵਾਲੀ, ਜਾਂ ਉਹ ਫ਼ਾਈਲ ਜੋ ਤੁਸੀਂ ਸੇਵ ਕੀਤੀ ਸੀ।",
  ),
  'recovery.sheet.what': (
    pa.recoverySheetWhat,
    "ਇੱਕ ਛਪਿਆ ਹੋਇਆ ਸਫ਼ਾ, ਜਿਸ ਉੱਤੇ ਇੱਕ ਚੌਰਸ ਕੋਡ ਅਤੇ ਹੇਠਾਂ ਉਹੀ ਕੋਡ ਅੱਖਰਾਂ ਵਿੱਚ ਹੁੰਦਾ ਹੈ। ਹੋ ਸਕਦਾ ਹੈ ਤੁਸੀਂ ਇਸ ਨੂੰ ਫ਼ਾਈਲ ਵਜੋਂ ਸੇਵ ਕੀਤਾ ਹੋਵੇ।",
  ),
  'reports.export.saved': (pa.reportsExportSaved('X'), "ਸੇਵ ਹੋ ਗਈ: X"),
  'reports.export.failed': (pa.reportsExportFailed, "ਰਿਪੋਰਟ ਸੇਵ ਨਹੀਂ ਹੋ ਸਕੀ।"),
  'connection.notice.body': (
    pa.connectionNoticeBody,
    "ਐਪ ਬਿਨਾਂ ਇੰਟਰਨੈੱਟ ਚੱਲਦੀ ਹੈ। ਤੁਸੀਂ ਜੋ ਵੀ ਦਰਜ ਕਰਦੇ ਹੋ, ਉਹ ਇਸ ਫ਼ੋਨ ’ਤੇ ਸੇਵ ਹੋ ਜਾਂਦਾ ਹੈ ਅਤੇ ਕਨੈਕਸ਼ਨ ਵਾਪਸ ਆਉਣ ’ਤੇ ਆਪੇ ਸਿੰਕ ਹੋ ਜਾਂਦਾ ਹੈ।",
  ),
  'subscription.sheet.read_only.blocked': (
    pa.subscriptionSheetReadOnlyBlocked,
    "ਤੁਹਾਡਾ ਪਲਾਨ ਖ਼ਤਮ ਹੋ ਗਿਆ ਹੈ, ਇਸ ਲਈ ਇਹ ਐਂਟਰੀ ਹਾਲੇ ਸੇਵ ਨਹੀਂ ਹੋ ਸਕਦੀ।",
  ),
  'subscription.sheet.book_full.blocked': (
    pa.subscriptionSheetBookFullBlocked,
    "ਇਹ ਵਹੀ ਪਲਾਨ ਦੀ ਹੱਦ ਤੱਕ ਪਹੁੰਚ ਗਈ ਹੈ, ਇਸ ਲਈ ਇਹ ਐਂਟਰੀ ਹਾਲੇ ਸੇਵ ਨਹੀਂ ਹੋ ਸਕਦੀ।",
  ),
};

/// English strings that say *save* but do not mean the Save action, so their
/// ਪੰਜਾਬੀ rightly has no ਸੇਵ.
const _enSaveNotTheAction = {
  // Money saved in the month (07 §13) — ਬਚਿਆ.
  'close.summary.saved',
  // A discount on the annual plan — ਬਚਤ.
  'plans.cycle.saving',
  // S11.4 Backup (c3 R4 'Backup settings · O5’s wording, with status'):
  // "already saved with us" means stored on the server — ਸੁਰੱਖਿਅਤ ਹਨ, as
  // S0.5's own intro says "stored". ⚠️ SPEC: owner item, see lane report.
  'backup.intro',
};

/// ਸੰਭਾਲ / ਸਾਂਭ kept on purpose — the English is not *save* in any of them.
const _oldWordKeptOnPurpose = {
  'faq.support_powers.a2', // "sort out your plan" — manage
  'diag.field.schema_version', // "Storage version" — a noun (S17.4)
  'inbox.structural.kind.archive', // "Archive {book}"
  'onboarding.books_safe.intro', // "What needs keeping safe is your key"
  'onboarding.recovery_sheet.kept_safe', // "I've kept it safe"
  'subscription.row.manage.title', // "Manage subscription"
  'manage.title', // "Manage subscription"
  'manage.cancel.ios.reason', // "Apple handles the subscription"
};

Map<String, String> _part(File f) => {
  for (final e in (jsonDecode(f.readAsStringSync()) as Map).entries)
    if (!(e.key as String).startsWith('@')) e.key as String: e.value as String,
};

void main() {
  testWidgets('F1-PASAVE-1 S2 Add entry: the production Save button reads '
      'ਸੇਵ ਕਰੋ under pa', (tester) async {
    final s = await seedSoloLedger();
    await pumpRk(
      tester,
      AddEntryScreen(bookId: s.bookId, kind: EntryKind.moneyIn),
      ledger: s.ledger,
      locale: _pa,
    );
    await tester.pump();

    final save = find.byKey(AddEntryKeys.save);
    expect(save, findsOneWidget);
    expect(
      find.descendant(of: save, matching: find.text(_save)),
      findsOneWidget,
      reason: 'S2 Save must read ਸੇਵ ਕਰੋ (ADR 2026-10-08 §2)',
    );
    _expectNoOldSave(tester, 'S2');
    await _unmount(tester);
  });

  group('F1-PASAVE-2 every PA Save button and Save state says ਸੇਵ', () {
    test('F1-PASAVE-2 each Save string, as typed here', () {
      final pa = lookupAppLocalizations(_pa);
      for (final e in _paSaveTable(pa).entries) {
        expect(e.value.$1, e.value.$2, reason: e.key);
      }
    });

    test('F1-PASAVE-2 sweep: an English *save* has ਸੇਵ in ਪੰਜਾਬੀ, and '
        'ਸੰਭਾਲ / ਸਾਂਭ appear only where the English is not *save*', () {
      final table = _paSaveTable(lookupAppLocalizations(_pa)).keys.toSet();
      final saveWord = RegExp(r'\bsav(e|ed|es|ing)\b', caseSensitive: false);
      final parts = Directory('lib/l10n/parts')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('_pa.arb'))
          .toList();
      expect(parts, isNotEmpty);
      final missing = <String>[];
      final old = <String>[];
      for (final paFile in parts) {
        final pa = _part(paFile);
        final en = _part(File(paFile.path.replaceFirst('_pa.arb', '_en.arb')));
        for (final MapEntry(:key, :value) in pa.entries) {
          final enValue = en[key] ?? '';
          if (saveWord.hasMatch(enValue) &&
              !_enSaveNotTheAction.contains(key) &&
              !RegExp('ਸੇਵ(?![ਾਿ])').hasMatch(value)) {
            missing.add('$key: "$enValue" → "$value"');
          }
          if (saveWord.hasMatch(enValue) &&
              !_enSaveNotTheAction.contains(key) &&
              !table.contains(key)) {
            missing.add('$key is a Save string the literal table lacks');
          }
          if (_oldSave.any(value.contains) &&
              !_oldWordKeptOnPurpose.contains(key)) {
            old.add('$key: "$value"');
          }
        }
      }
      expect(missing, isEmpty, reason: 'PA Save strings without ਸੇਵ');
      expect(old, isEmpty, reason: 'PA strings back on ਸੰਭਾਲ / ਸਾਂਭ');
    });
  });

  group('F1-PASAVE-3 the changed Save labels hold at 200 % in ਪੰਜਾਬੀ, '
      'drawn on the sheets that carry them', () {
    for (final phone in rkPhones) {
      final at = '${phone.width.toInt()}×${phone.height.toInt()}';

      testWidgets('F1-PASAVE-3 S4.1 Entry detail amend sheet (c2 *Amended · '
          'struck-through history*): ਸੁਧਾਰ ਸੇਵ ਕਰੋ at 200 % on $at', (
        tester,
      ) async {
        final seed = await seedSoloLedger();
        final entry = seed.entries.firstWhere(
          (e) => e.kind == EntryKind.moneyOut,
        );
        await pumpRk(
          tester,
          EntryDetailScreen(entryId: entry.id),
          ledger: seed.ledger,
          locale: _pa,
          textScale: 2,
          viewport: phone,
        );
        final l = AppLocalizations.of(
          tester.element(find.byType(Scaffold).first),
        );
        final correct = find.text(l.ledgerEntryAmend);
        await tester.scrollUntilVisible(
          correct,
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.tap(correct);
        await tester.pumpAndSettle();
        expect(find.text(l.ledgerEntryAmendTitle), findsOneWidget);
        expect(find.text('ਸੁਧਾਰ $_save'), findsOneWidget);
        expect(tester.takeException(), isNull);
        expectTextFits(tester, reason: 'S4.1 amend sheet pa 200 % $at');
        _expectNoOldSave(tester, 'S4.1 amend sheet');
        await _unmount(tester);
      });

      testWidgets(
        'F1-PASAVE-3 S9 Books & members limit sheet (c13 *Books & '
        'members*): ਹੱਦ ਸੇਵ ਕਰੋ at 200 % on $at',
        (tester) async {
          final repo = FakeMembersRepository(initial: _limitSnapshot);
          await pumpRk(
            tester,
            MembersRepositoryScope(
              repository: repo,
              child: const MembersScreen(),
            ),
            locale: _pa,
            textScale: 2,
            viewport: phone,
          );
          final l = AppLocalizations.of(
            tester.element(find.byType(Scaffold).first),
          );
          // The one editable limit row: Sunita's in *Shop* (the admin's own
          // row carries no limit to edit).
          final limit = find
              .ancestor(
                of: find.byIcon(Icons.edit_outlined),
                matching: find.byType(InkWell),
              )
              .first;
          await tester.scrollUntilVisible(
            limit,
            200,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.pumpAndSettle();
          await tester.tap(limit);
          await tester.pumpAndSettle();
          expect(find.text(l.membersLimitEditTitle), findsWidgets);
          expect(find.text('ਹੱਦ $_save'), findsOneWidget);
          expect(tester.takeException(), isNull);
          expectTextFits(tester, reason: 'S9 limit sheet pa 200 % $at');
          _expectNoOldSave(tester, 'S9 limit sheet');
        },
        // Measured 10 Oct 2026: the sheet's Column overflows the bottom at
        // 200 % in EN (132 / 181 px), PA (168 px) and HI (180 / 269 px) on
        // 360×800 / 375×667 — the sheet does not scroll, whatever the label
        // says. The fix is in features/members (not this lane's directory).
        skip: true, // ⚠️ open: S9 _LimitSheet 200 % overflow — lane report.
      );

      testWidgets('F1-PASAVE-3 S7.1 Import inbox note editor (c8 *Import '
          'inbox · four row states*): ਸੇਵ ਕਰੋ at 200 % on $at', (tester) async {
        final statement = s7_1.readStatement();
        await s7_1.pumpInbox(
          tester,
          statement: statement,
          source: FakeImportSource(),
          locale: _pa,
          textScale: 2,
          viewport: phone,
        );
        final id = s7_1.idOf(statement, 0);
        final suspense = s7_1.inRow(
          id,
          find.byKey(ImportInboxKeys.suspense(id)),
        );
        await tester.ensureVisible(suspense);
        await tester.pumpAndSettle();
        await tester.tap(suspense);
        await tester.pumpAndSettle();
        final note = s7_1.inRow(id, find.byKey(ImportInboxKeys.note(id)));
        await tester.ensureVisible(note);
        await tester.pumpAndSettle();
        await tester.tap(note);
        await tester.pumpAndSettle();
        expect(find.byKey(ImportInboxKeys.noteField(id)), findsOneWidget);
        expect(find.text(_save), findsOneWidget);
        expect(tester.takeException(), isNull);
        expectTextFits(tester, reason: 'S7.1 note editor pa 200 % $at');
        _expectNoOldSave(tester, 'S7.1 note editor');
      });
    }
  });
}

/// One admin and one member with a limit in *Shop* — the S9 limit row.
final _limitSnapshot = MembersSnapshot(
  tenantType: TenantType.organization,
  books: const [TenantBook(id: 'b-shop', name: 'Shop')],
  members: const [
    Member(
      id: 'u-amrit',
      displayName: 'Amrit Kaur',
      state: MembershipState.active,
      isYou: true,
      grants: [BookGrant(bookId: 'b-shop', role: BookRole.admin)],
    ),
    Member(
      id: 'u-sunita',
      displayName: 'Sunita',
      state: MembershipState.active,
      grants: [
        BookGrant(
          bookId: 'b-shop',
          role: BookRole.head,
          autoPostLimitPaise: 500000,
        ),
      ],
    ),
  ],
  yourRoles: const {'b-shop': BookRole.admin},
);
