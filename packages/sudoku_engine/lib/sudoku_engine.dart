// TSudoku - an iOS port of Free Sudoku.
// Copyright (C) 2006 - 2007, Nicolas Juillerat
// Copyright (C) 2009 - 2011, Markus Wiederkehr
// Copyright (C) 2011 - NOW, Cool Android Appz
// Copyright (C) 2026, Sebastian Waschnick (Dart translation)
//
// This program is free software: you can redistribute it and/or modify it under the terms
// of the GNU General Public License as published by the Free Software Foundation, either
// version 3 of the License, or (at your option) any later version.
//
// This program is distributed in the hope that it will be useful, but WITHOUT ANY
// WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
// PARTICULAR PURPOSE. See the GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License along with this
// program. If not, see <https://www.gnu.org/licenses/>.

/// The TSudoku game engine.
///
/// This library is **pure Dart by contract**: no `package:flutter`, no `dart:ui`, no
/// `dart:io`. That is not a style preference. It keeps the engine testable without a
/// device, stops it growing a dependency on how anything looks, and prevents a trace from
/// depending on the machine that produced it. The rule is enforced by
/// `tool/check_engine_purity.dart`, because the analyzer cannot express it -- an illegal
/// `import 'dart:io'` produces no diagnostic at all.
///
/// Translation progress follows the order in the port plan's Phase 2 table. Everything
/// exported here has been verified against the Java original by byte-identical trace
/// comparison -- `difftest-harness/tool/diff.sh`. Nothing is exported on the strength of
/// a code review alone.
library;

export 'src/model/geometry.dart'
    show ExtraRegion, ExtraRegions, Position, Region;
export 'src/model/puzzle.dart' show Puzzle;
export 'src/model/puzzle_type.dart'
    show Difficulty, PuzzleType, difficultyFromFolderName;
export 'src/model/value_set.dart' show ValueSet;
export 'src/solver/dlx_puzzle_solver.dart' show DlxPuzzleSolver;
export 'src/solver/puzzle_solver.dart'
    show
        PuzzleReporter,
        PuzzleSolver,
        SingleSolutionReporter,
        SolutionCounterReporter,
        UniqueSolutionReporter;
export 'src/transfer/puzzle_decoder.dart' show decodePuzzle, javaSplitPipe;
export 'src/transfer/standard_areas.dart' show standardAreas;
export 'src/util/java_random.dart' show JavaRandom;

/// Identifies this engine build in traces and in the about screen.
///
/// Kept deliberately separate from the application's version: the engine is compared
/// against a Java oracle and it is useful to be able to say which engine produced a trace.
const String engineVersion = '0.1.0';

/// The upstream application this port reproduces, for attribution in UI and traces.
const String upstreamApplication =
    'Free Sudoku 1.060 (com.coolandroidappzfree.freesudoku)';
