// The step sequences of 13 §5 flows F1, F1b and F2, shared by the journey
// files. Every finder is a screen widget type, a widget Key the screen
// already exposes, or a string from the EN ARB (Journey.en) — never a
// hard-coded English sentence.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/auth/screens/s0_2_phone_otp_screen.dart';
import 'package:rukka_folio/features/auth/screens/s0_2e_no_books_screen.dart';
import 'package:rukka_folio/features/entry/entry_slots.dart';
import 'package:rukka_folio/features/entry/screens/s2_add_entry_screen.dart';
import 'package:rukka_folio/features/home/home_scope.dart';
import 'package:rukka_folio/features/home/screens/s1_home_screen.dart';
import 'package:rukka_folio/features/home/widgets/home_scope_switcher.dart';
import 'package:rukka_folio/features/onboarding/screens/s0_05_welcome_screen.dart';
import 'package:rukka_folio/features/onboarding/screens/s0_06_start_screen.dart';
import 'package:rukka_folio/features/onboarding/screens/s0_0_splash_screen.dart';
import 'package:rukka_folio/features/onboarding/screens/s0_1_language_screen.dart';
import 'package:rukka_folio/features/onboarding/screens/s0_3_purpose_screen.dart';
import 'package:rukka_folio/features/onboarding/screens/s0_4_name_photo_screen.dart';
import 'package:rukka_folio/features/onboarding/screens/s0_5_books_safe_screen.dart';
import 'package:rukka_folio/features/onboarding/screens/s0_5b_recovery_sheet_screen.dart';
import 'package:rukka_folio/features/onboarding/screens/s0_6_opening_balances_screen.dart';
import 'package:rukka_folio/features/onboarding/screens/s0_6a_business_name_screen.dart';
import 'package:rukka_folio/features/onboarding/screens/s0_6b_business_opening_balances_screen.dart';
import 'package:rukka_folio/features/onboarding/screens/s0_6c_add_another_business_screen.dart';
import 'package:rukka_folio/features/onboarding/screens/s0_6d_family_name_screen.dart';
import 'package:rukka_folio/features/onboarding/screens/s0_6e_family_members_screen.dart';
import 'package:rukka_folio/features/onboarding/screens/s0_6f_family_accounts_screen.dart';
import 'package:rukka_folio/features/onboarding/screens/s0_6g_trust_name_screen.dart';
import 'package:rukka_folio/features/onboarding/screens/s0_6h_trust_members_screen.dart';
import 'package:rukka_folio/features/onboarding/screens/s0_6i_trust_accounts_screen.dart';
import 'package:rukka_folio/features/onboarding/screens/s0_8_set_pin_screen.dart';

import 'harness.dart';

/// Which S0.06 door the journey takes.
enum Door { newBooks, signIn }

/// S0.0 → S0.1 → S0.05 → S0.06 → S0.2 (number + code). Ends with the code
/// verified; the caller waits for whatever comes after it.
Future<bool> openingSteps(Journey j, {required Door door}) async {
  final en = j.en;
  final phone = freshDemoNumber();
  j.facts['phone'] = '+91 $phone';
  j.facts['door'] = door.name;

  // S0.0 is a launch animation that hands on to S0.1 by itself; the first
  // frame can take a while on a cold emulator (libsodium, SQLCipher open).
  await j.step(
    'S0.0',
    'Splash (SplashScreen) or the language picker after it',
    find.byWidgetPredicate(
      (w) => w is SplashScreen || w is LanguagePickerScreen,
    ),
    timeout: const Duration(seconds: 90),
  );
  await j.step(
    'S0.1',
    'Language picker — "${en.onboardingLanguageTitle}"',
    find.byType(LanguagePickerScreen),
    act: () async {
      await j.tap(j.text(en.onboardingLanguageOptionEn));
      await j.tap(j.text(en.onboardingLanguageContinue));
    },
  );
  await j.step(
    'S0.05',
    'Welcome slides with "${en.onboardingWelcomeSkip}"',
    find.byType(WelcomeScreen),
    act: () => j.tap(j.text(en.onboardingWelcomeSkip)),
  );
  await j.step(
    'S0.06',
    'Start — "${en.onboardingStartNew}" / "${en.onboardingStartSignIn}"',
    find.byType(StartScreen),
    act: () => j.tap(
      j.text(
        door == Door.newBooks
            ? en.onboardingStartNew
            : en.onboardingStartSignIn,
      ),
    ),
  );
  await j.step(
    'S0.2',
    door == Door.newBooks
        ? 'Phone number — "${en.authPhoneTitle}"'
        : 'Sign-in state — "${en.authSignInTitle}"',
    find.descendant(
      of: find.byType(PhoneOtpScreen),
      matching: j.text(
        door == Door.newBooks ? en.authPhoneTitle : en.authSignInTitle,
      ),
    ),
    act: () async {
      await j.typePad(phone);
      await j.tap(j.text(en.authPhoneSend));
    },
  );
  return j.step(
    'S0.2-code',
    'Code step — "${en.authOtpTitle}"',
    j.text(en.authOtpTitle),
    timeout: const Duration(seconds: 45),
    act: () async {
      await j.typePad(journeyOtp);
      // The code verifies at the sixth digit; a Verify button, where drawn,
      // is pressed too.
      await j.settle(const Duration(milliseconds: 600));
      final verify = j.text(j.en.authOtpVerify);
      if (verify.evaluate().isNotEmpty) await j.tap(verify);
    },
  );
}

