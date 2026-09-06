import 'dart:convert';
import 'dart:typed_data';

/// Byte helpers shared by every module — canonical encodings that appear
/// inside signed or authenticated data must be built from these only, so that
/// two clients derive identical bytes.
final class Bytes {
  Bytes._();

  /// Concatenation.
  static Uint8List concat(List<Uint8List> parts) {
    var n = 0;
    for (final p in parts) {
      n += p.length;
    }
    final out = Uint8List(n);
    var o = 0;
    for (final p in parts) {
      out.setRange(o, o + p.length, p);
      o += p.length;
    }
    return out;
  }

  /// Unsigned 8-bit.
  static Uint8List u8(int v) {
    if (v < 0 || v > 0xff) throw ArgumentError.value(v, 'v', 'not a byte');
    return Uint8List.fromList([v]);
  }

  /// Unsigned 32-bit big-endian.
  static Uint8List u32be(int v) {
    if (v < 0 || v > 0xffffffff) {
      throw ArgumentError.value(v, 'v', 'out of u32 range');
    }
    return Uint8List(4)..buffer.asByteData().setUint32(0, v);
  }

  /// Signed 64-bit big-endian (HLCs, `issued_at` milliseconds).
  static Uint8List i64be(int v) =>
      Uint8List(8)..buffer.asByteData().setInt64(0, v);

  /// UTF-8 bytes of [s] prefixed by their u32 big-endian length, so
  /// variable-length fields cannot slide into their neighbours inside AAD or a
  /// signed header.
  static Uint8List lengthPrefixedUtf8(String s) {
    final b = utf8.encode(s);
    return concat([u32be(b.length), Uint8List.fromList(b)]);
  }

  /// Plain equality (not constant time — use for non-secret data only).
  static bool equal(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Unpadded base64url (04 §6.1 QR payloads, 04 §7.4 sheet QR).
  static String base64Url(Uint8List b) =>
      base64Url_.encode(b).replaceAll('=', '');

  /// Inverse of [base64Url]; tolerates missing padding.
  static Uint8List fromBase64Url(String s) {
    final pad = (4 - s.length % 4) % 4;
    return Uint8List.fromList(base64Url_.decode(s + '=' * pad));
  }

  /// Lower-case hex.
  static String hex(Uint8List b) =>
      b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

  /// Inverse of [hex].
  static Uint8List fromHex(String s) {
    if (s.length.isOdd) {
      throw FormatException('odd hex length', s);
    }
    final out = Uint8List(s.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = int.parse(s.substring(2 * i, 2 * i + 2), radix: 16);
    }
    return out;
  }

  /// URL-safe base64 codec (padded); [base64Url] strips the padding.
  // ignore: non_constant_identifier_names
  static const Codec<List<int>, String> base64Url_ = Base64Codec.urlSafe();
}

/// UUIDs as the 16 raw bytes they are on the wire (AAD, certificates, QR
/// payloads), parsed from and printed as the canonical 36-char lower-case form
/// every other package uses.
final class Uuid16 {
  Uuid16._();

  static final RegExp _canonical = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  );

  /// True when [s] is a canonical lower-case UUID string.
  static bool isCanonical(String s) => _canonical.hasMatch(s);

  /// 16 bytes of a canonical UUID string; throws [FormatException] otherwise.
  static Uint8List toBytes(String uuid) {
    if (!isCanonical(uuid)) throw FormatException('not a canonical uuid', uuid);
    return Bytes.fromHex(uuid.replaceAll('-', ''));
  }

  /// Canonical string of 16 bytes.
  static String fromBytes(Uint8List b) {
    if (b.length != 16) {
      throw FormatException('uuid needs 16 bytes, got ${b.length}');
    }
    final h = Bytes.hex(b);
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
        '${h.substring(16, 20)}-${h.substring(20)}';
  }
}
