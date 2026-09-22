// S12.6 Invoices — the dated list with amounts, the GST split, credit notes
// and the PDF door (13 §3.2 row S12.6, 07 §20 🔒, DESIGN-PACK §11 S12.6 🔒,
// ADR 2026-09-05g §10 🔒, §11 🔒).
//
// 💰 **Not one number is computed in this file.** Amounts arrive as integer
// paise and are formatted by `formatPaise`; the 18 %-inclusive split is
// `rkGstSplit`, a pure function over integer paise in `invoice_source.dart`.
// A `double` anywhere on this screen would be CLAUDE.md rule 1's bug.
//
// 🔒 **A refund is a credit note, in words.** ADR 2026-09-05g §10 — the row
// is labelled *Credit note* beside its own icon, never a negative invoice and
// never a minus sign doing the telling (07 §1 rule 3, colour and sign never
// alone).
//
// 🔒 **The invoice is delivered by email *and* WhatsApp** (08 §3.1). There is
// no PDF producer in this app and this lane does not invent one, so every PDF
// door is **disabled-with-reason naming those two channels** (07 §1 rule 6) —
// which is not a dead end: it tells the reader where the document already is.
//
// Newest first (13 §3.2) by `rkInvoicesNewestFirst`, a pure sort — the screen
// does not reorder in place and does not depend on the source's order.
import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/format/date_format.dart';
import '../../../shared/format/money_format.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';
import '../../../shared/widgets/rk_fit_text.dart';
import '../../../shared/widgets/rk_ruled_card.dart';
import '../../../shared/widgets/rk_states.dart';
import '../invoice_source.dart';
import '../widgets/subscription_action.dart';

/// S12.6 — invoices and credit notes.
class InvoicesScreen extends StatefulWidget {
  /// Creates the screen over [source].
  const InvoicesScreen({super.key, required this.source});

  /// Where the documents come from.
  final InvoiceSource source;

  @override
  State<InvoicesScreen> createState() => _InvoicesScreenState();
}

class _InvoicesScreenState extends State<InvoicesScreen> {
  List<RkInvoice>? _invoices;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant InvoicesScreen old) {
    super.didUpdateWidget(old);
    if (old.source != widget.source) _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final read = await widget.source.read();
      if (!mounted) return;
      setState(() {
        _invoices = rkInvoicesNewestFirst(read);
        _loading = false;
      });
    } on Object {
      // 🔒 A failed read says the READ failed — never "you have none", which
      // would be a figure invented out of an error (07 §1 rule 12).
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.invoicesTitle)),
      body: SafeArea(child: _body(l10n)),
    );
  }

  Widget _body(AppLocalizations l10n) {
    if (_loading) return RkSkeleton(label: l10n.invoicesLoading, rows: 5);
    final invoices = _invoices;
    if (_failed || invoices == null) {
      return RkErrorState(
        text: l10n.invoicesError,
        retryLabel: l10n.subscriptionActionRetry,
        onRetry: _load,
      );
    }
    if (invoices.isEmpty) {
      // In a scroller even when it is short: at 200 % on a 360 px phone the
      // empty state is taller than the viewport, and a Column there would
      // overflow rather than scroll (07 §1 — nothing is cut off).
      return ListView(
        padding: const EdgeInsets.symmetric(
          horizontal: RkSpace.gutter,
          vertical: RkSpace.s10,
        ),
        children: const [_Empty()],
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(
        RkSpace.gutter,
        RkSpace.s3,
        RkSpace.gutter,
        RkSpace.s8,
      ),
      itemCount: invoices.length,
      itemBuilder: (context, i) => Padding(
        padding: const EdgeInsets.only(bottom: RkSpace.s3),
        child: _InvoiceCard(invoice: invoices[i]),
      ),
    );
  }
}