/// After the code, a device-activation "This phone is ready" may stand
/// between S0.2 and the next step; it is passed through when shown.
Future<void> passDeviceReady(Journey j, Finder next) async {
  if (j.failed) return;
  final ready = j.text(j.en.authDeviceDoneTitle);
  final i = await j.waitForAny([
    next,
    ready,
  ], timeout: const Duration(seconds: 45));
  if (i == 1) {
    await j.step(
      'S0.2-ready',
      '"${j.en.authDeviceDoneTitle}"',
      ready,
      act: () => j.tap(j.text(j.en.authDeviceContinue)),
    );
  }
}

/// F1b: after the code on a number with no books → S0.2e → *Set up new books*.
Future<bool> noBooksSteps(Journey j) async {
  final s02e = find.byType(NoBooksScreen);
  await passDeviceReady(j, s02e);
  return j.step(
    'S0.2e',
    'No books on this number — "${j.en.authNoBooksTitle}"',
    s02e,
    timeout: const Duration(seconds: 45),
    act: () => j.tap(j.text(j.en.authNoBooksSetUp)),
  );
}

/// S0.3 → S0.4 → S0.8 (set + confirm) → S0.5 → S0.5b, for [purpose].
Future<bool> sharedSetupSteps(Journey j, OnboardingPurpose purpose) async {
  final en = j.en;
  j.facts['purpose'] = purpose.name;
  await passDeviceReady(j, find.byType(PurposeScreen));
  await j.step(
    'S0.3',
    'Purpose — "${en.onboardingPurposeTitle}"',
    find.byType(PurposeScreen),
    timeout: const Duration(seconds: 45),
    act: () => j.tap(find.byKey(purposeCardKey(purpose))),
  );
  await j.step(
    'S0.4',
    'Name & photo — "${en.onboardingNamePhotoTitle}"',
    find.byType(NamePhotoScreen),
    act: () async {
      await j.enterFirstField('Journey Tester');
      await j.tap(j.text(en.onboardingNamePhotoContinueLabel));
    },
  );
  await j.step(
    'S0.8',
    'Set your PIN — "${en.onboardingSetPinTitle}"',
    find.byType(SetPinScreen),
    act: () => j.typePad(journeyPin),
  );
  await j.step(
    'S0.8-confirm',
    'Confirm PIN — "${en.onboardingSetPinConfirmTitle}"',
    j.text(en.onboardingSetPinConfirmTitle),
    act: () => j.typePad(journeyPin),
  );
  // S0.5: the sheet action is the one under test ("Make my recovery sheet"
  // was reported to jump to Home); Continue is its fallback when the sheet
  // row is not drawn.
  await j.step(
    'S0.5',
    'Keeping your books safe — "${en.onboardingBooksSafeTitle}"',
    find.byType(BooksSafeScreen),
    timeout: const Duration(seconds: 45),
    act: () async {
      final sheet = j.text(en.onboardingBooksSafeSheetAction);
      await j.tap(
        sheet.evaluate().isNotEmpty
            ? sheet
            : j.text(en.onboardingBooksSafeContinueLabel),
      );
    },
  );
  // S0.5b (ADR 2026-10-06d ruling 3 🔒, ADR 2026-10-07 ruling 1): the sheet
  // is required — *Print or save the sheet* must be live, *Skip for now*
  // absent, *I've kept it safe* asleep until the page has been opened.
  // Print makes the sheet, publishes its sealed blob to the dev server and
  // only then raises Android's print sheet (`Printing.layoutPdf`). That
  // sheet is another app's activity: this harness cannot drive it, so the
  // run waits for the page to be **saved or printed** from outside — by the
  // person watching (Save as PDF → save). Closing the sheet with Back is a
  // cancel: `layoutPdf` answers false and *I've kept it safe* stays asleep
  // (RUNG3B repair #1 — a cancelled print sheet is not an opened page), so an
  // `adb shell input keyevent BACK` no longer wakes it (⚠️ run_journeys.sh
  // sends nothing yet; reported). A publish that fails shows its reason
  // and a *Skip for now*, and the journey records the reason as a defect.
  final shown = await j.step(
    'S0.5b',
    'Recovery sheet — "${en.onboardingRecoverySheetTitle}"',
    find.byType(RecoverySheetScreen),
  );
  if (!shown) return false;
  const sheetAuthority =
      '13 §5 F1 "S0.5b sheet: print → verify by scanning it back"; '
      '13 §3.2 S0.5b "generate, print/save, verify by scanning back"; '
      '07 §3.1 step 6 🔒; ADR 2026-10-06d ruling 3; ADR 2026-10-07 ruling 1';
  final print = j.text(en.onboardingRecoverySheetPrint);
  final keptSafe = j.text(en.onboardingRecoverySheetKeptSafe);
  final skip = j.text(en.onboardingRecoverySheetSkip);
  if (!_buttonLive(print)) {
    await j.defect(
      'S0.5b-print',
      '"${en.onboardingRecoverySheetPrint}" enabled',
      '"${en.onboardingRecoverySheetPrint}" is drawn disabled, so the '
          'recovery sheet cannot be made on this path',
      authority: sheetAuthority,
    );
  }
  if (skip.evaluate().isNotEmpty) {
    await j.defect(
      'S0.5b-required',
      'no "${en.onboardingRecoverySheetSkip}" before a publish has failed',
      '"${en.onboardingRecoverySheetSkip}" is offered on arrival',
      authority: sheetAuthority,
    );
  }
  if (_buttonLive(keptSafe)) {
    await j.defect(
      'S0.5b-asleep',
      '"${en.onboardingRecoverySheetKeptSafe}" asleep until the sheet is opened',
      '"${en.onboardingRecoverySheetKeptSafe}" is live before anything was '
          'opened',
      authority: 'canvas c1/O5b',
    );
  }
  if (!_buttonLive(print)) {
    return j.step(
      'S0.5b-skip',
      'Recovery sheet — leave by "${en.onboardingRecoverySheetSkip}"',
      find.byType(RecoverySheetScreen),
      act: () => j.tap(skip),
    );
  }
  var woke = false;
  final made = await j.step(
    'S0.5b-made',
    'Sheet made, published and opened — "${en.onboardingRecoverySheetKeptSafe}" '
        'wakes',
    find.byType(RecoverySheetScreen),
    timeout: const Duration(seconds: 150),
    act: () async {
      await j.tap(print);
      final deadline = DateTime.now().add(const Duration(seconds: 140));
      while (DateTime.now().isBefore(deadline)) {
        await j.waitFor(keptSafe, timeout: const Duration(seconds: 2));
        if (_buttonLive(keptSafe)) {
          woke = true;
          return;
        }
        if (skip.evaluate().isNotEmpty) return; // the publish failed
      }
    },
  );
  if (!made) return false;
  if (!woke) {
    await j.defect(
      'S0.5b-made',
      'the sheet published and the print sheet opened',
      skip.evaluate().isNotEmpty
          ? 'the publish failed — S0.5b shows its reason and a Skip'
          : '"${en.onboardingRecoverySheetKeptSafe}" never woke (the page '
                'was not saved or printed — Back on the print sheet is a '
                'cancel — or nothing opened)',
      authority: sheetAuthority,
    );
    if (skip.evaluate().isEmpty) return false;
    return j.step(
      'S0.5b-skip',
      'Recovery sheet — leave by "${en.onboardingRecoverySheetSkip}"',
      find.byType(RecoverySheetScreen),
      act: () => j.tap(skip),
    );
  }
  j.note(
    'S0.5b: the sheet was made and published and the print sheet opened; '
    'scanning it back is the S0.7 row\'s (F1-1006d-3) and is not driven here.',
  );
  return j.step(
    'S0.5b-kept',
    'Recovery sheet — leave by "${en.onboardingRecoverySheetKeptSafe}"',
    keptSafe,
    act: () => j.tap(keptSafe),
  );
}

