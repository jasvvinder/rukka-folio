// S2.2 — the in-place date picker (07 §5 step 4 🔒, 13 §3.2 row S2.2). It
// replaces the keypad in the lower region exactly like S2.1's account picker
// does: not a modal sheet, not a second screen (07 §5's single-screen block
// 🔒) — the date chip toggles it open the same way a slot field does.
//
// 07 §5 step 4 is precise and 🔒:
//   * any date in an open period is selectable — backdating works;
//   * a future date is disabled, with the tooltip *"Use a recurring entry
//     for future dates"*;
//   * a locked date renders 🔒-greyed; tapping one explains the lock and
//     offers **Fix an old entry** (the reversal flow of 02 §5) — never a
//     dead error (07 §1 rule 6).
//
// ⚠️ SPEC / open gap: `LocalLedger` has no public query for a period's lock
// status ahead of a post attempt — the engine only reports `periodLocked`
// when a post is actually tried (`local_ledger.dart` §8, `PostRejected`).
// [EntryDatePicker.isLocked] is therefore an injected lookup so this widget
// and its states are fully buildable and testable now; the screen that hosts
// it (`s2_add_entry_screen.dart`) currently wires a resolver that reports
// every period open, because no book in this milestone's build ever locks a
// month (month close is 07 §13 / S4, M9). Lighting the grey/explain states up
// against real data needs a small read added to `LocalLedger` — that file is
// outside this lane's owned directories (and another lane is editing it right
// now), so the addition is reported to the owner rather than made here.
import 'package:core_ledger/core_ledger.dart';
import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/format/date_format.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';

/// Whether [period] is locked (02 §8) — see the ⚠️ SPEC note above.
typedef PeriodLockLookup = bool Function(YearMonth period);

/// Widget keys the picker's own tests drive it by.
abstract final class EntryDatePickerKeys {
  /// Steps the shown month back.
  static const prevMonth = Key('entry.date.prev_month');

  /// Steps the shown month forward; disabled once the current month shows.
  static const nextMonth = Key('entry.date.next_month');

  /// The locked-day explanation's *Fix an old entry* action.
  static const fixOldEntry = Key('entry.date.fix_old_entry');

  /// The locked-day explanation's way back to the grid.
  static const lockedBack = Key('entry.date.locked_back');

  /// The locked-day explanation text.
  static const lockedMessage = Key('entry.date.locked_message');

  /// One day cell.
  static Key day(LocalDate d) => Key('entry.date.day.${d.toIso()}');
}

/// The in-place calendar for one date (07 §5 step 4).
class EntryDatePicker extends StatefulWidget {
  /// Creates the picker.
  const EntryDatePicker({
    super.key,
    required this.today,
    required this.selected,
    required this.onPick,
    required this.onFixOldEntry,
    this.isLocked = _neverLocked,
  });

  /// The clock's own today (`LocalLedger.today()`) — never read from
  /// `DateTime.now()` here (CLAUDE.md rule 3).
  final LocalDate today;

  /// The date currently answering the entry's date chip.
  final LocalDate selected;

  /// A valid, open-period, non-future date was chosen.
  final ValueChanged<LocalDate> onPick;

  /// *Fix an old entry* was chosen on a locked day (02 §5's reversal flow).
  /// This screen never navigates itself (07 §5 🔒); the caller decides what
  /// leaving to fix an old entry means (this lane leaves it as Back, the
  /// exit 07 §5 step 7 already offers).
  final VoidCallback onFixOldEntry;

  /// True when [period] is locked. Defaults to "nothing is ever locked" —
  /// see the file-level ⚠️ SPEC note.
  final PeriodLockLookup isLocked;

  static bool _neverLocked(YearMonth _) => false;

  @override
  State<EntryDatePicker> createState() => _EntryDatePickerState();
}

class _EntryDatePickerState extends State<EntryDatePicker> {
  late YearMonth _shown = widget.selected.yearMonth;
  LocalDate? _explaining;

  bool get _canGoNext => _shown.compareTo(widget.today.yearMonth) < 0;

  void _prev() => setState(() {
    _shown = _shown.month == 1
        ? YearMonth(_shown.year - 1, 12)
        : YearMonth(_shown.year, _shown.month - 1);
    _explaining = null;
  });

  void _next() {
    if (!_canGoNext) return;
    setState(() {
      _shown = _shown.next;
      _explaining = null;
    });
  }

  /// Monday-indexed weekday (0 = Monday) — Howard Hinnant's epoch (1970-01-01,
  /// a Thursday) needs a +3 shift before the mod (`LocalDate.toEpochDays`).
  int _mondayIndex(LocalDate d) => ((d.toEpochDays() + 3) % 7 + 7) % 7;

