// S10.4 — Year close + carry-forward (02 §8.1 🔒, 07 §13 last bullet 🔒,
// 13 §3.2 row S10.4, 13 §6 🔒).
//
// **One ceremony, four states, and the state is the ledger's, not a step
// counter's.** 13 §6 🔒 gives the year state machine as
// `open → closed/certified → (voided by re-open, loudly)`, and this screen is
// that machine and nothing more:
//
//   * **open** — the preconditions checklist (02 §8.1 🔒: every month locked,
//     Suspense zero, no open review flag, no pending advance request, no
//     author-sequence gap, no held envelope), stated as **two lists**: what
//     blocks and what merely warns. The split is not this screen's opinion; a
//     blocker carries `core_ledger`'s own [CloseBlocker] and a warning is a
//     different type altogether (see `year_close_source.dart`). Each blocker
//     names its month or its queue, because *a month is open* tells the closer
//     nothing and *March 2027 is still open* tells them where to go (07 §1
//     rule 6). For a business with an undistributed surplus, the optional
//     *Distribute profit first* door to **S14.1** sits above the action —
//     a door, never a rebuild of the wizard (02 §7.2.1: distribution is
//     structural, and S14.1 already owns it). Then the closing vector, shown
//     **before** anything is published, and the one certify action.
//   * **closed** — `Certified ✓ FY 2026-27`, the b/f it hands on, and the FY
//     switcher, which appears here for the first time (ADR 2026-09-09 §4 🔒:
//     one control on S4 · S8.2 · S10.4, and **no switcher until the first year
//     close**).
//   * **unverified-by-you** — `Certified · update to verify`. The certifier's
//     projector was newer than this phone's, so this phone cannot check the
//     figures. It is the **third outcome**, a state and not an alarm, and it
//     is never drawn as a mismatch (ADR 2026-09-05c §3 🔒).
//   * **uncertified** — the loud banner: a month inside the year was
//     re-opened, so this year's certificate and **every later year's** are
//     void, and re-closing happens in order (02 §8.1 🔒 *Reopening*). It uses
//     the shared banner atom, `RkBannerSurface`, because 13 §4.2 lists the
//     banner once.
//
// **Resumable 🔒** (07 §13) — by derivation rather than by a saved cursor.
// S10's four steps hold typed work (bank confirmations) that would be lost on
// leaving, so they are written through the seam at every step change. S10.4
// holds none: the checklist, the vector and the year's status are all read
// from the ledger, so leaving and coming back re-reads the same ceremony in
// the same state. Nothing can be lost because nothing is held here.
//
// The ledger reaches this screen through the feature-local [YearCloseSource] —
// `shared/ledger/` is another lane's folder this round, and nothing here
// imports `LocalLedger`. Two path constants come from other features
// ([PartnersPaths]), and one widget: [FySwitcher], which ADR 2026-09-09 §4 🔒
// requires be **one** control on all three surfaces, so it is consumed and
// never copied.
import 'dart:math' as math;

import 'package:core_ledger/core_ledger.dart';
import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/format/date_format.dart';
import '../../../shared/format/money_format.dart';
import '../../../shared/seams/closed_years.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';
import '../../../shared/widgets/rk_banner.dart';
import '../../../shared/widgets/rk_fit_text.dart';
import '../../../shared/widgets/rk_states.dart';
import '../../ledger/widgets/fy_switcher.dart';
import '../../ledger/widgets/text_metrics.dart';
import '../../partners/partners_paths.dart';
import '../close_paths.dart';
import '../close_source.dart' show CloseWarning, CloseWarningItem;
import '../widgets/close_blocked_panel.dart';
import '../widgets/close_parts.dart';
import '../year_close_source.dart';

/// Keys S10.4's parts answer to, so a test names a thing rather than a string
/// (the strings are asserted separately, in all three languages).
abstract final class YearCloseKeys {
  /// The preconditions checklist's **blocking** list.
  static const blocks = Key('close.year.blocks');

  /// The checklist's **warning** list — never the same list as [blocks].
  static const warns = Key('close.year.warns');

  /// The optional *Distribute profit first* door to S14.1.
  static const distribute = Key('close.year.distribute');

  /// The 02 §7.1 settlement door — carry forward preselected.
  static const settlement = Key('close.year.settlement');