/// The designed empty state (13 §4.3) — and the honest one today, since
/// nothing in the app issues an invoice.
class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final status = RkStatusColors.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.receipt_long_outlined,
          size: RkSpace.s10,
          color: status.muted,
        ),
        const SizedBox(height: RkSpace.s3),
        RkFitText(l10n.invoicesEmptyTitle, style: text.titleMedium),
        const SizedBox(height: RkSpace.s2),
        // 🔒 Says where the document already is: email AND WhatsApp (08 §3.1).
        RkFitText(l10n.invoicesEmptyBody, style: text.bodyMedium),
      ],
    );
  }
}

/// One document: kind, serial, date, amount, its GST split and the PDF door.
class _InvoiceCard extends StatelessWidget {
  const _InvoiceCard({required this.invoice});

  final RkInvoice invoice;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context);
    final text = Theme.of(context).textTheme;
    final status = RkStatusColors.of(context);
    final creditNote = invoice.kind == RkInvoiceKind.creditNote;
    final split = rkGstSplit(invoice.totalPaise);
    final amount = formatPaise(
      split.roundedTotalPaise,
      locale: locale,
      showPaise: true,
    );
    return RkRuledCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 🔒 The kind in words beside its own icon (ADR 2026-09-05g §10).
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                creditNote
                    ? Icons.assignment_return_outlined
                    : Icons.receipt_long_outlined,
                size: RkIcon.grid,
                color: creditNote ? status.info : status.muted,
              ),
              const SizedBox(width: RkSpace.s2),
              Expanded(
                child: RkFitText(
                  creditNote
                      ? l10n.invoicesKindCreditNote
                      : l10n.invoicesKindInvoice,
                  style: text.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: RkSpace.s2),
          // The continuous per-FY serial, exactly as the issuer wrote it.
          RkFitText(
            l10n.invoicesSerial(invoice.serial),
            style: text.bodySmall?.copyWith(color: status.muted),
          ),
          const SizedBox(height: 2),
          RkFitText(
            formatLedgerDate(localDateOf(invoice.issuedOn), strings: l10n),
            style: text.bodyMedium,
          ),
          if (creditNote) ...[
            const SizedBox(height: RkSpace.s2),
            RkFitText(
              l10n.invoicesKindCreditNoteBody,
              style: text.bodySmall?.copyWith(color: status.muted),
            ),
          ],
          const SizedBox(height: RkSpace.s3),
          // The split, half-up to the paisa on integer paise.
          _SplitLine(
            label: l10n.invoicesTaxable,
            value: formatPaise(
              split.taxablePaise,
              locale: locale,
              showPaise: true,
            ),
          ),
          _SplitLine(
            label: l10n.invoicesGst,
            value: formatPaise(split.taxPaise, locale: locale, showPaise: true),
          ),
          // 🔒 round_off is shown as a line — when there is one to show.
          if (split.roundOffPaise != 0)
            _SplitLine(
              label: l10n.invoicesRoundOff,
              value: formatPaise(
                split.roundOffPaise,
                locale: locale,
                showPaise: true,
              ),
            ),
          _SplitLine(label: l10n.invoicesTotal, value: amount, strong: true),
          const SizedBox(height: RkSpace.s3),
          // ⛔ No PDF producer. The row names the two channels that do have
          // the document (08 §3.1 🔒).
          SubscriptionAction.shut(
            label: l10n.invoicesPdf,
            reason: l10n.invoicesPdfReason,
            emphasis: SubscriptionEmphasis.secondary,
          ),
        ],
      ),
    );
  }
}

/// One `label … value` line of the split, stacked so 200 % on a 360 px phone
/// has room for both.
class _SplitLine extends StatelessWidget {
  const _SplitLine({
    required this.label,
    required this.value,
    this.strong = false,
  });

  final String label;
  final String value;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final status = RkStatusColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: RkSpace.s1),
      child: Semantics(
        label: '$label. $value',
        child: ExcludeSemantics(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              RkFitText(
                label,
                style: text.bodySmall?.copyWith(color: status.muted),
              ),
              RkFitText(
                value,
                style: strong
                    ? text.titleMedium?.copyWith(fontFeatures: RkType.tabular)
                    : text.bodyLarge?.copyWith(fontFeatures: RkType.tabular),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
