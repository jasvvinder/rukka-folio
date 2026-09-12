// S2 Add entry — the 8-second flow (07 §5 🔒, 13 §3.2 rows S2 / S2.1 / S2.3,
// 13 §5 flow F2).
//
// **Screen order: amount first.** A full-screen numeric keypad with the
// amount huge at top; the verb is the five-position pill (ADR 2026-09-03b),
// switchable without losing the amount. Both slots are labelled by verb
// ([VerbPlan]) — the money-account label is never a fixed "FROM".
//
// **Single screen, always 🔒** (owner-directed, 31 Aug 2026): the entry never
// navigates, never overlays and never scrolls. The **lower region swaps in
// place** — keypad by default, the searchable account list (S2.1) when a slot
// is tapped, keypad again once an account is chosen. Everything already
// entered stays visible. No modal sheet, no second screen.
//
// **Nothing is pre-selected 🔒** (ADR 2026-09-05f §C): no chip ticked, no
// last-used account remembered. A wrong default posts a wrong entry and
// nobody notices until the month will not reconcile.
//
// **Completion is the validation 🔒**: the preview line moves muted → full
// ink and Save turns solid at the same moment. No "please choose an account"
// message exists on this screen, because the UI cannot build an unbalanced
// entry — the posting itself is the engine's (02 §2), reached only through
// [LocalLedger]'s verbs.
//
// Consumer surface (02 §10 🔒, CLAUDE.md rule 9): Money in / Money out / Gave
// on credit / Took on credit / Move money — never Dr/Cr, and no
// amount-in-words (01 §1 rule 10 🔒, it costs a line on a screen that must
// not scroll).
//
// After Save: an instant local write, the snackbar `Saved ✓ (on phone)` with
// **Undo (10 s)**, and the keypad stays open, zeroed, for the next entry
// (07 §5 steps 6–7). Undo posts an append-only **reversal** (02 §5) — the
// entry and its mirror both stay in history; nothing is ever deleted.
import 'package:core_ledger/core_ledger.dart';
import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/format/money_format.dart';
import '../../../shared/ledger/ledger_scope.dart';
import '../../../shared/ledger/local_ledger.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';
import '../../ledger/ledger_book.dart';
import '../../../shared/format/date_format.dart';
import '../entry_amount.dart';
import '../entry_data.dart';
import '../entry_slots.dart';
import '../widgets/entry_account_picker.dart';
import '../widgets/entry_chip_row.dart';
import '../widgets/entry_date_picker.dart';
import '../widgets/entry_drawings_banner.dart';
import '../widgets/entry_keypad.dart';
import '../widgets/entry_preview_line.dart';
import '../widgets/entry_slot_field.dart';
import '../widgets/entry_verb_pill.dart';

/// Widget keys the screen's own tests drive it by.
abstract final class AddEntryKeys {
  /// The five-position verb pill.
  static const verbPill = Key('entry.verb_pill');

  /// The big amount at top.
  static const amount = Key('entry.amount');

  /// The reserved-height preview line (07 §5.5 🔒).
  static const preview = Key('entry.preview');

  /// The preview's rendered text — its ink is the validation.
  static const previewText = Key('entry.preview_text');

  /// The lower region holding the keypad.
  static const keypad = Key('entry.keypad');

  /// The lower region holding the in-place account list (S2.1).
  static const picker = Key('entry.picker');

  /// The picker's search field.
  static const search = Key('entry.search');

  /// The picker's inline-create row.
  static const create = Key('entry.create');

  /// Save.
  static const save = Key('entry.save');

  /// The `Today` / picked-date chip — tapping it opens S2.2's calendar in
  /// place, exactly like a slot field opens its picker.
  static const dateChip = Key('entry.date_chip');

  /// The lower region holding S2.2's in-place calendar.
  static const datePicker = Key('entry.date_picker');

  /// The S2.5 drawings confirmation banner.
  static const drawingsBanner = EntryDrawingsBannerKeys.banner;

  /// One keypad key.
  static Key pad(String key) => Key('entry.pad.$key');

  /// One slot field.
  static Key slot(EntrySlot slot) => Key('entry.slot.${slot.name}');
}

