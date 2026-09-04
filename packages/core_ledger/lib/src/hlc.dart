/// Hybrid logical clock value (03 §1): 48-bit physical milliseconds + 16-bit
/// logical counter, packed into one integer. The clock itself is injected —
/// this type never reads time; [tick] takes the physical reading as an argument.
extension type const Hlc(int raw) {
  /// Packs a physical time and counter.
  factory Hlc.compose({required int physicalMs, required int counter}) {
    if (physicalMs < 0 || physicalMs >= (1 << 48)) {
      throw ArgumentError.value(physicalMs, 'physicalMs', 'must fit 48 bits');
    }
    if (counter < 0 || counter >= (1 << 16)) {
      throw ArgumentError.value(counter, 'counter', 'must fit 16 bits');
    }
    return Hlc((physicalMs << 16) | counter);
  }

  /// Physical milliseconds component.
  int get physicalMs => raw >> 16;

  /// Logical counter component.
  int get counter => raw & 0xFFFF;

  /// The next HLC given an injected physical reading: if the wall clock has moved
  /// past this value it is used with counter 0; otherwise the counter increments.
  Hlc tick({required int physicalMs}) {
    if (physicalMs > this.physicalMs) {
      return Hlc.compose(physicalMs: physicalMs, counter: 0);
    }
    return Hlc.compose(physicalMs: this.physicalMs, counter: counter + 1);
  }

  /// Orders by value.
  int compareTo(Hlc other) => raw.compareTo(other.raw);

  /// Strictly before.
  bool operator <(Hlc other) => raw < other.raw;

  /// Strictly after.
  bool operator >(Hlc other) => raw > other.raw;

  /// At or before.
  bool operator <=(Hlc other) => raw <= other.raw;

  /// At or after.
  bool operator >=(Hlc other) => raw >= other.raw;
}

/// Projection order is `(hlc, event_id)` per book (03 §3.3 rule 1) — a total,
/// deterministic order on every device.
int compareEventOrder(Hlc a, String idA, Hlc b, String idB) {
  final c = a.compareTo(b);
  return c != 0 ? c : idA.compareTo(idB);
}
