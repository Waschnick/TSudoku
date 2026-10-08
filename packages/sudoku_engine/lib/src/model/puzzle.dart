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
// Ported from: app/src/main/java/com/googlecode/andoku/model/Puzzle.java
// Translation rules applied: R-01, R-03, R-04, R-05, R-10, R-13

import 'geometry.dart';
import 'value_set.dart';

/// The geometric *problem*: which cells exist, which regions they belong to, and
/// which values are currently placed.
///
/// This is Andoku's `com.googlecode.andoku.model.Puzzle`, the lower of the two
/// grid representations. It knows nothing about givens versus entered digits,
/// pencil marks, errors or the clock -- `AndokuPuzzle` wraps this and adds all
/// of that. The Dancing Links solver consumes *only* this class, through
/// [regions] and [regionsAt], which is why its region order is load-bearing (see
/// [regions]).
///
/// ### Values are 0-based
///
/// A "value" here is `0 .. size - 1`, not `1 .. 9`. `ValueSet` stores value *v*
/// in bit *v*, so a 9x9 board uses bits 0..8 and the bit-11 pencil-mark sentinel
/// (R-02) can never collide with a digit. The `+ '1'` in [toString] is where the
/// 0-based value becomes a printable digit. Mixing the two conventions up is the
/// single easiest way to produce an off-by-one that the oracle will catch only
/// several files later.
///
/// ### Aliasing is deliberate
///
/// The Java constructor stores the caller's `int[][] areaCodes` and
/// `ExtraRegion[] extraRegions` by reference without copying, and [Puzzle.copy]
/// passes the *same* arrays on to the copy. Nothing in the app mutates them --
/// `standardAreas` hands out a shared table on purpose -- so the port keeps the
/// aliasing rather than inventing defensive copies that would change identity
/// comparisons and allocation counts for no behavioural gain.
final class Puzzle {
  /// Java: `REGION_TYPE_ROW`. These four strings are not decoration: they end up
  /// in `Region.name`, which the DLX matrix uses as its column name, and the geom
  /// trace prints them verbatim.
  static const String typeRow = 'row';

  /// Java: `REGION_TYPE_COLUMN`. Note the name is abbreviated while
  /// [typeRow]/[typeArea]/[typeExtra] are not -- an upstream inconsistency that is
  /// observable in trace output, so it is preserved exactly.
  static const String typeCol = 'col';

  /// Java: `REGION_TYPE_AREA`. An "area" is a box on a standard board and an
  /// irregular blob on a squiggly one; the model does not distinguish.
  static const String typeArea = 'area';

  /// Java: `REGION_TYPE_EXTRA`. X diagonals, hyper boxes, percent shapes and so on.
  static const String typeExtra = 'extra';

  /// Java: `UNDEFINED`. The empty-cell marker in [getValue].
  ///
  /// It is `-1` and not `0`, because `0` is the first legal value (see the
  /// 0-based note on [Puzzle]).
  static const int undefined = -1;

  /// Row-major area code per cell, `0 .. size - 1`. Aliased, never copied.
  final List<List<int>> areaCodes;

  /// The variant's additional regions, in the order `ExtraRegions` produced them.
  /// That order fixes the `extra 0`, `extra 1`, ... numbering in [regions].
  final List<ExtraRegion> extraRegions;

  /// Board edge length. Always 9 in the shipped corpus; the model allows 3..16.
  final int size;

  final List<Region> _regions;
  final List<List<List<Region>>> _regionsAt;
  final List<List<int>> _values;
  final List<List<ValueSet>> _eliminated;

  /// Number of cells currently holding a value.
  ///
  /// Java keeps this as a private counter maintained by `set`/`clear` rather than
  /// recounting, and `isSolved` compares it against `size * size`.
  ///
  /// Read-only, which Java's `private int valuesCount` + `getValuesCount()` pair
  /// also is. An earlier version exposed it as a public mutable field, which let
  /// `puzzle.valuesCount = 81` make [isSolved] lie with no other state change --
  /// a state Java forbids by construction. (`getValuesCount()` has zero call
  /// sites in the whole Java tree; the counter is read only through `isSolved`.)
  int get valuesCount => _valuesCount;
  int _valuesCount = 0;

  /// Builds a puzzle from an area map and the variant's extra regions, validating
  /// both.
  ///
  /// Java: the public `Puzzle(int[][], ExtraRegion[])` constructor, which delegates
  /// to the private one with `check = true`.
  factory Puzzle(List<List<int>> areaCodes, List<ExtraRegion> extraRegions) {
    _checkParameters(areaCodes, extraRegions);
    return _unchecked(areaCodes, extraRegions);
  }

