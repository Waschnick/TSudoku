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
// Ported from: app/src/main/java/com/googlecode/andoku/model/Position.java
// Ported from: app/src/main/java/com/googlecode/andoku/model/Region.java
// Ported from: app/src/main/java/com/googlecode/andoku/model/ExtraRegion.java
// Ported from: app/src/main/java/com/googlecode/andoku/model/ExtraRegions.java
// Translation rules applied: R-03, R-13

/// Board geometry: the four tiny `com.googlecode.andoku.model` classes that
/// describe *where* cells are, collapsed into one library.
///
/// They are one concept and Dart has no package-private visibility, so keeping
/// them in four files would buy nothing but four copies of the GPL header.
///
/// ## Why the cell order inside every region is load-bearing
///
/// `AndokuPuzzle.determinePuzzleType` (Java `model/AndokuPuzzle.java:1323`)
/// infers the `PuzzleType` from the *count* of extra regions alone — 2 means X,
/// 4 hyper, 3 percent, 9 color — except for the two single-region variants,
/// where it discriminates on one cell:
///
/// ```java
/// if (puzzle.getExtraRegions()[0].positions[0].row == 1) {   // line 1340/1358
///     return PuzzleType.STANDARD_DOT;
/// } else {
///     return PuzzleType.STANDARD_WHEEL;
/// }
/// ```
///
/// [ExtraRegions.dot] emits `(1,1)` first, [ExtraRegions.wheel] emits `(4,1)`
/// first. Sorting either list — or building the wheel in reading order, which
/// would put `(1,4)` first — silently retypes every WHEEL puzzle as DOT. There
/// is no assertion anywhere that would catch it; the board would simply be
/// painted and solved as the wrong variant.
///
/// Region *order* is observable for the same reason: `Puzzle.getRegions()`
/// appends extra regions in factory order, `AndokuPuzzle.getExtraRegionCode`
/// returns that index, and the differential harness prints both (the `RG1`
/// rows' `cells=` field and the `ARE` row's `extra=` field). So the deliberately
/// unnatural `hyper` order — `(1,1), (5,1), (1,5), (5,5)`, row offset varying
/// first — must be preserved exactly.
library;

import 'value_set.dart';

/// A cell coordinate. Java: `model/Position.java`.
///
/// Immutable and used as a map key: `Puzzle.initRegionsAt` builds a
/// `HashMap<Position, List<Region>>` and then looks up `new Position(row, col)`
/// for every cell, so value equality is not optional (R-03). A `Position`
/// with only `==` overridden, or only `hashCode`, would make that lookup return
/// null and `Puzzle` would throw on construction.
final class Position implements Comparable<Position> {
  final int row;
  final int col;

  const Position(this.row, this.col);

  @override
  bool operator ==(Object other) =>
      other is Position && row == other.row && col == other.col;

  /// Java: `row * 9901 + col`. Transcribed rather than replaced with
  /// `Object.hash` so that any hash-derived ordering stays comparable with the
  /// JVM oracle should one ever leak into a trace. 9901 is prime and the board
  /// is at most 16 wide, so for real inputs this is a perfect hash.
  @override
  int get hashCode => row * 9901 + col;

  /// Java: `compareTo` — row first, then column; both by subtraction.
  ///
  /// Java returns the raw difference, not -1/0/1. Reproduced, because a
  /// comparator's magnitude is visible to any caller that inspects it (and
  /// because coordinates are 0..15, so the subtraction cannot overflow; R-10
  /// does not apply here).
  @override
  int compareTo(Position other) {
    final diff = row - other.row;
    if (diff != 0) return diff;
    return col - other.col;
  }

  /// Java: `same_position`. Identical to [==]; the original added it for the
  /// game Activity, which compares a remembered cell against the current one.
  /// Kept so the UI layer has the same vocabulary as the Java it replaces.
  bool samePosition(Position p2) => row == p2.row && col == p2.col;