/// True when the button whose label is [label] is on screen and enabled.
bool _buttonLive(Finder label) {
  final button = find.ancestor(
    of: label,
    matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
  );
  if (button.evaluate().isEmpty) return false;
  return (button.evaluate().first.widget as ButtonStyleButton).enabled;
}

/// The branch steps S0.6a–i of the purpose card (07 §3.1.1).
Future<bool> branchSteps(Journey j, OnboardingPurpose purpose) async {
  final en = j.en;
  switch (purpose) {
    case OnboardingPurpose.myself:
      return !j.failed;
    case OnboardingPurpose.businesses:
      await j.step(
        'S0.6a',
        'Name your business — "${en.onboardingBusinessTitle}"',
        find.byType(BusinessNameScreen),
        act: () async {
          await j.enterFirstField('Journey Traders');
          final justMe = j.text(en.onboardingBusinessOwnershipJustMe);
          if (justMe.evaluate().isNotEmpty) await j.tap(justMe);
          await j.tap(j.text(en.onboardingBusinessContinueLabel));
        },
      );
      await j.step(
        'S0.6b',
        'Business opening balances — "${en.onboardingBusinessOpeningTitle}"',
        find.byType(BusinessOpeningBalancesScreen),
        act: () => j.tap(j.text(en.onboardingBusinessOpeningSave)),
      );
      return j.step(
        'S0.6c',
        'Add another business? — "${en.onboardingBusinessAnotherTitle}"',
        find.byType(AddAnotherBusinessScreen),
        timeout: const Duration(seconds: 60),
        act: () => j.tap(j.text(en.onboardingBusinessAnotherDone)),
      );
    case OnboardingPurpose.family:
      await j.step(
        'S0.6d',
        'Name your family — "${en.onboardingFamilyTitle}"',
        find.byType(FamilyNameScreen),
        act: () async {
          await j.enterFirstField('Journey Family');
          await j.tap(j.text(en.onboardingFamilyContinueLabel));
        },
      );
      await j.step(
        'S0.6e',
        'Who else is in the family? — "${en.onboardingFamilyMembersTitle}"',
        find.byType(FamilyMembersScreen),
        act: () => j.tap(j.text(en.onboardingFamilyMembersSkip)),
      );
      return j.step(
        'S0.6f',
        'Family shared accounts — "${en.onboardingFamilyAccountsTitle}"',
        find.byType(FamilySharedAccountsScreen),
        act: () => j.tap(j.text(en.onboardingFamilyAccountsSave)),
      );
    case OnboardingPurpose.trust:
      await j.step(
        'S0.6g',
        'Name your trust — "${en.onboardingTrustTitle}"',
        find.byType(TrustNameScreen),
        act: () async {
          await j.enterFirstField('Journey Gurudwara');
          final kind = j.text(en.onboardingTrustTypeGurudwara);
          if (kind.evaluate().isNotEmpty) await j.tap(kind);
          await j.tap(j.text(en.onboardingTrustContinueLabel));
        },
      );
      await j.step(
        'S0.6h',
        'Who runs the trust? — "${en.onboardingTrustMembersTitle}"',
        find.byType(TrustMembersScreen),
        act: () => j.tap(j.text(en.onboardingTrustMembersSkip)),
      );
      return j.step(
        'S0.6i',
        "The trust's accounts — \"${en.onboardingTrustAccountsTitle}\"",
        find.byType(TrustAccountsScreen),
        act: () => j.tap(j.text(en.onboardingTrustAccountsSave)),
      );
  }
}