  /// Copies [other]'s geometry *and replays* its contents.
  ///
  /// Java: the `Puzzle(Puzzle other)` copy constructor. Two details are easy to
  /// get wrong and both are reproduced here:
  ///
  /// 1. It skips validation (`check = false`) -- the source puzzle was already
  ///    validated, so re-running it would be pure cost.
  /// 2. It does **not** copy the derived state. Fresh [Region] objects are built
  ///    with empty `values` sets, and every placed value is re-applied through
  ///    [set], which rebuilds the per-region value sets and recounts
  ///    [valuesCount] from zero. So a copy is self-consistent even if the source
  ///    somehow was not.
  ///
  /// The eliminated sets *are* copied, by [eliminateValues] -- i.e. unioned into
  /// a fresh [ValueSet], not shared. The loop calls [eliminateValues]
  /// unconditionally, including for filled cells, which keeps eliminations that
  /// are invisible while the cell is filled but reappear if it is cleared.
  factory Puzzle.copy(Puzzle other) {
    final Puzzle copy = _unchecked(other.areaCodes, other.extraRegions);

    for (int row = 0; row < copy.size; row++) {
      for (int col = 0; col < copy.size; col++) {
        final int value = other._values[row][col];
        if (value != undefined) {
          copy.set(row, col, value);
        }

        copy.eliminateValues(row, col, other._eliminated[row][col]);
      }
    }

    return copy;
  }

  /// Java: the private `Puzzle(int[][], ExtraRegion[], boolean)` with
  /// `check == false`.
  ///
  /// Dart cannot run a method on `this` before the final fields are initialised,
  /// so region construction is lifted into static helpers and threaded through
  /// the private constructor. The *order* of the original constructor body is
  /// preserved: regions, then the per-cell region index, then the empty value and
  /// eliminated grids.
  static Puzzle _unchecked(
    List<List<int>> areaCodes,
    List<ExtraRegion> extraRegions,
  ) {
    final List<Region> regions = _createRegions(areaCodes, extraRegions);
    return Puzzle._(
      areaCodes,
      extraRegions,
      regions,
      _initRegionsAt(areaCodes.length, regions),
    );
  }

  Puzzle._(this.areaCodes, this.extraRegions, this._regions, this._regionsAt)
    : size = areaCodes.length,
      _values = List<List<int>>.generate(
        areaCodes.length,
        (_) => List<int>.filled(areaCodes.length, undefined),
      ),
      _eliminated = List<List<ValueSet>>.generate(
        areaCodes.length,
        (_) => List<ValueSet>.generate(areaCodes.length, (_) => ValueSet()),
      );

  /// All regions of the board, in **Java construction order**: every row, then
  /// every column, then every area, then every extra region, with `id` assigned
  /// sequentially from 0 across the whole sequence.
  ///
  /// This order is not an implementation detail. `DlxPuzzleSolver.createMatrix`
  /// derives a matrix column from `regionOffset + region.id * size + v`, so the
  /// ids fix the DLX column order, which fixes which column the solver's
  /// min-column heuristic selects, which fixes the search path and the node
  /// count. Reorder this list and the dlx trace diverges even though the solution
  /// is unchanged.
  ///
  /// The returned list is the live internal list, as in Java where `getRegions()`
  /// returns an array. It is **unmodifiable**: Java hands back
  /// `regions.toArray(new Region[...])`, whose length and ordering a caller cannot
  /// change in place, and an earlier version of this returned a growable list. The
  /// natural Dart spelling of `AndokuActivity.java:1039-1045`'s "collect the area
  /// regions" loop -- `puzzle.regions..removeWhere((r) => r.type != typeArea)` --
  /// would otherwise destroy the puzzle's region list permanently, changing the
  /// `RGN`/`RG1` geom rows and the whole DLX column set.
  ///
  /// The view is built once in the constructor, so this getter allocates nothing.
  List<Region> get regions => _regions;

  /// The regions containing cell ([row], [col]), in ascending `Region.id` order.
  ///
  /// Java builds this from a `HashMap<Position, List<Region>>` and the question
  /// "does the hash map's iteration order leak into the result?" has a reassuring
  /// answer: **no**. The map is only ever *looked up* per cell, never iterated,
  /// and each cell's list is appended to while walking `regions` in id order. So
  /// the per-cell order is region construction order -- row, column, area, then
  /// extras -- on both sides, independent of hashing. See [_initRegionsAt].
  ///
  /// For a standard 9x9 board this has exactly 3 entries; X-sudoku cells on a
  /// diagonal have 4, and the centre cell of a hyper/percent board can have more.
  ///
  /// Returns the live internal list, matching Java's `getRegionsAt` -- and like
  /// [regions] it is unmodifiable, because Java's is an array. This is called once
  /// per cell during DLX matrix construction (81 times per puzzle, ~3.6M times over
  /// a T2 run), so the view is built once at construction rather than wrapped here.
  List<Region> regionsAt(int row, int col) => _regionsAt[row][col];

