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
// Translation rules applied: R-03, R-06, R-10, R-11

import 'package:sudoku_engine/src/model/geometry.dart';
import 'package:sudoku_engine/src/model/puzzle.dart';
import 'package:sudoku_engine/src/solver/dlx_puzzle_solver.dart';
import 'package:sudoku_engine/src/solver/puzzle_solver.dart';
import 'package:sudoku_engine/src/transfer/puzzle_decoder.dart';
import 'package:sudoku_engine/src/util/java_random.dart';
import 'package:test/test.dart';

/// `Long.MAX_VALUE`, the value the JVM oracle's `CountingDlxSolver` passes.
///
/// It is what makes `numberOfUpdates` count at all, because `select`'s
/// `maxUpdates == 0 || ++updates < maxUpdates` short-circuits past the increment
/// when the budget is 0. R-10: Dart's `int` is 64-bit, so this literal is the
/// exact equivalent.
const int unlimitedButCounting = 9223372036854775807;

/// One DLX trace line from the Java oracle, with the record it came from.
///
/// These are not hand-computed expectations. Every field was lifted verbatim out
/// of `difftest-harness/build/java.T0.parse-geom-dlx.trace`, produced by the JVM
/// oracle over the shipped `.adk` corpus. The `nodes` figure is the whole point:
/// a Dart DLX that reaches the right answer by a different route gets the
/// solution right and this number wrong.
class Golden {
  final String key;
  final String raw;
  final String status;
  final int nodes;
  final String sol;

  const Golden(this.key, this.raw, this.status, this.nodes, this.sol);
}

const List<Golden> goldens = <Golden>[
  Golden(
    'handcrafted_n_1#00000',
    '.....7....69..1.8...2..951.793.....................738.312..6...8.3..94....4.....',
    'UNIQUE',
    57,
    '514827369369541287872639514793182456648753192125964738431298675286375941957416823',
  ),
  Golden(
    'handcrafted_n_1#00001',
    '5...7...3..62.98...4.....1...9...6..2..7.6..8..3...7...2.....6...85.41..7...9...5',
    'UNIQUE',
    55,
    '582671943136249857947853216879425631214736598653918724425187369398564172761392485',
  ),
  Golden(
    'handcrafted_n_2#00000',
    '.......9.9....45.1.27....6.4...3......69.28......4...7.9....25.5.31....6.8.......',
    'UNIQUE',
    57,
    '345261798968374521127895364459738612736912845812546937691487253573129486284653179',
  ),
  // STANDARD_HYPER. Note the `||H`: field 2 is empty (R-07, a trailing empty
  // field Java's split would drop) and field 3 adds four extra regions. The
  // four hyper boxes contribute 36 extra matrix columns, so if `regionOffset`
  // or `region.id * size + v` were off this record would diverge loudly.
  Golden(
    'standard_h_5#00001',
    '..9.41.7.1...67.........4......7...5.........5...9......4.........61...4.6.72.3..||H',
    'UNIQUE',
    375,
    '859241673143867529276539418492176835631458297587392146314985762725613984968724351',
  ),
  // SQUIGGLY_X: irregular areas *and* two extra regions. The highest-value
  // single record here -- it exercises the area-region positions, the extra
  // regions and the deepest search of the six.
  Golden(
    'squiggly_x_1#00000',
    '.428.9.57.1..6..9..9........6.3..724..5...8..289..4.7........6..5..7..8.82.9.731.|999998888996988877696687877666557777665555533444455333442423313442221311222211111|X',
    'UNIQUE',
    49,
    '642839157714563298197285436568391724935726841289614573473158962351472689826947315',
  ),
  Golden(
    'squiggly_h_5#00000',
    '.......5.1..4.6......7...8...6.....7.........7.....8...6...3......1.7..4.2.......|777899995777899995748888955748886655746666651446622251443222251433332111433332111|H',
    'UNIQUE',
    339,
    '678314259192486375431725986356892147514978632743569821967253418289137564825641793',
  ),
];

/// The oracle's `sol=` format: 1-based digit per cell, `.` for an empty one.
/// Values are 0-based in `Puzzle`, hence the `+ 1`.
String flat(Puzzle p) {
  final StringBuffer sb = StringBuffer();
  for (int row = 0; row < p.size; row++) {
    for (int col = 0; col < p.size; col++) {
      final int v = p.getValue(row, col);
      sb.writeCharCode(v == Puzzle.undefined ? 0x2E : 0x31 + v);
    }
  }
  return sb.toString();
}

