// R2.4's camera path, the one conversion it needs (04 §7.4 🔒, ADR 2026-09-19
// ruling 1 🔒): the sheet's QR — `base64url(version ‖ user_id ‖ RK)` — becomes
// the very code the typed path would make, so the scan and the keyboard reach
// **one** verdict by one route (the checksum, then the AEAD open).
//
// It materialises RK, so it runs where a `CryptoSuite` is and disposes the
// sheet in the same statement that decoded it; only the typed form leaves,
// which is what a person typing the sheet would have produced anyway. A QR
// that is not a sheet is null — the scan screen keeps looking.
import 'package:core_crypto/core_crypto.dart'
    show CryptoSuite, RecoverySheet, recoverySheetFromQr, recoverySheetTyped;

import '../../shared/seams/recovery_ladder.dart' show RecoverySheetCode;

/// The [RecoverySheetCode] a scanned sheet QR stands for, or null.
RecoverySheetCode? recoverySheetCodeOfQr(CryptoSuite suite, String qrText) {
  RecoverySheet? sheet;
  try {
    sheet = recoverySheetFromQr(suite, qrText);
    return RecoverySheetCode.parse(
      recoverySheetTyped(suite, sheet.userId, sheet.rk),
    );
  } on FormatException {
    return null;
  } finally {
    sheet?.dispose();
  }
}