  /// Java: `getAreaCode`.
  int getAreaCode(int row, int col) => areaCodes[row][col];

  /// Java: `getValue`. Returns [undefined] for an empty cell.
  int getValue(int row, int col) => _values[row][col];

  /// The live eliminated-candidate set of cell ([row], [col]).
  ///
  /// Java reads the private `eliminated[row][col]` field directly (from the copy
  /// constructor and from `getPossibleValues`). This accessor returns the same
  /// mutable [ValueSet] instance rather than a snapshot, so that
  /// [eliminateValue]/[eliminateValues] and any caller that pokes at the set
  /// observe each other exactly as the Java code does.
  ValueSet eliminated(int row, int col) => _eliminated[row][col];

  /// Places [value] in an **empty** cell.
  ///
  /// Java: `set(int, int, int)`, which opens with `assert values[row][col] ==
  /// UNDEFINED`. Reproduced as a Dart `assert`, which is the closest match: Java
  /// assertions need `-ea` and Android never enables it, so in the shipped app
  /// the guard is *inert* and setting an occupied cell silently double-counts
  /// [valuesCount] and corrupts the region value sets. Dart asserts are likewise
  /// stripped from release AOT builds but are live under `dart run` and
  /// `dart test`. The asymmetry is intentional: no reachable path in the app
  /// violates the precondition ([force] clears first), so if the differential
  /// harness ever trips this assert it has found a real divergence that should be
  /// investigated, not silenced.
  ///
  /// Note the ordering: the region sets are updated *before* the cell, and
  /// [valuesCount] after. Nothing observes the intermediate state, but keeping
  /// the order makes the two sources line up line for line.
  void set(int row, int col, int value) {
    assert(
      _values[row][col] == undefined,
      'Puzzle.set on an occupied cell ($row, $col): Java asserts this '
      'precondition but runs with assertions disabled on Android.',
    );

    for (final Region r in _regionsAt[row][col]) {
      r.values.add(value);
    }

    _values[row][col] = value;

    _valuesCount++;
  }

  /// Places [value] in ([row], [col]), clearing whatever stands in its way.
  ///
  /// Java: `force(int, int, int)`. It clears the target cell if occupied, then
  /// walks every region the cell belongs to and clears any cell in those regions
  /// already holding [value], then calls [set]. The result therefore cannot
  /// violate [set]'s precondition and cannot leave a duplicate in a region.
  ///
  /// **No call site exists in the shipped app** (`grep -rn '\.force('` over the
  /// Java tree finds none), so this method is translated for completeness and is
  /// *not* covered by the differential oracle. Verified only by this port's unit
  /// tests.
  void force(int row, int col, int value) {
    if (_values[row][col] != undefined) {
      clear(row, col);
    }

    for (final Region region in _regionsAt[row][col]) {
      for (final Position position in region.positions) {
        if (_values[position.row][position.col] == value) {
          clear(position.row, position.col);
        }
      }
    }

    set(row, col, value);
  }

  /// Empties a **filled** cell.
  ///
  /// Java: `clear(int, int)`, with `assert value != UNDEFINED`. See [set] for why
  /// the assertion is translated rather than turned into a thrown error.
  ///
  /// Removing the value from the region sets is unconditional and unguarded: if
  /// the same value had somehow been placed twice in one region, clearing one
  /// cell would wrongly drop the value from the region. That cannot happen
  /// through the public API, and the Java has no guard either.
  void clear(int row, int col) {
    final int value = _values[row][col];
    assert(
      value != undefined,
      'Puzzle.clear on an empty cell ($row, $col): Java asserts this '
      'precondition but runs with assertions disabled on Android.',
    );

    for (final Region r in _regionsAt[row][col]) {
      r.values.remove(value);
    }

    _values[row][col] = undefined;

    _valuesCount--;
  }

