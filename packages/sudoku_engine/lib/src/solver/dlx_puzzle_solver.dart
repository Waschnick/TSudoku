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
// Ported from: app/src/main/java/com/googlecode/andoku/solver/DlxPuzzleSolver.java
// Translation rules applied: R-03, R-06, R-09, R-10, R-11, R-13

import '../dlx/dlx.dart';
import '../model/geometry.dart';
import '../model/puzzle.dart';
import '../util/java_random.dart';
import 'puzzle_solver.dart';

/// Reduces a sudoku to an exact-cover problem and hands it to the Dancing Links
/// search.
///
/// Java: `com.googlecode.andoku.solver.DlxPuzzleSolver`. This is the solver on
/// the *gameplay* path -- `AndokuPuzzle.computeSolution` uses it to obtain the
/// ground-truth solution and to decide uniqueness. It is variant-agnostic:
/// everything it knows about the 14 puzzle types arrives through
/// [Puzzle.regions] and [Puzzle.regionsAt], so X diagonals, hyper boxes and
/// squiggly areas all solve through this one code path. The Sudoku Explainer
/// engine (`com.diuf.sudoku`) is a different solver for a different job and is
/// never involved here.
///
/// ### The matrix layout is the search order
///
/// The exact-cover matrix is built by [_createMatrix] in a fixed column order:
///
/// 1. `size * size` *cell* columns, named `<row>x<col>`, in row-major order --
///    "cell (r, c) holds exactly one value".
/// 2. then one column per (region, value) pair, named `<region.name> value <v>`,
///    walking [Puzzle.regions] in region-id order and values `0 .. size - 1`
///    innermost -- "region R holds value v exactly once".
///
/// A row of the matrix is one (row, col, value) triple and sets exactly two
/// kinds of bit: `row * size + col`, and `regionOffset + region.id * size + v`
/// for every region containing the cell.
///
/// None of that is free to change. `Solver` picks the column with the fewest
/// remaining rows and `chooseColumn`'s strict `<` keeps the *first* minimum, so
/// ties are broken by column position. Column position comes from this layout
/// and from the order of [Puzzle.regions]. Reorder either and the search visits
/// a different set of nodes in a different order: the solution is still correct,
/// but the `nodes=` field of the dlx trace changes for essentially every puzzle
/// and the differential gate fails. The same applies to `regionOffset`, which
/// Java captures as `m.getColumnCount()` *after* the cell columns and *before*
/// the region columns -- not as a constant.
///
/// ### The randomised paths are dead in the shipped app
///
/// The only Java call site, `AndokuPuzzle.java:350`, is `new DlxPuzzleSolver()`
/// -- no random source. So [_Strategy.compare]'s coin-flip branch and
/// [_Strategy.sort]'s shuffle never execute in the app and are *not* covered by
/// the differential oracle. They are translated faithfully anyway, using
/// [JavaRandom] rather than `dart:math`'s `Random` (R-06), so that if a future
/// puzzle *generator* needs them they already reproduce Java's sequence.
class DlxPuzzleSolver implements PuzzleSolver {
  /// Java: `protected final Random random`. Null means "deterministic", which is
  /// the only configuration the app and the oracle ever use.
  ///
  /// R-06: this is [JavaRandom], a transcription of `java.util.Random`'s LCG.
  /// `dart:math`'s `Random` is a different algorithm and a seeded sequence would
  /// not match the JVM, which would make any randomised trace uncomparable.
  final JavaRandom? random;

  /// Java: `private final long maxUpdates`.
  ///
  /// A budget on the number of `select` callbacks before the search gives up.
  /// **Zero means unlimited**, not "stop immediately" -- see [_Strategy.select]
  /// for the short-circuit that makes that work and for why zero also disables
  /// [numberOfUpdates].
  ///
  /// R-10: Java's type is `long`. Dart's `int` is 64-bit on every target this
  /// port supports, so `maxUpdates: 9223372036854775807` is the exact equivalent
  /// of `Long.MAX_VALUE` -- which is what the trace driver passes to turn
  /// [numberOfUpdates] into a usable node counter.
  final int _maxUpdates;

