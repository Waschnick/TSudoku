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
// Ported from: app/src/main/java/com/googlecode/andoku/transfer/PuzzleDecoder.java
// Translation rules applied: R-07, R-08

import 'package:sudoku_engine/src/model/puzzle.dart';
import 'package:sudoku_engine/src/transfer/puzzle_decoder.dart';
import 'package:sudoku_engine/src/transfer/standard_areas.dart';
import 'package:test/test.dart';

/// Records lifted verbatim from the shipped corpus, so a divergence here is a
/// divergence against something the player actually plays.
///
/// `standardX` is the `<81 clues>||X` shape — 18,000 of the 45,166 live records
/// look like this, with field 2 present but empty.
const String standardPlain =
    '.9.5...616....7..3....9.72...5.8....7.3...2.5....1.6...41.2....3..1....985...9.3.';
const String standardX =
    '39....4.6..1549.7.........297..8..4..532.681..1..3..697.........3.6729..8.9....25||X';
const String squigglyX =
    '.428.9.57.1..6..9..9........6.3..724..5...8..289..4.7........6..5..7..8.82.9.731.'
    '|999998888996988877696687877666557777665555533444455333442423313442221311222211111|X';
const String squigglyPlain =
    '.65...1.3...3...4...4.8...7.89...675.4.7.5.9.718...32.9...6.7...9...1...1.3...26.'
    '|999988877999988887695588777666557747666654444363355444333225514322221111332221111';