  /// Java: `eliminateValue`. Marks [value] as ruled out for this cell.
  ///
  /// Eliminations are purely additive here -- there is no `restoreValue`. An
  /// earlier version of this comment explained that by appealing to the undo path
  /// rebuilding state through the command history; nothing in the Java supports
  /// that, because no undo path reaches these eliminations at all. The real
  /// situation: `Puzzle.eliminateValue`/`eliminateValues` have exactly one caller
  /// in the entire Java tree, `Puzzle.java:60` inside the copy constructor, so
  /// [eliminated] is an all-empty 81-cell grid for every puzzle the app builds.
  /// The same-named methods on `AndokuPuzzle` (`AndokuPuzzle.java:1112, 1117,
  /// 1131`) and in `commands/EliminateValuesCommand.java:46, 58` are a *different*
  /// class operating on a *different* field.
  void eliminateValue(int row, int col, int value) {
    _eliminated[row][col].add(value);
  }

  /// Java: `eliminateValues`. Unions [values] into this cell's eliminated set.
  void eliminateValues(int row, int col, ValueSet values) {
    _eliminated[row][col].addAll(values);
  }

  /// The values still legal for cell ([row], [col]).
  ///
  /// Java: `getPossibleValues`. A filled cell returns an **empty** set, not the
  /// value it holds. Otherwise it starts from `ValueSet.all(size)` and subtracts
  /// every region's placed values plus the cell's eliminated set.
  ///
  /// The only Java callers are in `solver/BrutePuzzleSolver`, which the port's
  /// do-not-port list marks as unreachable, so this is translated for
  /// completeness and is not exercised by the oracle.
  ValueSet getPossibleValues(int row, int col) {
    if (_values[row][col] != undefined) {
      return ValueSet();
    }

    final ValueSet values = ValueSet.all(size);

    for (final Region r in _regionsAt[row][col]) {
      values.removeAll(r.values);
    }

    values.removeAll(_eliminated[row][col]);

    return values;
  }

  /// Java: `isSolved`. True once every cell holds a value.
  ///
  /// It is a pure cell count -- it does **not** check that the values are
  /// consistent. Validity is `AndokuPuzzle`'s job, which is why a board full of
  /// wrong digits still reports solved here.
  bool get isSolved => _valuesCount == size * size;

  /// Java: `toString`. One row of `.`/digits per `size` characters, rows
  /// separated by a single space and no trailing separator.
  ///
  /// The character offset carries an upstream quirk worth keeping: values are
  /// 0-based, so `size <= 9` renders value 0 as `'1'`; `size == 10` uses `'0'`
  /// (giving `0..9`) and anything larger uses `'A'`, which for a 0-based value
  /// would print `'A'` for value 0 and is almost certainly not what was intended.
  /// Only the `size <= 9` branch is reachable with the shipped corpus.
  @override
  String toString() {
    final int offset = size <= 9
        ? '1'.codeUnitAt(0)
        : (size == 10 ? '0'.codeUnitAt(0) : 'A'.codeUnitAt(0));

    final StringBuffer sb = StringBuffer();

    for (int row = 0; row < size; row++) {
      for (int col = 0; col < size; col++) {
        if (_values[row][col] == undefined) {
          sb.write('.');
        } else {
          sb.writeCharCode(_values[row][col] + offset);
        }
      }
      if (row < size - 1) {
        sb.write(' ');
      }
    }

    return sb.toString();
  }

  /// Java: `createRegions`. Rows, then columns, then areas, then extra regions,
  /// with one running `id` counter -- see [regions] for why the order matters.
  ///
  /// Each area region is collected by scanning the whole board row-major and
  /// keeping cells whose area code matches, so an area's positions are in
  /// row-major order even for a squiggly blob. That is O(size^3) and upstream did
  /// not care; neither do we, since it runs once per puzzle.
  ///
  /// Extra regions are passed `extraRegion.positions` directly. Java does the
  /// same via `Region`'s `Position[]` overload, which stores the array without
  /// copying, so a [Region] of type [typeExtra] shares its position list with the
  /// [ExtraRegion] it came from. Row/column/area regions get freshly built lists
  /// on both sides.
  static List<Region> _createRegions(
    List<List<int>> areaCodes,
    List<ExtraRegion> extraRegions,
  ) {
    final int size = areaCodes.length;
    final List<Region> regions = <Region>[];

    int id = 0;

    for (int row = 0; row < size; row++) {
      final List<Position> positions = <Position>[];
      for (int col = 0; col < size; col++) {
        positions.add(Position(row, col));
      }

      regions.add(Region(id++, typeRow, row, positions));
    }

    for (int col = 0; col < size; col++) {
      final List<Position> positions = <Position>[];
      for (int row = 0; row < size; row++) {
        positions.add(Position(row, col));
      }

      regions.add(Region(id++, typeCol, col, positions));
    }

    for (int areaCode = 0; areaCode < size; areaCode++) {
      final List<Position> positions = <Position>[];
      for (int row = 0; row < size; row++) {
        for (int col = 0; col < size; col++) {
          if (areaCodes[row][col] == areaCode) {
            positions.add(Position(row, col));
          }
        }
      }

      regions.add(Region(id++, typeArea, areaCode, positions));
    }

    for (
      int extraNumber = 0;
      extraNumber < extraRegions.length;
      extraNumber++
    ) {
      final ExtraRegion extraRegion = extraRegions[extraNumber];
      regions.add(Region(id++, typeExtra, extraNumber, extraRegion.positions));
    }

    // Unmodifiable, mirroring Java's regions.toArray(new Region[...]).
    return List<Region>.unmodifiable(regions);
  }

