// Test-only reading of a ledger identity's tenant id (ADR 2026-10-10 §1 🔒).
//
// Production code reaches an id only by matching `KnownTenant`; the suites
// that exercise a first device — whose tenant is always known, minted at its
// first run — read it through this, which fails the test outright on a
// tenant not known yet rather than inventing one.
import 'package:rukka_folio/shared/ledger/local_ledger.dart';

/// The tenant id of an identity that holds one.
extension KnownTenantId on LedgerIdentity {
  /// Throws [StateError] when the tenant is not known.
  String get tenantId => switch (tenant) {
    KnownTenant(:final id) => id,
    TenantNotKnownYet() => throw StateError('tenant not known yet'),
  };
}