  /// Java: `row + "x" + col`.
  ///
  /// This string does **not** reach the compared trace, and an earlier version of
  /// this comment claimed it did, citing a `Canon.java:389` that does not exist
  /// (`Canon.java` is 75 lines). The only canonicaliser for an `andoku.model.Position`
  /// is `Canon.pos` — `"r" + row + col`, i.e. `r35`, never `toString()`. The
  /// `Object.toString()` fallback is `Oracle.safe`, applied to exactly one field:
  /// `tostr=` on a `com.diuf.sudoku` `Hint`, which carries `Cell`s and never a
  /// `Position`. Kept faithful to the Java anyway — but protect `Canon.pos`'s
  /// shape, not this one.
  @override
  String toString() => '${row}x$col';
}

/// One variant-specific extra constraint group: the X diagonals, a hyper box,
/// the percent shape, a colour class, the dot cells or the wheel cells.
/// Java: `model/ExtraRegion.java`.
///
/// Java has two constructors — `ExtraRegion(List<Position>)` copies via `toArray`
/// (`ExtraRegion.java:32-34`), `ExtraRegion(Position[])` aliases (`:36-38`) — and
/// the field is a fixed-length `Position[]`.
///
/// Dart has one list type, so there is one constructor, and it takes the **copying**
/// branch and stores an unmodifiable view. That is the stricter of the two Java
/// behaviours and it is deliberate; see D-05 in `DIVERGENCES.md`. An earlier
/// version aliased a growable list, which was less faithful than Java in two ways at
/// once: the caller's later mutations leaked in, and `positions.add(...)` could grow a
/// region *after* `Puzzle` had already validated its size.
final class ExtraRegion {
  /// Unmodifiable, mirroring Java's fixed-length `Position[]`.
  final List<Position> positions;

  ExtraRegion(List<Position> positions)
    : positions = List<Position>.unmodifiable(positions);

  /// Java compares as a *set*: `new HashSet<>(asList(positions)).equals(...)`.
  /// Order and duplicates therefore do not matter for equality even though they
  /// matter for everything else about this class. Reproduced literally — the
  /// upstream comment says it is "only needed by PuzzleEncoder", i.e. it is a
  /// convenience, not a hot path, and it is deliberately *not* the identity
  /// that drives puzzle typing.
  @override
  bool operator ==(Object other) {
    if (other is! ExtraRegion) return false;
    final mine = positions.toSet();
    final theirs = other.positions.toSet();
    return mine.length == theirs.length && mine.containsAll(theirs);
  }

  /// Java: `new HashSet<Position>(asList(positions)).hashCode()`, and
  /// `AbstractSet.hashCode` is the sum of the *distinct* element hash codes.
  /// Summing the deduplicated set reproduces that exactly. Dart's
  /// `Set.hashCode` is identity-based, so delegating to it would break the
  /// `==`/`hashCode` contract this class needs (R-03).
  @override
  int get hashCode {
    var h = 0;
    for (final p in positions.toSet()) {
      h += p.hashCode;
    }
    return h;
  }
}

/// A constraint group that must contain each value exactly once, together with
/// the set of values currently placed in it. Java: `model/Region.java`.
///
/// [values] is mutable live state, not geometry: `Puzzle.set`/`clear` add and
/// remove the placed digit on every region covering the cell, and
/// `Puzzle.getPossibleValues` subtracts these sets. It is a fresh [ValueSet]
/// per region, exactly as the Java constructors do.
final class Region {
  /// Index of this region within `Puzzle.getRegions()`. Assigned by `Puzzle`,
  /// not derived here.
  final int id;

  /// One of `Puzzle.typeRow`, `typeCol`, `typeArea`, `typeExtra`.
  final String type;

  /// Ordinal within the type: row index, column index, area code, or the extra
  /// region's position in the variant's factory output.
  final int number;

  /// Unmodifiable, mirroring Java's fixed-length `Position[]`.
  final List<Position> positions;

  final ValueSet values;

