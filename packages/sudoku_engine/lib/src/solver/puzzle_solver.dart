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

import '../model/puzzle.dart';

/// Gets notified of puzzle solutions and decides if the search should continue.
///
/// Java: the `PuzzleReporter` interface. Two things about this one-method
/// interface are load-bearing and neither is obvious from the signature.
///
/// ### 1. The argument is the solver's LIVE working grid
///
/// `DlxPuzzleSolver.Strategy.solutionFound()` is literally
/// `return reporter.report(puzzle)`, where `puzzle` is the solver's own mutable
/// field -- the grid its `select`/`deselect` callbacks have been poking values
/// into all the way down the search. The Java javadoc says so outright: *"The
/// reporter implementation has to copy this solution if it wants to keep it."*
/// The instant the search unwinds, `deselect` starts clearing those cells again,
/// so a reporter that stores the reference ends up holding a grid that empties
/// itself. [SingleSolutionReporter] and [UniqueSolutionReporter] therefore both
/// copy; [SolutionCounterReporter] keeps nothing and so needs no copy.
///
/// ### 2. The return value is the search's continue/stop signal
///
/// `true` means "keep looking", `false` means "stop now". In
/// `dlx/Solver.search0()` the value becomes `proceed`, which `break`s the row
/// loop and is returned up the recursion, so every frame breaks in turn -- the
/// whole search unwinds, running `uncover`/`deselect` properly on the way out.
/// It is a clean early exit, not an abort, which is why a reporter can safely
/// use it to count rather than enumerate (see [UniqueSolutionReporter]).
///
/// R-13: Java declares no checked exceptions here, so there is nothing to drop;
/// the interface translates one-for-one.
abstract interface class PuzzleReporter {
  /// Reports one solution and answers whether the solver should continue.
  ///
  /// [solution] is the solver's live grid -- copy it (via [Puzzle.copy]) if you
  /// intend to keep it. Return `true` to search on, `false` to stop.
  bool report(Puzzle solution);
}

/// Can solve sudoku puzzles and notify a puzzle reporter of its solution(s).
///
/// Java: the `PuzzleSolver` interface. Only one implementation survives the port
/// (`DlxPuzzleSolver`, in `dlx_puzzle_solver.dart`); the other Java
/// implementation, `solver/BrutePuzzleSolver`, is on the do-not-port list and
/// `grep -rn 'BrutePuzzleSolver' --include=*.java` over the upstream tree finds
/// hits only inside the file that declares it -- never an import, never a `new`.
/// Keeping the interface anyway costs nothing and is what `AndokuPuzzle` holds
/// its solver through (`PuzzleSolver solver = new DlxPuzzleSolver()`).
abstract interface class PuzzleSolver {
  /// Solves [puzzle], handing every solution to [reporter], which decides
  /// whether to keep going.
  ///
  /// The solver works on its own copy; [puzzle] itself is not modified.
  void solve(Puzzle puzzle, PuzzleReporter reporter);
}

/// Puzzle reporter that captures a single solution and stops searching.
///
/// Java: `SingleSolutionReporter` (declared `final`, hence Dart `final class`).
/// This is the reporter the actual gameplay path uses --
/// `AndokuPuzzle.computeSolution()` pairs it with a `DlxPuzzleSolver` to get the
/// ground-truth solution for error checking.
///
/// It copies on report and returns `false`, so the search stops at the **first**
/// solution. That means it cannot distinguish a unique puzzle from an ambiguous
/// one -- it does not try to. `computeSolution()` only asks "is there a
/// solution?", treating `getSolution() == null` as failure. Uniqueness is
/// [UniqueSolutionReporter]'s job.
final class SingleSolutionReporter implements PuzzleReporter {
  Puzzle? _solution;

  /// The captured solution, or `null` if [report] was never called.
  ///
  /// Java: `getSolution()`, which returns the uninitialised field -- i.e. `null`
  /// -- for an unsolvable puzzle. `AndokuPuzzle.computeSolution()` branches on
  /// exactly that null, so the nullable type is the faithful translation and not
  /// a Dart-ism to be engineered away.
  Puzzle? get solution => _solution;

  /// Java: `report`. Copies, then returns `false` to stop the search.
  @override
  bool report(Puzzle solution) {
    // Java: `this.solution = new Puzzle(solution)`. The copy constructor is
    // mandatory here, not defensive: `solution` is the solver's live grid (see
    // PuzzleReporter) and the search clears it on the way out.
    _solution = Puzzle.copy(solution);
    return false;
  }
}