/// The oracle's `status=` field, derived exactly as `Oracle.java` derives it.
String statusOf(UniqueSolutionReporter reporter) {
  if (!reporter.hasSolution) {
    return 'NONE';
  }
  if (reporter.hasMultipleSolutions) {
    return 'MULTIPLE';
  }
  return 'UNIQUE';
}

int clueCount(Puzzle p) {
  int n = 0;
  for (int row = 0; row < p.size; row++) {
    for (int col = 0; col < p.size; col++) {
      if (p.getValue(row, col) != Puzzle.undefined) {
        n++;
      }
    }
  }
  return n;
}

void main() {
  group('golden DLX traces from the JVM oracle', () {
    for (final Golden g in goldens) {
      test('${g.key}: status, NODE COUNT and solution', () {
        final Puzzle problem = decodePuzzle(g.raw);
        final UniqueSolutionReporter reporter = UniqueSolutionReporter();
        final DlxPuzzleSolver solver = DlxPuzzleSolver(
          maxUpdates: unlimitedButCounting,
        );

        solver.solve(problem, reporter);

        expect(statusOf(reporter), g.status);
        expect(flat(reporter.solution!), g.sol);
        // The node count is the assertion that cannot be satisfied by accident.
        // It pins the column layout, the order of `Puzzle.regions`, the
        // min-column heuristic's first-minimum tie-break and the row order
        // `Solver.getRows` produces -- all at once.
        expect(
          solver.numberOfUpdates,
          g.nodes,
          reason:
              'node count differs from the Java oracle: the search visited a '
              'different set of nodes, so the matrix layout or the column/row '
              'ordering has drifted even though the answer may be right',
        );
      });
    }
  });

  group('the solution honours every region of the puzzle', () {
    // This is what proves the (region, value) columns are wired up at
    // `regionOffset + region.id * size + v`. A wrong offset or a wrong stride
    // would still yield *a* latin-square-ish board, but some region -- most
    // likely an extra region, which sits at the far end of the column range --
    // would come out with a duplicate.
    for (final Golden g in goldens) {
      test('${g.key}: every region holds every value exactly once', () {
        final Puzzle problem = decodePuzzle(g.raw);
        final UniqueSolutionReporter reporter = UniqueSolutionReporter();
        DlxPuzzleSolver().solve(problem, reporter);

        final Puzzle solution = reporter.solution!;
        expect(solution.isSolved, isTrue);

        for (final Region region in solution.regions) {
          final List<int> values = <int>[
            for (final Position p in region.positions)
              solution.getValue(p.row, p.col),
          ];
          expect(
            values.toSet().length,
            solution.size,
            reason: 'region "${region.name}" (id ${region.id}) has a duplicate',
          );
        }
      });
    }
  });

  test('the givens survive into the solution (RCV equality is a value key)', () {
    // `eliminateGivenClues` looks a freshly built RCV back up in the matrix's
    // payload map (R-03). With identity semantics the lookup returns null and
    // the `!` throws; with a *wrong but non-null* key the clue rows would stay
    // in the matrix and the solver could place a different digit on a given
    // cell. Both failures are caught here.
    final Golden g = goldens[3];
    final Puzzle problem = decodePuzzle(g.raw);
    final UniqueSolutionReporter reporter = UniqueSolutionReporter();
    DlxPuzzleSolver().solve(problem, reporter);

    final Puzzle solution = reporter.solution!;
    for (int row = 0; row < problem.size; row++) {
      for (int col = 0; col < problem.size; col++) {
        final int given = problem.getValue(row, col);
        if (given != Puzzle.undefined) {
          expect(solution.getValue(row, col), given);
        }
      }
    }
  });

  group('maxUpdates', () {
    test('defaults to 0, and 0 means unlimited AND uncounted', () {
      // The short-circuit in `select`: `maxUpdates == 0 || ++updates < maxUpdates`.
      // The left operand is true, so the increment never runs. The search is
      // *not* capped -- it finds the full unique solution -- yet the counter
      // stays at 0. Reproducing this is mandatory: an eager `++updates` would
      // change the trace's `nodes=` field for every puzzle, because the oracle
      // only gets a usable count by passing Long.MAX_VALUE.
      final Golden g = goldens[3];
      final UniqueSolutionReporter reporter = UniqueSolutionReporter();
      final DlxPuzzleSolver solver = DlxPuzzleSolver();

      solver.solve(decodePuzzle(g.raw), reporter);

      expect(statusOf(reporter), 'UNIQUE');
      expect(flat(reporter.solution!), g.sol);
      expect(
        solver.numberOfUpdates,
        0,
        reason:
            'maxUpdates == 0 must short-circuit past ++updates, leaving the '
            'counter at 0 exactly as Java does',
      );
    });

    test('Long.MAX_VALUE counts without changing the boolean result', () {
      // Same puzzle, same answer, same search -- only the counter wakes up.
      final Golden g = goldens[3];
      final UniqueSolutionReporter counted = UniqueSolutionReporter();
      final UniqueSolutionReporter uncounted = UniqueSolutionReporter();

      DlxPuzzleSolver(maxUpdates: unlimitedButCounting)
          .solve(decodePuzzle(g.raw), counted);
      DlxPuzzleSolver().solve(decodePuzzle(g.raw), uncounted);

      expect(flat(counted.solution!), flat(uncounted.solution!));
      expect(statusOf(counted), statusOf(uncounted));
    });

    test('a budget of 1 aborts after the very first selection', () {
      // `++updates` makes updates 1, and `1 < 1` is false, so `select` returns
      // false on its first call. The search unwinds with nothing found.
      final UniqueSolutionReporter reporter = UniqueSolutionReporter();
      final DlxPuzzleSolver solver = DlxPuzzleSolver(maxUpdates: 1);

      solver.solve(decodePuzzle(goldens[3].raw), reporter);

      expect(reporter.hasSolution, isFalse);
      expect(statusOf(reporter), 'NONE');
      expect(solver.numberOfUpdates, 1);
    });

    test('a finite budget short of the answer reports no solution', () {
      // 20 clues means 61 cells to fill, so 10 selections cannot reach a
      // solution. The counter stops exactly at the budget.
      final UniqueSolutionReporter reporter = UniqueSolutionReporter();
      final DlxPuzzleSolver solver = DlxPuzzleSolver(maxUpdates: 10);

      solver.solve(decodePuzzle(goldens[3].raw), reporter);

      expect(reporter.hasSolution, isFalse);
      expect(solver.numberOfUpdates, 10);
    });
  });

  group('the solver works on a copy', () {
    test("solve() never mutates the caller's puzzle", () {
      // Java: `this.puzzle = new Puzzle(puzzle)`. Without the copy the caller's
      // board would come back solved, and `AndokuPuzzle.computeSolution` would
      // hand the player a filled grid.
      final Puzzle problem = decodePuzzle(goldens[0].raw);
      final int before = clueCount(problem);
      final String snapshot = flat(problem);

      DlxPuzzleSolver().solve(problem, UniqueSolutionReporter());

      expect(clueCount(problem), before);
      expect(flat(problem), snapshot);
    });

    test('the reported puzzle is the live working board, not a snapshot', () {
      // `solutionFound` passes `puzzle` itself. Every stock reporter copies it;
      // a reporter that keeps the reference watches the search unwind the board
      // back down to the givens. Pinning this stops a well-meaning
      // `Puzzle.copy` from being added inside `solutionFound`, which would make
      // the stock reporters copy twice.
      final Puzzle problem = decodePuzzle(goldens[0].raw);
      final int clues = clueCount(problem);
      final CapturingReporter reporter = CapturingReporter();

      DlxPuzzleSolver().solve(problem, reporter);

      expect(reporter.reports, 1);
      expect(flat(reporter.copyAtReportTime!), goldens[0].sol);
      expect(
        clueCount(reporter.live!),
        clues,
        reason:
            'the live board should have been unwound back to its givens after '
            'the search completed, proving it was never copied for the report',
      );
    });

    test('the same solver instance can solve twice', () {
      // `solve(Puzzle, PuzzleReporter)` rebuilds everything -- copy, matrix,
      // counter -- so reuse is safe even though the aborted-budget path leaves
      // the previous working board dirty.
      final DlxPuzzleSolver solver = DlxPuzzleSolver(
        maxUpdates: unlimitedButCounting,
      );

      final UniqueSolutionReporter first = UniqueSolutionReporter();
      solver.solve(decodePuzzle(goldens[0].raw), first);
      expect(solver.numberOfUpdates, goldens[0].nodes);

      final UniqueSolutionReporter second = UniqueSolutionReporter();
      solver.solve(decodePuzzle(goldens[1].raw), second);
      expect(
        solver.numberOfUpdates,
        goldens[1].nodes,
        reason: 'the update counter must be reset per solve() call',
      );
      expect(flat(second.solution!), goldens[1].sol);
    });
  });

  group('the reporter steers the search', () {
    test('SingleSolutionReporter stops at the first solution', () {
      // Returning false from `report` aborts. The unique-solution run has to
      // keep going to prove there is no second solution, so it must do strictly
      // more work -- which is also a check that `solutionFound`'s return value
      // is actually propagated rather than swallowed.
      final Golden g = goldens[3];
      final SingleSolutionReporter single = SingleSolutionReporter();
      final DlxPuzzleSolver solver = DlxPuzzleSolver(
        maxUpdates: unlimitedButCounting,
      );

      final Puzzle problem = decodePuzzle(g.raw);
      solver.solve(problem, single);

      expect(flat(single.solution!), g.sol);
      final int emptyCells = problem.size * problem.size - clueCount(problem);
      expect(solver.numberOfUpdates, greaterThanOrEqualTo(emptyCells));
      expect(solver.numberOfUpdates, lessThan(g.nodes));
    });

    test('SolutionCounterReporter counts the solutions it is allowed to see', () {
      // It always returns true, so it would run forever on an underconstrained
      // board -- never point it at an empty grid. On a unique puzzle it sees
      // exactly one.
      final SolutionCounterReporter counter = SolutionCounterReporter();
      DlxPuzzleSolver().solve(decodePuzzle(goldens[0].raw), counter);
      expect(counter.counter, 1);
    });
  });

  group('the randomised strategy (dead in the shipped app)', () {
    // `AndokuPuzzle.java:350` uses the no-arg constructor, so `random` is always
    // null in production and the differential oracle never exercises these two
    // branches. They are translated because R-06 says a Java-seeded sequence
    // must be reproduced with JavaRandom rather than dart:math's Random, and
    // tested here only for internal consistency -- there is no JVM golden to
    // compare against.

    test('a seeded run still finds the unique solution', () {
      final Golden g = goldens[3];
      final UniqueSolutionReporter reporter = UniqueSolutionReporter();

      DlxPuzzleSolver(random: JavaRandom(42))
          .solve(decodePuzzle(g.raw), reporter);

      // Uniqueness is a property of the puzzle, not of the search order, so the
      // answer must be identical however the rows were shuffled.
      expect(flat(reporter.solution!), g.sol);
      expect(statusOf(reporter), 'UNIQUE');
    });

    test('the same seed reproduces the same search', () {
      final Golden g = goldens[3];

      final DlxPuzzleSolver a = DlxPuzzleSolver(
        random: JavaRandom(12345),
        maxUpdates: unlimitedButCounting,
      );
      final DlxPuzzleSolver b = DlxPuzzleSolver(
        random: JavaRandom(12345),
        maxUpdates: unlimitedButCounting,
      );

      a.solve(decodePuzzle(g.raw), UniqueSolutionReporter());
      b.solve(decodePuzzle(g.raw), UniqueSolutionReporter());

      expect(a.numberOfUpdates, b.numberOfUpdates);
    });

    test('a null random source leaves the row order untouched', () {
      // `sort` returns immediately when random == null, so the deterministic
      // run must reproduce the golden node count -- already covered above, but
      // asserted here next to its randomised sibling so the contrast is
      // visible: if `sort` ever started reordering unconditionally, this is the
      // test that says which branch broke.
      final Golden g = goldens[5];
      final DlxPuzzleSolver solver = DlxPuzzleSolver(
        maxUpdates: unlimitedButCounting,
      );
      solver.solve(decodePuzzle(g.raw), UniqueSolutionReporter());
      expect(solver.numberOfUpdates, g.nodes);
    });
  });
}

/// Keeps both the live board and a copy taken at report time.
class CapturingReporter implements PuzzleReporter {
  int reports = 0;
  Puzzle? live;
  Puzzle? copyAtReportTime;

  @override
  bool report(Puzzle solution) {
    reports++;
    live = solution;
    copyAtReportTime = Puzzle.copy(solution);
    return true;
  }
}
