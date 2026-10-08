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
// Ported from: app/src/main/java/com/googlecode/andoku/model/PuzzleType.java
// Ported from: app/src/main/java/com/googlecode/andoku/model/Difficulty.java
// Translation rules applied: R-13

import 'package:sudoku_engine/src/model/puzzle_type.dart';
import 'package:test/test.dart';

/// The trace compares `typeOrd=` and `diffOrd=` against Java's `ordinal()`, so
/// these tests pin the *numbers*, not just the set of members. They are written
/// as literal ordinal-to-name tables so that a reordering shows up as a failing
/// assertion naming both the ordinal and the Java constant, rather than as a
/// 45,166-line trace diff.
void main() {
  group('PuzzleType', () {
    // Transcribed from PuzzleType.java:27-40, which carries the comment
    // "do not change order of constants - used in db".
    const javaOrder = <int, String>{
      0: 'STANDARD',
      1: 'STANDARD_X',
      2: 'STANDARD_HYPER',
      3: 'SQUIGGLY',
      4: 'SQUIGGLY_X',
      5: 'SQUIGGLY_HYPER',
      6: 'STANDARD_PERCENT',
      7: 'SQUIGGLY_PERCENT',
      8: 'STANDARD_COLOR',
      9: 'SQUIGGLY_COLOR',
      10: 'STANDARD_DOT',
      11: 'STANDARD_WHEEL',
      12: 'SQUIGGLY_DOT',
      13: 'SQUIGGLY_WHEEL',
    };

    test('has exactly 14 constants', () {
      // A 15th variant would silently shift nothing, but a *missing* one shifts
      // every later ordinal. Pin the count so that cannot happen unnoticed.
      expect(PuzzleType.values, hasLength(14));
      expect(javaOrder, hasLength(14));
    });

    test('every ordinal maps to the Java constant name', () {
      for (final entry in javaOrder.entries) {
        final type = PuzzleType.values[entry.key];
        expect(
          type.javaName,
          entry.value,
          reason:
              'ordinal ${entry.key} must be ${entry.value}, '
              'got ${type.javaName} (Dart ${type.name})',
        );
        expect(type.index, entry.key);
      }
    });

    test('the squiggly trio sits at ordinals 3..5, not grouped at the end', () {
      // The most likely "tidying" mistake: grouping all STANDARD_* first. That
      // compiles, analyses clean, and breaks every trace line. CLAUDE.md's prose
      // summary of the variants lists them in the grouped order; the enum does
      // not, and the enum wins.
      expect(PuzzleType.squiggly.index, 3);
      expect(PuzzleType.squigglyX.index, 4);
      expect(PuzzleType.squigglyHyper.index, 5);
      expect(PuzzleType.standardPercent.index, 6);
    });

    test('DOT/WHEEL pairs are interleaved the way Java appended them', () {
      // STANDARD_DOT, STANDARD_WHEEL, then SQUIGGLY_DOT, SQUIGGLY_WHEEL -- not
      // DOT, DOT, WHEEL, WHEEL.
      expect(PuzzleType.values.sublist(10).map((t) => t.javaName), [
        'STANDARD_DOT',
        'STANDARD_WHEEL',
        'SQUIGGLY_DOT',
        'SQUIGGLY_WHEEL',
      ]);
    });

    test('declaration order is not alphabetical', () {
      // Guards against an IDE "sort members" action, which would pass analysis.
      final names = PuzzleType.values.map((t) => t.javaName).toList();
      final sorted = [...names]..sort();
      expect(names, isNot(equals(sorted)));
    });

    test('javaName is unique and SCREAMING_SNAKE', () {
      final names = PuzzleType.values.map((t) => t.javaName).toList();
      expect(names.toSet(), hasLength(names.length));
      for (final name in names) {
        expect(name, matches(RegExp(r'^[A-Z]+(_[A-Z]+)*$')));
      }
    });

    test('forOrdinal round-trips every constant', () {
      // Reproduces PuzzleType.forOrdinal (PuzzleType.java:42), the path by which
      // a saved game's stored integer becomes a variant again.
      for (final type in PuzzleType.values) {
        expect(PuzzleType.forOrdinal(type.index), same(type));
      }
    });

    test('forOrdinal throws on an out-of-range ordinal, as Java does', () {
      // Java indexes values() unguarded -> ArrayIndexOutOfBoundsException.
      // Dart's unguarded index -> RangeError. Deliberately no clamping and no
      // fallback constant: adding one would hide corrupt save data.
      expect(() => PuzzleType.forOrdinal(-1), throwsA(isA<RangeError>()));
      expect(() => PuzzleType.forOrdinal(14), throwsA(isA<RangeError>()));
    });
  });

  group('Difficulty', () {
    // Transcribed from Difficulty.java:26.
    const javaOrder = <int, String>{
      0: 'EASY',
      1: 'MEDIUM',
      2: 'CHALLENGING',
      3: 'HARD',
      4: 'FIENDISH',
      5: 'UNKNOWN',
    };

    test('has exactly 6 constants in the Java order', () {
      expect(Difficulty.values, hasLength(6));
      for (final entry in javaOrder.entries) {
        final difficulty = Difficulty.values[entry.key];
        expect(
          difficulty.javaName,
          entry.value,
          reason:
              'ordinal ${entry.key} must be ${entry.value}, '
              'got ${difficulty.javaName} (Dart ${difficulty.name})',
        );
        expect(difficulty.index, entry.key);
      }
    });

    test('declaration order is not alphabetical', () {
      final names = Difficulty.values.map((d) => d.javaName).toList();
      final sorted = [...names]..sort();
      expect(names, isNot(equals(sorted)));
    });

    test('asset folder suffix 1..5 maps to EASY..FIENDISH', () {
      // Reproduces AssetsPuzzleSource.getDifficulty() (AssetsPuzzleSource.java:
      // 102-108): charAt(len-1) - '0' - 1, then Difficulty.values()[...].
      // This arithmetic is why the enum order is a correctness requirement and
      // not a label list.
      //
      // The formula under test is difficultyFromFolderName in lib/. An earlier
      // version of this test declared its own local copy of the arithmetic and
      // asserted against that, which is a closed loop: it would have stayed
      // green while the shipped code had the `- 1` missing and every EASY
      // folder decoded as MEDIUM.
      expect(difficultyFromFolderName('standard_n_1'), Difficulty.easy);
      expect(difficultyFromFolderName('standard_n_2'), Difficulty.medium);
      expect(difficultyFromFolderName('squiggly_x_3'), Difficulty.challenging);
      expect(difficultyFromFolderName('standard_h_4'), Difficulty.hard);
      expect(difficultyFromFolderName('squiggly_p_5'), Difficulty.fiendish);

      // Every folder name in the shipped corpus must resolve. This is the
      // assertion that would have caught a missing `- 1`.
      expect(difficultyFromFolderName('handcrafted_n_1'), Difficulty.easy);
    });

    test('UNKNOWN is ordinal 5 and unreachable from the asset corpus', () {
      // The folder formula accepts only 1..5, so UNKNOWN can never come out of
      // an .adk folder name. It is reachable only as PuzzleInfo.Builder's
      // default (PuzzleInfo.java:49). Any code that derives difficulty from a
      // folder and still sees UNKNOWN has a bug upstream of the enum.
      expect(Difficulty.unknown.index, 5);
      // Suffix 6 would be ordinal 5 == UNKNOWN, and the Java range check
      // rejects it rather than letting UNKNOWN through. Asserted against the
      // shipped function, not against a local re-derivation of it.
      expect(
        () => difficultyFromFolderName('standard_n_6'),
        throwsA(isA<StateError>()),
      );
      expect(
        () => difficultyFromFolderName('standard_n_0'),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('toString matches Java Enum.toString', () {
    // Java's Enum.toString() returns name(), so interpolating an enum yields the
    // SCREAMING_SNAKE spelling. Dart's default would yield 'PuzzleType.standardX'.
    // Live Java code interpolates a Difficulty directly (AndokuActivity.java:4752,
    // 4754, 4773, 4779, 4879), and every trace line carries type= and diff=, so a
    // default toString is worth 45,100 diverging lines.
    test('every PuzzleType stringifies to its Java constant name', () {
      for (final type in PuzzleType.values) {
        expect('$type', type.javaName);
      }
      expect('${PuzzleType.standardX}', 'STANDARD_X');
    });

    test('every Difficulty stringifies to its Java constant name', () {
      for (final difficulty in Difficulty.values) {
        expect('$difficulty', difficulty.javaName);
      }
      expect('${Difficulty.easy}', 'EASY');
    });

    test('Dart .name is still the Dart identifier -- do not reach for it', () {
      // The toString override does NOT fix .name. Pinned so nobody "simplifies"
      // javaName away in favour of it.
      expect(PuzzleType.standardX.name, 'standardX');
      expect(PuzzleType.standardX.javaName, 'STANDARD_X');
    });
  });
}
