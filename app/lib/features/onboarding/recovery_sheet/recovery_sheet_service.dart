// Rung 3's making half (04 §7.4 🔒; ADR 2026-10-06d ruling 3 🔒): S0.5b makes
// the paper sheet, publishes its sealed blob, hands the one-page PDF to the
// platform's print sheet, and checks a printed sheet back.
//
// **Order is the ruling.** `make` draws a fresh RK and seals this install's
// UMK under it (`LocalLedger.makeRecoverySheet`), renders the page, zeroises
// RK, and only then publishes the blob (`RecoveryApi.publishSheet`). The
// printout is returned — and so can be shown — **only after the server said
// it holds the blob**. A failed publish wipes the rendered page and throws
// [RecoverySheetNotMade] with its reason; nothing is printable, so no sheet
// the server does not hold is ever shown (ruling 3).
//
// **Where RK lives, and for how long** (CLAUDE.md rule 7; ADR 2026-10-06d §2
// *every buffer is zeroised*):
//   * as a libsodium `SecureKey` from `makeRecoverySheet` for one
//     synchronous derivation of the page's two strings: [LiveRecoverySheetService
//     .make] disposes it in a `finally` before the PDF is built and before
//     `publishSheet` is awaited — never across an await;
//   * in two Dart `String`s (the QR text and the typed code — 04 §7.4's
//     spec-mandated exception, `recoverySheetQr`'s own note) which cannot be
//     zeroised and are dropped as soon as the page is built;
//   * in the rendered PDF bytes, held by [RecoverySheetPrintout] while S0.5b
//     is on screen so *Print or save* can be opened again without rotating RK
//     (a second make would void the page just printed); [RecoverySheetPrintout
//     .discard] overwrites them with zeros when S0.5b goes away or a publish
//     fails. The print sheet gets its own copy (`Printing.layoutPdf`), which
//     the platform owns; no file is written by this code.
//
// The check (04 §7.4 *verified-storage nag*): the typed or scanned code is
// decoded, its user id must be this install's, and its RK must open **the
// blob the server holds now** to this install's own UMK. Fetch first, then
// decode → open → dispose in one synchronous stretch, so RK is never held
// across the network. Nothing is logged anywhere here (rule 4).
import 'dart:async';
import 'dart:typed_data';

import 'package:core_crypto/core_crypto.dart';
import 'package:flutter/widgets.dart';

import '../../../shared/ledger/local_ledger.dart';
import '../../../shared/seams/recovery_ladder.dart' show RecoverySheetCode;
import '../../../shared/sync/recovery_api.dart';
import '../../../shared/sync/recovery_seams.dart'
    show
        RecoveryQrCancelled,
        RecoveryQrNoCamera,
        RecoveryQrReader,
        RecoveryQrValue;
import 'recovery_sheet_pdf.dart';

/// Why a sheet was not made. Each has its own sentence on S0.5b (13 §4.3 —
/// an error states its reason).
enum RecoverySheetNotMadeReason {
  /// The server was not reached.
  offline,

  /// This phone holds no live session, or its identity is not yet confirmed
  /// (ADR 2026-10-04b §2): the payload would name an id that may change.
  notSignedIn,

  /// `sheet_flood` — too many sheets in a short time.
  tooMany,

  /// `upgrade_required`.
  needsUpdate,

  /// Any other refusal, or the page could not be built.
  server,
}

/// [RecoverySheetService.make] failed; nothing is printable.
final class RecoverySheetNotMade implements Exception {
  /// Creates the failure.
  const RecoverySheetNotMade(this.reason);

  /// Why.
  final RecoverySheetNotMadeReason reason;

  @override
  String toString() => 'RecoverySheetNotMade(${reason.name})';
}

/// What checking a printed sheet found. Only [opens] verifies.
enum RecoverySheetCheckResult {
  /// The code opens the blob the server holds to this account's own key.
  opens,

  /// The code was well formed for nobody, mistyped (checksum), or opens
  /// nothing the server holds now — an older sheet after a regeneration is
  /// this (R2.4b's two causes).
  didNotOpen,

  /// A sheet for a different account.
  otherAccount,

  /// The server holds no sheet for this account.
  noSheet,

  /// The server could not be asked; nothing is known about the code.
  couldNotCheck,

  /// The person backed out of the scanner.
  cancelled,

  /// This phone cannot scan here.
  noCamera,
}

/// Hands a rendered PDF to the platform's print / save sheet. True when the
/// page was printed or saved; false when the person cancelled the sheet —
/// a cancelled sheet is not an opened page (O5b's *I've kept it safe* stays
/// asleep).
typedef RecoverySheetPrinter = Future<bool> Function(
  Uint8List pdf,
  String name,
);

