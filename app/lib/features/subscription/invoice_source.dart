// Invoices and credit notes as **data** (S12.6; 08 §3.1 🔒, ADR 2026-09-05g
// §10 🔒, §11 🔒), plus the one pure function that splits a GST-inclusive
// total.
//
// 💰 **Integer paise throughout** (CLAUDE.md rule 1). The split is integer
// arithmetic — `~/` on scaled integers — and every part sums back to the
// total exactly. A `double` anywhere here would be the bug the rule names.
//
// ⛔ **No producer, and none invented.** Nothing in this app issues an
// invoice: the gateway does, and on IAP Apple/Google are merchant of record
// and issue nothing to us at all (ADR 2026-09-05g §8 🔒). So the shipped
// implementation is [UnwiredInvoiceSource], which reads **empty**, and S12.6
// draws its designed empty state — which is also the true screen for a tenant
// that has never paid.
//
// ⛔ **No PDF producer either.** ADR 2026-09-05g / 08 §3.1 🔒 deliver the
// invoice by **email *and* WhatsApp**; there is no PDF renderer in the app and
// this lane does not invent one, so every PDF door is disabled-with-reason
// naming those two channels (07 §1 rule 6).
//
// No clock: an invoice's date is a fact it carries, never `DateTime.now()`.
library;

/// What a row *is* — 🔒 a refund is a **credit note**, not a negative invoice
/// (ADR 2026-09-05g §10: "credit note on refund"), and S12.6 says so in
/// words, not by a minus sign alone (07 §1 rule 3).
enum RkInvoiceKind {
  /// A tax invoice for a purchase or renewal.
  invoice,

  /// A credit note against a refund or chargeback (ADR 2026-09-05g §11 🔒).
  creditNote,
}

/// One row of S12.6.
class RkInvoice {
  /// Creates a row.
  const RkInvoice({
    required this.serial,
    required this.issuedOn,
    required this.totalPaise,
    required this.kind,
  });

  /// The continuous per-FY serial (ADR 2026-09-05g §10 🔒) exactly as the
  /// issuer wrote it — a string, never a number to be re-formatted.
  final String serial;

  /// The date on the document.
  final DateTime issuedOn;

  /// The GST-**inclusive** total, integer paise, always non-negative: a
  /// credit note's direction is [kind], not a sign (see [RkInvoiceKind]).
  final int totalPaise;

  /// Invoice or credit note.
  final RkInvoiceKind kind;
}

/// The GST-inclusive total broken out (ADR 2026-09-05g §10 🔒, 08 §3.1 🔒).
///
/// Every field is integer paise and [taxablePaise] + [taxPaise] +
/// [roundOffPaise] == [roundedTotalPaise], with [cgstPaise] + [sgstPaise] ==
/// [taxPaise].
class RkGstSplit {
  /// Creates a split. Prefer [rkGstSplit].
  const RkGstSplit({
    required this.totalPaise,
    required this.taxablePaise,
    required this.cgstPaise,
    required this.sgstPaise,
    required this.roundOffPaise,
  });

  /// The GST-inclusive total the split was taken from.
  final int totalPaise;

  /// The taxable value — the total less GST, half-up to the paisa.
  final int taxablePaise;

  /// Half the tax, half-up to the paisa.
  final int cgstPaise;

  /// The other half — [taxPaise] less [cgstPaise], so the two always sum
  /// exactly whatever the rounding did.
  final int sgstPaise;

  /// The `round_off` line (ADR 2026-09-05g §10 🔒): what must be added to
  /// [totalPaise] to reach the whole rupee shown. Zero when the total is
  /// already whole rupees, which every catalogue price is.
  final int roundOffPaise;

  /// The whole tax.
  int get taxPaise => cgstPaise + sgstPaise;

  /// The rupee-rounded total actually shown as the document's total.
  int get roundedTotalPaise => totalPaise + roundOffPaise;
}

/// The GST rate, in **hundredths of a percent** so the rate itself is an
/// integer: 18 % (08 §3.1 🔒).
const int rkGstRateBasisPoints = 1800;

/// Splits a GST-inclusive [totalPaise] at 18 % (ADR 2026-09-05g §10 🔒).
///
/// Pure: no clock, no locale, no settings — the same total always gives the
/// same split, which is what lets a test pin it at the paisa.
///
/// - taxable = total × 10000 ÷ (10000 + 1800), **half-up to the paisa**;
/// - tax = total − taxable, split half-up to the paisa, the second half taking
///   the remainder so the pair sums exactly;
/// - `round_off` = the whole rupee nearest the total, half-up, less the total.
///
/// ⚠️ SPEC — **CGST/SGST vs IGST is not decided here.** A GSTIN buyer's
/// recipient state is captured (ADR 2026-09-05g §10, 06 §9.1) and it, not this
/// function, decides whether the tax is one IGST line or two half lines. The
/// conservative reading is taken: the halves are computed so both renderings
/// are available, and S12.6 shows the **combined** GST line because the list
/// data carries no state. Flagged for the owner rather than settled here.
RkGstSplit rkGstSplit(int totalPaise) {
  assert(totalPaise >= 0, 'a total is non-negative; a credit note is a kind');
  // Half-up division of a/b for non-negative a: (2a + b) ~/ 2b.
  const gross = 10000 + rkGstRateBasisPoints;
  final taxable = (2 * totalPaise * 10000 + gross) ~/ (2 * gross);
  final tax = totalPaise - taxable;
  final cgst = (2 * tax + 2) ~/ 4;
  final rupees = (2 * totalPaise + 100) ~/ 200;
  return RkGstSplit(
    totalPaise: totalPaise,
    taxablePaise: taxable,
    cgstPaise: cgst,
    sgstPaise: tax - cgst,
    roundOffPaise: rupees * 100 - totalPaise,
  );
}

/// [invoices] newest first — the order S12.6 lists them in (13 §3.2).
///
/// A pure sort on a copy: the source's list is never mutated, and ties break
/// on the serial descending so the order is total and a test is not at the
/// mercy of a stable-sort detail.
List<RkInvoice> rkInvoicesNewestFirst(List<RkInvoice> invoices) {
  final sorted = [...invoices];
  sorted.sort((a, b) {
    final byDate = b.issuedOn.compareTo(a.issuedOn);
    return byDate != 0 ? byDate : b.serial.compareTo(a.serial);
  });
  return sorted;
}

/// Reads the tenant's invoices and credit notes.
abstract interface class InvoiceSource {
  /// Every document this tenant has, in any order — S12.6 sorts.
  Future<List<RkInvoice>> read();
}

/// The shipped implementation: no issuer, so no documents.
///
/// Honest rather than empty-for-now: an app that has never had a payment
/// channel has genuinely never been invoiced, and S12.6's empty state says
/// what will make one appear.
class UnwiredInvoiceSource implements InvoiceSource {
  /// Creates the implementation.
  const UnwiredInvoiceSource();

  @override
  Future<List<RkInvoice>> read() async => const [];
}

/// Test double. Hands back what it was built with, or throws.
class FakeInvoiceSource implements InvoiceSource {
  /// Creates the fake. With [failure] set, [read] throws it.
  FakeInvoiceSource({List<RkInvoice>? invoices, this.failure})
    : invoices = invoices ?? const [];

  /// The documents handed back.
  List<RkInvoice> invoices;

  /// When set, [read] throws this instead.
  Object? failure;

  /// How many times [read] was called — a retry is observable.
  int reads = 0;

  @override
  Future<List<RkInvoice>> read() async {
    reads++;
    final failure = this.failure;
    if (failure != null) throw failure;
    return invoices;
  }
}