  /// The closing balance vector, shown before certifying.
  static const vector = Key('close.year.vector');

  /// The one certify action, enabled.
  static const certify = Key('close.year.certify');

  /// The S10.5-shaped panel, in place of the certify action.
  static const blocked = Key('close.year.blocked');

  /// The sealed state — `Certified ✓ FY 2026-27` and what it hands on.
  static const sealed = Key('close.year.sealed');

  /// The loud voided-by-re-open banner (02 §8.1 🔒).
  static const voided = Key('close.year.voided');

  /// The FY switcher, which exists only once a year has closed.
  static const switcher = Key('close.year.switcher');
}

/// How certifying is going (13 §4.3: default · loading · error, plus the
/// refusal the engine may still raise).
enum _CertifyPhase { idle, working, done, error, refused }

/// How a vector line draws — decided once for the whole table by measuring
/// it, never by a text-scale threshold (07 §1 rule 11).
enum _VectorLayout {
  /// Name on the left, figure on the right: the paper-khata shape.
  beside,

  /// Name on its own line, figure on the next — what a 360 px phone at 200 %
  /// has room for, and the S4 statement's own answer at this width.
  stacked,
}

/// S10.4 — certify one book's financial year.
class YearCloseScreen extends StatefulWidget {
  /// Creates the ceremony for [bookId]'s [financialYear].
  const YearCloseScreen({
    super.key,
    required this.bookId,
    required this.financialYear,
    this.source,
    this.onOpen,
    this.onDone,
    this.offline = false,
  });

  /// The book whose year is being closed.
  final String bookId;

  /// The year being closed.
  final FinancialYear financialYear;

  /// The ledger door; when null it is read from [YearCloseScope].
  final YearCloseSource? source;

  /// Opens a location — S14.1 the distribution wizard, S14 the partner
  /// positions, or S10 for a month still open. `closeRoutes` passes
  /// `context.push`; a test passes a recorder, so the **path** is asserted and
  /// not a callback.
  final void Function(String path)? onOpen;

  /// Leaves the ceremony — the one action on the sealed state, so a certified
  /// year is not a dead end (07 §1 rule 6). Null renders no action.
  final VoidCallback? onDone;

  /// True while this device cannot reach the server. A chip, never a blocking
  /// banner (07 §1 rule 7 🔒): a close is computed locally.
  final bool offline;

  @override
  State<YearCloseScreen> createState() => _YearCloseScreenState();
}

class _YearCloseScreenState extends State<YearCloseScreen> {
  YearCloseSource? _source;
  YearCloseView? _view;
  Object? _loadError;
  bool _started = false;

  _CertifyPhase _phase = _CertifyPhase.idle;
  List<CloseBlockerItem> _refusedBy = const [];

  /// What this device made of the vector it has just certified — the third
  /// outcome included (ADR 2026-09-05c §3 🔒).
  CloseVerification? _justVerified;

  /// The FY switcher's input. Empty until the first year close, which is what
  /// makes *no switcher at all* true by construction (ADR 2026-09-09 §4 🔒).
  List<CertifiedYear> _years = const [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final source = widget.source ?? YearCloseScope.maybeOf(context);
    if (source == null) {
      // No scope, no door: the error state, not a thrown red screen.
      if (_loadError == null && !_started) {
        setState(() => _loadError = StateError('no YearCloseSource in scope'));
      }
      return;
    }
    if (identical(source, _source) && _started) return;
    _source = source;
    _started = true;
    _load();
  }