  void _tapDay(LocalDate date) {
    if (date.isAfter(widget.today)) return; // disabled — tooltip only.
    if (widget.isLocked(date.yearMonth)) {
      setState(() => _explaining = date);
      return;
    }
    widget.onPick(date);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final explaining = _explaining;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconButton(
              key: EntryDatePickerKeys.prevMonth,
              icon: const Icon(Icons.chevron_left),
              tooltip: l10n.entryDatePrevMonth,
              onPressed: _prev,
            ),
            Expanded(
              child: Center(
                child: Text(
                  '${monthName(l10n, _shown.month)} ${_shown.year}',
                  style: RkType.body,
                ),
              ),
            ),
            IconButton(
              key: EntryDatePickerKeys.nextMonth,
              icon: const Icon(Icons.chevron_right),
              tooltip: l10n.entryDateNextMonth,
              onPressed: _canGoNext ? _next : null,
            ),
          ],
        ),
        Expanded(
          child: explaining != null
              ? _LockedExplain(
                  date: explaining,
                  onFix: widget.onFixOldEntry,
                  onBack: () => setState(() => _explaining = null),
                )
              : _Grid(
                  shown: _shown,
                  today: widget.today,
                  selected: widget.selected,
                  isLocked: widget.isLocked,
                  mondayIndex: _mondayIndex,
                  onTap: _tapDay,
                ),
        ),
      ],
    );
  }
}

class _Grid extends StatelessWidget {
  const _Grid({
    required this.shown,
    required this.today,
    required this.selected,
    required this.isLocked,
    required this.mondayIndex,
    required this.onTap,
  });

  final YearMonth shown;
  final LocalDate today;
  final LocalDate selected;
  final PeriodLockLookup isLocked;
  final int Function(LocalDate) mondayIndex;
  final void Function(LocalDate) onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final leading = mondayIndex(shown.firstDay);
    final days = shown.daysInMonth;
    return GridView.builder(
      padding: const EdgeInsets.only(top: RkSpace.s2),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
      ),
      itemCount: leading + days,
      itemBuilder: (context, i) {
        if (i < leading) return const SizedBox.shrink();
        final date = LocalDate(shown.year, shown.month, i - leading + 1);
        return _Day(
          date: date,
          isToday: date == today,
          isSelected: date == selected,
          isFuture: date.isAfter(today),
          isLocked: !date.isAfter(today) && isLocked(date.yearMonth),
          futureTooltip: l10n.entryDateFutureTooltip,
          onTap: () => onTap(date),
        );
      },
    );
  }
}

class _Day extends StatelessWidget {
  const _Day({
    required this.date,
    required this.isToday,
    required this.isSelected,
    required this.isFuture,
    required this.isLocked,
    required this.futureTooltip,
    required this.onTap,
  });

  final LocalDate date;
  final bool isToday;
  final bool isSelected;
  final bool isFuture;
  final bool isLocked;
  final String futureTooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final status = RkStatusColors.of(context);
    final disabled = isFuture;
    final Color? fill = isSelected
        ? scheme.primary
        : isLocked
        ? status.sunk
        : null;
    final Color textColor = isSelected
        ? scheme.onPrimary
        : disabled
        ? status.muted.withValues(alpha: 0.5)
        : isLocked
        ? status.locked
        : scheme.onSurface;
    final cell = Padding(
      padding: const EdgeInsets.all(2),
      child: Material(
        color: fill,
        shape: isToday && !isSelected
            ? CircleBorder(side: BorderSide(color: status.muted))
            : const CircleBorder(),
        child: InkWell(
          key: EntryDatePickerKeys.day(date),
          customBorder: const CircleBorder(),
          onTap: disabled ? null : onTap,
          // A Stack, not a Column: a locked day still reads as one glyph at
          // 200 % (11 §4.4) — the lock rides as a small badge rather than
          // pushing the cell to grow past its circle (07 §5 🔒 never scrolls
          // governs the screen this picker sits inside).
          child: Stack(
            alignment: Alignment.center,
            children: [
              Text(
                '${date.day}',
                style: RkType.body.copyWith(color: textColor),
              ),
              if (isLocked && !isSelected)
                Positioned(
                  bottom: 1,
                  right: 1,
                  child: Icon(Icons.lock, size: 8, color: textColor),
                ),
            ],
          ),
        ),
      ),
    );
    return disabled ? Tooltip(message: futureTooltip, child: cell) : cell;
  }
}

class _LockedExplain extends StatelessWidget {
  const _LockedExplain({
    required this.date,
    required this.onFix,
    required this.onBack,
  });

  final LocalDate date;
  final VoidCallback onFix;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final status = RkStatusColors.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(RkSpace.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock, color: status.locked),
          const SizedBox(height: RkSpace.s3),
          Text(
            l10n.entryDateLockedMessage(formatLedgerDate(date, strings: l10n)),
            key: EntryDatePickerKeys.lockedMessage,
            style: RkType.body,
          ),
          const SizedBox(height: RkSpace.s4),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              key: EntryDatePickerKeys.fixOldEntry,
              onPressed: onFix,
              child: Text(l10n.entryDateLockedFix),
            ),
          ),
          const SizedBox(height: RkSpace.s2),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              key: EntryDatePickerKeys.lockedBack,
              onPressed: onBack,
              child: Text(l10n.entryDateLockedBack),
            ),
          ),
        ],
      ),
    );
  }
}