  /// Java: `protected int size`. Set by [solve]; 0 before the first call.
  int size = 0;

  /// The solver's private working board. Java: `protected Puzzle puzzle`.
  ///
  /// [solve] assigns `Puzzle.copy(puzzle)`, so the caller's puzzle is never
  /// touched: the search writes values into this copy as it descends and clears
  /// them as it backtracks, and `solutionFound` reports *this* instance. A
  /// reporter that wants to keep a solution must copy it -- which is exactly
  /// what `UniqueSolutionReporter` and `SingleSolutionReporter` do.
  ///
  /// `late` stands in for Java's null-before-first-use: calling
  /// [solveCurrentPuzzle] without [solve] throws `LateInitializationError` where
  /// Java would throw `NullPointerException`.
  late Puzzle puzzle;

  late PuzzleReporter _reporter;

  int _updates = 0;

  /// Java's three constructors collapse into one: `DlxPuzzleSolver()`,
  /// `DlxPuzzleSolver(Random)` and `DlxPuzzleSolver(Random, long)` differ only in
  /// which defaults they fill in, and both defaults are expressible as named
  /// parameters. `DlxPuzzleSolver()` is the app's configuration.
  ///
  /// `prefer_initializing_formals` is suppressed rather than obeyed: the field
  /// mirrors Java's *private* `maxUpdates`, and Dart forbids a named parameter
  /// whose name starts with an underscore, so `this._maxUpdates` is not a legal
  /// alternative. The choice is between this line and widening the field to
  /// public, which would export state the original keeps private.
  // ignore: prefer_initializing_formals
  DlxPuzzleSolver({this.random, int maxUpdates = 0}) : _maxUpdates = maxUpdates;

  /// Java: `getNumberOfUpdates()`. The number of rows the search selected.
  ///
  /// **This returns 0 unless `maxUpdates` is non-zero.** Not a bug to fix: see
  /// [_Strategy.select]. The JVM oracle works around it by subclassing with
  /// `maxUpdates = Long.MAX_VALUE`; the Dart equivalent is
  /// `DlxPuzzleSolver(maxUpdates: 9223372036854775807)`.
  int get numberOfUpdates => _updates;

  /// Java: `solve(Puzzle, PuzzleReporter)`.
  ///
  /// Note what this method does *not* do: it does not reset [_updates]. Java
  /// resets it inside the protected no-arg `solve()`, and the split is preserved
  /// in [solveCurrentPuzzle] because the oracle's counting subclass drives that
  /// method's contract. Moving the reset up here would be harmless today and
  /// would quietly change the shape the oracle relies on.
  @override
  void solve(Puzzle puzzle, PuzzleReporter reporter) {
    size = puzzle.size;
    this.puzzle = Puzzle.copy(puzzle);
    _reporter = reporter;

    solveCurrentPuzzle();
  }

  /// Java: `protected void solve()`.
  ///
  /// Renamed because Dart has no overloading and [solve] already owns the name.
  /// Dart also has no `protected`, and this package has no `package:meta`
  /// dependency to borrow `@protected` from, so the visibility is documented
  /// rather than enforced: this method expects [size], [puzzle] and the reporter
  /// to have been set by [solve] and is not part of the public contract.
  ///
  /// Build the matrix, remove the rows contradicted by the givens, then search.
  /// One [_Strategy] instance plays all three roles the Java inner class plays.
  void solveCurrentPuzzle() {
    final Matrix<_Rcv> m = _createMatrix();
    _eliminateGivenClues(m);

    _updates = 0;
    final _Strategy strategy = _Strategy(this);
    // Java: `new Solver(m, strategy, strategy, strategy)` -- one object as
    // DlxListener, Comparator<Header> and RowSorter. Dart's `Comparator<Header>`
    // is a function type, so the comparator role is a tear-off of
    // [_Strategy.compare]; it still dispatches on this same instance, so the
    // identity the Java relies on (all three roles share `random`) is kept.
    //
    // Passing a non-null comparator also means `Solver`'s fallback
    // SIZE_COLUMN_COMPARATOR is never installed from here -- although with
    // `random == null` the two are behaviourally identical.
    Solver(m, strategy, strategy.compare, strategy).search();
  }