  Future<void> _load() async {
    final source = _source;
    if (source == null) return;
    setState(() {
      _loadError = null;
      _view = null;
    });
    try {
      final view = await source.loadYearClose(
        widget.bookId,
        widget.financialYear,
      );
      if (!mounted) return;
      setState(() => _view = view);
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _loadError = e);
      return;
    }
    // The switcher rides **beside** the ceremony, never in front of it: a
    // years list that cannot be read must not cost the closer his close, so
    // its failure simply leaves the control unbuilt (ADR 2026-09-09 §4 🔒 —
    // an empty list is *no switcher*, which is the shipped state anyway).
    try {
      final years = await source.certifiedYears(widget.bookId);
      if (!mounted) return;
      setState(() => _years = years);
    } on Object {
      if (!mounted) return;
      setState(() => _years = const []);
    }
  }

  Future<void> _certify() async {
    final source = _source;
    if (source == null) return;
    setState(() {
      _phase = _CertifyPhase.working;
      _refusedBy = const [];
    });
    try {
      final result = await source.closeYear(
        widget.bookId,
        widget.financialYear,
      );
      if (!mounted) return;
      setState(() {
        _phase = _CertifyPhase.done;
        _justVerified = result.verification;
      });
      // The switcher appears the moment the year seals (07 §13 🔒).
      try {
        final years = await source.certifiedYears(widget.bookId);
        if (!mounted) return;
        setState(() => _years = years);
      } on Object {
        // Already certified; a missing switcher is not a failed close.
      }
    } on YearCloseRefused catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _CertifyPhase.refused;
        _refusedBy = e.blockers;
      });
    } on Object {
      if (!mounted) return;
      setState(() => _phase = _CertifyPhase.error);
    }
  }

  /// A month in words — *Aug 2026* in EN, *ਅਗਸਤ 2026* / *अगस्त 2026* in PA/HI,
  /// from the locale's own month strings (07 §1 rule 5 🔒).
  String _month(AppLocalizations l, YearMonth m) =>
      '${monthName(l, m.month)} ${m.year}';

  /// The year this screen is on, after any close it has just run.
  YearStatus get _status => _phase == _CertifyPhase.done
      ? YearStatus.closed
      : (_view?.status ?? YearStatus.open);

  /// This device's reading of the certificate — the one it has just published
  /// if it published one, else the one it loaded (ADR 2026-09-05c §3 🔒).
  CloseVerification? get _verification => _justVerified ?? _view?.verification;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final view = _view;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RkFitText(l.closeYearTitle, maxLines: 1),
            RkFitText(
              view == null
                  ? l.closeYearFy(widget.financialYear.label)
                  : l.closeBook(view.bookName),
              maxLines: 1,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: RkStatusColors.of(context).muted),
            ),
          ],
        ),
      ),
      body: SafeArea(child: _body(l)),
    );
  }

  Widget _body(AppLocalizations l) {
    if (_loadError != null) {
      return RkErrorState(
        text: l.closeYearError,
        retryLabel: l.closeRetry,
        onRetry: _load,
      );
    }
    final view = _view;
    if (view == null) return RkSkeleton(label: l.closeYearSkeleton, rows: 5);
    // **Everything scrolls, including the banners.** A chip, a loud banner, a
    // read-only banner and the switcher pinned above a scrolling body cost
    // nothing at 100 % and more than the whole viewport at 200 % on a 360 px
    // phone — the body's own space goes negative and the column overflows off
    // the bottom, which is the silent failure 07 §1 rule 11 exists to prevent
    // (F1-07-199). Order is what carries the meaning here, not pinning: the
    // voided banner is still the first thing the closer reads, above the
    // checklist (02 §8.1 🔒).
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: RkSpace.s8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.offline)
            CloseQuietChip(
              label: l.connectionNoticeTitle,
              icon: Icons.cloud_off_outlined,
            ),
          // The loud one first: a voided certificate is the most important
          // fact on the screen and must not sit under a checklist (02 §8.1 🔒).
          if (_status == YearStatus.uncertified) _voidedBanner(l, view),
          if (view.readOnly) CloseBanner(reason: l.closeYearReadonly),
          // ADR 2026-09-09 §4 🔒: no switcher at all until the first year
          // close.
          if (_years.isNotEmpty) _switcher(l),
          ...(_status == YearStatus.closed
              ? _sealed(l, view)
              : _openYear(l, view)),
        ],
      ),
    );
  }

  // ── the switcher (ADR 2026-09-09 §4 🔒) ────────────────────────────────────

  Widget _switcher(AppLocalizations l) => KeyedSubtree(
    key: YearCloseKeys.switcher,
    child: FySwitcher(
      selected: widget.financialYear,
      // Book-scoped here: S4 shows one A/C's b/f, S10.4 shows the whole
      // book's, so the figure is the certified vector's own balance-sheet
      // total. Same control, same copy, the scope of the surface it is on.
      closedYears: [
        for (final y in _years)
          if (y.isCertified)
            ClosedYear(year: y.year, carriedForwardPaise: y.carriedForward.raw),
      ],
      openYear: _status == YearStatus.closed
          ? widget.financialYear.next
          : widget.financialYear,
      // Switching year from the ceremony re-enters the ceremony for that year
      // — the same screen at another path, never a silent in-place swap that
      // would leave the title and the action disagreeing.
      onSelected: (fy) => widget.onOpen?.call(
        ClosePaths.forYear(widget.bookId, ClosePaths.fyStartOf(fy)),
      ),
    ),
  );

  // ── voided by re-open (02 §8.1 🔒, 13 §6 🔒) ───────────────────────────────

  Widget _voidedBanner(AppLocalizations l, YearCloseView view) {
    final month = view.voidedBy;
    return KeyedSubtree(
      key: YearCloseKeys.voided,
      child: RkBannerSurface(
        // Loud: this is the one banner on the screen that reports a security-
        // and-trust position rather than a state (13 §4.2, 07 §1 rule 3 — the
        // icon and the words carry it without the tint).
        tone: RkBannerTone.danger,
        icon: Icons.gpp_maybe_outlined,
        title: l.closeYearVoidedTitle,
        body: month == null
            ? l.closeYearVoidedBodyUnknown(view.financialYear.label)
            : l.closeYearVoidedBody(_month(l, month), view.financialYear.label),
      ),
    );
  }

  // ── the open year: checklist → doors → vector → certify ───────────────────

  List<Widget> _openYear(AppLocalizations l, YearCloseView view) => [
    CloseStepHeader(
      title: l.closeYearChecklistTitle,
      help: l.closeYearChecklistHelp,
    ),
    ..._checklist(l, view),
    if (view.isBusiness) _distributeDoor(l, view),
    if (view.isBusiness) _settlementDoor(l, view),
    ..._vectorCard(l, view),
    _certifyAction(l, view),
  ];

  String _blockerText(AppLocalizations l, YearCloseBlocker b) {
    final who = b.deviceName ?? l.closeBlockedUnknownDevice;
    return switch (b.kind) {
      CloseBlocker.monthOpen => l.closeYearBlockerMonthOpen(
        b.month == null ? b.ref : _month(l, b.month!),
      ),
      CloseBlocker.suspenseNonZero => l.closeYearBlockerSuspense,
      CloseBlocker.reviewFlagOpen => l.closeYearBlockerReviewFlag,
      CloseBlocker.advancePending => l.closeYearBlockerAdvancePending,
      CloseBlocker.authorGapOpen => l.closeYearBlockerAuthorGap(who),
      CloseBlocker.heldEnvelope => l.closeYearBlockerHeld(who),
    };
  }

  /// The second line of a blocker row: the **month's way out**, or the name of
  /// the **queue** it sits in. 02 §8.1 🔒 is explicit that the review flags and
  /// the advance requests are *two distinct queues* and both must be empty, so
  /// the checklist says which is which rather than running them together.
  String? _blockerMeta(AppLocalizations l, YearCloseBlocker b) =>
      switch (b.kind) {
        CloseBlocker.monthOpen => l.closeYearBlockerMonthOpenHelp,
        CloseBlocker.reviewFlagOpen =>
          b.label == null
              ? l.closeYearBlockerReviewFlagQueue
              : '${l.closeYearBlockerReviewFlagQueue} · ${b.label}',
        CloseBlocker.advancePending =>
          b.label == null
              ? l.closeYearBlockerAdvancePendingQueue
              : '${l.closeYearBlockerAdvancePendingQueue} · ${b.label}',
        _ => b.label,
      };

  String _warningText(AppLocalizations l, CloseWarningItem w) =>
      switch (w.kind) {
        CloseWarning.agedAdvance => l.closeWarningAgedAdvance,
        CloseWarning.unverifiedCount => l.closeWarningUnverifiedCount,
      };

  List<Widget> _checklist(AppLocalizations l, YearCloseView view) {
    final status = RkStatusColors.of(context);
    return [
      if (view.blockers.isEmpty && view.warnings.isEmpty)
        CloseCard(
          rule: status.success,
          child: CloseStateRow(
            icon: Icons.check_circle_outline,
            tint: status.success,
            text: l.closeYearChecklistReady(view.financialYear.label),
          ),
        ),
      // Two lists, never one (07 §13 🔒). A list that is empty is simply
      // absent: the closer is never shown an empty *These stop the year
      // close* heading and left to wonder what it means.
      if (view.blockers.isNotEmpty)
        CloseCard(
          key: YearCloseKeys.blocks,
          rule: status.danger,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RkFitText(
                l.closeYearBlocksTitle,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              RkFitText(
                l.closeYearBlocksHelp,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: status.muted),
              ),
              const SizedBox(height: RkSpace.s2),
              for (final b in view.blockers)
                CloseStateRow(
                  icon: Icons.block,
                  tint: status.danger,
                  text: _blockerText(l, b),
                  meta: _blockerMeta(l, b),
                ),
            ],
          ),
        ),
      if (view.warnings.isNotEmpty)
        CloseCard(
          key: YearCloseKeys.warns,
          rule: status.warning,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RkFitText(
                l.closeYearWarnsTitle,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              RkFitText(
                l.closeYearWarnsHelp,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: status.muted),
              ),
              const SizedBox(height: RkSpace.s2),
              for (final w in view.warnings)
                CloseStateRow(
                  icon: Icons.error_outline,
                  tint: status.warning,
                  text: _warningText(l, w),
                  meta: w.label,
                ),
            ],
          ),
        ),
    ];
  }

  // ── the optional distribute door (02 §8.1 🔒, 07 §13 🔒) ───────────────────

  Widget _distributeDoor(AppLocalizations l, YearCloseView view) {
    final status = RkStatusColors.of(context);
    if (!view.distributionPending) {
      return CloseCard(
        key: YearCloseKeys.distribute,
        rule: status.success,
        child: CloseStateRow(
          icon: Icons.check_circle_outline,
          tint: status.success,
          text: l.closeYearDistributeDone,
        ),
      );
    }
    return CloseCard(
      key: YearCloseKeys.distribute,
      rule: status.info,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RkFitText(
            l.closeYearDistributeTitle,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: RkSpace.s1),
          Text(
            l.closeYearDistributeBody,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: status.muted),
          ),
          const SizedBox(height: RkSpace.s3),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: OutlinedButton.icon(
              // The door, not the wizard: S14.1 already exists and owns
              // distribution (02 §7.2.1 — it is a structural action).
              onPressed: view.readOnly
                  ? null
                  : () => widget.onOpen?.call(
                      PartnersPaths.distributeOf(view.bookId),
                    ),
              icon: const Icon(Icons.call_split),
              label: RkFitText(l.closeYearDistributeAction),
            ),
          ),
        ],
      ),
    );
  }

  // ── settlement: three routes, carry forward preselected (02 §7.1 🔒) ───────

  /// 02 §7.1 *Settlement* 🔒 names three routes offered at year close after
  /// distribution, with **carry forward preselected**.
  ///
  /// ⚠️ SPEC: routes 1 (*business pays out*) and 2 (*partner-to-partner*) are
  /// **postings**, not outcomes of this ceremony — the spec gives each its own
  /// `Dr/Cr` pair — while route 3 *is* what the ceremony does. A three-way
  /// chooser here would therefore offer two options that post nothing and one
  /// that is already happening. The conservative reading is to state all three
  /// with carry forward marked as chosen, and to give routes 1 and 2 the door
  /// to S14 where those entries are made. If the owner wants a real chooser
  /// that posts, 02 §7.1 needs to say what the ceremony writes for each route.
  Widget _settlementDoor(AppLocalizations l, YearCloseView view) {
    final status = RkStatusColors.of(context);
    return CloseCard(
      key: YearCloseKeys.settlement,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RkFitText(
            l.closeYearSettlementTitle,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: RkSpace.s2),
          // Selected, and the word says so — never the tint alone (07 §1).
          CloseStateRow(
            icon: Icons.radio_button_checked,
            tint: status.success,
            text: l.closeYearSettlementCarry,
            meta: l.closeYearSettlementCarryHelp,
          ),
          const SizedBox(height: RkSpace.s2),
          Text(
            l.closeYearSettlementOthers,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: status.muted),
          ),
          const SizedBox(height: RkSpace.s2),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: () =>
                  widget.onOpen?.call(PartnersPaths.of(view.bookId)),
              icon: const Icon(Icons.groups_outlined),
              label: RkFitText(l.closeYearSettlementOpen),
            ),
          ),
        ],
      ),
    );
  }

  // ── the closing vector, before anything is published (02 §8.1 🔒) ──────────

  /// Name beside figure, or figure under the name — **measured**, never a
  /// text-scale threshold (07 §1 rule 11; `features/ledger/widgets/
  /// text_metrics.dart`, and the same decision S3 and S4 make).
  ///
  /// An A/C name is the user's own word and may not be shortened; a certified
  /// figure may never be shrunk to fit. Where the two cannot share the line a
  /// card has, the figure takes the line below. **One decision for the whole
  /// table**, so the column does not come and go row by row.
  _VectorLayout _vectorLayout(AppLocalizations l, YearCloseVector vector) {
    final text = Theme.of(context).textTheme;
    final rowStyle = text.bodyMedium;
    final totalStyle = text.titleMedium;
    // Exactly what [MoneyText] resolves for its own run, or the measurement
    // measures a different string from the one that will be drawn.
    double figureRun(int paise, TextStyle? style) => textRunWidth(
      context,
      professionalFigure(context, paise),
      (style ?? text.labelLarge ?? RkType.amountRow).copyWith(
        fontFeatures: RkType.tabular,
      ),
    );

    var words = 0.0;
    var figures = 0.0;
    for (final line in vector.lines) {
      words = math.max(
        words,
        longestWordWidth(
          context,
          line.isNetResult
              ? l.closeYearVectorNetResult
              : (line.name ?? line.key),
          rowStyle,
        ),
      );
      figures = math.max(figures, figureRun(line.amount.raw, rowStyle));
    }
    words = math.max(
      words,
      longestWordWidth(context, l.closeYearVectorTotal, totalStyle),
    );
    figures = math.max(
      figures,
      figureRun(vector.carriedForward.raw, totalStyle),
    );

    // The line a card's contents actually have: the screen less both gutters
    // and both of the card's own paddings.
    final line =
        MediaQuery.sizeOf(context).width -
        (RkSpace.gutter + RkSpace.cardPadding) * 2;
    return words + RkSpace.s3 + figures <= line
        ? _VectorLayout.beside
        : _VectorLayout.stacked;
  }

  List<Widget> _vectorCard(AppLocalizations l, YearCloseView view) {
    final status = RkStatusColors.of(context);
    final vector = view.vector;
    if (vector == null || vector.isEmpty) {
      return [
        CloseCard(
          key: YearCloseKeys.vector,
          child: CloseStateRow(
            icon: Icons.info_outline,
            tint: status.info,
            text: l.closeYearVectorEmpty,
          ),
        ),
      ];
    }
    final layout = _vectorLayout(l, vector);
    return [
      CloseCard(
        key: YearCloseKeys.vector,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            RkFitText(
              l.closeYearVectorTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: RkSpace.s1),
            Text(
              l.closeYearVectorHelp(view.financialYear.next.label),
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: status.muted),
            ),
            const SizedBox(height: RkSpace.s3),
            for (final line in vector.lines)
              _VectorRow(
                label: line.isNetResult
                    ? l.closeYearVectorNetResult
                    : (line.name ?? line.key),
                paise: line.amount.raw,
                layout: layout,
              ),
            const Divider(height: RkSpace.s5),
            _VectorRow(
              label: l.closeYearVectorTotal,
              paise: vector.carriedForward.raw,
              emphasis: true,
              layout: layout,
            ),
            if (!vector.isBalanced) ...[
              const SizedBox(height: RkSpace.s2),
              CloseStateRow(
                icon: Icons.report_problem_outlined,
                tint: status.danger,
                text: l.closeYearVectorUnbalanced,
              ),
            ],
          ],
        ),
      ),
    ];
  }

  // ── the one action ─────────────────────────────────────────────────────────

  Widget _certifyAction(AppLocalizations l, YearCloseView view) {
    final status = RkStatusColors.of(context);
    // The S10.5 shape takes the place of the action while entries are known to
    // be missing (07 §28 🔒, ADR 2026-09-05b §3–4): nobody certifies a balance
    // with entries missing, and *whose phone* is the useful fact.
    final gaps = view.gaps;
    if (gaps.isNotEmpty) {
      final who = gaps.first.deviceName ?? l.closeBlockedUnknownDevice;
      return KeyedSubtree(
        key: YearCloseKeys.blocked,
        child: CloseBlockedPanel(
          title: l.closeYearBlockedTitle,
          body: l.closeYearBlockedBody(who),
          remindLabel: l.closeBlockedRemind(who),
          remindReason: l.closeBlockedRemindUnavailable,
          lockOffText: l.closeYearBlockedOff,
        ),
      );
    }
    final fy = view.financialYear.label;
    if (view.blockers.isNotEmpty) {
      return CloseCard(
        rule: status.danger,
        child: CloseDisabledAction(
          label: l.closeYearCertifyAction(fy),
          reason: l.closeYearCertifyBlocked(view.blockers.length),
          wayOut: l.closeYearCertifyBlockedAction,
          // The checklist is the top of this same screen, so the way out
          // scrolls back to it rather than pushing a destination.
          onWayOut: () => Scrollable.ensureVisible(
            context,
            duration: const Duration(milliseconds: 200),
          ),
        ),
      );
    }
    if (view.readOnly) {
      return CloseCard(
        child: CloseDisabledAction(
          label: l.closeYearCertifyAction(fy),
          reason: l.closeYearReadonly,
        ),
      );
    }
    final vector = view.vector;
    if (vector != null && !vector.isBalanced) {
      return CloseCard(
        rule: status.danger,
        child: CloseDisabledAction(
          label: l.closeYearCertifyAction(fy),
          reason: l.closeYearVectorUnbalanced,
        ),
      );
    }
    return CloseCard(
      child: switch (_phase) {
        _CertifyPhase.working => CloseStateRow(
          icon: Icons.hourglass_empty,
          tint: status.muted,
          text: l.closeYearCertifyWorking,
        ),
        // Unreachable: a done phase draws the sealed state instead.
        _CertifyPhase.done => const SizedBox.shrink(),
        _CertifyPhase.refused => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CloseStateRow(
              icon: Icons.block,
              tint: status.danger,
              text: l.closeYearCertifyRefused(_refusedBy.length),
            ),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                onPressed: _load,
                child: RkFitText(l.closeYearCertifyBlockedAction),
              ),
            ),
          ],
        ),
        _CertifyPhase.error => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CloseStateRow(
              icon: Icons.error_outline,
              tint: status.danger,
              text: l.closeYearCertifyError,
            ),
            const SizedBox(height: RkSpace.s2),
            FilledButton(onPressed: _certify, child: RkFitText(l.closeRetry)),
          ],
        ),
        _CertifyPhase.idle => FilledButton.icon(
          key: YearCloseKeys.certify,
          onPressed: _certify,
          icon: const Icon(Icons.verified_outlined),
          label: RkFitText(l.closeYearCertifyAction(fy)),
        ),
      },
    );
  }

  // ── the sealed year, and the three verification outcomes ──────────────────

  List<Widget> _sealed(AppLocalizations l, YearCloseView view) {
    final status = RkStatusColors.of(context);
    final fy = view.financialYear;
    final verification = _verification;
    // ADR 2026-09-05c §3 🔒 — `readerOutdated` is *update to verify* and never
    // a mismatch; the two are drawn apart, in different words and tints.
    final (
      String title,
      String body,
      IconData icon,
      Color tint,
    ) = switch (verification) {
      CloseVerification.readerOutdated => (
        l.closeYearSealedUnverified,
        l.closeYearSealedUnverifiedBody,
        Icons.system_update_alt,
        status.info,
      ),
      CloseVerification.mismatch => (
        l.closeYearSealedMismatch,
        l.closeYearSealedMismatchBody,
        Icons.report_problem_outlined,
        status.danger,
      ),
      CloseVerification.certifierOutdated => (
        l.closeYearSealedStale,
        l.closeYearSealedStaleBody,
        Icons.history,
        status.warning,
      ),
      CloseVerification.verified || null => (
        l.closeYearSealedBadge(fy.label),
        l.closeYearSealedBody(fy.next.label),
        Icons.verified_outlined,
        status.success,
      ),
    };
    final carried = view.certifiedVector ?? view.vector;
    return [
      CloseCard(
        key: YearCloseKeys.sealed,
        rule: tint,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Colour never alone: glyph + word + tint, and the word alone
            // carries it (07 §1 rule 3).
            CloseStateRow(icon: icon, tint: tint, text: title, meta: body),
            // The badge stays readable even in the two unverified variants:
            // the year *is* certified, only this phone cannot check it.
            if (verification != null &&
                verification != CloseVerification.verified) ...[
              const SizedBox(height: RkSpace.s2),
              RkFitText(
                l.closeYearSealedBadge(fy.label),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
            if (carried != null && !carried.isEmpty) ...[
              const SizedBox(height: RkSpace.s3),
              _VectorRow(
                label: l.closeYearVectorTotal,
                paise: carried.carriedForward.raw,
                emphasis: true,
                layout: _vectorLayout(l, carried),
              ),
            ],
          ],
        ),
      ),
      if (widget.onDone != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(
            RkSpace.gutter,
            RkSpace.s2,
            RkSpace.gutter,
            RkSpace.s4,
          ),
          child: FilledButton(
            onPressed: widget.onDone,
            child: RkFitText(l.closeYearSealedDone),
          ),
        ),
    ];
  }
}

