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
// Ported from: app/src/main/java/com/googlecode/andoku/transfer/StandardAreas.java
// Translation rules applied: R-13

/// The default region layout for a board of a given edge length.
///
/// A `.adk` record omits field 2 (the 81-character area map) whenever the puzzle
/// uses the default regions, so the decoder falls back to this table -- see
/// `PuzzleDecoder.parseAreaCodes`, which calls `StandardAreas.getAreas(size)`
/// exactly when `areas.length() == 0`. `AndokuPuzzle.isSquiggly` uses the same
/// table the other way round: a puzzle is squiggly iff any cell's area code
/// differs from the standard one, so the *values* here decide puzzle typing and
/// are therefore trace-visible, not cosmetic.
library;

/// 5x5 default areas, verbatim from `StandardAreas.STD_5` (Java lines 26-27).
///
/// Note this is a jigsaw layout, not boxes: 5 is prime, so there is no
/// rectangular tiling. Kept because the Java keeps it (see [standardAreas] on
/// why the non-9 sizes are transcribed rather than dropped).
const List<List<int>> _std5 = <List<int>>[
  <int>[0, 0, 0, 1, 1],
  <int>[0, 0, 4, 1, 1],
  <int>[2, 4, 4, 4, 1],
  <int>[2, 2, 4, 3, 3],
  <int>[2, 2, 3, 3, 3],
];

/// 6x6 default areas, verbatim from `StandardAreas.STD_6` (Java lines 29-30):
/// six 3-wide, 2-tall boxes.
const List<List<int>> _std6 = <List<int>>[
  <int>[0, 0, 0, 1, 1, 1],
  <int>[0, 0, 0, 1, 1, 1],
  <int>[2, 2, 2, 3, 3, 3],
  <int>[2, 2, 2, 3, 3, 3],
  <int>[4, 4, 4, 5, 5, 5],
  <int>[4, 4, 4, 5, 5, 5],
];

/// 7x7 default areas, verbatim from `StandardAreas.STD_7` (Java lines 32-34).
///
/// Another jigsaw layout: area 3 is a plus/snake shape spanning rows 2-4, which
/// looks like a typo in the Java literal and is not one. Every area still holds
/// exactly 7 cells (asserted in the test), which is the cheap check that this
/// transcription is faithful.
const List<List<int>> _std7 = <List<int>>[
  <int>[0, 0, 0, 0, 1, 1, 1],
  <int>[0, 0, 0, 1, 1, 1, 1],
  <int>[2, 2, 2, 3, 4, 4, 4],
  <int>[2, 3, 3, 3, 3, 3, 4],
  <int>[2, 2, 2, 3, 4, 4, 4],
  <int>[5, 5, 5, 5, 6, 6, 6],
  <int>[5, 5, 5, 6, 6, 6, 6],
];

/// 8x8 default areas, verbatim from `StandardAreas.STD_8` (Java lines 36-38):
/// eight 4-wide, 2-tall boxes.
const List<List<int>> _std8 = <List<int>>[
  <int>[0, 0, 0, 0, 1, 1, 1, 1],
  <int>[0, 0, 0, 0, 1, 1, 1, 1],
  <int>[2, 2, 2, 2, 3, 3, 3, 3],
  <int>[2, 2, 2, 2, 3, 3, 3, 3],
  <int>[4, 4, 4, 4, 5, 5, 5, 5],
  <int>[4, 4, 4, 4, 5, 5, 5, 5],
  <int>[6, 6, 6, 6, 7, 7, 7, 7],
  <int>[6, 6, 6, 6, 7, 7, 7, 7],
];

/// 9x9 default areas, verbatim from `StandardAreas.STD_9` (Java lines 40-44):
/// the familiar nine 3x3 boxes, numbered row-major.
///
/// This is the only entry the shipped corpus can reach -- all 45,166 records are
/// 9x9 -- so it is the one the differential oracle actually exercises.
const List<List<int>> _std9 = <List<int>>[
  <int>[0, 0, 0, 1, 1, 1, 2, 2, 2],
  <int>[0, 0, 0, 1, 1, 1, 2, 2, 2],
  <int>[0, 0, 0, 1, 1, 1, 2, 2, 2],
  <int>[3, 3, 3, 4, 4, 4, 5, 5, 5],
  <int>[3, 3, 3, 4, 4, 4, 5, 5, 5],
  <int>[3, 3, 3, 4, 4, 4, 5, 5, 5],
  <int>[6, 6, 6, 7, 7, 7, 8, 8, 8],
  <int>[6, 6, 6, 7, 7, 7, 8, 8, 8],
  <int>[6, 6, 6, 7, 7, 7, 8, 8, 8],
];

/// Returns the default (non-squiggly) area code per cell for a board of edge
/// length [size], as `StandardAreas.getAreas(int)` does.
///
/// Row-major: `standardAreas(9)[row][col]` is the area code of that cell, and
/// codes run `0 .. size - 1`. Only 5 through 9 exist; anything else throws, the
/// same `switch` default as Java line 61-62 (`throw new
/// IllegalArgumentException()` with no message -- R-13: no checked-exception
/// wrapper, Dart's [ArgumentError] is the direct equivalent).
///
/// **Why sizes 5-8 are here at all.** The shipped corpus cannot reach them: all
/// 96 `.adk` files hold 81-character clue fields, so `PuzzleDecoder` only ever
/// derives `size == 9`, and the JVM oracle can therefore never diff these four
/// tables. The brief offers two honest options for an unexercisable path --
/// faithful translation, or an explicit error -- and this takes the first,
/// because the Java literals are unambiguous data that can be transcribed
/// character for character and checked by eye. Inventing a formula for them
/// would be the guess; `size * size / size`-style box arithmetic produces the
/// wrong answer for the prime sizes 5 and 7, where Andoku's default layout is a
/// jigsaw. The sizes outside 5-9 stay an error, exactly as in Java: there the
/// Java has no data to be faithful to.
///
/// **Aliasing.** Java hands out its shared `static final int[][]`, uncopied, and
/// `Puzzle` stores the reference without copying either (`Puzzle.java:73`), so a
/// caller that wrote through it would corrupt the table for the whole process.
/// Nothing in the Java does, and the Dart tables are `const`, so the same
/// identity is returned on every call (canonicalised) while a write throws
/// instead of silently poisoning later puzzles. Callers needing a mutable grid
/// must copy.
List<List<int>> standardAreas(int size) {
  switch (size) {
    case 5:
      return _std5;
    case 6:
      return _std6;
    case 7:
      return _std7;
    case 8:
      return _std8;
    case 9:
      return _std9;
    default:
      // Java: `throw new IllegalArgumentException()` -- message-less.
      throw ArgumentError.value(
        size,
        'size',
        'no standard areas for this size',
      );
  }
}