/// Renders the page for [content] in English plus [locale]'s language.
typedef RecoverySheetRenderer = Future<Uint8List> Function(
  RecoverySheetContent content,
  Locale locale,
);

/// A made, published sheet, ready to open. Holds the rendered page until
/// [discard].
final class RecoverySheetPrintout {
  /// Wraps [pdf] (owned from here on).
  RecoverySheetPrintout(this._pdf, this._printer, {required this.version});

  final Uint8List _pdf;
  final RecoverySheetPrinter _printer;
  bool _discarded = false;

  /// The server's `sheet_version` for this sheet.
  final int version;

  /// The file name the print sheet shows — no name, no figure (rule 4).
  static const fileName = 'Rukka recovery sheet.pdf';

  /// True once [discard] ran.
  bool get isDiscarded => _discarded;

  /// Opens the print / save sheet over the page: true when it was printed or
  /// saved, false when cancelled. Throws [StateError] once discarded.
  Future<bool> open() {
    if (_discarded) throw StateError('recovery sheet printout discarded');
    return _printer(_pdf, fileName);
  }

  /// Overwrites the page with zeros. Idempotent.
  void discard() {
    if (_discarded) return;
    _pdf.fillRange(0, _pdf.length, 0);
    _discarded = true;
  }
}

/// What S0.5b asks of rung 3.
abstract interface class RecoverySheetService {
  /// Makes, renders and publishes a fresh sheet (rotating RK — every earlier
  /// sheet stops working). Throws [RecoverySheetNotMade].
  Future<RecoverySheetPrintout> make(Locale locale);

  /// Whether the server holds a sheet for this account. Throws when it could
  /// not be asked.
  Future<bool> sheetOnServer();

  /// Checks a typed code.
  Future<RecoverySheetCheckResult> checkTyped(String typed);

  /// Scans the printed sheet's square and checks it.
  Future<RecoverySheetCheckResult> scan();
}

/// The live service over the ledger and `/recovery/sheet`.
final class LiveRecoverySheetService implements RecoverySheetService {
  /// Creates the service.
  LiveRecoverySheetService({
    required this.ledger,
    required this.api,
    required this.printer,
    required this.render,
    this.read,
  });

  /// The open ledger (its UMK, suite and user id).
  final LocalLedger ledger;

  /// `POST|GET /sync-meta/recovery/sheet`.
  final RecoveryApi api;

  /// The print sheet.
  final RecoverySheetPrinter printer;

  /// The page.
  final RecoverySheetRenderer render;

  /// The camera, or null where this phone cannot scan.
  final RecoveryQrReader? read;

  @override
  Future<RecoverySheetPrintout> make(Locale locale) async {
    final RecoverySheetMaterial material;
    try {
      material = ledger.makeRecoverySheet();
    } on IdentityNotConfirmed {
      throw const RecoverySheetNotMade(RecoverySheetNotMadeReason.notSignedIn);
    } on LedgerNotOpen {
      throw const RecoverySheetNotMade(RecoverySheetNotMadeReason.notSignedIn);
    }
    final Uint8List blob = material.sealedBlob;
    // RK's whole life in guarded memory: the two strings the page prints.
    final RecoverySheetContent content;
    try {
      content = recoverySheetContentOf(
        ledger.suite,
        material.userId,
        material.rk,
      );
    } on Object {
      throw const RecoverySheetNotMade(RecoverySheetNotMadeReason.server);
    } finally {
      material.dispose();
    }
    final Uint8List pdf;
    try {
      pdf = await render(content, locale);
    } on Object {
      throw const RecoverySheetNotMade(RecoverySheetNotMadeReason.server);
    }

    final int version;
    try {
      version = await api.publishSheet(blob);
    } on RecoveryApiFailure catch (e) {
      pdf.fillRange(0, pdf.length, 0);
      throw RecoverySheetNotMade(_reasonOf(e.refusal));
    } on Object {
      pdf.fillRange(0, pdf.length, 0);
      throw const RecoverySheetNotMade(RecoverySheetNotMadeReason.server);
    }
    return RecoverySheetPrintout(pdf, printer, version: version);
  }

  static RecoverySheetNotMadeReason _reasonOf(RecoveryRefusal r) => switch (r) {
    RecoveryRefusal.offline => RecoverySheetNotMadeReason.offline,
    RecoveryRefusal.unauthorized => RecoverySheetNotMadeReason.notSignedIn,
    RecoveryRefusal.flood => RecoverySheetNotMadeReason.tooMany,
    RecoveryRefusal.upgradeRequired => RecoverySheetNotMadeReason.needsUpdate,
    _ => RecoverySheetNotMadeReason.server,
  };

