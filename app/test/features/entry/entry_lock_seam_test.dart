// The entry side of the shell's lock seam (07 §5.6 🔒, ADR 2026-09-05 §7,
// ADR 2026-09-05i §10 minting C-05a-7): "idle lock never fires with digits in
// the keypad; a lock mid-entry returns the draft to the same field."
//
// `shared/lock/draft_activity.dart` and `shared/lock/auto_lock.dart` already
// build the registry and the timers (owned elsewhere) — this lane's part is
// that `features/entry` actually reports into them. This file drives the
// *real* `AddEntryScreen` reporting through the *real* `DraftActivity` and
// `RkAutoLock`, rather than simulating the report by hand (that simulation
// already exists as F1-07-69 in app/test/shared/app_lock_test.dart, proving
// the timer side; this id proves the entry side).
//
// What this test does not prove: the shell's actual S15 route push/pop on
// lock/unlock is main.dart's wiring (F1-07-68/69 cover that). `RkAutoLock`
// never disposes its child on a lock change — it only ever wraps `child` in
// a `Listener` — so "the draft returns to the same field" is demonstrated
// here by showing the entry screen's own State survives a lock/unlock cycle
// untouched, which is what "returns to the same field" rests on.
@Tags(['F1'])
library;

import 'package:core_ledger/core_ledger.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rukka_folio/features/entry/entry_slots.dart';
import 'package:rukka_folio/features/entry/screens/s2_add_entry_screen.dart';
import 'package:rukka_folio/features/entry/widgets/entry_keypad.dart';
import 'package:rukka_folio/shared/lock/auto_lock.dart';
import 'package:rukka_folio/shared/lock/draft_activity.dart';

import '../../shared/test_app.dart';

void main() {
  testWidgets('C-05a-7 the idle lock never fires with digits in the keypad; a lock '
      'mid-entry returns the draft to the same field', (tester) async {
    final s = await seedSoloLedger();
    final draft = DraftActivity();
    final lock = AppLockState();
    // Long enough that `pumpRk`'s own settling pump (and every `pumpAndSettle`
    // below) can never itself cross the threshold — only the deliberate
    // `pump(idle)` calls do.
    const idle = Duration(seconds: 2);

    await pumpRk(
      tester,
      DraftActivityScope(
        activity: draft,
        child: RkAutoLock(
          lock: lock,
          now: DateTime.now,
          idleTimeout: idle,
          draft: draft,
          child: AddEntryScreen(bookId: s.bookId, kind: EntryKind.moneyOut),
        ),
      ),
      ledger: s.ledger,
    );

    // Nothing typed yet: the seam is quiet and the idle timer runs down as
    // normal — no digits, nothing to suppress.
    expect(draft.hasDigits, isFalse);

    // Type into the keypad — the screen reports on every change (this
    // lane's own wiring, not the shell's).
    await tester.tap(find.byKey(AddEntryKeys.pad('2')));
    await tester.pump();
    expect(draft.hasDigits, isTrue, reason: 'a digit is in the keypad');

    // The idle timeout elapses twice over: it never fires while digits sit
    // in the draft (07 §5.6 🔒).
    await tester.pump(idle);
    await tester.pump(idle);
    expect(lock.locked, isFalse, reason: 'digits are in the keypad');

    // Open the ledger slot's picker mid-entry too — the seam holds on the
    // amount alone, so the suppression survives a slot being open.
    await tester.tap(find.byKey(AddEntryKeys.slot(EntrySlot.ledger)));
    await tester.pumpAndSettle();
    await tester.pump(idle);
    expect(lock.locked, isFalse);
    // Back to the keypad, the digit is still there — nothing was reset by
    // opening and closing the picker.
    await tester.tap(find.byKey(AddEntryKeys.slot(EntrySlot.ledger)));
    await tester.pumpAndSettle();
    expect(find.textContaining('₹2'), findsWidgets);

    // Clear the one digit: the seam reports empty, and the idle lock is
    // free to fire again.
    await tester.tap(find.byKey(AddEntryKeys.pad(keypadBackspace)));
    await tester.pump();
    expect(draft.hasDigits, isFalse);
    await tester.pump(idle);
    expect(lock.locked, isTrue, reason: 'no digits left to suppress it');

    // "A lock mid-entry returns the draft to the same field": type again,
    // then let the shell's own lock signal fire and clear mid-entry.
    // `RkAutoLock` never disposes `child` on a lock change (it only ever
    // wraps it in a `Listener`), so the entry screen's State — the same
    // field, the same digits — was never at risk; unlocking finds it
    // exactly as it was.
    lock.unlock();
    await tester.pump();
    await tester.tap(find.byKey(AddEntryKeys.pad('4')));
    await tester.pump();
    expect(find.textContaining('₹4'), findsWidgets);
    lock.lock();
    await tester.pump();
    lock.unlock();
    await tester.pump();
    expect(
      find.textContaining('₹4'),
      findsWidgets,
      reason: 'the draft returned to the same field after the lock cycle',
    );
    expect(draft.hasDigits, isTrue);

    // dispose(): leaving the screen forgets its own token so a lock landed
    // on some *other* screen is never suppressed by a draft this one left
    // behind.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    expect(draft.hasDigits, isFalse);
  });
}
