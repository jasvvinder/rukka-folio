// S14 Partner positions (02 §7.1 🔒, 13 §3.2 row S14; reached from S8.1),
// carrying the S14.2 drift & settlement card (07 §27 🔒).
//
// Every figure comes off the ledger through [PartnersPort] — which is filled
// from `core_ledger`'s own `settlementCapacity` / `partnerDrift` (A-02-65…67)
// — so this screen holds no derived state of its own and cannot drift from the
// engine. It never imports `LocalLedger`: the implementing lane owns that.
//
// Vocabulary: consumer (02 §10 🔒). *Put in · Took out · Profit share*, and
// the net stated in a sentence — never Dr/Cr, which belongs to the A/C
// statement and the exports.
//
// ADR 2026-09-09b 🔒: a *Just me* business never mentions partners, ratios or
// distribution anywhere in the app. The shell never links here for such a
// book; if the route is reached anyway, [_SoloState] answers in words that
// contain none of those three ideas.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/format/money_format.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';
import '../../../shared/widgets/rk_connection_notice.dart';
import '../../../shared/widgets/rk_connection_notice_copy.dart';
import '../partners_paths.dart';
import '../partners_port.dart';
import '../partners_scope.dart';
import '../widgets/drift_settlement_card.dart';
import '../widgets/partner_position_card.dart';
import '../../../shared/widgets/rk_ruled_card.dart';
import '../widgets/settlement_sheet.dart';

/// S14 — one card per owner, the settlement-capacity sentence, and S14.2.
class PartnerPositionsScreen extends StatefulWidget {
  /// Creates the screen for [bookId].
  const PartnerPositionsScreen({super.key, required this.bookId, this.port});

  /// The business book whose owners these are (02 §7.1: partner accounts are
  /// per business book).
  final String bookId;

  /// Overrides the ambient [PartnersScope] — used by tests and by a host that
  /// builds the screen directly.
  final PartnersPort? port;

  @override
  State<PartnerPositionsScreen> createState() => _PartnerPositionsScreenState();
}

class _PartnerPositionsScreenState extends State<PartnerPositionsScreen> {
  PartnersPort? _port;
  Stream<PartnersView>? _view;
  int _attempt = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // PartnersScope is an InheritedWidget, so it may only be read from here on.
    _port ??= widget.port ?? PartnersScope.of(context);
    _view ??= _port!.watch(widget.bookId);
  }

  @override
  void didUpdateWidget(PartnerPositionsScreen old) {
    super.didUpdateWidget(old);
    // The host may hand the screen a different book — or a different port —
    // without it leaving the tree. Re-subscribe rather than keep showing the
    // old book's figures, which is the one way this screen could ever lie.
    if (widget.bookId != old.bookId || widget.port != old.port) {
      _port = widget.port ?? PartnersScope.of(context);
      _view = _port!.watch(widget.bookId);
    }
  }

  void _retry() {
    setState(() {
      _attempt++;
      _view = _port!.watch(widget.bookId);
    });
  }

  Future<void> _settle(
    SettlementMode mode,
    PartnerDriftView drift,
    PartnersView view,
  ) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final posted = await showSettlementSheet(
      context,
      mode: mode,
      bookId: widget.bookId,
      partner: drift,
      view: view,
      port: _port!,
    );
    if (posted) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.partnersSaved)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return StreamBuilder<PartnersView>(
      key: ValueKey(_attempt),
      stream: _view,
      builder: (context, snapshot) {
        final view = snapshot.hasError ? null : snapshot.data;
        // ADR 2026-09-09b 🔒 governs the app bar too: the word *Partners* is
        // only spoken once the book is known to be shared. While the stream is
        // still loading, or on a single-owner book, the bar carries no title
        // at all rather than name something this book must never hear about.
        final shared = view?.ownership == BookOwnership.shared;
        return Scaffold(
          appBar: AppBar(title: shared ? Text(l10n.partnersTitle) : null),
          body: SafeArea(
            child: switch ((snapshot.hasError, view)) {
              (true, _) => _ErrorState(
                text: l10n.partnersError,
                onRetry: _retry,
              ),
              (false, null) => _Skeleton(label: l10n.partnersSkeleton),
              (false, final v!) when v.ownership == BookOwnership.justMe =>
                const _SoloState(),
              (false, final v!) when v.positions.isEmpty => const _EmptyState(),
              (false, final v!) => _Positions(
                bookId: widget.bookId,
                view: v,
                onSettle: (mode, drift) => _settle(mode, drift, v),
              ),
            },
          ),
        );
      },
    );
  }
}

class _Positions extends StatelessWidget {
  const _Positions({
    required this.bookId,
    required this.view,
    required this.onSettle,
  });

  /// The book whose owners these are — the S14.1 door carries it.
  final String bookId;

