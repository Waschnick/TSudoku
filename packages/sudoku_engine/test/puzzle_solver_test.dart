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
// Ported from: app/src/main/java/com/googlecode/andoku/solver/PuzzleSolver.java
// Ported from: app/src/main/java/com/googlecode/andoku/solver/PuzzleReporter.java
// Ported from: app/src/main/java/com/googlecode/andoku/solver/SingleSolutionReporter.java
// Ported from: app/src/main/java/com/googlecode/andoku/solver/SolutionCounterReporter.java
// Ported from: app/src/main/java/com/googlecode/andoku/solver/UniqueSolutionReporter.java
// Translation rules applied: R-10, R-13

import 'package:sudoku_engine/src/model/geometry.dart';
import 'package:sudoku_engine/src/model/puzzle.dart';
import 'package:sudoku_engine/src/solver/puzzle_solver.dart';
import 'package:test/test.dart';

/// Standard 3x3-box area map, built locally so these tests do not depend on
/// `standardAreas`.
List<List<int>> standardBoxes() => List<List<int>>.generate(
  9,
  (int row) => List<int>.generate(9, (int col) => (row ~/ 3) * 3 + col ~/ 3),
);

/// A genuinely valid 9x9 solution, 0-based (see `Puzzle`'s value convention).
///
/// `(3 * (r % 3) + r ~/ 3 + c) % 9` is the classic shifted-band construction, so
/// every row, column and 3x3 box is a permutation of 0..8. Validity matters:
/// `Puzzle.set` adds the value to each of the cell's `Region.values` sets and
/// `Puzzle.clear` removes it unguarded, so a grid with a duplicate inside one
/// region would make set/clear non-symmetric and the fake driver below would
/// leak state between solutions.
List<List<int>> validSolution({int shift = 0}) => List<List<int>>.generate(
  9,
  (int r) =>
      List<int>.generate(9, (int c) => (3 * (r % 3) + r ~/ 3 + c + shift) % 9),
);

/// Writes [values] into [p], which must be empty.
void fill(Puzzle p, List<List<int>> values) {
  for (int r = 0; r < 9; r++) {
    for (int c = 0; c < 9; c++) {
      p.set(r, c, values[r][c]);
    }
  }
}

/// Empties every filled cell of [p] -- what `DlxListener.deselect` does on the
/// way out of the search.
void wipe(Puzzle p) {
  for (int r = 0; r < 9; r++) {
    for (int c = 0; c < 9; c++) {
      if (p.getValue(r, c) != Puzzle.undefined) {
        p.clear(r, c);
      }
    }
  }
}

/// Stands in for `DlxPuzzleSolver` so these tests pin the *reporter* contract
/// without depending on a sibling file another agent owns.
///
/// It reproduces the two things about the real solver that reporters can observe:
///
/// 1. It reports its **own live working grid** (`this.puzzle = new
///    Puzzle(puzzle)` in `DlxPuzzleSolver.solve`), the same instance every time,
///    mutated in place between reports -- exactly the hand-over
///    `PuzzleReporter`'s javadoc warns about.
/// 2. It treats `report`'s result as the continue/stop signal, stopping as soon
///    as it sees `false`, the way `dlx/Solver.search0()` propagates `proceed`.
///
/// It is *not* a DLX search: it replays a canned list of solutions. Node order
/// and the min-column heuristic are `dlx_puzzle_solver_test.dart`'s business.
final class FakeSolver implements PuzzleSolver {
  FakeSolver(this.solutions);

  /// Solutions to hand over, in order.
  final List<List<List<int>>> solutions;

  /// The live working grid, kept after [solve] returns so a test can assert that
  /// a reporter's stored copy is detached from it.
  Puzzle? working;

  /// How many solutions were actually reported before the reporter said stop.
  int reportCount = 0;

  @override
  void solve(Puzzle puzzle, PuzzleReporter reporter) {
    final Puzzle work = Puzzle.copy(puzzle);
    working = work;

    for (final List<List<int>> values in solutions) {
      fill(work, values);
      reportCount++;
      final bool proceed = reporter.report(work);
      wipe(work);

      if (!proceed) {
        return;
      }
    }
  }
}

