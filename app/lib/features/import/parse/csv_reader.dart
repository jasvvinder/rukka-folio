// A small RFC 4180 CSV reader, because a bank's CSV is the one file format
// M10 parses on-device this round (07 §11 item 1 🔒: *all parsing on-device*).
//
// Pure string work: no `dart:io`, no clock, no locale. Bytes in, rows out —
// which is what lets `statement_parser.dart` stay testable and CI-pure.
//
// Fields are returned **verbatim** apart from the quoting itself (an outer
// pair of quotes removed, `""` collapsed to `"`). Nothing is trimmed, re-cased
// or "cleaned up": the description cell becomes `bank_text`, which 02 §10 🔒
// makes immutable evidence.
import 'dart:convert';
import 'dart:typed_data';

/// The delimiters a bank CSV is seen to use, in the order they are tried.
const csvDelimiters = [',', ';', '\t', '|'];

/// Decodes [bytes] as text.
///
/// UTF-8 with `allowMalformed` — a statement exported from an old core banking
/// system is often Latin-1, and a mangled character in a narration must never
/// cost the whole file. The UTF-8 BOM is dropped: it is an encoding artefact,
/// not part of the first header cell.
String decodeStatementText(Uint8List bytes) {
  final text = const Utf8Decoder(allowMalformed: true).convert(bytes);
  return text.startsWith('﻿') ? text.substring(1) : text;
}

/// Splits [text] into rows of fields.
///
/// [delimiter] defaults to the one [sniffDelimiter] picks. Line breaks inside
/// a quoted field are kept, as RFC 4180 requires — an Indian UPI narration
/// wrapped by an export tool would otherwise become two broken rows.
List<List<String>> parseCsv(String text, {String? delimiter}) {
  final d = (delimiter ?? sniffDelimiter(text)).codeUnitAt(0);
  const quote = 0x22; // "
  const cr = 0x0D;
  const lf = 0x0A;
  final rows = <List<String>>[];
  var row = <String>[];
  final field = StringBuffer();
  var inQuotes = false;
  var sawAnything = false;

  void endField() {
    row.add(field.toString());
    field.clear();
  }

  void endRow() {
    endField();
    rows.add(row);
    row = <String>[];
  }

  final units = text.codeUnits;
  for (var i = 0; i < units.length; i++) {
    final c = units[i];
    sawAnything = true;
    if (inQuotes) {
      if (c == quote) {
        if (i + 1 < units.length && units[i + 1] == quote) {
          field.writeCharCode(quote);
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        field.writeCharCode(c);
      }
      continue;
    }
    if (c == quote && field.isEmpty) {
      inQuotes = true;
    } else if (c == d) {
      endField();
    } else if (c == cr) {
      if (i + 1 < units.length && units[i + 1] == lf) i++;
      endRow();
    } else if (c == lf) {
      endRow();
    } else {
      field.writeCharCode(c);
    }
  }
  if (sawAnything && (field.isNotEmpty || row.isNotEmpty)) endRow();
  return rows;
}

/// Picks the delimiter that yields the most consistent row width.
///
/// Indian bank exports use commas, but a statement with commas inside
/// unquoted amounts is shipped semicolon- or tab-separated often enough that
/// guessing beats assuming. The winner is the delimiter whose most common row
/// width is largest; ties go to the earlier entry of [csvDelimiters].
String sniffDelimiter(String text) {
  final sample = const LineSplitter()
      .convert(text)
      .where((l) => l.trim().isNotEmpty)
      .take(20)
      .toList();
  if (sample.isEmpty) return csvDelimiters.first;
  var best = csvDelimiters.first;
  var bestWidth = 0;
  for (final d in csvDelimiters) {
    final counts = <int, int>{};
    for (final line in sample) {
      final w = d.allMatches(line).length + 1;
      counts[w] = (counts[w] ?? 0) + 1;
    }
    var width = 1;
    var seen = 0;
    counts.forEach((w, n) {
      if (w > 1 && (n > seen || (n == seen && w > width))) {
        width = w;
        seen = n;
      }
    });
    if (width > bestWidth) {
      bestWidth = width;
      best = d;
    }
  }
  return best;
}