  @override
  Future<bool> sheetOnServer() async => await api.sheet() != null;

  @override
  Future<RecoverySheetCheckResult> checkTyped(String typed) async {
    final code = RecoverySheetCode.parse(typed);
    if (code == null) return RecoverySheetCheckResult.didNotOpen;
    return _check(code);
  }

  @override
  Future<RecoverySheetCheckResult> scan() async {
    final reader = read;
    if (reader == null) return RecoverySheetCheckResult.noCamera;
    final suite = ledger.suite;
    final got = await reader<RecoverySheetCode>(
      (text) => recoverySheetCodeOfQrText(suite, text),
    );
    return switch (got) {
      RecoveryQrValue(:final value) => _check(value),
      RecoveryQrCancelled() => RecoverySheetCheckResult.cancelled,
      RecoveryQrNoCamera() => RecoverySheetCheckResult.noCamera,
    };
  }

  Future<RecoverySheetCheckResult> _check(RecoverySheetCode code) async {
    final suite = ledger.suite;
    // The checksum first, on this phone and for nothing (R2.4b's mistype).
    if (!_wellFormed(suite, code)) return RecoverySheetCheckResult.didNotOpen;

    final RecoverySheetWire? wire;
    try {
      wire = await api.sheet();
    } on Object {
      return RecoverySheetCheckResult.couldNotCheck;
    }
    if (wire == null) return RecoverySheetCheckResult.noSheet;

    // From here to the end: synchronous — RK is never held across an await.
    RecoverySheet? sheet;
    UmkKeyPair? opened;
    try {
      sheet = recoverySheetFromTyped(suite, code.value);
      if (sheet.userId != ledger.identity.userId) {
        return RecoverySheetCheckResult.otherAccount;
      }
      final blob = SealedRecoveryBlob.decode(wire.blob);
      opened = openUmkWithRecoveryKeyVerified(
        suite,
        sheet.rk,
        blob,
        expected: ledger.keyMaterial.umk.public,
      );
      return RecoverySheetCheckResult.opens;
    } on RecoveryUnsealFailed {
      return RecoverySheetCheckResult.didNotOpen;
    } on RecoveredUmkMismatch {
      // The pair was disposed by `verifyRecoveredUmk`.
      return RecoverySheetCheckResult.didNotOpen;
    } on RecoverySheetChecksumFailed {
      return RecoverySheetCheckResult.didNotOpen;
    } on FormatException {
      return RecoverySheetCheckResult.didNotOpen;
    } finally {
      opened?.dispose();
      sheet?.dispose();
    }
  }

  static bool _wellFormed(CryptoSuite suite, RecoverySheetCode code) {
    RecoverySheet? sheet;
    try {
      sheet = recoverySheetFromTyped(suite, code.value);
      return true;
    } on RecoverySheetChecksumFailed {
      return false;
    } on FormatException {
      return false;
    } finally {
      sheet?.dispose();
    }
  }
}

/// The typed code a scanned sheet QR stands for, or null for any other QR —
/// the scanner keeps looking (`RecoveryQrReader`). Same conversion as
/// S11.3's (`features/recovery/sheet_qr.dart`): RK lives for one statement.
RecoverySheetCode? recoverySheetCodeOfQrText(CryptoSuite suite, String qr) {
  RecoverySheet? sheet;
  try {
    sheet = recoverySheetFromQr(suite, qr);
    return RecoverySheetCode.parse(
      recoverySheetTyped(suite, sheet.userId, sheet.rk),
    );
  } on FormatException {
    return null;
  } finally {
    sheet?.dispose();
  }
}

/// Installs the [RecoverySheetService] S0.5b uses. With none, S0.5b says the
/// sheet cannot be made here and keeps *Skip for now* (07 §1 rule 6).
class RecoverySheetServiceScope extends InheritedWidget {
  /// Installs [service].
  const RecoverySheetServiceScope({
    super.key,
    required this.service,
    required super.child,
  });

  /// The service.
  final RecoverySheetService service;

  /// The nearest service, or null.
  static RecoverySheetService? maybeOf(BuildContext context) => context
      .getInheritedWidgetOfExactType<RecoverySheetServiceScope>()
      ?.service;

  @override
  bool updateShouldNotify(RecoverySheetServiceScope old) =>
      service != old.service;
}