void main() {
  final List<List<int>> boxes = standardBoxes();
  final List<List<int>> solutionA = validSolution();
  final List<List<int>> solutionB = validSolution(shift: 1);

  group('SingleSolutionReporter', () {
    test('starts with no solution', () {
      // Java: the `solution` field is left uninitialised, and
      // AndokuPuzzle.computeSolution() branches on `getSolution() == null` to
      // decide the puzzle is unsolvable. Null is a meaningful value here.
      expect(SingleSolutionReporter().solution, isNull);
    });

    test('report returns false, stopping the search at the first solution', () {
      final SingleSolutionReporter reporter = SingleSolutionReporter();
      final Puzzle p = Puzzle(boxes, ExtraRegions.none());
      fill(p, solutionA);

      expect(reporter.report(p), isFalse);
    });

    test('stores a COPY, not the solver live grid', () {
      // The whole point of PuzzleReporter's javadoc. If this stored the
      // reference, `wipe` in FakeSolver -- standing in for `deselect` -- would
      // empty the "solution" and the gameplay path would silently lose its
      // ground truth.
      final SingleSolutionReporter reporter = SingleSolutionReporter();
      final FakeSolver solver = FakeSolver(<List<List<int>>>[solutionA]);

      solver.solve(Puzzle(boxes, ExtraRegions.none()), reporter);

      expect(solver.working!.valuesCount, 0, reason: 'live grid was wiped');
      expect(reporter.solution, isNotNull);
      expect(reporter.solution, isNot(same(solver.working)));
      expect(reporter.solution!.isSolved, isTrue);
      expect(
        reporter.solution!.toString(),
        _filled(boxes, solutionA).toString(),
      );
    });

    test('is handed only one solution even when more exist', () {
      final SingleSolutionReporter reporter = SingleSolutionReporter();
      final FakeSolver solver = FakeSolver(<List<List<int>>>[
        solutionA,
        solutionB,
      ]);

      solver.solve(Puzzle(boxes, ExtraRegions.none()), reporter);

      expect(solver.reportCount, 1);
    });
  });

  group('SolutionCounterReporter', () {
    test('starts at zero', () {
      expect(SolutionCounterReporter().counter, 0);
    });

    test('report always returns true, so the search is never cut short', () {
      // The only reporter of the three that never stops the search. Returning
      // false here would turn an exhaustive count into "at most one".
      final SolutionCounterReporter reporter = SolutionCounterReporter();
      final Puzzle p = Puzzle(boxes, ExtraRegions.none());
      fill(p, solutionA);

      expect(reporter.report(p), isTrue);
      expect(reporter.report(p), isTrue);
      expect(reporter.report(p), isTrue);
      expect(reporter.counter, 3);
    });

    test('enumerates every solution offered', () {
      final SolutionCounterReporter reporter = SolutionCounterReporter();
      final FakeSolver solver = FakeSolver(<List<List<int>>>[
        solutionA,
        solutionB,
        solutionA,
        solutionB,
      ]);

      solver.solve(Puzzle(boxes, ExtraRegions.none()), reporter);

      expect(solver.reportCount, 4);
      expect(reporter.counter, 4);
    });
  });

  group('UniqueSolutionReporter', () {
    test('reports NONE before any solution', () {
      final UniqueSolutionReporter reporter = UniqueSolutionReporter();

      expect(reporter.solution, isNull);
      expect(reporter.hasSolution, isFalse);
      expect(reporter.hasUniqueSolution, isFalse);
      expect(reporter.hasMultipleSolutions, isFalse);
    });

    test('first report returns TRUE -- the search must continue', () {
      // `return ++solutions == 1`. This is the assertion that catches the
      // classic misreading (`solutions++ == 1`, or a blunt `return false`):
      // either one makes every solvable puzzle look UNIQUE, because the search
      // stops before a second solution can be found.
      final UniqueSolutionReporter reporter = UniqueSolutionReporter();
      final Puzzle p = Puzzle(boxes, ExtraRegions.none());
      fill(p, solutionA);

      expect(reporter.report(p), isTrue);
      expect(reporter.hasSolution, isTrue);
      expect(reporter.hasUniqueSolution, isTrue);
      expect(reporter.hasMultipleSolutions, isFalse);
    });

    test('second report returns FALSE and flips UNIQUE to MULTIPLE', () {
      final UniqueSolutionReporter reporter = UniqueSolutionReporter();
      final Puzzle p = Puzzle(boxes, ExtraRegions.none());
      fill(p, solutionA);

      expect(reporter.report(p), isTrue);
      expect(reporter.report(p), isFalse);

      expect(reporter.hasSolution, isTrue);
      expect(reporter.hasUniqueSolution, isFalse);
      expect(reporter.hasMultipleSolutions, isTrue);
    });

    test('a unique puzzle ends with exactly one report and status UNIQUE', () {
      final UniqueSolutionReporter reporter = UniqueSolutionReporter();
      final FakeSolver solver = FakeSolver(<List<List<int>>>[solutionA]);

      solver.solve(Puzzle(boxes, ExtraRegions.none()), reporter);

      expect(solver.reportCount, 1);
      expect(reporter.hasUniqueSolution, isTrue);
      expect(reporter.hasMultipleSolutions, isFalse);
    });

    test('an ambiguous puzzle stops after the SECOND report', () {
      // Uniqueness is proved by failing to find a second solution, so the search
      // has to run past the first. Stopping at the second is what bounds the
      // cost: the counter saturates at 2 and never enumerates further.
      final UniqueSolutionReporter reporter = UniqueSolutionReporter();
      final FakeSolver solver = FakeSolver(<List<List<int>>>[
        solutionA,
        solutionB,
        solutionA,
        solutionB,
      ]);

      solver.solve(Puzzle(boxes, ExtraRegions.none()), reporter);

      expect(solver.reportCount, 2, reason: 'never a third report');
      expect(reporter.hasMultipleSolutions, isTrue);
    });

    test('solution holds the LAST reported solution, not the first', () {
      // The assignment is unconditional in Java, so the second solution
      // overwrites the first. The harness prints the stored solution string, so
      // this is observable; do not "fix" it into first-wins.
      final UniqueSolutionReporter reporter = UniqueSolutionReporter();
      final FakeSolver solver = FakeSolver(<List<List<int>>>[
        solutionA,
        solutionB,
      ]);

      solver.solve(Puzzle(boxes, ExtraRegions.none()), reporter);

      expect(
        reporter.solution!.toString(),
        _filled(boxes, solutionB).toString(),
      );
      expect(
        reporter.solution!.toString(),
        isNot(_filled(boxes, solutionA).toString()),
      );
    });

    test('stores a COPY, detached from the solver live grid', () {
      final UniqueSolutionReporter reporter = UniqueSolutionReporter();
      final FakeSolver solver = FakeSolver(<List<List<int>>>[solutionA]);

      solver.solve(Puzzle(boxes, ExtraRegions.none()), reporter);

      expect(solver.working!.valuesCount, 0);
      expect(reporter.solution, isNot(same(solver.working)));
      expect(reporter.solution!.isSolved, isTrue);
    });

    test('a third report would still return false', () {
      // `solutions > 1` rather than `== 2` is the Java predicate, and it is
      // deliberately kept: a reporter driven by something that ignores the stop
      // signal still answers MULTIPLE rather than wrapping around.
      final UniqueSolutionReporter reporter = UniqueSolutionReporter();
      final Puzzle p = Puzzle(boxes, ExtraRegions.none());
      fill(p, solutionA);

      reporter.report(p);
      reporter.report(p);

      expect(reporter.report(p), isFalse);
      expect(reporter.hasMultipleSolutions, isTrue);
      expect(reporter.hasUniqueSolution, isFalse);
    });
  });

  group('the three reporters differ exactly where Java says they do', () {
    test('copy behaviour: single and unique copy, counter keeps nothing', () {
      // Stated as a test so the asymmetry is not mistaken for an oversight in
      // SolutionCounterReporter.
      final Puzzle p = Puzzle(boxes, ExtraRegions.none());
      fill(p, solutionA);

      final SingleSolutionReporter single = SingleSolutionReporter();
      final UniqueSolutionReporter unique = UniqueSolutionReporter();
      final SolutionCounterReporter counter = SolutionCounterReporter();

      single.report(p);
      unique.report(p);
      counter.report(p);

      wipe(p);

      expect(single.solution!.isSolved, isTrue);
      expect(unique.solution!.isSolved, isTrue);
      expect(counter.counter, 1, reason: 'nothing retained, nothing to detach');
      expect(p.valuesCount, 0);
    });

    test('stop signal: false, true, then true-once-then-false', () {
      final Puzzle p = Puzzle(boxes, ExtraRegions.none());
      fill(p, solutionA);

      expect(SingleSolutionReporter().report(p), isFalse);
      expect(SolutionCounterReporter().report(p), isTrue);

      final UniqueSolutionReporter unique = UniqueSolutionReporter();
      expect(<bool>[unique.report(p), unique.report(p)], <bool>[true, false]);
    });
  });
}

/// A fresh solved puzzle, for comparing against a reporter's stored copy.
Puzzle _filled(List<List<int>> boxes, List<List<int>> values) {
  final Puzzle p = Puzzle(boxes, ExtraRegions.none());
  fill(p, values);
  return p;
}
