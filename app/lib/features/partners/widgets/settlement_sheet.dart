// The two settlement doors of S14.2 that actually post (02 §7.1 🔒 routes 1
// and 2). Both open **in this feature**, as a bottom sheet over S14, and post
// through [PartnersPort]: 07 §27 wants doors that lead somewhere real, and the
// lane brief forbids routing into `features/entry` — a settlement is not a
// day-book entry the user composes, it is a named movement between two
// accounts the app already knows.
//
//   pay out            `Dr Partner Current · Cr {money a/c}`   (needs cash)
//   partner-to-partner `Dr {over-funded} · Cr {under-funded}`  (no cash moves)
//
// Route 3, *carry forward*, posts nothing here: 02 §7.1 makes it the default
// and the year-close ceremony (§8.1) performs it, so its door is
// disabled-with-reason on the card and never opens a sheet.
import 'package:core_ledger/core_ledger.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/format/money_format.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';
import '../../../shared/money/paise_input.dart';
import '../partners_port.dart';

/// Which of the two posting routes the sheet is running.
enum SettlementMode {
  /// 02 §7.1 route 1 — the business pays the partner from a money account.
  payOut,

  /// 02 §7.1 route 2 — another owner pays them, outside the business.
  partnerToPartner,
}

/// Opens the settlement sheet for [partner]. Returns true when something was
/// posted.
Future<bool> showSettlementSheet(
  BuildContext context, {
  required SettlementMode mode,
  required String bookId,
  required PartnerDriftView partner,
  required PartnersView view,
  required PartnersPort port,
}) async {
  final posted = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => _SettlementSheet(
      mode: mode,
      bookId: bookId,
      partner: partner,
      view: view,
      port: port,
    ),
  );
  return posted ?? false;
}

class _SettlementSheet extends StatefulWidget {
  const _SettlementSheet({
    required this.mode,
    required this.bookId,
    required this.partner,
    required this.view,
    required this.port,
  });

  final SettlementMode mode;
  final String bookId;
  final PartnerDriftView partner;
  final PartnersView view;
  final PartnersPort port;

  @override
  State<_SettlementSheet> createState() => _SettlementSheetState();
}

class _SettlementSheetState extends State<_SettlementSheet> {
  final _amount = TextEditingController();
  String? _counterpartId;
  String? _error;
  bool _busy = false;

  /// The partners the over-funded owner could be paid by — everybody but
  /// themselves (02 §7.1 route 2).
  List<PartnerPosition> get _others => [
    for (final p in widget.view.positions)
      if (p.accountId != widget.partner.accountId) p,
  ];

  /// Money accounts with something in them (route 1 *needs cash*).
  List<SettlementSource> get _sources => [
    for (final s in widget.view.sources)
      if (s.balance.raw > 0) s,
  ];

  @override
  void initState() {
    super.initState();
    _counterpartId = switch (widget.mode) {
      SettlementMode.payOut =>
        _sources.isEmpty ? null : _sources.first.accountId,
      SettlementMode.partnerToPartner =>
        _others.isEmpty ? null : _others.first.accountId,
    };
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context);
    final paise = paiseOf(_amount.text);
    if (paise == null) {
      setState(() => _error = l10n.partnersSheetAmountInvalid);
      return;
    }
    // Never settle more than the business owes them: the claim being bought
    // or paid cannot exceed the claim itself (02 §7.1).
    if (paise > widget.partner.owed.raw) {
      setState(
        () => _error = l10n.partnersSheetAmountMax(
          widget.partner.name,
          formatPaise(widget.partner.owed.raw, locale: locale),
        ),
      );
      return;
    }
    final counterpart = _counterpartId;
    if (counterpart == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      switch (widget.mode) {
        case SettlementMode.payOut:
          await widget.port.payOut(
            bookId: widget.bookId,
            partnerAccountId: widget.partner.accountId,
            fromAccountId: counterpart,
            amount: Paise(paise),
          );
        case SettlementMode.partnerToPartner:
          await widget.port.settleBetweenPartners(
            bookId: widget.bookId,
            fromPartnerAccountId: widget.partner.accountId,
            toPartnerAccountId: counterpart,
            amount: Paise(paise),
          );
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = l10n.partnersSheetError;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context);
    final payOut = widget.mode == SettlementMode.payOut;
    final options = payOut
        ? [
            for (final s in _sources)
              (
                id: s.accountId,
                name: s.name,
                meta: formatPaise(s.balance.raw, locale: locale),
              ),
          ]
        : [
            for (final p in _others)
              (
                id: p.accountId,
                name: p.name,
                meta: formatPaise(p.net.raw.abs(), locale: locale),
              ),
          ];

    return Padding(
      padding: EdgeInsets.only(
        left: RkSpace.gutter,
        right: RkSpace.gutter,
        top: RkSpace.s5,
        bottom: MediaQuery.viewInsetsOf(context).bottom + RkSpace.s5,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              payOut
                  ? l10n.partnersSheetPayoutTitle
                  : l10n.partnersSheetP2pTitle,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: RkSpace.s2),
            Text(
              payOut
                  ? l10n.partnersSheetPayoutBody(widget.partner.name)
                  : l10n.partnersSheetP2pBody(widget.partner.name),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: RkStatusColors.of(context).muted,
              ),
            ),
            const SizedBox(height: RkSpace.s5),
            Text(
              payOut ? l10n.partnersSheetPayoutFrom : l10n.partnersSheetP2pTo,
              style: theme.textTheme.bodySmall,
            ),
            for (final o in options)
              _Choice(
                name: o.name,
                meta: o.meta,
                selected: o.id == _counterpartId,
                onTap: _busy
                    ? null
                    : () => setState(() => _counterpartId = o.id),
              ),
            const SizedBox(height: RkSpace.s4),
            TextField(
              controller: _amount,
              enabled: !_busy,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\s]')),
              ],
              style: (theme.textTheme.labelLarge ?? RkType.amountRow).copyWith(
                fontFeatures: RkType.tabular,
              ),
              decoration: InputDecoration(
                labelText: l10n.partnersSheetAmount,
                prefixText: '$rupeeSign ',
                errorText: _error,
              ),
            ),
            const SizedBox(height: RkSpace.s5),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: _busy || _counterpartId == null ? null : _save,
                    child: Text(l10n.partnersSheetSave),
                  ),
                ),
                const SizedBox(width: RkSpace.s3),
                TextButton(
                  onPressed: _busy ? null : () => Navigator.of(context).pop(),
                  child: Text(l10n.partnersSheetCancel),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// One pickable account. Selection is a check **icon plus** the selected
/// state on the row's semantics — never a tint alone (07 §1 rule 3).
class _Choice extends StatelessWidget {
  const _Choice({
    required this.name,
    required this.meta,
    required this.selected,
    required this.onTap,
  });

  final String name;
  final String meta;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      selected: selected,
      button: true,
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        onTap: onTap,
        leading: Icon(
          selected ? Icons.check_circle : Icons.circle_outlined,
          color: selected
              ? theme.colorScheme.primary
              : RkStatusColors.of(context).muted,
        ),
        title: Text(name),
        subtitle: Text(
          meta,
          style: (theme.textTheme.bodySmall ?? RkType.caption).copyWith(
            fontFeatures: RkType.tabular,
          ),
        ),
      ),
    );
  }
}
