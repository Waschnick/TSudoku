// Free Sudoku - a sudoku puzzle game based on the original Andoku, by Markus
// Wiederkehr, and the Sudoku Explainer by Nicolas Juillerat.
//
// Copyright (C) 2006 - 2007, Nicolas Juillerat
// Copyright (C) 2009 - 2011, Markus Wiederkehr
// Copyright (C) 2011 - NOW, Cool Android Appz
// Copyright (C) 2026 - NOW, the Dart/Flutter port authors
//
// This program is free software: you can redistribute it and/or modify it under
// the terms of the GNU General Public License as published by the Free Software
// Foundation, either version 3 of the License, or (at your option) any later
// version.
//
// This program is distributed in the hope that it will be useful, but WITHOUT
// ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
// FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License along with
// this program. If not, see <http://www.gnu.org/licenses/>.
//
// Ported from: app/src/main/java/com/googlecode/andoku/model/ValueSet.java
// Translation rules applied: R-01, R-02, R-03, R-10, R-13

/// A mutable 16-bit set of cell values, plus one sentinel bit.
///
/// This is the single most behaviour-critical type in the port (rule R-02). Three facts
/// about it are counter-intuitive, and all three are observable in the differential trace:
///
/// **1. Values are zero-based.** Bit *b* means "the value *b*", and the *displayed* digit
/// is `b + 1`. `transfer/PuzzleDecoder.java:150` encodes a given as `encodedValue - '1'`,
/// so the character `'1'` becomes value `0`; the renderer displays it again as
/// `nextValue(0) + 1` (`AndokuPuzzleView.java:814`) or via `theme.getSymbol(value)`
/// (`AndokuPuzzleView.java:1895`), and hints compare against `hint.getValue() - 1`
/// (`AndokuPuzzleView.java:485`). For a 9x9 board the digit bits are therefore **0..8**,
/// not 1..9. Any loop written as `for (b = 1; b < 11; b++)` silently drops the digit 1
/// from every cell.
///
/// **2. Bit 11 is a sentinel, not a value.** It means "this lone value is a *tentative*
/// pencil mark, not the committed answer". `im/ValuesThenCellInputMethod.java:42`
/// redeclares it as `private final int indMarcaUnica = 11` and toggles it at lines 119-125.
/// Bits 9 and 10 are left unused on a 9x9 board so that the sentinel does not collide with
/// a value; see [tentativeBit].
///
/// **3. Only [nextValue] hides the sentinel.** [size], [isEmpty], [contains],
/// [containsAny], [toString] and every mask operation see all 16 bits, so a cell holding
/// one value plus the sentinel has `size == 2`. That is not an oversight -- the Java
/// source says so in as many words at `ValueSet.java:115`: *"Esta funcion determina el
/// numero de celdas selccionadas, debe devolver un 2 para anotaciones unicas - NINGUN
/// CAMBIO NECESARIO"* ("must return 2 for unique annotations - NO CHANGE NEEDED"), and
/// `ValuesThenCellInputMethod.onTap` relies on it: it tests `cellValues.size() == 1`
/// specifically to mean "exactly one value *and* no sentinel yet".
///
/// A `ValueSet` that models only the nine digits compiles, passes naive tests, and
/// silently breaks the "values then cell" input method -- the one the player uses.
///
/// Mutability is deliberate: `AndokuPuzzle.setValues` writes through its STORED instance
/// via [setFromInt] (`AndokuPuzzle.java:435`), so a value type here would change aliasing
/// behaviour.
///
/// **But the board does NOT hand out that stored instance, and getting this backwards
/// breaks the whole game.** `AndokuPuzzle.getValues` is a defensive copy:
///
/// ```java
/// public ValueSet getValues(int row, int col) {
///     return new ValueSet(values[row][col]);     // AndokuPuzzle.java:427-429
/// }
/// ```
///
/// `ValuesThenCellInputMethod.onTap` therefore mutates a COPY and passes it back to
/// `setCellValues`. Only then does `setValues` write through the stored instance. Its first
/// two lines are what make the distinction load-bearing:
///
/// ```java
/// if (value_set[row][col].equals(valueSet))      // AndokuPuzzle.java:431-432
///     return false;
/// value_set[row][col].setFromInt(valueSet.toInt());
/// ```
///
/// If a port returns the live instance from `getValues`, then `valueSet` *is*
/// `value_set[row][col]`, the `equals` is always true, `setValues` always returns `false`
/// without invalidating, and **every move silently becomes a no-op**. The `marks` trace
/// section would not catch it either: those masks come from `computePencilMarks`, not from
/// moves. An earlier version of this comment claimed the input method mutates the board's
/// own instance in place -- it does not. Whoever ports `AndokuPuzzle` must copy here.
final class ValueSet {
  /// Number of bits the Java class scans -- `ValueSet.MAX_SIZE`.
  ///
  /// It is both the loop bound of [size] and [toString] and the maximum board size
  /// (`Puzzle.checkParameters` rejects anything above it). Note that it is *larger* than
  /// [tentativeBit], which is why the sentinel is inside the range those methods count.
  static const int maxSize = 16;