  /// Parameter order mirrors the Java constructor
  /// `Region(int id, String type, int number, List<Position> positions)`, which
  /// copies (`positions.toArray(...)`, `Region.java:35-41`). `Puzzle.createRegions`
  /// uses that copying overload for rows, columns and areas (`Puzzle.java:211, 219,
  /// 229`) and the aliasing `Position[]` overload only for extras (`:234`).
  ///
  /// Both collapse into this one constructor, which copies and stores an
  /// unmodifiable view. For the extras path that is stricter than Java; the source
  /// list is a throwaway from an `ExtraRegions` factory, so nothing observes it.
  /// Recorded as D-05 in `DIVERGENCES.md`.
  Region(this.id, this.type, this.number, List<Position> positions)
    : positions = List<Position>.unmodifiable(positions),
      values = ValueSet();

  /// Java: `getName()` — `type + " " + number`. Reaches the user through hint
  /// text, so the single space is part of the contract.
  String get name => '$type $number';

  /// Java: `"Region " + type + " " + number + ": " + Arrays.asList(positions)`.
  /// Dart's `List.toString` and Java's `AbstractCollection.toString` agree on
  /// `[a, b, c]`, so this is byte-identical given [Position.toString].
  @override
  String toString() => 'Region $type $number: $positions';
}

/// Factories for the per-variant extra regions. Java: `model/ExtraRegions.java`.
///
/// Every cell list below was checked cell-by-cell against the Java. Read the
/// library doc comment before changing any of them: the count and the first
/// cell of each list are what `AndokuPuzzle` uses to decide which of the 14
/// puzzle types it is looking at.
class ExtraRegions {
  ExtraRegions._();

  /// Java returns a shared `private static final ExtraRegion[] NONE = {}`
  /// (`ExtraRegions.java:30`). It is **zero-length**, so it has no elements to
  /// overwrite and a Java array cannot grow — there is no aliasing hazard here,
  /// and an earlier version of this comment invented one. `const []` is simply
  /// the same thing: empty, and shared across calls on both sides.
  static List<ExtraRegion> none() => const <ExtraRegion>[];

  /// X-sudoku: both diagonals, main diagonal first.
  ///
  /// Unlike [hyper], [percent] and [color], Java does **not** restrict this to
  /// 9x9 — it honours `size`. Reproduced.
  static List<ExtraRegion> x(int size) => <ExtraRegion>[
    _diag1(size),
    _diag2(size),
  ];

  /// Declared by Java but never called anywhere in the app. Kept so the class
  /// surface matches the original; see also [percentCount] and [colorCount].
  static int hyperCount(int size) => size == 9 ? 4 : 0;

  /// Hyper sudoku: four 3x3 boxes inset by one cell.
  ///
  /// **The order is not reading order.** Java lists
  /// `square(1,1), square(5,1), square(1,5), square(5,5)` — row offset varies
  /// first, so the *bottom-left* box is extra region 1 and the top-right box is
  /// extra region 2. `AndokuPuzzle.getExtraRegionCode` returns that index and
  /// the theme paints by it, so swapping them to the intuitive order changes
  /// the rendered board and the `extra=` trace field.
  static List<ExtraRegion> hyper(int size) {
    if (size != 9) {
      throw ArgumentError('Hyper restricted to 9x9 for now..');
    }

    return <ExtraRegion>[
      _square(1, 1),
      _square(5, 1),
      _square(1, 5),
      _square(5, 5),
    ];
  }

  /// Dot sudoku: a single region made of the nine box centres.
  ///
  /// First cell is `(1,1)`, which is the *only* thing distinguishing this
  /// variant from [wheel] downstream. Java applies no 9x9 guard here even
  /// though the `1 + (i/3)*3` arithmetic only makes sense for size 9;
  /// reproduced, guard and all — i.e. none.
  static List<ExtraRegion> dot(int size) => <ExtraRegion>[_dotRegion(size)];

  /// Wheel sudoku: a single nine-cell pinwheel.
  ///
  /// First cell is `(4,1)`, row 4. That is what makes
  /// `determinePuzzleType` choose WHEEL over DOT. Java ignores `size`
  /// completely here — the nine positions are hard-coded — and the parameter is
  /// kept only so the call site in `PuzzleDecoder` reads uniformly.
  static List<ExtraRegion> wheel(int size) => <ExtraRegion>[_wheelRegion(size)];