void main() {
  group('javaSplitPipe (R-07)', () {
    test('drops trailing empty fields, as Java String.split does', () {
      // Java: "a|b|".split("\\|") -> ["a", "b"].  Dart's split keeps the "".
      expect(javaSplitPipe('a|b|'), <String>['a', 'b']);
      expect(javaSplitPipe('a|b||'), <String>['a', 'b']);
      expect(javaSplitPipe('a||'), <String>['a']);
    });

    test('keeps interior empty fields - the <clues>||X shape', () {
      // 18,000 live records look like this. The empty field 2 is not trailing,
      // so neither Java nor Dart removes it.
      expect(javaSplitPipe('a||X'), <String>['a', '', 'X']);
      expect(javaSplitPipe('|b|X'), <String>['', 'b', 'X']);
    });

    test('a no-match input is returned whole and NOT trimmed', () {
      // The JDK's `if (off == 0) return new String[]{this};` fast path returns
      // before the trailing-empty trim, so "" yields [""], length 1 - not [].
      // This is the case the throwaway oracle twin gets wrong.
      expect(javaSplitPipe(''), <String>['']);
      expect(javaSplitPipe('abc'), <String>['abc']);
    });

    test('an all-separators input yields a zero-length list', () {
      // This, and only this, is what PuzzleDecoder's `parts.length == 0` guard
      // can ever see.
      expect(javaSplitPipe('|'), isEmpty);
      expect(javaSplitPipe('||'), isEmpty);
      expect(javaSplitPipe('|||'), isEmpty);
    });

    test('an all-separators record throws, reaching the length-0 guard', () {
      expect(() => decodePuzzle('|'), throwsArgumentError);
    });
  });

  group('CRLF (R-08) - the caller must strip the carriage return', () {
    test(
      'a trailing \\r makes an X record mistype, with \\r in the message',
      () {
        // Every record in the corpus ends in \r (all 96 files are CRLF and 22
        // have no final newline). readLine() strips it in Java; LineSplitter in
        // Dart does too, but split('\n') does not. If one survives, field 3 is
        // "X\r" and matches no extra-region letter.
        ArgumentError? caught;
        try {
          decodePuzzle('$standardX\r');
        } on ArgumentError catch (e) {
          caught = e;
        }
        expect(caught, isNotNull);
        expect(caught!.message, 'Unsupported extra regions: X\r');
      },
    );

    test(
      'a trailing \\r on a record with no field 3 breaks the size check',
      () {
        // Here the \r lands on the clue string, making it 82 characters, so the
        // failure is the size*size check rather than the extra-region lookup -
        // a different symptom for the same mistake.
        expect(() => decodePuzzle('$standardPlain\r'), throwsArgumentError);
      },
    );

    test('a \\r-stripped record parses identically to a bare-\\n one', () {
      // R-08 requires this assertion explicitly.
      final List<String> viaRegExp = '$standardX\r\n'.split(RegExp(r'\r?\n'));
      final List<String> viaLf = '$standardX\n'.split(RegExp(r'\r?\n'));
      expect(viaRegExp.first, viaLf.first);

      final Puzzle fromCrlf = decodePuzzle(viaRegExp.first);
      final Puzzle fromLf = decodePuzzle(viaLf.first);
      expect(fromCrlf.toString(), fromLf.toString());
      expect(fromCrlf.extraRegions.length, fromLf.extraRegions.length);
    });
  });

  group('field layout', () {
    test('an absent field 2 means standard areas, not an error', () {
      final Puzzle p = decodePuzzle(standardPlain);
      expect(p.size, 9);
      expect(p.extraRegions, isEmpty);
      for (int r = 0; r < 9; r++) {
        for (int c = 0; c < 9; c++) {
          expect(p.getAreaCode(r, c), standardAreas(9)[r][c]);
        }
      }
    });

    test(
      'an empty field 2 with a field 3 present also means standard areas',
      () {
        final Puzzle p = decodePuzzle(standardX);
        expect(
          p.extraRegions.length,
          2,
          reason: 'X contributes both diagonals',
        );
        expect(p.getAreaCode(0, 0), 0);
        expect(p.getAreaCode(4, 4), 4);
        expect(p.getAreaCode(8, 8), 8);
      },
    );

    test('field 2 overrides the standard boxes for squiggly records', () {
      final Puzzle p = decodePuzzle(squigglyX);
      // Field 2 of this record starts "999998888...", and the char decoder is
      // zero-based: '9' -> 8, '8' -> 7.
      expect(p.getAreaCode(0, 0), 8);
      expect(p.getAreaCode(0, 5), 7);
      expect(p.extraRegions.length, 2);
    });

    test('a squiggly record with no field 3 has no extra regions', () {
      final Puzzle p = decodePuzzle(squigglyPlain);
      expect(p.extraRegions, isEmpty);
      expect(p.getAreaCode(0, 0), 8);
    });

    test(
      'a field 2 of the wrong length throws before field 3 is looked at',
      () {
        // Java evaluates parseAreaCodes before parseExtraRegions, so the areas
        // error wins and the message is null (traced as "-"), not the
        // "Unsupported extra regions" text.
        ArgumentError? caught;
        try {
          decodePuzzle('$standardPlain|123|ZZZ');
        } on ArgumentError catch (e) {
          caught = e;
        }
        expect(caught, isNotNull);
        expect(caught!.message, isNull);
      },
    );
  });

  group('clue decoding', () {
    test('values are zero-based: \'1\' decodes to 0', () {
      // standardPlain begins ".9.5", so (0,1) holds digit 9 -> value 8 and
      // (0,3) holds digit 5 -> value 4.
      final Puzzle p = decodePuzzle(standardPlain);
      expect(p.getValue(0, 0), Puzzle.undefined);
      expect(p.getValue(0, 1), 8);
      expect(p.getValue(0, 3), 4);
    });

    test('valuesCount equals the number of givens in field 1', () {
      final int givens = standardPlain
          .split('')
          .where((String ch) => ch != '.')
          .length;
      expect(decodePuzzle(standardPlain).valuesCount, givens);
    });

    test('a space clue char is an empty cell, exactly like a dot', () {
      // The corpus never writes a space, but Java accepts it. Keep both paths.
      final String spaced = standardPlain.replaceAll('.', ' ');
      final Puzzle fromDots = decodePuzzle(standardPlain);
      final Puzzle fromSpaces = decodePuzzle(spaced);
      for (int r = 0; r < 9; r++) {
        for (int c = 0; c < 9; c++) {
          expect(fromSpaces.getValue(r, c), fromDots.getValue(r, c));
        }
      }
    });

    test(
      "'0' is accepted by the char decoder but rejected by the range check",
      () {
        // Java's decode('0') returns 9, and every caller then rejects
        // `value >= size`. For a 9x9 board that is always. So '0' can never
        // appear in a valid record despite having its own branch - and indeed
        // the corpus contains none.
        final String withZero = '0${standardPlain.substring(1)}';
        expect(() => decodePuzzle(withZero), throwsArgumentError);
      },
    );

    test("'A' and 'a' decode to 10 and are therefore always out of range", () {
      // decode('A') == 'A' + 10 - 'A' == 10, not 11. Since size is clamped to
      // 5..9, the alpha branches are vestigial 16x16 support and can never
      // yield a valid value.
      expect(
        () => decodePuzzle('A${standardPlain.substring(1)}'),
        throwsArgumentError,
      );
      expect(
        () => decodePuzzle('a${standardPlain.substring(1)}'),
        throwsArgumentError,
      );
    });

    test('a character outside the alphabet throws', () {
      expect(
        () => decodePuzzle('*${standardPlain.substring(1)}'),
        throwsArgumentError,
      );
    });
  });

  group('extra-region codes', () {
    test('every supported letter maps to the right region count', () {
      int countFor(String code) =>
          decodePuzzle('$standardPlain||$code').extraRegions.length;
      expect(countFor('X'), 2, reason: 'both diagonals');
      expect(countFor('H'), 4, reason: 'four inset boxes');
      expect(countFor('P'), 3, reason: 'two boxes plus the anti-diagonal');
      expect(countFor('C'), 9, reason: 'nine colour groups');
      expect(countFor('D'), 1, reason: 'one region of nine box centres');
      expect(countFor('W'), 1, reason: 'one nine-cell pinwheel');
    });

    test(
      'DOT and WHEEL are told apart by their first cell, not their count',
      () {
        // Both yield exactly one extra region; AndokuPuzzle types them by the
        // first position (DOT starts at (1,1), WHEEL at (4,1)). A decoder that
        // mixed the two up would pass a count-only test.
        final dotFirst = decodePuzzle('$standardPlain||D')
            .extraRegions
            .first
            .positions
            .first;
        final wheelFirst = decodePuzzle('$standardPlain||W')
            .extraRegions
            .first
            .positions
            .first;
        expect(dotFirst.row, 1);
        expect(dotFirst.col, 1);
        expect(wheelFirst.row, 4);
        expect(wheelFirst.col, 1);
      },
    );

    test('matching is case-insensitive, mirroring equalsIgnoreCase', () {
      // The corpus writes only uppercase, so this branch is never exercised in
      // production - but DbPuzzleSource concatenates whatever the database
      // holds, so it stays faithful.
      expect(decodePuzzle('$standardPlain||x').extraRegions.length, 2);
      expect(decodePuzzle('$standardPlain||w').extraRegions.length, 1);
    });

    test('a multi-character code never matches, even if it starts right', () {
      // equalsIgnoreCase compares lengths first. "XX" and "X " must both fail,
      // which is also what stops "X\r" from being quietly accepted.
      for (final String bad in <String>['XX', 'X ', ' X', 'Q']) {
        ArgumentError? caught;
        try {
          decodePuzzle('$standardPlain||$bad');
        } on ArgumentError catch (e) {
          caught = e;
        }
        expect(caught, isNotNull, reason: 'code "$bad" must be rejected');
        expect(caught!.message, 'Unsupported extra regions: $bad');
      }
    });
  });

  group('size validation', () {
    test('a clue field whose length is not a perfect square throws', () {
      expect(
        () => decodePuzzle(standardPlain.substring(0, 80)),
        throwsArgumentError,
      );
    });

    test('a perfect square below 5 or above 9 throws', () {
      expect(() => decodePuzzle('.' * 16), throwsArgumentError); // size 4
      expect(() => decodePuzzle('.' * 100), throwsArgumentError); // size 10
    });

    test('the empty record throws via the size check, not the split guard', () {
      // javaSplitPipe('') is [''], so parts is non-empty; size becomes 0,
      // 0 == 0 * 0 passes, and `size < 5` is what rejects it. Same exception
      // as Java, reached by the same route.
      expect(() => decodePuzzle(''), throwsArgumentError);
    });

    test('size 5 is supported end to end', () {
      // No shipped record is anything but 9x9, so this is the only coverage the
      // 5..8 standard-area tables will ever get.
      final Puzzle p = decodePuzzle('${'.' * 24}1');
      expect(p.size, 5);
      expect(p.getValue(4, 4), 0);
      expect(p.getAreaCode(0, 0), standardAreas(5)[0][0]);
    });

    test('a non-9 board rejects the 9x9-only extra families', () {
      // ExtraRegions.hyper/percent/color throw for size != 9; X does not.
      expect(decodePuzzle('${'.' * 25}||X').extraRegions.length, 2);
      expect(() => decodePuzzle('${'.' * 25}||H'), throwsArgumentError);
      expect(() => decodePuzzle('${'.' * 25}||P'), throwsArgumentError);
      expect(() => decodePuzzle('${'.' * 25}||C'), throwsArgumentError);
    });
  });
}