  /// Java: `createMatrix()`. See the class doc for why the column order is
  /// load-bearing.
  Matrix<_Rcv> _createMatrix() {
    final Matrix<_Rcv> m = Matrix<_Rcv>();

    for (int row = 0; row < size; row++) {
      for (int col = 0; col < size; col++) {
        // Java: `row + "x" + col`, e.g. "0x0". The name is never parsed; it
        // exists for debugging and must simply not collide.
        final String name = '${row}x$col';
        m.addColumn(Header(name));
      }
    }

    // Java: `final int regionOffset = m.getColumnCount()`. Read *here*, between
    // the two groups of columns -- i.e. it is `size * size`, but derived rather
    // than assumed.
    final int regionOffset = m.columnCount;
    for (final Region region in puzzle.regions) {
      for (int v = 0; v < size; v++) {
        // Java: `region.getName() + " value " + v`, e.g. "row 0 value 0".
        // Values are 0-based here, as everywhere in `Puzzle`.
        final String name = '${region.name} value $v';
        // The region is carried as the column's payload. Nothing in this file
        // reads it back; it is kept because `Header`'s payload is part of the
        // matrix the Java builds and a future consumer may want it.
        m.addColumn(Header(name, region));
      }
    }

    for (int row = 0; row < size; row++) {
      for (int col = 0; col < size; col++) {
        final List<Region> regions = puzzle.regionsAt(row, col);

        for (int v = 0; v < size; v++) {
          // Java allocates a fresh `boolean[m.getColumnCount()]` per row and
          // relies on Java's default-false initialisation. `columnCount` is
          // re-read every iteration; it is constant by now because `addRow` does
          // not add columns, but the re-read is kept so the loop reads the same
          // on both sides.
          final List<bool> values = List<bool>.filled(m.columnCount, false);

          values[row * size + col] = true;

          for (final Region region in regions) {
            values[regionOffset + region.id * size + v] = true;
          }

          m.addRow(_Rcv(row, col, v), values);
        }
      }
    }

    return m;
  }

  /// Java: `eliminateGivenClues(Matrix)`.
  ///
  /// The givens are already *placed* on the working board -- [Puzzle.copy]
  /// replays them -- so what is left is to delete their matrix rows, which covers
  /// the cell column and every (region, value) column the given satisfies. The
  /// search then simply never visits those cells.
  ///
  /// Two faithfully-unguarded details:
  ///
  /// * `m.getRow(...)` is dereferenced without a null check (Java would throw
  ///   `NullPointerException`). It cannot be null: [_createMatrix] adds a row for
  ///   every (row, col, value) triple in range, and `getValue` only ever returns
  ///   a value in range or `Puzzle.undefined`. The `!` here is that same
  ///   assumption, and it also makes a broken [_Rcv] equality loud instead of
  ///   silent -- see [_Rcv].
  /// * An *invalid* puzzle, with the same given twice in one region, makes the
  ///   second `eliminateRow` cover an already-covered column and corrupts the
  ///   matrix. Java has no guard and neither does this; no shipped `.adk` record
  ///   is invalid, and adding a check would change behaviour the oracle has
  ///   already pinned.
  void _eliminateGivenClues(Matrix<_Rcv> m) {
    for (int row = 0; row < size; row++) {
      for (int col = 0; col < size; col++) {
        final int value = puzzle.getValue(row, col);
        if (value != Puzzle.undefined) {
          final Data data = m.getRow(_Rcv(row, col, value))!;
          m.eliminateRow(data);
        }
      }
    }
  }
}