/// S0.6 *Opening balances · first run* — "What do you have?" over the
/// person's personal book (desk 172, owner-ruled 6 Oct: shown once after the
/// branch steps on **every** path, canvas 1 "All five paths converge here";
/// 13 §5 F1), left by *Finish* with every figure at ₹0 — which ticks the S0.7
/// *Opening balances* row — then S1 Home with the S0.7 setup checklist, no
/// blocking state, and the books the card creates (13 §2.1).
///
/// Changed by lane P1A because S0.6 is now in the chain: the step has a
/// finder (`OpeningBalancesScreen`) and an action, and the trust card is no
/// longer exempt.
Future<bool> homeStep(Journey j, OnboardingPurpose purpose) async {
  final en = j.en;
  if (j.failed) return false;
  final home = find.byType(HomeScreen);
  final opened = await j.step(
    'S0.6',
    'Opening balances · first run — "${en.onboardingOpeningTitle}", leave by '
        '"${en.onboardingOpeningFinish}"',
    find.byType(OpeningBalancesScreen),
    timeout: const Duration(seconds: 60),
    act: () => j.tap(j.text(en.onboardingOpeningFinish)),
  );
  if (!opened) return false;
  await j.step(
    'S1',
    'Home — position + "${en.homeSetupTitle}" checklist (S0.7)',
    home,
    timeout: const Duration(seconds: 60),
  );
  if (j.failed) return false;
  // The skeleton ("Loading your position") must resolve to the checklist;
  // "Couldn't load your position" is caught by the step's blocking check
  // even when it arrives late.
  final ok = await j.step(
    'S1-checklist',
    'Setup checklist "${en.homeSetupTitle}" on Home (no "${en.homeError}")',
    j.text(en.homeSetupTitle),
  );
  if (!ok) return false;
  await _booksCheck(j, purpose);
  return !j.failed;
}