/// S2 Add entry.
class AddEntryScreen extends StatefulWidget {
  /// Creates the screen.
  const AddEntryScreen({super.key, this.bookId, this.kind = EntryKind.moneyIn});

  /// Explicit book; when null the solo book is resolved ([soloBookId]).
  final String? bookId;

  /// The pill position to open on — Home passes the verb it was tapped with
  /// (07 §4). Default *Money in*.
  final EntryKind kind;

  @override
  State<AddEntryScreen> createState() => _AddEntryScreenState();
}

class _AddEntryScreenState extends State<AddEntryScreen> {
  late EntryKind _kind = widget.kind;
  AmountExpression _amount = const AmountExpression.empty();
  String? _moneyId;
  String? _ledgerId;

  /// Which slot's list holds the lower region; null = the keypad does.
  EntrySlot? _openSlot;

  /// True while S2.2's calendar holds the lower region instead (mutually
  /// exclusive with [_openSlot] — only one thing replaces the keypad at a
  /// time, 07 §5's single-screen block 🔒).
  bool _dateOpen = false;

  /// The date chip's answer; null means *Today* — re-resolved against the
  /// injected clock on every read rather than captured once, so a book left
  /// open across midnight still calls "today" today.
  LocalDate? _selectedDate;

  String? _bookId;
  Object? _resolveError;
  bool _resolveStarted = false;
  bool _saving = false;

  Stream<List<AccountBalance>>? _accounts;
  Stream<Map<String, int>>? _counts;