/// One line of the closing vector: a name and a professional amount.
///
/// **Professional vocabulary, deliberately** (02 §10 🔒, CLAUDE.md rule 9).
/// A closing balance vector is a balance sheet — the same surface as the A/C
/// statement's b/f, which already reads Dr/Cr — so the figures carry the true
/// ledger side rather than *Money in / Money out*. The consumer words belong
/// on the month summary and the day book, not on a certificate.
class _VectorRow extends StatelessWidget {
  const _VectorRow({
    required this.label,
    required this.paise,
    this.emphasis = false,
    this.layout = _VectorLayout.beside,
  });

  final String label;
  final int paise;
  final bool emphasis;

  /// Beside or stacked, as `_vectorLayout` measured for this table.
  final _VectorLayout layout;

  @override
  Widget build(BuildContext context) {
    final style = emphasis ? Theme.of(context).textTheme.titleMedium : null;
    final status = RkStatusColors.of(context);
    if (layout == _VectorLayout.beside) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: RkSpace.s1),
        // The figure keeps its measured width and the name takes the rest:
        // two flexible children would split the line evenly and squeeze a
        // grouped amount that has no break opportunity at all, which is the
        // silent cut 07 §1 rule 11 exists to prevent (F1-07-199).
        child: Row(
          children: [
            Expanded(child: RkFitText(label, style: style)),
            const SizedBox(width: RkSpace.s3),
            MoneyText(
              paise,
              vocabulary: Vocabulary.professional,
              showDirection: true,
              textAlign: TextAlign.end,
              style: style,
            ),
          ],
        ),
      );
    }
    // Stacked: the name keeps its line, the figure takes the next, and the
    // Dr/Cr word wraps under the numerals where even that will not fit — the
    // figure is never shrunk and never cut (02 §10 🔒, 07 §1 rule 11).
    final side = directionLabel(
      AppLocalizations.of(context),
      Vocabulary.professional,
      paise,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: RkSpace.s1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RkFitText(label, style: style),
          const SizedBox(height: RkSpace.s1),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: RkSpace.s2,
              children: [
                MoneyText(
                  paise,
                  vocabulary: Vocabulary.professional,
                  textAlign: TextAlign.end,
                  style: style,
                ),
                if (side != null)
                  Text(
                    side,
                    style: Theme.of(context).textTheme.labelLarge
                        ?.copyWith(color: status.muted),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// What the route shows when the `:fyStart` path parameter is not a financial
/// year.
///
/// A malformed link is another screen's bug, but it still reaches a user, and
/// a red screen is the worst dead end there is (07 §1 rule 6).
class YearCloseUnavailableScreen extends StatelessWidget {
  /// Creates the screen. [onBack] pops; the route passes `context.pop`.
  const YearCloseUnavailableScreen({super.key, required this.onBack});

  /// Leaves the ceremony.
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: RkErrorState(
          text: l.closeYearError,
          retryLabel: l.closeBack,
          onRetry: onBack,
        ),
      ),
    );
  }
}