  /// The "tentative single" sentinel bit -- Java: `indMarcaUnica` (rule R-02).
  ///
  /// Java does not declare this in `ValueSet` at all. It appears as the bare literal `11`
  /// in `nextValue`'s guard (`ValueSet.java:133`) and is redeclared privately in
  /// `im/ValuesThenCellInputMethod.java:42`. Naming it once here is the only deviation
  /// from the original's structure in this file; the value must stay 11.
  static const int tentativeBit = 11;

  /// The raw bit mask, exactly Java's `private int values` (rule R-01).
  ///
  /// Public and mutable because the trace prints it verbatim and because [setFromInt] and
  /// [toInt] exist only to move it around. Treat it as the identity of the set: [hashCode]
  /// is this number and [operator ==] compares nothing else.
  int values;

  /// Creates a set from a raw mask; defaults to empty.
  ///
  /// Collapses Java's `ValueSet()` and `ValueSet(int values)` into one optional-positional
  /// constructor (rule R-13).
  ValueSet([this.values = 0]);

  /// Copy constructor -- Java's `ValueSet(ValueSet other)`.
  ///
  /// Copies the mask, so the sentinel bit travels with the copy.
  ValueSet.from(ValueSet other) : values = other.values;

  /// A set containing every value of a board of `size` -- Java's `ValueSet.all(int)`.
  ///
  /// Used by `Puzzle.getPossibleValues` (`Puzzle.java:163`) and `AndokuPuzzle` to seed the
  /// candidate mask, always with the board size, which is 9 for every shipped puzzle.
  ///
  /// Two traps, both harmless at `size == 9` but worth stating because they are the kind
  /// of thing a "cleanup" would get wrong:
  ///
  /// * The result is zero-based, so `all(9)` is `0x01FF` (bits 0..8), *not* bits 1..9.
  /// * At `size > 11` the result would include [tentativeBit] -- `all(16)` is `0xFFFF`.
  ///   Java has the same hole; it is unreachable only because no board is that big.
  static ValueSet all(int size) {
    if (size <= 0 || size > maxSize) {
      // Java throws a bare `IllegalArgumentException()` with no message.
      throw ArgumentError.value(size, 'size', 'must be in 1..$maxSize');
    }

    // Java: `int values = size < 32 ? (1 << size) - 1 : -1;`. The `-1` branch is dead --
    // the guard above already rejected everything above 16 -- and it only existed because
    // Java's `1 << 32` wraps to 1. Transcribed rather than dropped so that this line stays
    // diffable against the original; see rule R-10 for the 32-bit shift semantics.
    return ValueSet(size < 32 ? (1 << size) - 1 : -1);
  }

  /// The raw mask -- Java's `toInt()`.
  int toInt() => values;

  /// Overwrites the whole mask -- Java's `setFromInt(int)`.
  ///
  /// This is how `AndokuPuzzle.setValues` (`AndokuPuzzle.java:435`, `:475`) writes into the
  /// board's own `ValueSet` instances instead of replacing them, and how
  /// `ValuesThenCellInputMethod.setValues` resets the keypad. It carries the sentinel bit
  /// like any other, which is what makes the pencil-mark flag survive a save/restore round
  /// trip through `Bundle.putInt(toInt())`.
  void setFromInt(int values) {
    this.values = values;
  }