/// The search callbacks, column heuristic and row order, in one object.
///
/// Java: the non-static inner class `DlxPuzzleSolver.Strategy`, which implements
/// `DlxListener`, `Comparator<Header>` and `RowSorter` simultaneously and reaches
/// the enclosing solver's `puzzle`, `random`, `maxUpdates`, `updates` and
/// `reporter` through `DlxPuzzleSolver.this`.
///
/// R-11: Dart has no inner classes, so the enclosing instance is an explicit
/// field. Keeping it in the same library is what lets it touch the solver's
/// private `_maxUpdates`, `_updates` and `_reporter` -- Dart privacy is
/// per-library, so this is exactly Java's inner-class access and not a widening
/// of the solver's API.
class _Strategy implements DlxListener, RowSorter {
  final DlxPuzzleSolver _solver;

  _Strategy(this._solver);

  /// Java: `select(Data)`. Place the row's value, then say whether to continue.
  ///
  /// **The `||` short-circuit is the whole point of this method.** With
  /// `maxUpdates == 0` -- the app's and the oracle's configuration -- the left
  /// operand is already true, so `++updates` is *never evaluated* and
  /// `getNumberOfUpdates()` stays 0 forever. An eager `_updates++` before the
  /// return would read identically to a casual reviewer and would change the
  /// `nodes=` field of the dlx trace for every puzzle, because the oracle's
  /// counting subclass exists precisely to make this counter work (it passes
  /// `Long.MAX_VALUE`, which leaves the boolean result unchanged while enabling
  /// the increment).
  ///
  /// When the budget *is* finite, returning false aborts the search from here.
  /// `Solver.search0` breaks out of its row loop **without** calling [deselect]
  /// for this row, so the aborted board keeps one extra value. Nothing reads it
  /// afterwards and Java behaves the same way; it is only a reason not to call
  /// `solveCurrentPuzzle` twice on one instance.
  @override
  bool select(Data row) {
    final _Rcv r = row.payload as _Rcv;
    _solver.puzzle.set(r.row, r.col, r.value);
    return _solver._maxUpdates == 0 || ++_solver._updates < _solver._maxUpdates;
  }

  /// Java: `deselect(Data)`. Backtracking: take the value back out.
  ///
  /// Clears by *cell*, not by value, matching `Puzzle.clear`'s signature. The
  /// cell is guaranteed filled because [select] filled it and the search unwinds
  /// in reverse order.
  @override
  void deselect(Data row) {
    final _Rcv r = row.payload as _Rcv;
    _solver.puzzle.clear(r.row, r.col);
  }

  /// Java: `solutionFound()`. Hand the *live* working board to the reporter and
  /// let it decide whether to keep searching.
  ///
  /// The board is not copied here, which is why every reporter that stores a
  /// solution copies it itself. Returning true continues the search -- that is
  /// how `UniqueSolutionReporter` detects a second solution.
  @override
  bool solutionFound() {
    return _solver._reporter.report(_solver.puzzle);
  }

  /// Java: `compare(Header, Header)` -- the column-choice heuristic.
  ///
  /// Plain size difference, so `Solver.chooseColumn` picks the column with the
  /// fewest remaining rows (Knuth's S heuristic). Note it returns the raw
  /// difference rather than a normalised -1/0/1; `chooseColumn` only tests
  /// `< 0`, so this is equivalent, and R-10 does not bite because column sizes
  /// are small positive ints that cannot overflow.
  ///
  /// The tie-break is where randomisation would enter: *only* when the sizes are
  /// equal **and** a random source was supplied does it coin-flip. Dead in the
  /// shipped app and uncovered by the oracle -- see the class doc of
  /// [DlxPuzzleSolver].
  ///
  /// R-09 does not apply: this comparator feeds a linear minimum scan, not a
  /// sort, so a 0 result keeps the earlier column deterministically.
  int compare(Header c1, Header c2) {
    final int diff = c1.size - c2.size;
    if (diff != 0 || _solver.random == null) {
      return diff;
    }

    return _solver.random!.nextBoolean() ? -1 : 1;
  }