  final PartnersView view;
  final void Function(SettlementMode, PartnerDriftView) onSettle;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final ratioTotal = view.positions.fold<int>(
      0,
      (sum, p) => sum + (p.ratioWeight ?? 0),
    );
    return ListView(
      padding: const EdgeInsets.only(bottom: RkSpace.s8),
      children: [
        // 07 §1 rule 7: offline is normal, never a blocking banner.
        if (view.offline)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              RkSpace.gutter,
              RkSpace.s3,
              RkSpace.gutter,
              0,
            ),
            child: RkConnectionNotice(copy: rkConnectionNoticeCopy(context)),
          ),
        _CapacityCard(view: view),
        if (view.hasDrift)
          for (final d in view.drift)
            DriftSettlementCard(
              drift: d,
              view: view,
              onPayOut: () => onSettle(SettlementMode.payOut, d),
              onPartnerToPartner: () =>
                  onSettle(SettlementMode.partnerToPartner, d),
            ),
        for (final p in view.positions)
          PartnerPositionCard(position: p, ratioTotal: ratioTotal),
        // The door to S14.1 (13 §3.2: S14.1's parent is S14). It is inside
        // `_Positions`, so it exists only on a shared business whose owner
        // accounts are seeded — ADR 2026-09-09b 🔒 keeps a *Just me* book from
        // ever seeing the word, and 07 §1 rule 6 keeps it from being a door to
        // an empty room.
        Padding(
          padding: const EdgeInsets.fromLTRB(
            RkSpace.gutter,
            RkSpace.s4,
            RkSpace.gutter,
            0,
          ),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              key: const Key('partners.distribute'),
              onPressed: () =>
                  GoRouter.maybeOf(context)
                      ?.push(PartnersPaths.distributeOf(bookId)),
              child: Text(l10n.distributeDoor),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            RkSpace.gutter,
            RkSpace.s4,
            RkSpace.gutter,
            0,
          ),
          child: Text(
            l10n.partnersNotePayer,
            style: theme.textTheme.bodySmall?.copyWith(
              color: RkStatusColors.of(context).muted,
            ),
          ),
        ),
      ],
    );
  }
}

/// 02 §7.1 🔒 *Settlement capacity*: the sentence first, the figures beneath —
/// never left for the reader to subtract.
class _CapacityCard extends StatelessWidget {
  const _CapacityCard({required this.view});

  final PartnersView view;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final status = RkStatusColors.of(context);
    final locale = Localizations.localeOf(context);
    return RkRuledCard(
      child: Padding(
        padding: const EdgeInsets.all(RkSpace.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              view.canSettleAll
                  ? l10n.partnersCapacityCan
                  : l10n.partnersCapacityShort(
                      formatPaise(view.shortBy.raw, locale: locale),
                    ),
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: RkSpace.s2),
            Text(
              l10n.partnersCapacityFigures(
                formatPaise(view.moneyTotal.raw, locale: locale),
                formatPaise(view.partnerCreditTotal.raw, locale: locale),
              ),
              style: (theme.textTheme.bodySmall ?? RkType.caption).copyWith(
                color: status.muted,
                fontFeatures: RkType.tabular,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The ruled skeleton of 11 §4.5 — static, no shimmer.
class _Skeleton extends StatelessWidget {
  const _Skeleton({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final status = RkStatusColors.of(context);
    return Semantics(
      label: label,
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: RkSpace.s4),
        children: [
          for (var i = 0; i < 3; i++)
            RkRuledCard(
              ruleColor: status.hairline,
              child: Padding(
                padding: const EdgeInsets.all(RkSpace.cardPadding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: RkSpace.s3,
                      width: 140,
                      color: status.skeletonLabel,
                    ),
                    const SizedBox(height: RkSpace.s3),
                    Container(
                      height: RkSpace.s4,
                      width: 96,
                      color: status.skeletonAmount,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A shared business whose Partner Current A/cs have not been seeded yet.
class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(RkSpace.gutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: RkSpace.s8),
          Text(l10n.partnersEmptyTitle, style: theme.textTheme.titleMedium),
          const SizedBox(height: RkSpace.s3),
          Text(
            l10n.partnersEmptyBody,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: RkStatusColors.of(context).muted,
            ),
          ),
        ],
      ),
    );
  }
}

/// ADR 2026-09-09b 🔒 — a single-owner business is told nothing about
/// partners, ratios or distribution. Reached only by a stale link; the way
/// out is the app bar's back button, so it is not a dead end (07 §1 rule 6).
class _SoloState extends StatelessWidget {
  const _SoloState();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(RkSpace.gutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: RkSpace.s8),
          Text(l10n.partnersSoloTitle, style: theme.textTheme.titleMedium),
          const SizedBox(height: RkSpace.s3),
          Text(
            l10n.partnersSoloBody,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: RkStatusColors.of(context).muted,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.text, required this.onRetry});

  final String text;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(RkSpace.gutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: RkSpace.s8),
          Text(text, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: RkSpace.s3),
          OutlinedButton(onPressed: onRetry, child: Text(l10n.partnersRetry)),
        ],
      ),
    );
  }
}