  /// Adds `value` to the set -- Java's `add(int)`.
  ///
  /// Accepts [tentativeBit] as well as a value; `ValuesThenCellInputMethod.onTap`
  /// (`ValuesThenCellInputMethod.java:120`) sets the sentinel through exactly this method.
  ///
  /// The reachable domain is `0..15`. Outside it Dart and Java part company (rule R-10):
  /// Java masks the shift distance to 5 bits, so `add(32)` would set bit 0, whereas Dart
  /// shifts a 64-bit int and `add(32)` sets bit 32. Not reproduced, because no caller can
  /// get there -- the keypad loop is bounded by the number of digit buttons.
  void add(int value) {
    values |= 1 << value;
  }

  /// Unions in another set -- Java's `addAll(ValueSet)`.
  ///
  /// Mask-level, so it copies the other set's sentinel bit too.
  void addAll(ValueSet values) {
    this.values |= values.values;
  }

  /// Removes `value` from the set -- Java's `remove(int)`.
  ///
  /// Also the way the sentinel is cleared (`ValuesThenCellInputMethod.java:125`), which is
  /// why this must not validate its argument against the board size.
  void remove(int value) {
    values &= ~(1 << value);
  }

  /// Subtracts another set -- Java's `removeAll(ValueSet)`.
  void removeAll(ValueSet values) {
    this.values &= ~values.values;
  }

  /// Intersects with another set -- Java's `retainAll(ValueSet)`.
  ///
  /// Mask-level: intersecting with a set that lacks the sentinel therefore *clears* the
  /// sentinel, so a tentative mark does not survive `retainAll`.
  void retainAll(ValueSet values) {
    this.values &= values.values;
  }

  /// Empties the set -- Java's `clear()`. Clears the sentinel along with the values.
  void clear() {
    values = 0;
  }

  /// Whether `value` is in the set -- Java's `contains(int)`.
  ///
  /// **No `bit < 11` guard**, by design: `contains(tentativeBit)` is the sentinel test, and
  /// `ValuesThenCellInputMethod.onTap` calls it that way at lines 119 and 124.
  ///
  /// The `try`/`catch` mirrors a real oddity. `ValueSet.java:95-105` (commented *"Diego -
  /// 17 abr 2017 - rodeando de un try/catch"*) wraps a bitwise test that cannot throw in
  /// Java, and then `return`s from the `finally` block -- which swallows *any* throwable
  /// and yields the initialiser `false`. In Java that is dead defensive code. In Dart it is
  /// not: `1 << value` throws `ArgumentError` for a negative `value`, so without the catch
  /// this method would start throwing where the original quietly returned something. The
  /// swallow is kept so the contract "contains never throws" holds on both sides.
  bool contains(int value) {
    var returnedValue = false;
    try {
      returnedValue = (values & 1 << value) != 0;
    } catch (_) {
      // Java: empty `catch (Exception e)` with a commented-out printStackTrace.
    }
    return returnedValue;
  }

  /// Whether the two sets overlap at all -- Java's `containsAny(ValueSet)`.
  ///
  /// Mask-level and therefore sentinel-blind: two sets that share only [tentativeBit]
  /// count as overlapping. Unreachable in practice, because the keypad set that this is
  /// always tested against (`ValuesThenCellInputMethod.java:119`, `:127`) can only hold
  /// values, never the sentinel.
  bool containsAny(ValueSet values) => (this.values & values.values) != 0;

  /// Whether the sentinel bit is set -- Java: `contains(indMarcaUnica)` (rule R-02).
  ///
  /// "The lone value in this cell is a tentative pencil mark, not the committed answer."
  /// Convenience for the one question callers actually ask about bit 11; it is the sentinel
  /// *flag* only and says nothing about how many values are present. Java never checks
  /// both together either -- `onTap` tests `size() == 1` and the flag separately.
  bool get isTentativeSingle => contains(tentativeBit);