/// ADR 2026-10-07 ruling 3, on the family and trust paths whose invite step
/// (S0.6e / S0.6h) the branch skipped: Home's S0.7 checklist carries one
/// *Finish* + book-name row naming the next step, in place of *Add your
/// family*; tapping it resumes the invite step; skipping there again returns
/// to Home with the row still open. Then the recovery-sheet row reads *Check
/// your recovery sheet · Not scanned back yet* (canvas 1 O8b / O8c).
Future<bool> invitesSkippedRow(Journey j, OnboardingPurpose purpose) async {
  final en = j.en;
  if (j.failed) return false;
  final (bookName, hint, resumed, skip) = switch (purpose) {
    OnboardingPurpose.family => (
      'Journey Family',
      en.homeSetupFinishFamilyHint,
      find.byType(FamilyMembersScreen),
      en.onboardingFamilyMembersSkip,
    ),
    OnboardingPurpose.trust => (
      'Journey Gurudwara',
      en.homeSetupFinishTrustHint,
      find.byType(TrustMembersScreen),
      en.onboardingTrustMembersSkip,
    ),
    _ => throw ArgumentError.value(purpose, 'purpose', 'no invite step'),
  };
  const authority =
      'ADR 2026-10-07 ruling 3 (a *Finish <book name>* row while the invite '
      'step was skipped; it replaces *Add your family*); canvas 1 O8b / O8c';
  final row = j.text(en.homeSetupFinishBook(bookName));
  final shown = await j.step(
    'S0.7-finish',
    'Setup checklist row "${en.homeSetupFinishBook(bookName)}" · "$hint"',
    row,
    timeout: const Duration(seconds: 20),
  );
  if (!shown) return false;
  if (j.text(hint).evaluate().isEmpty) {
    await j.defect(
      'S0.7-finish',
      'the row names the next step: "$hint"',
      '"$hint" is not under the row',
      authority: authority,
    );
  }
  if (j.text(en.homeSetupAddFamily).evaluate().isNotEmpty) {
    await j.defect(
      'S0.7-finish',
      'no "${en.homeSetupAddFamily}" row on the ${purpose.name} path',
      '"${en.homeSetupAddFamily}" is drawn beside the Finish row',
      authority: authority,
    );
  }
  if (j.text(en.homeSetupRecoverySheet).evaluate().isEmpty ||
      j.text(en.homeSetupRecoverySheetHint).evaluate().isEmpty) {
    await j.defect(
      'S0.7-sheet',
      '"${en.homeSetupRecoverySheet}" · "${en.homeSetupRecoverySheetHint}"',
      'the recovery-sheet row does not read as ruling 3 says',
      authority: 'ADR 2026-10-07 ruling 3; canvas 1 O8',
    );
  }
  final opened = await j.step(
    'S0.7-resume',
    'Tapping the row resumes the skipped invite step',
    j.text(en.homeSetupFinishBook(bookName)),
    act: () => j.tap(j.text(en.homeSetupFinishBook(bookName))),
  );
  if (!opened) return false;
  final again = await j.step(
    purpose == OnboardingPurpose.family ? 'S0.6e-resumed' : 'S0.6h-resumed',
    'The invite step again, still skippable — leave by "$skip"',
    resumed,
    act: () => j.tap(j.text(skip)),
  );
  if (!again) return false;
  return j.step(
    'S0.7-finish-kept',
    'Back on Home, the row still open',
    j.text(en.homeSetupFinishBook(bookName)),
  );
}