  VerbPlan get _plan => VerbPlan.of(_kind);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // LedgerScope is an InheritedWidget, so it may only be read from here on.
    if (_resolveStarted) return;
    _resolveStarted = true;
    _resolveBook();
  }

  Future<void> _resolveBook() async {
    final explicit = widget.bookId;
    if (explicit != null) {
      // Synchronous, and reached from didChangeDependencies — assign the
      // fields the coming build will read rather than marking this element
      // dirty while it is already building.
      _openStreams(explicit, notify: false);
      return;
    }
    try {
      final id = await soloBookId(LedgerScope.of(context));
      if (mounted) _openStreams(id);
    } catch (e) {
      if (mounted) setState(() => _resolveError = e);
    }
  }

  void _openStreams(String bookId, {bool notify = true}) {
    final ledger = LedgerScope.of(context);
    _bookId = bookId;
    // Built once, not per build: a stream rebuilt on every setState would
    // re-query the projection on every keystroke.
    _accounts = ledger.watchAccounts(bookId);
    _counts = watchMoneyUseCounts(ledger, bookId);
    if (notify) setState(() {});
  }

  void _retry() {
    setState(() => _resolveError = null);
    _resolveBook();
  }

  String? _idOf(EntrySlot slot) =>
      slot == EntrySlot.money ? _moneyId : _ledgerId;

  void _choose(EntrySlot slot, String accountId) {
    setState(() {
      if (slot == EntrySlot.money) {
        _moneyId = accountId;
        if (_ledgerId == accountId) _ledgerId = null;
      } else {
        _ledgerId = accountId;
        if (_moneyId == accountId) _moneyId = null;
      }
      _openSlot = null;
    });
  }

  /// Switching position keeps the amount (07 §5) but drops both slots: the
  /// same account rarely answers a different verb's slot, and a carried-over
  /// choice would be exactly the wrong default 🔒.
  void _switchVerb(EntryKind kind) => setState(() {
    _kind = kind;
    _moneyId = null;
    _ledgerId = null;
    _openSlot = null;
    _dateOpen = false;
  });

  /// Opens a slot's list, closing the calendar first — only one thing ever
  /// replaces the keypad (07 §5 🔒).
  void _openSlotTap(EntrySlot slot) => setState(() {
    _openSlot = _openSlot == slot ? null : slot;
    _dateOpen = false;
  });

  /// Toggles S2.2's calendar, closing any open slot list first.
  void _toggleDate() => setState(() {
    _dateOpen = !_dateOpen;
    _openSlot = null;
  });

  void _pickDate(LocalDate date) => setState(() {
    _selectedDate = date;
    _dateOpen = false;
  });

  /// *Fix an old entry* on a locked day (02 §5's reversal flow). This screen
  /// never navigates itself (07 §5 🔒); leaving to fix an old entry is a
  /// different task from creating this one, so it takes the exit 07 §5 step
  /// 7 already offers (Back) when there is somewhere to go back to, and
  /// otherwise just closes the calendar rather than dead-ending (07 §1 rule
  /// 6) — the F1-07-58 test drives both paths.
  void _fixOldEntry() {
    final nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.maybePop();
    } else {
      setState(() => _dateOpen = false);
    }
  }

  void _onKey(String key) => setState(() {
    _amount = switch (key) {
      keypadPlus => _amount.plus(),
      keypadDot => _amount.dot(),
      keypadBackspace => _amount.backspace(),
      _ => _amount.digit(key),
    };
  });

  bool get _complete =>
      _amount.paise > 0 && _moneyId != null && _ledgerId != null;

  Account? _accountOf(List<AccountBalance> all, String? id) {
    if (id == null) return null;
    for (final a in all) {
      if (a.account.id == id) return a.account;
    }
    return null;
  }

  /// The chip row belongs to a slot only while a money account can answer it
  /// — it is **absent entirely** once the slot holds something else (07 §5
  /// step 2 🔒, milk on khata).
  bool _chipsVisible(EntrySlot slot, List<AccountBalance> all) {
    if (!_plan.spec(slot).showChips) return false;
    final chosen = _accountOf(all, _idOf(slot));
    return chosen == null || chosen.accountClass == AccountClass.money;
  }

  /// The candidates for [slot]'s in-place list — [slotCandidates] plus, on
  /// Money out's ledger slot only, the book's Drawings account (S2.5, 07 §5
  /// "Owner's drawings" 🔒): `VerbPlan.moneyOut.ledger.classes` deliberately
  /// excludes `equitySystem` (every other equity-system role — Suspense,
  /// Adjustments, Opening Balance — must never be a manual pick target), so
  /// Drawings is added back in here, narrowly, by `SystemRole` rather than by
  /// widening the slot's classes.
  List<AccountBalance> _candidatesFor(
    EntrySlot slot,
    List<AccountBalance> accounts,
    Map<String, int> counts,
  ) {
    final rows = slotCandidates(
      accounts,
      _plan.spec(slot),
      counts: counts,
      exclude: _idOf(
        slot == EntrySlot.money ? EntrySlot.ledger : EntrySlot.money,
      ),
    );
    if (_kind != EntryKind.moneyOut || slot != EntrySlot.ledger) return rows;
    final drawings = drawingsAccountOf(accounts);
    if (drawings == null || rows.any((r) => r.account.id == drawings.id)) {
      return rows;
    }
    for (final a in accounts) {
      if (a.account.id == drawings.id) return [...rows, a];
    }
    return rows;
  }

  Future<void> _save(LocalLedger ledger, String bookId) async {
    if (!_complete || _saving) return;
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final money = _moneyId!;
    final other = _ledgerId!;
    final paise = _amount.paise;
    // S2.2 (07 §5 step 4 🔒): the date chip's answer, or today's date when
    // nothing was picked.
    final date = _selectedDate ?? ledger.today();
    setState(() => _saving = true);
    try {
      // The engine's own verbs (02 §2) — this screen never builds lines.
      final entry = await switch (_kind) {
        EntryKind.moneyIn => ledger.moneyIn(
          bookId: bookId,
          into: money,
          from: other,
          paise: paise,
          date: date,
        ),
        EntryKind.moneyOut => ledger.moneyOut(
          bookId: bookId,
          from: money,
          forWhat: other,
          paise: paise,
          date: date,
        ),
        EntryKind.gaveCredit => ledger.gaveCredit(
          bookId: bookId,
          gave: money,
          toWhom: other,
          paise: paise,
          date: date,
        ),
        EntryKind.tookCredit => ledger.tookCredit(
          bookId: bookId,
          took: money,
          fromWhom: other,
          paise: paise,
          date: date,
        ),
        // S2.3 within one book. Inter-book movement switches the flow to
        // 02 §6 / 07 §10 and is not this lane's screen.
        EntryKind.transfer => ledger.transfer(
          bookId: bookId,
          from: money,
          to: other,
          paise: paise,
          date: date,
        ),
        EntryKind.adjustment => throw ArgumentError('S2.4 is guided-only'),
      };
      if (!mounted) return;
      // 07 §5 step 7: stay on the keypad, zeroed, for the next entry. Both
      // sides are kept so a repeat is one amount away (design canvas 2, S2-B
      // "Both sides kept for the next one").
      setState(() {
        _amount = _amount.cleared;
        _saving = false;
        _openSlot = null;
      });
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.entrySaved),
          duration: const Duration(seconds: 10),
          action: SnackBarAction(
            label: l10n.entryUndo,
            onPressed: () => _undo(ledger, entry.id),
          ),
        ),
      );
      // Out of scope (M7 member limits): over the limit the snackbar reads
      // `Saved ✓ · Sunita will review` — saved and counted either way
      // (07 §5 step 6, 02 §3). The limit itself does not exist yet.
      // Out of scope (S12.5, book full / `rejected:quota`): Save is blocked
      // with the S12.5 sheet pointing at S12.1 and the draft is preserved
      // (ADR 2026-09-05b §7) — the quota signal lands with sync.
      // S2.5 (ADR 2026-09-02): a *business* book's Drawings account is a
      // real account of the chart (SystemRole.drawings) — choosing it as
      // Money out's ledger slot posts through this same `ledger.moneyOut`
      // call, the banner above only narrates it (02 §10 🔒: the posting
      // logic never bends to the display language).
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(content: Text(l10n.entrySaveError)));
    }
  }

  /// Undo — an **append-only reversal** (02 §5): the auto-built mirror, dated
  /// in the open period, `refs.reverses = original`. Both stay in history;
  /// the original shows as `void`. 02 §5 allows an amendment in an open
  /// period too, but an amendment of a just-saved entry would have nothing to
  /// replace it with — a reversal says plainly that it did not happen.
  Future<void> _undo(LocalLedger ledger, String entryId) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ledger.reverse(entryId, date: ledger.today());
      if (!mounted) return;
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(content: Text(l10n.entryUndone)));
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(l10n.entrySaveError)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: RkSpace.gutter),
          child: _resolveError != null
              ? _ErrorState(
                  text: l10n.entryError,
                  retry: l10n.entryRetry,
                  onRetry: _retry,
                )
              : _bookId == null
              ? _Loading(label: l10n.entryLoading)
              : _data(context, _bookId!),
        ),
      ),
    );
  }

  Widget _data(BuildContext context, String bookId) {
    final l10n = AppLocalizations.of(context);
    return StreamBuilder<List<AccountBalance>>(
      stream: _accounts,
      builder: (context, accSnap) {
        if (accSnap.hasError) {
          return _ErrorState(
            text: l10n.entryError,
            retry: l10n.entryRetry,
            onRetry: _retry,
          );
        }
        final accounts = accSnap.data;
        if (accounts == null) return _Loading(label: l10n.entryLoading);
        return StreamBuilder<Map<String, int>>(
          stream: _counts,
          builder: (context, cntSnap) =>
              _form(context, bookId, accounts, cntSnap.data ?? const {}),
        );
      },
    );
  }

  Widget _form(
    BuildContext context,
    String bookId,
    List<AccountBalance> accounts,
    Map<String, int> counts,
  ) {
    final l10n = AppLocalizations.of(context);
    final ledger = LedgerScope.of(context);
    final status = RkStatusColors.of(context);
    final plan = _plan;
    final creditName = _accountOf(accounts, _idOf(plan.creditSlot))?.name;
    final debitName = _accountOf(accounts, _idOf(plan.debitSlot))?.name;
    final scale = MediaQuery.textScalerOf(context).scale(1);
    // At 200 % every fixed row grows, and *Move money* carries two chip rows
    // rather than one: on 375×667 the natural stack is 35 px taller than the
    // viewport. The screen must not scroll (07 §5 🔒), so the chrome tightens
    // instead — the paddings between rows, and the amount's reserved box,
    // which is a FittedBox and loses nothing by staying at its base height.
    //
    // ⚠️ SPEC: even tightened, *Move money* at 200 % on 375×667 leaves the
    // keypad ~30 px — present and correct, but not usable. 07 §5's "never
    // scrolls" 🔒 and the 200 % requirement genuinely collide on this one
    // verb at this one size. The conservative reading is taken here (keep the
    // no-scroll rule; let the lower region take the squeeze) and the choice
    // is left to the owner rather than invented — see the lane report.
    final dense = scale >= 1.5;
    final rowPad = dense ? RkSpace.s1 : RkSpace.s2;

    return Column(
      children: [
        // ── the verb, five positions ──────────────────────────────────────
        Padding(
          padding: EdgeInsets.symmetric(vertical: rowPad),
          child: Row(
            children: [
              if (Navigator.of(context).canPop())
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              Expanded(
                child: EntryVerbPill(
                  key: AddEntryKeys.verbPill,
                  kind: _kind,
                  onKind: _switchVerb,
                ),
              ),
            ],
          ),
        ),
        // ── the amount, huge, first ───────────────────────────────────────
        Semantics(
          label: l10n.entryAmountA11y(
            formatPaise(_amount.paise, locale: Localizations.localeOf(context)),
            verbLabel(l10n, _kind),
          ),
          excludeSemantics: true,
          child: SizedBox(
            height: dense ? 56.0 : (56 + 24 * (scale - 1)).clamp(56.0, 96.0),
            width: double.infinity,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                '$rupeeSign${_amount.display}',
                key: AddEntryKeys.amount,
                maxLines: 1,
                style: RkType.amountHero.copyWith(
                  color: _amount.isEmpty
                      ? status.muted
                      : Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
          ),
        ),
        // ── the two slots, labelled by verb ───────────────────────────────
        for (final slot in plan.order) ...[
          EntrySlotField(
            key: AddEntryKeys.slot(slot),
            label: slotLabel(l10n, plan.spec(slot).label),
            value: _accountOf(accounts, _idOf(slot))?.name,
            placeholder: l10n.entrySlotChoose,
            open: _openSlot == slot,
            onTap: () => _openSlotTap(slot),
          ),
          if (_chipsVisible(slot, accounts))
            Padding(
              padding: const EdgeInsets.only(top: RkSpace.s1),
              child: EntryChipRow(
                names: [
                  for (final a in topMoneyAccounts(
                    accounts,
                    counts,
                    exclude: _idOf(
                      slot == EntrySlot.money
                          ? EntrySlot.ledger
                          : EntrySlot.money,
                    ),
                  ))
                    (a.account.id, a.account.name),
                ],
                selectedId: _idOf(slot),
                onPick: (id) => _choose(slot, id),
                onMore: () => setState(() {
                  _openSlot = slot;
                  _dateOpen = false;
                }),
                moreLabel: l10n.entryChipsMore,
              ),
            ),
          // S2.5 (07 §5 "Owner's drawings" 🔒, ADR 2026-09-02): fires the
          // instant Money out's ledger slot answers to the book's Drawings
          // account — never silently, and never as a blocking sheet.
          if (_kind == EntryKind.moneyOut &&
              slot == EntrySlot.ledger &&
              _idOf(slot) != null &&
              _idOf(slot) == drawingsAccountOf(accounts)?.id)
            // ⚠️ SPEC: at 200 % on 360×800 the sentence 07 §5 🔒 fixes runs
            // to ~312 pt — more than the whole free height the fixed rows
            // leave, so a rigid banner overflows the body by ~90 pt. 07 §5's
            // "never scrolls" 🔒 governs the *screen*, and it still does not
            // move: the banner is made flexible instead, so it takes only
            // what is free (splitting it with the lower region) and carries
            // its own scroll for the remainder, exactly as the picker's list
            // and its create question already do. This is a second instance
            // of the collision the owner parked on 07 §5 — the conservative
            // reading is kept and nothing is resolved here; see the lane
            // report.
            Flexible(
              fit: FlexFit.loose,
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.only(top: RkSpace.s2),
                  child: EntryDrawingsBanner(
                    message: l10n.entryDrawingsConfirmation,
                  ),
                ),
              ),
            ),
        ],
        // ── date · and the optional row ───────────────────────────────────
        Padding(
          padding: EdgeInsets.symmetric(vertical: rowPad),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            // S2.2 (07 §5 step 4 🔒): tapping the chip opens the calendar in
            // the lower region, exactly like a slot field opens its picker.
            // TODO(U-next): the optional row (note · 📷 bill photo · channel
            // tag, 07 §5 step 5) attaches immediately below this line; the
            // preview already renders a note when one is given.
            child: Semantics(
              button: true,
              label: l10n.entryDateA11y(
                _selectedDate == null
                    ? l10n.entryDateToday
                    : formatLedgerDate(_selectedDate!, strings: l10n),
              ),
              excludeSemantics: true,
              child: InkWell(
                key: AddEntryKeys.dateChip,
                onTap: _toggleDate,
                child: Text(
                  _selectedDate == null
                      ? l10n.entryDateToday
                      : l10n.entryDatePicked(
                          formatLedgerDate(_selectedDate!, strings: l10n),
                        ),
                  style: RkType.caption.copyWith(
                    color: _dateOpen
                        ? Theme.of(context).colorScheme.primary
                        : status.muted,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ),
          ),
        ),
        // ── the live preview, full height from the first frame ────────────
        EntryPreviewLine(
          key: AddEntryKeys.preview,
          textKey: AddEntryKeys.previewText,
          amountPaise: _amount.paise,
          creditName: creditName,
          debitName: debitName,
          complete: _complete,
        ),
        // ── the lower region: keypad, or one slot's list, in place ────────
        Expanded(
          child: _dateOpen
              ? EntryDatePicker(
                  key: AddEntryKeys.datePicker,
                  today: ledger.today(),
                  selected: _selectedDate ?? ledger.today(),
                  onPick: _pickDate,
                  onFixOldEntry: _fixOldEntry,
                  // ⚠️ SPEC (see entry_date_picker.dart's file-level note):
                  // `LocalLedger` has no public period-lock query yet, so
                  // every period reads as open here — no book in this
                  // milestone's build ever locks a month.
                )
              : _openSlot == null
              ? EntryKeypad(
                  key: AddEntryKeys.keypad,
                  onKey: _onKey,
                  keyOf: AddEntryKeys.pad,
                )
              : EntryAccountPicker(
                  key: AddEntryKeys.picker,
                  searchKey: AddEntryKeys.search,
                  createKey: AddEntryKeys.create,
                  spec: plan.spec(_openSlot!),
                  rows: _candidatesFor(_openSlot!, accounts, counts),
                  onPick: (id) => _choose(_openSlot!, id),
                  onCreate: (name, accountClass) =>
                      _create(ledger, bookId, name, accountClass),
                ),
        ),
        // ── Save: solid the instant the entry is complete ─────────────────
        Padding(
          padding: EdgeInsets.symmetric(vertical: rowPad),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              key: AddEntryKeys.save,
              onPressed: _complete && !_saving
                  ? () => _save(ledger, bookId)
                  : null,
              child: Text(l10n.entrySave),
            ),
          ),
        ),
      ],
    );
  }

  /// Inline create (02 §1.2): the class comes from the slot, so a new A/C is
  /// one tap and lands chosen.
  Future<void> _create(
    LocalLedger ledger,
    String bookId,
    String name,
    AccountClass accountClass,
  ) async {
    final slot = _openSlot;
    if (slot == null || name.isEmpty) return;
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final account = await ledger.addAccount(
        bookId,
        name: name,
        accountClass: accountClass,
      );
      if (!mounted) return;
      _choose(slot, account.id);
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(l10n.entrySaveError)));
    }
  }
}

/// The ruled loading state (11 §4.5 — never a spinner).
class _Loading extends StatelessWidget {
  const _Loading({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final status = RkStatusColors.of(context);
    return Semantics(
      liveRegion: true,
      label: label,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < 4; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: RkSpace.s3),
              child: Container(
                height: RkSpace.s4,
                width: double.infinity,
                color: status.skeletonLabel,
              ),
            ),
        ],
      ),
    );
  }
}

/// Error with retry (13 §4.3) — never a dead end (07 §1 rule 6).
class _ErrorState extends StatelessWidget {
  const _ErrorState({
    required this.text,
    required this.retry,
    required this.onRetry,
  });

  final String text;
  final String retry;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, color: RkStatusColors.of(context).debit),
          const SizedBox(height: RkSpace.s3),
          Text(text, textAlign: TextAlign.center, style: RkType.body),
          const SizedBox(height: RkSpace.s3),
          OutlinedButton(onPressed: onRetry, child: Text(retry)),
        ],
      ),
    );
  }
}