/// Puzzle reporter that counts the number of solutions of a sudoku puzzle.
///
/// Java: `SolutionCounterReporter` (declared `final`). The odd one out of the
/// three in both respects that matter:
///
/// * It **does not copy** -- it keeps no reference to the grid at all, so there
///   is nothing to detach. Its `report` body ignores its own argument entirely.
/// * It **always returns `true`**, so it never stops the search. The DLX tree is
///   enumerated exhaustively and [counter] ends up as the true total number of
///   solutions, however large.
///
/// Unused in the shipped app (`grep` finds no construction site), so it is not
/// exercised by the differential oracle; it is translated because it is part of
/// this package's surface and because it is the only reporter that documents, by
/// contrast, what the other two are doing.
final class SolutionCounterReporter implements PuzzleReporter {
  int _counter = 0;

  /// Number of solutions reported so far.
  ///
  /// R-10: Java declares this `long`. Dart's `int` is 64-bit on the platforms
  /// this port targets, so the width matches and no `.toSigned` dance is needed.
  /// The count is never truncated to 32 bits on either side.
  int get counter => _counter;

  /// Java: `report`. Increments and returns `true` -- search on, forever.
  @override
  bool report(Puzzle solution) {
    _counter++;
    return true;
  }
}

/// Puzzle reporter that can be used to determine if a puzzle has a unique
/// solution. Also stores that solution.
///
/// Java: `UniqueSolutionReporter` (the one reporter *not* declared `final`,
/// hence a plain Dart `class`).
///
/// ### The off-by-one that is not one
///
/// `report` is `return ++solutions == 1`, which reads like an error and is the
/// whole trick. The increment happens first, so the **first** solution makes
/// `solutions == 1` and returns `true` -> keep searching; the **second** makes
/// `solutions == 2` and returns `false` -> stop. Uniqueness is proved by
/// failing to find a second solution, which needs the search to continue past
/// the first one. Writing `solutions++ == 1` or `return false` here would make
/// every solvable puzzle report UNIQUE -- the exact class of silent divergence
/// the differential harness exists to catch, since the answer stays "solvable"
/// and only the *status* word changes.
///
/// ### `solutions` never exceeds 2
///
/// Because the search stops on the second report, the counter saturates at 2.
/// So [hasUniqueSolution] (`solutions == 1`) and [hasMultipleSolutions]
/// (`solutions > 1`) are asymmetric in form but exhaustive in practice: the only
/// reachable states are 0, 1 and 2. Do not "tidy" [hasMultipleSolutions] into
/// `solutions == 2`; the Java predicate is `> 1` and a reporter reused without a
/// stopping search (nothing does that today) would still be correct.
///
/// ### [solution] holds the LAST solution, not the first
///
/// The assignment is unconditional, so a second report overwrites the first.
/// For a puzzle with multiple solutions, [solution] is therefore the *second*
/// one found, not the first. That is observable -- the differential harness
/// prints the stored solution string -- so the overwrite is reproduced as-is.
class UniqueSolutionReporter implements PuzzleReporter {
  Puzzle? _solution;
  int _solutions = 0;

  /// The most recently reported solution, or `null` if there was none.
  ///
  /// Java: `getSolution()`. See the class doc on why "most recent" matters.
  Puzzle? get solution => _solution;

  /// Java: `hasSolution()` -- `solutions > 0`.
  bool get hasSolution => _solutions > 0;

  /// Java: `hasUniqueSolution()` -- `solutions == 1`, i.e. the search ran to
  /// completion without finding a second solution.
  bool get hasUniqueSolution => _solutions == 1;

  /// Java: `hasMultipleSolutions()` -- `solutions > 1`. Reachable only as
  /// `solutions == 2`, because [report] stops the search there.
  bool get hasMultipleSolutions => _solutions > 1;

  /// Java: `report`. Copies the live grid, then returns `++solutions == 1`.
  @override
  bool report(Puzzle solution) {
    // Java: `this.solution = new Puzzle(solution)`. Unconditional -- the second
    // solution replaces the first.
    _solution = Puzzle.copy(solution);

    // Java: `return ++solutions == 1`. Pre-increment: continue after the first
    // solution, stop after the second. See the class doc.
    return ++_solutions == 1;
  }
}