/// The books the card must have created (13 §2.1 🔒 "Books created" column),
/// read from the scope holder Home renders from, and the switcher it draws
/// (13 §2.2: hidden for one book, two chips for two, the sheet for three+).
Future<void> _booksCheck(Journey j, OnboardingPurpose purpose) async {
  const authority =
      '13 §2.1 (Individual: 1 personal · Shopkeeper: 1 personal + 1 business '
      '· Joint family: 1 joint + n family + n personal …)';
  final screen = find.byType(HomeScreen).evaluate().first.widget as HomeScreen;
  final controller = screen.scopeController;
  if (controller == null) {
    await j.defect(
      'S1-books',
      'Home reads its books from the shell scope holder',
      'HomeScreen has no scopeController, so the books cannot be read',
      authority: authority,
    );
    return;
  }
  // The scope holder fills from the mirror after Home is up.
  final end = DateTime.now().add(const Duration(seconds: 10));
  while (DateTime.now().isBefore(end) && controller.books.isEmpty) {
    await j.settle(const Duration(milliseconds: 300));
  }
  final books = controller.books;
  j.facts['books'] = [
    for (final b in books) {'name': b.name, 'group': b.group.name},
  ];
  final groups = books.map((b) => b.group).toSet();
  final want = switch (purpose) {
    OnboardingPurpose.myself => {HomeScopeGroup.me},
    OnboardingPurpose.businesses => {
      HomeScopeGroup.me,
      HomeScopeGroup.businesses,
    },
    OnboardingPurpose.family => {HomeScopeGroup.me, HomeScopeGroup.family},
    // 13 §2.1 "1 organization (+ members' personal)": the creator is a
    // member, and S0.6 — now on every path (desk 172) — fills their personal
    // book, so it is required too (lane P1A).
    OnboardingPurpose.trust => {
      HomeScopeGroup.me,
      HomeScopeGroup.organizations,
    },
  };
  final missing = want.difference(groups);
  if (missing.isNotEmpty) {
    await j.defect(
      'S1-books',
      'books for the ${purpose.name} card: ${want.map((g) => g.name).join(' + ')}',
      'missing ${missing.map((g) => g.name).join(', ')} '
          '(found: ${books.isEmpty ? 'none' : books.map((b) => '${b.name} [${b.group.name}]').join(', ')})',
      authority: authority,
    );
  }
  final drawn = find.byType(HomeScopeControl).evaluate().isNotEmpty;
  if (books.length > 1 && !drawn) {
    await j.defect(
      'S1-scope',
      'a scope switcher for ${books.length} books',
      'no scope switcher is drawn on Home',
      authority: '13 §2.2 🔒; 07 §5.7 🔒',
    );
  }
}