  /// Number of bits set -- Java's `size()`.
  ///
  /// **Counts the sentinel.** One value plus a tentative mark is `size == 2`. See the class
  /// doc: `ValueSet.java:115` states this is required, and the trace prints both `size`
  /// and the raw mask, so a "fixed" version that excluded bit 11 would diff immediately.
  ///
  /// The explicit loop is kept rather than `values.bitCount`: Java counts bits 0..15 of a
  /// 32-bit int, while `bitCount` would count all 64 bits of a Dart int and so disagree for
  /// any negative mask (rule R-10).
  int get size {
    var count = 0;
    for (var bit = 0; bit < maxSize; bit++) {
      if ((values & 1 << bit) != 0) {
        count++;
      }
    }
    return count;
  }

  /// Whether the mask is zero -- Java's `isEmpty()`.
  ///
  /// **Not the same as "has no values".** A set holding only [tentativeBit] is non-empty,
  /// has `size == 1`, and yet `nextValue(0)` returns -1: nothing to paint, but the cell is
  /// not blank either. Java has the identical hole; keep it, and do not route emptiness
  /// checks through [nextValue] to "fix" it.
  bool get isEmpty => values == 0;

  /// Lowest value at or above `from`, or -1 if there is none -- Java's `nextValue(int)`.
  ///
  /// Iterate a set with `for (var v = s.nextValue(0); v != -1; v = s.nextValue(v + 1))`,
  /// the shape used by `MultiValuesPainter` (lines 64, 80, 98).
  ///
  /// This is the **only** method carrying the `bit < 11` guard, added by hand -- the
  /// original body is still in the file, commented out, at `ValueSet.java:140-148`, and the
  /// live version's comment explains why: *"He incluido (bit < 11) && para intentar no
  /// pintar el 11 al invalidar"* ("I added `(bit < 11) &&` to try not to paint the 11 when
  /// invalidating"). Everything that draws a cell goes through here, so the sentinel never
  /// reaches a glyph. The guard also means values 11..15 are unreachable through iteration
  /// even though [size] and [toString] would report them.
  ///
  /// `from` is always >= 0 at every call site (`nextValue(0)` or `nextValue(value + 1)`).
  /// A negative `from` throws here, where Java would have tested wrapped high bits and then
  /// fallen through to bit 0; the difference is unreachable (rule R-10).
  int nextValue(int from) {
    for (var bit = from; bit < maxSize; bit++) {
      // Order matters: `bit < 11` short-circuits, which is what stops the sentinel being
      // returned. Reversing the operands would be equivalent in Java but still wrong here.
      if ((bit < tentativeBit) && (values & 1 << bit) != 0) {
        return bit;
      }
    }
    return -1;
  }

  /// Java's `hashCode()`: the raw mask, unchanged (rule R-03).
  ///
  /// `ValueSet` is not used as a hash key anywhere in the original, but [operator ==] is
  /// overridden, so this must be too.
  @override
  int get hashCode => values;

  /// Mask equality -- Java's `equals(Object)` (rule R-03).
  ///
  /// Two sets holding the same value but differing in the sentinel are **not** equal.
  @override
  bool operator ==(Object other) => other is ValueSet && values == other.values;

  /// Java's `toString()`: zero-based bit indices in brackets, e.g. `[0, 4, 8]`.
  ///
  /// Sentinel-blind like [size] -- a tentative mark prints as the member `11` -- and
  /// zero-based, so the rendered digits are each one higher than what this shows. Only
  /// `android.util.Log` calls consumed it upstream; it is reproduced because the format is
  /// cheap to keep faithful and expensive to discover wrong inside a trace.
  @override
  String toString() {
    final sb = StringBuffer('[');

    for (var bit = 0; bit < maxSize; bit++) {
      if ((values & 1 << bit) != 0) {
        if (sb.length > 1) {
          sb.write(', ');
        }
        sb.write(bit);
      }
    }

    sb.write(']');
    return sb.toString();
  }

  // Deliberately NOT ported (see PORT-GUIDELINES.md section 4 -- dead code):
  //
  // * `static ValueSet none()` and both `static ValueSet of(...)` overloads: no call site
  //   anywhere in the Android sources. `ValueSet()` and `ValueSet()..add(v)` cover them.
  // * `int getValues(int[] array)`: its only caller is
  //   `solver/BrutePuzzleSolver.java:92`, which is on the do-not-port list. Note for
  //   anyone tempted to resurrect it -- it has no `bit < 11` guard, so it would hand the
  //   sentinel to its caller as if it were a value.
}