  /// Java: `initRegionsAt`. Inverts [regions] into a per-cell index.
  ///
  /// R-04/R-05: the Java uses a `HashMap<Position, List<Region>>`, keyed by a
  /// `Position` with a real `hashCode`/`equals` (`row * 9901 + col`), so it is a
  /// value-keyed map and translates to a plain Dart `Map` -- which is
  /// insertion-ordered, while `HashMap` is not. That difference is harmless
  /// *here* and it is worth being precise about why: the map is written while
  /// iterating [regions] in id order and then read back one cell at a time, so
  /// what reaches the result is the per-cell append order, never the map's own
  /// order. Nothing observable depends on the hashing.
  ///
  /// The lookup is unguarded in Java (`regionsList.toArray(...)` would throw
  /// `NullPointerException` for a cell in no region at all); the `!` here is the
  /// same assumption, and it holds because the row regions alone cover every
  /// cell.
  static List<List<List<Region>>> _initRegionsAt(
    int size,
    List<Region> regions,
  ) {
    final Map<Position, List<Region>> regionsAtMap = <Position, List<Region>>{};
    for (final Region region in regions) {
      for (final Position position in region.positions) {
        (regionsAtMap[position] ??= <Region>[]).add(region);
      }
    }

    // Unmodifiable per cell, mirroring Java's Region[] -- see regionsAt.
    return List<List<List<Region>>>.generate(
      size,
      (int row) => List<List<Region>>.generate(
        size,
        (int col) =>
            List<Region>.unmodifiable(regionsAtMap[Position(row, col)]!),
      ),
    );
  }

  /// Java: `checkParameters`. Rejects a malformed board before any of it is used.
  ///
  /// Order of the checks is preserved because the message of the *first* failure
  /// is what a caller sees: size range, then per-row width and area-code range
  /// while counting, then "each area code appears exactly `size` times", then the
  /// extra regions (right length, no duplicate positions, all inside the grid).
  ///
  /// R-13: Java's `IllegalArgumentException` becomes [ArgumentError] with the
  /// same message text; there are no checked exceptions to carry over.
  ///
  /// Note what is *not* checked: areas need not be contiguous, and extra regions
  /// may overlap areas freely. Both are true of the shipped variants.
  static void _checkParameters(
    List<List<int>> areaCodes,
    List<ExtraRegion> extraRegions,
  ) {
    final int size = areaCodes.length;

    if (size < 3 || size > ValueSet.maxSize) {
      throw ArgumentError('Invalid size: $size');
    }

    final List<int> counters = List<int>.filled(size, 0);
    for (final List<int> areaCodesRow in areaCodes) {
      if (areaCodesRow.length != size) {
        throw ArgumentError('Invalid number of area code columns');
      }

      for (final int areaCode in areaCodesRow) {
        if (areaCode < 0 || areaCode >= size) {
          throw ArgumentError('Invalid area code: $areaCode');
        }

        counters[areaCode]++;
      }
    }

    for (int i = 0; i < counters.length; i++) {
      if (counters[i] != size) {
        throw ArgumentError("Invalid number of $i's: ${counters[i]}");
      }
    }

    for (final ExtraRegion extraRegion in extraRegions) {
      if (extraRegion.positions.length != size) {
        throw ArgumentError(
          'Invalid extra region size: ${extraRegion.positions.length}',
        );
      }

      // Java: `new HashSet<Position>(Arrays.asList(...)).size() != size`. R-03 --
      // this only detects duplicates because `Position` overrides
      // `hashCode`/`equals`; the Dart `toSet()` relies on the same `==`/`hashCode`
      // pair on [Position].
      if (extraRegion.positions.toSet().length != size) {
        throw ArgumentError(
          'Invalid number of unique positions in extra region',
        );
      }

      for (final Position position in extraRegion.positions) {
        if (position.row < 0 ||
            position.col < 0 ||
            position.row >= size ||
            position.col >= size) {
          throw ArgumentError('Extra region position outside grid');
        }
      }
    }
  }
}