/// F2: S1 → *Money in* → S2 keypad → money account → other side → Save →
/// back to S1, which shows it.
Future<bool> firstEntrySteps(Journey j) async {
  final en = j.en;
  const amountKeys = ['5', '0', '0'];
  await j.step(
    'S1-verb',
    'Home verb "${en.homeVerbMoneyIn}"',
    j.text(en.homeVerbMoneyIn),
    act: () => j.tap(j.text(en.homeVerbMoneyIn)),
  );
  await j.step(
    'S2',
    'Add entry keypad (AddEntryScreen, Key entry.keypad)',
    find.byKey(AddEntryKeys.keypad),
    act: () async {
      for (final k in amountKeys) {
        await j.tap(find.byKey(AddEntryKeys.pad(k)));
      }
    },
  );
  await j.step(
    'S2-money',
    'Money slot (Key entry.slot.money) with an account chip',
    find.byKey(AddEntryKeys.slot(EntrySlot.money)),
    act: () async {
      Finder chips() => find.byWidgetPredicate(
        (w) =>
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith('entry.chip.'),
      );
      if (chips().evaluate().isEmpty) {
        await j.tap(find.byKey(AddEntryKeys.slot(EntrySlot.money)));
      }
      if (chips().evaluate().isEmpty) {
        throw StateError('no money-account chip to choose');
      }
      await j.tap(chips().first);
    },
  );
  await j.step(
    'S2.1',
    'Other side (Key entry.slot.ledger) → picker, create "Journey Sales"',
    find.byKey(AddEntryKeys.slot(EntrySlot.ledger)),
    act: () async {
      await j.tap(find.byKey(AddEntryKeys.slot(EntrySlot.ledger)));
      if (await j.waitFor(
        find.byKey(AddEntryKeys.search),
        timeout: const Duration(seconds: 5),
      )) {
        await j.tester.enterText(
          find.byKey(AddEntryKeys.search),
          'Journey Sales',
        );
        await j.settle();
      }
      // The keyboard is put away first, so the create row is not squeezed
      // under it.
      FocusManager.instance.primaryFocus?.unfocus();
      await j.settle(const Duration(milliseconds: 800));
      if (find.byKey(AddEntryKeys.create).evaluate().isEmpty) {
        throw StateError('no "+ Create" row in the account picker');
      }
      await j.tap(find.byKey(AddEntryKeys.create));
      final income = j.text(en.entryCreateIncome);
      if (await j.waitFor(income, timeout: const Duration(seconds: 3))) {
        await j.tap(income);
      }
      // The new account must land in the slot: the create row goes away.
      final end = DateTime.now().add(const Duration(seconds: 10));
      while (DateTime.now().isBefore(end) &&
          find.byKey(AddEntryKeys.create).evaluate().isNotEmpty) {
        await j.settle(const Duration(milliseconds: 300));
      }
      if (find.byKey(AddEntryKeys.create).evaluate().isNotEmpty) {
        throw StateError(
          'tapping "+ Create" did not fill the slot within 10 s '
          '(the create row is still shown)',
        );
      }
    },
  );
  await j.step(
    'S2-save',
    'Save (Key entry.save)',
    find.byKey(AddEntryKeys.save),
    act: () => j.tap(find.byKey(AddEntryKeys.save)),
  );
  await j.step(
    'S2-saved',
    'Toast "${en.entrySaved}" (no "${en.entrySaveError}")',
    find.textContaining(en.entrySaved.split(' ').first),
    timeout: const Duration(seconds: 20),
    act: () async {
      if (find.text(en.entrySaveError).evaluate().isNotEmpty) {
        throw StateError(en.entrySaveError);
      }
      // System Back, as the person would press it.
      await j.tester.binding.handlePopRoute();
      await j.settle(const Duration(milliseconds: 800));
    },
  );
  return j.step(
    'S1-after',
    'Home shows the entry (an amount with "500" on Home)',
    find.descendant(
      of: find.byType(HomeScreen),
      matching: find.textContaining('500'),
    ),
    timeout: const Duration(seconds: 30),
  );
}
