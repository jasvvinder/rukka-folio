// The PDF gate (ADR 2026-09-25 §5 🔒: Individual's Free plan has *"no PDF
// output"* — PDF statements and reports, and sharing them — while *"every
// statement and report on screen"* and *"Export everything as CSV/XLSX"* are
// never restricted, on any plan).
//
// 🔒 **It reads the token's `features`, never the plan's name** (ADR
// 2026-09-25 §6: *"The app's gates read the token, so moving a feature
// between plans takes effect at the next sync"*). A plan called `free` whose
// token carries `pdf_output` writes PDFs; a plan called `family` whose token
// does not, does not. The catalogue is not asked either — it is unsigned and
// display-only.
//
// **No token is Free** (ADR 2026-09-05g §1 🔒), and Free has no PDF (ADR 25
// §5 🔒), so with no `EntitlementScope` mounted — or a source that cannot be
// read — the gate is **shut**. ⚠️ SPEC (M13-CAT2): until the client token
// verifier lands (PLAN desk 23c) every build reads untokened, so PDF output
// is shut in every build; CSV and XLSX are untouched. Reported to the owner.
//
// Only PDF is ever gated here. CSV and XLSX never pass through this file.
import 'package:flutter/widgets.dart';

import '../../subscription/entitlement_source.dart';

/// The entitlement the reports feature reads: the mounted scope's, or the
/// untokened reading ADR 2026-09-05g §1 🔒 requires of an app holding none.
EntitlementSource reportEntitlementOf(BuildContext context) =>
    EntitlementScope.maybeOf(context)?.source ??
    const UntokenedEntitlementSource();

/// Whether [source]'s reading includes PDF output. A reading that cannot be
/// made is **not** a PDF licence: it answers false, and CSV/XLSX still work.
Future<bool> reportPdfIncluded(EntitlementSource source) async {
  try {
    return (await source.read()).has(RkFeature.pdfOutput);
  } on Object {
    return false;
  }
}