  /// Declared by Java but never called. See [hyperCount].
  static int percentCount(int size) => size == 9 ? 3 : 0;

  /// Percent sudoku: top-left inset box, the anti-diagonal, bottom-right inset
  /// box — three regions, in that order.
  ///
  /// Note it is [_diag2] (the anti-diagonal), not [_diag1]. Using the main
  /// diagonal would still produce three regions and would still type as
  /// PERCENT, so nothing downstream would complain.
  static List<ExtraRegion> percent(int size) {
    if (size != 9) {
      throw ArgumentError('Percent restricted to 9x9 for now..');
    }

    return <ExtraRegion>[_square(1, 1), _diag2(size), _square(5, 5)];
  }

  /// Declared by Java but never called. See [hyperCount].
  static int colorCount(int size) => size == 9 ? 9 : 0;

  /// Colour sudoku: nine regions, each collecting the cells that sit at the
  /// same offset inside their box.
  static List<ExtraRegion> color(int size) {
    if (size != 9) {
      throw ArgumentError('Color restricted to 9x9 for now..');
    }

    return <ExtraRegion>[for (var i = 0; i < 9; i++) _col(i)];
  }

  /// Java: `dot_region`. The centre cell of every box, box-reading order:
  /// (1,1) (1,4) (1,7) (4,1) (4,4) (4,7) (7,1) (7,4) (7,7).
  static ExtraRegion _dotRegion(int size) => ExtraRegion(<Position>[
    for (var i = 0; i < size; i++) Position(1 + (i ~/ 3) * 3, 1 + (i % 3) * 3),
  ]);

  /// Java: `wheel_region`. Transcribed in source order — see [wheel].
  ///
  /// `size` is accepted and ignored, exactly as in Java.
  /// The cells are built non-`const` on purpose. With `const` literals Dart
  /// canonicalizes them, so `wheel(9)` returned the *same* `Position` objects on
  /// every call while the other five factories returned fresh ones — an internal
  /// inconsistency Java does not have, since Java allocates everywhere. `Position`
  /// is immutable so nothing observes it today, but a port that is uniform is one
  /// less thing to reason about.
  static ExtraRegion _wheelRegion(int size) => ExtraRegion(<Position>[
    Position(4, 1),
    Position(2, 2),
    Position(6, 2),
    Position(1, 4),
    Position(4, 4),
    Position(7, 4),
    Position(2, 6),
    Position(6, 6),
    Position(4, 7),
  ]);

  /// Main diagonal, top-left to bottom-right.
  static ExtraRegion _diag1(int size) =>
      ExtraRegion(<Position>[for (var i = 0; i < size; i++) Position(i, i)]);

  /// Anti-diagonal, top-right to bottom-left.
  static ExtraRegion _diag2(int size) => ExtraRegion(<Position>[
    for (var i = 0; i < size; i++) Position(i, size - 1 - i),
  ]);

  /// A 3x3 block anchored at [rowOffset]/[colOffset], row-major.
  static ExtraRegion _square(int rowOffset, int colOffset) =>
      ExtraRegion(<Position>[
        for (var row = rowOffset; row < rowOffset + 3; row++)
          for (var col = colOffset; col < colOffset + 3; col++)
            Position(row, col),
      ]);

  /// Java: `col(int i)` — the colour class for box-offset [i].
  ///
  /// The name is misleading: this is not a column. `i` decomposes into an
  /// offset `(i / 3, i % 3)` *within* a box, and the region collects that same
  /// offset from all nine boxes. The 9 and the step of 3 are hard-coded in
  /// Java regardless of board size; [color] already rejects anything but 9x9.
  static ExtraRegion _col(int i) {
    final row = i ~/ 3;
    final col = i % 3;

    return ExtraRegion(<Position>[
      for (var r = 0; r < 9; r += 3)
        for (var c = 0; c < 9; c += 3) Position(row + r, col + c),
    ]);
  }
}