  /// Java: `sort(Data[] rows)` -- the order in which a column's rows are tried.
  ///
  /// With no random source this returns immediately and the rows keep the order
  /// `Solver.getRows` collected them in, walking the column top-to-bottom. That
  /// is the only path the app and the oracle take, and it is what makes the
  /// search deterministic.
  ///
  /// The shuffle is a Fisher-Yates from the top: `i` runs from `rows.length` down
  /// to 2 and swaps `rows[i - 1]` with `rows[random.nextInt(i)]`. Transcribed
  /// index-for-index, including the self-swap when `nextInt` returns `i - 1`,
  /// because the number of [JavaRandom] draws is itself part of the sequence --
  /// skipping a "pointless" swap would desynchronise every later draw.
  ///
  /// R-09/R-13: Java mutates a `Data[]` in place and `Solver` uses the mutated
  /// array; the Dart contract passes a `List<Data>` and this mutates it in place
  /// for the same reason. It is deliberately *not* a `List.sort` call -- there is
  /// no ordering here to be stable about.
  @override
  void sort(List<Data> rows) {
    final JavaRandom? random = _solver.random;
    if (random == null) {
      return;
    }

    for (int i = rows.length; i > 1; i--) {
      final int x = i - 1;
      final int y = random.nextInt(i);

      final Data tmp = rows[x];
      rows[x] = rows[y];
      rows[y] = tmp;
    }
  }
}

/// A (row, column, value) triple: the payload of every matrix row.
///
/// Java: `private static final class DlxPuzzleSolver.RCV`.
///
/// R-03: this is a value key. `Matrix.addRow` stores it in a `Map` and
/// `eliminateGivenClues` looks a freshly constructed one back up, so `==` and
/// `hashCode` are load-bearing: with identity semantics the lookup returns null,
/// the givens are never eliminated, and the solver happily reports a solution
/// that contradicts the clues.
///
/// **Chosen as a class, not a Dart record**, for two reasons. The weaker one is
/// that `toString` is observable in debugging output and reads `value@rowxcol`,
/// which a record cannot produce. The real one is [hashCode]: Java's formula
/// `9901 * row + 1009 * col + value` is reproduced exactly, so the port's hash
/// distribution matches the original's. Nothing observable depends on it today
/// -- `Matrix.rowByPayload` is only ever looked up, never iterated, so its
/// bucket order cannot leak into a trace -- but a record's hash is
/// implementation-defined and would make that reassurance unverifiable if the
/// map ever *is* iterated.
class _Rcv {
  final int row;
  final int col;
  final int value;

  const _Rcv(this.row, this.col, this.value);

  /// Java: `9901 * row + 1009 * col + value`. Two primes, chosen so a 9x9 board's
  /// 729 triples collide rarely; R-10 does not bite because the largest value on
  /// a 16x16 board is well inside 32 bits, so Java never wraps here either.
  @override
  int get hashCode => 9901 * row + 1009 * col + value;

  /// Java checks `obj == this`, then `instanceof`, then the three fields. The
  /// identity fast path is folded into Dart's `other is _Rcv` test plus the field
  /// comparison, which is equivalent for a class with final int fields.
  @override
  bool operator ==(Object other) =>
      other is _Rcv &&
      row == other.row &&
      col == other.col &&
      value == other.value;

  /// Java: `value + "@" + row + "x" + col`. Debug only -- no trace reads it.
  @override
  String toString() => '$value@${row}x$col';
}
