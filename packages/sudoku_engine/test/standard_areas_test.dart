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

import 'package:sudoku_engine/src/transfer/standard_areas.dart';
import 'package:test/test.dart';

void main() {
  group('standardAreas(9)', () {
    test('is the row-major 3x3 box layout, derived independently', () {
      // Checking the literal against a formula rather than against itself: this
      // is what catches a single mistyped digit in the transcribed Java table,
      // which no other test in the suite would see. The 9x9 table is the only
      // one the .adk corpus reaches, so a typo here mis-types real puzzles --
      // AndokuPuzzle.isSquiggly compares against this table and would report
      // every standard puzzle as squiggly, which in turn routes the whole board
      // down the variant-blind getBlockAt() path.
      final areas = standardAreas(9);
      for (var row = 0; row < 9; row++) {
        for (var col = 0; col < 9; col++) {
          expect(
            areas[row][col],
            (row ~/ 3) * 3 + col ~/ 3,
            reason: 'cell ($row,$col)',
          );
        }
      }
    });

    test('makes a standard board test as non-squiggly', () {
      // Mirrors AndokuPuzzle.isSquiggly (Java lines 1369-1380): the predicate is
      // "differs from standardAreas anywhere".
      //
      // The comparison MUST be against an independently constructed table. An
      // earlier version of this test compared standardAreas(9) with
      // standardAreas(9) -- the same canonical object -- so every comparison was
      // an element against itself and the test could not fail for any table at
      // all, correct or scrambled. It passed while proving nothing.
      final shipped = standardAreas(9);
      final independent = [
        for (var row = 0; row < 9; row++)
          [for (var col = 0; col < 9; col++) (row ~/ 3) * 3 + col ~/ 3],
      ];
      final differing = [
        for (var row = 0; row < 9; row++)
          for (var col = 0; col < 9; col++)
            if (shipped[row][col] != independent[row][col]) '($row,$col)',
      ];
      expect(differing, isEmpty);

      // Guard the guard: if the independent table were itself wrong, the check
      // above would still pass. Scrambling one cell must be detected.
      independent[4][4] = (independent[4][4] + 1) % 9;
      expect(shipped[4][4], isNot(independent[4][4]));
    });
  });

  group('every supported size', () {
    // Java's switch accepts exactly 5..9; PuzzleDecoder independently rejects
    // sizes outside that window before ever calling in.
    const sizes = <int>[5, 6, 7, 8, 9];

    test('is size x size', () {
      for (final size in sizes) {
        final areas = standardAreas(size);
        expect(areas.length, size, reason: 'row count for $size');
        for (final row in areas) {
          expect(row.length, size, reason: 'row length for $size');
        }
      }
    });

    test('uses only codes 0..size-1', () {
      // Puzzle.checkParameters (Java lines 262-278) rejects an out-of-range
      // area code, so a bad table would throw at decode time rather than
      // mis-solve. Assert it here where the cause is visible.
      for (final size in sizes) {
        for (final row in standardAreas(size)) {
          for (final code in row) {
            expect(
              code,
              inInclusiveRange(0, size - 1),
              reason: 'code $code in a $size board',
            );
          }
        }
      }
    });

    test('gives every area exactly size cells', () {
      // The real guard on the two jigsaw tables (5 and 7), where the layout
      // cannot be checked against box arithmetic. A mistyped digit moves one
      // cell between areas and shows up here as 6/8 instead of 7/7.
      for (final size in sizes) {
        final counts = List<int>.filled(size, 0);
        for (final row in standardAreas(size)) {
          for (final code in row) {
            counts[code]++;
          }
        }
        expect(counts, List<int>.filled(size, size), reason: 'size $size');
      }
    });

    test('gives every area a 4-connected shape', () {
      // True of all five Java tables including the odd plus-shaped area 3 of
      // STD_7. A transposition typo can preserve the cell counts above while
      // splitting an area in two, and a disconnected "region" is not a sudoku
      // region -- this is the second half of the transcription check.
      for (final size in sizes) {
        final areas = standardAreas(size);
        for (var code = 0; code < size; code++) {
          final cells = <(int, int)>{
            for (var row = 0; row < size; row++)
              for (var col = 0; col < size; col++)
                if (areas[row][col] == code) (row, col),
          };
          final reached = <(int, int)>{cells.first};
          final queue = <(int, int)>[cells.first];
          while (queue.isNotEmpty) {
            final (r, c) = queue.removeLast();
            for (final n in [(r - 1, c), (r + 1, c), (r, c - 1), (r, c + 1)]) {
              if (cells.contains(n) && reached.add(n)) queue.add(n);
            }
          }
          expect(
            reached.length,
            cells.length,
            reason: 'area $code of size $size is disconnected',
          );
        }
      }
    });
  });

  group('unsupported sizes', () {
    // Java line 61-62: the switch default throws a message-less
    // IllegalArgumentException. R-13 -- no wrapper type, ArgumentError is the
    // direct equivalent. 4 and 10 are the interesting neighbours: a port that
    // computed boxes from sqrt(size) would happily answer for 4 and 16.
    for (final size in <int>[-1, 0, 1, 4, 10, 16, 81]) {
      test('$size throws', () {
        expect(() => standardAreas(size), throwsArgumentError);
      });
    }
  });

  group('aliasing', () {
    test('returns the same instance on every call, as Java does', () {
      // Java hands out its shared static int[][] uncopied and Puzzle stores the
      // reference without copying (Puzzle.java:73). Preserved so no caller can
      // come to depend on getting a fresh copy.
      //
      // This asserts OUTER identity only. Inner-row identity does NOT match
      // Java -- see the D-02 test below.
      expect(identical(standardAreas(9), standardAreas(9)), isTrue);
    });

    test('is unmodifiable -- a RECORDED DIVERGENCE from Java, see D-01', () {
      // Java PERMITS this write. StandardAreas hands out its shared static
      // int[][] and Puzzle.java:73 stores the reference uncopied, so a stray
      // write corrupts STD_9 for the rest of the process and every later
      // standard puzzle decodes against the corrupted table -- at which point
      // AndokuPuzzle.isSquiggly (AndokuPuzzle.java:1369-1380) starts reporting
      // standard puzzles as SQUIGGLY.
      //
      // Throwing instead is a deliberate choice, recorded as D-01 in
      // DIVERGENCES.md. It cannot diverge from the oracle because nothing
      // in the Java writes through the table -- every areaCodes use in
      // Puzzle.java (40, 52, 64-73, 95, 226, 262-273) is a read or a length
      // check. This test pins OUR choice, not Java's behaviour; that is why it
      // names the divergence rather than claiming fidelity.
      expect(() => standardAreas(9)[0][0] = 7, throwsUnsupportedError);
      expect(() => standardAreas(9).removeLast(), throwsUnsupportedError);
    });

    test('const canonicalization collapses rows -- RECORDED DIVERGENCE D-02', () {
      // Java allocates nine distinct int[9] rows, so STD_9[0] != STD_9[1].
      // Dart canonicalizes equal const lists, so the three distinct row
      // patterns are three objects and rows 0..2 are literally the same list.
      //
      // Unobservable today: nothing keys on row identity and the trace prints
      // values. It becomes observable the moment anything does per-row identity
      // work -- a Set<List<int>>, a copy-on-write grid, an allocation count.
      // Pinned here so that change shows up as a failing test rather than as a
      // trace diff 45,100 lines long.
      final std9 = standardAreas(9);
      expect(
        identical(std9[0], std9[1]),
        isTrue,
        reason: 'D-02: rows 0-2 share one canonical const list',
      );
      expect(
        identical(std9[0], std9[3]),
        isFalse,
        reason: 'different patterns remain different objects',
      );
      expect(
        {for (final row in std9) identityHashCode(row)}.length,
        3,
        reason: 'Java would have 9 distinct row objects here',
      );
    });
  });
}
