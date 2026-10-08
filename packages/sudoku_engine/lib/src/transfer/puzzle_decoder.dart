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
// Translation rules applied: R-07, R-08, R-10, R-13

/// Decoder for the `.adk` puzzle record format.
///
/// One record, pipe-separated, is the whole format:
///
/// ```text
/// <size*size clue chars>|<size*size area-id chars>|<extra-region code>
/// ```
///
/// Fields 2 and 3 are optional. Field 2 is present only for squiggly
/// (irregular-region) puzzles; when absent the standard boxes from
/// [standardAreas] are used. Field 3 is one letter selecting an extra-region
/// family (`X`, `H`, `P`, `C`, `D`, `W`); when absent there are no extra
/// regions.
///
/// Java counterpart: `com.googlecode.andoku.transfer.PuzzleDecoder`. That class
/// also carries an unused `import android.util.Log` — there is no logging in it,
/// so the file is genuinely Android-free and translates without an injected
/// context.
///
/// `PuzzleDecoder.decodeValues` (and with it `model.Solution`) is deliberately
/// **not** ported: its only callers were in the SQLite save/restore path, which
/// is out of scope (no save-data migration). During play the ground-truth
/// solution comes from the DLX solver, not from a stored value string.
library;

import '../model/geometry.dart';
import '../model/puzzle.dart';
import 'standard_areas.dart';

/// Splits on `|` the way Java's `String.split("\\|")` does — **not** the way
/// Dart's `String.split('|')` does (R-07).
///
/// Two behaviours of `java.lang.String.split(regex)` with the default limit of
/// `0` have to be reproduced, and they are separate things:
///
/// 1. **Trailing empty fields are dropped.** `"a|b|".split("\\|")` is
///    `["a", "b"]` in Java but `["a", "b", ""]` in Dart. The JDK trims them in
///    the `if (limit == 0) while (resultSize > 0 && ...isEmpty()) resultSize--;`
///    tail of `String.split`/`Pattern.split`.
/// 2. **A no-match input is returned whole, untrimmed.** Both the JDK's
///    single-char fast path (`if (off == 0) return new String[]{this};`) and
///    `Pattern.split` (`if (index == 0) return new String[]{input.toString()};`)
///    return early *before* the trimming step. So `"".split("\\|")` is `[""]`
///    (length 1), even though `""` is itself a trailing empty field. Only an
///    input made entirely of separators — `"|"`, `"||"` — yields a
///    **zero-length** array, which is what `PuzzleDecoder.decode`'s
///    `if (parts.length == 0) throw` is actually guarding against.
///
/// Rule 2 is the one a naive "strip trailing empties" helper gets wrong; the
/// throwaway Dart twin in `difftest-harness/oracle-dart/oracle.dart` does get it
/// wrong and returns `[]` for `""`. See the port report — for `decodePuzzle` the
/// difference is unobservable (both paths end in an `ArgumentError`), but this
/// function is public API and other record formats are built by string
/// concatenation, so it is faithful here rather than at the call site.
List<String> javaSplitPipe(String s) {
  // Java's no-match early return, which skips the trailing-empty trim.
  if (!s.contains('|')) return <String>[s];

  final List<String> parts = s.split('|');
  int end = parts.length;
  while (end > 0 && parts[end - 1].isEmpty) {
    end--;
  }
  return parts.sublist(0, end);
}

/// Decodes one `.adk` record into a [Puzzle].
///
/// ## The caller owns line splitting, and owns the carriage return (R-08)
///
/// [encoded] must be **one record with no line terminator of any kind**. The
/// engine cannot read files (no `dart:io` by contract), so there is no place
/// inside it where a line ending could be stripped; `decodePuzzle` therefore
/// treats every character it is given as part of the record.
///
/// This matters because all 96 shipped `.adk` files are CRLF and 22 of them have
/// no trailing newline, so **every record's final byte is `\r`**. Java never
/// sees it: `AssetsPuzzleSource.loadEntries` reads through a
/// `BufferedReader.readLine()`, which consumes `\n`, `\r` and `\r\n` alike and
/// returns the line without its terminator. Dart's `LineSplitter` and
/// `split('\n')` do not — they leave the `\r` attached.
///
/// An unstripped `\r` does not fail loudly. Field 3 becomes `"X\r"`, which
/// matches none of the extra-region letters, and the record dies in
/// `ArgumentError('Unsupported extra regions: X\r')` — or, for a record with no
/// field 3, the `\r` lands on the clue string and makes its length 82 so the
/// `size * size` check rejects it. Either way all 36,000 extra-region puzzles
/// break at once, which is why this is stated here rather than left implicit.
///
/// Callers must split with `RegExp(r'\r?\n')` (or `LineSplitter`, which also
/// handles a lone `\r`), then skip empty lines and lines starting with `#`,
/// mirroring `AssetsPuzzleSource.loadEntries`. Note that `#` is not only the GPL
/// header: the corpus also contains commented-out puzzle records (e.g. 101 of
/// them in `standard_x_1.adk`), and they must stay skipped or the puzzle
/// numbering shifts.
///
/// ## Values are zero-based
///
/// Returned cell values are `0..size-1`, matching Java: `decode('1')` is `0`.
/// Cells whose clue char is `' '` or `'.'` are left at [Puzzle.undefined].
///
/// Throws [ArgumentError] on any malformed record, at the same point and with
/// the same message as the Java original — the differential harness traces the
/// exception message, so an early `throw` is observable behaviour.
Puzzle decodePuzzle(String encoded) {
  final List<String> parts = javaSplitPipe(encoded);
  if (parts.isEmpty) {
    // Reachable only for an all-separators input such as "|" — see javaSplitPipe.
    throw ArgumentError();
  }

  final String clues = parts[0];
  final String areas = parts.length > 1 ? parts[1] : '';
  final String extra = parts.length > 2 ? parts[2] : '';

  // Java: `int size = (int) Math.sqrt(clues.length());` — a truncating cast, so
  // this is floor(sqrt(n)) and the following equality is what rejects a clue
  // string whose length is not a perfect square. Computed with integers here
  // (R-10) to keep it independent of double rounding; the two agree for every
  // length a record can plausibly have.
  final int size = _floorSqrt(clues.length);
  if (clues.length != size * size) throw ArgumentError();

  if (size < 5 || size > 9) throw ArgumentError();

  // Order matters: a record with both a bad area string and a bad extra code
  // must fail on the areas, because that is the order Java evaluates them in
  // and the harness compares the exception message.
  final List<List<int>> areaCodes = _parseAreaCodes(size, areas);
  final List<ExtraRegion> extraRegions = _parseExtraRegions(size, extra);

  final Puzzle puzzle = Puzzle(areaCodes, extraRegions);

  int idx = 0;
  for (int row = 0; row < size; row++) {
    for (int col = 0; col < size; col++) {
      final int clueChar = clues.codeUnitAt(idx++);
      if (clueChar == _space || clueChar == _dot) continue;

      final int clue = _decodeChar(clueChar);
      // Java re-checks the range here even though _decodeChar already rejects
      // unknown characters, because the character alphabet is wider than any
      // supported grid size. This check is what actually rejects '0' and
      // 'A'-'Z'/'a'-'z' — see _decodeChar.
      if (clue < 0 || clue >= size) throw ArgumentError();

      puzzle.set(row, col, clue);
    }
  }

  return puzzle;
}

/// Java: `PuzzleDecoder.parseAreaCodes`.
///
/// An empty field 2 means "standard boxes", which is how every non-squiggly
/// record in the corpus is stored — the field is simply absent.
List<List<int>> _parseAreaCodes(int size, String areas) {
  if (areas.isEmpty) return standardAreas(size);

  if (areas.length != size * size) throw ArgumentError();

  int idx = 0;
  final List<List<int>> areaCodes = <List<int>>[];
  for (int row = 0; row < size; row++) {
    final List<int> rowCodes = List<int>.filled(size, 0);
    for (int col = 0; col < size; col++) {
      final int areaCode = _decodeChar(areas.codeUnitAt(idx++));
      if (areaCode < 0 || areaCode >= size) throw ArgumentError();
      rowCodes[col] = areaCode;
    }
    areaCodes.add(rowCodes);
  }

  return areaCodes;
}

/// Java: `PuzzleDecoder.parseExtraRegions`.
///
/// The `if/else if` chain is kept in Java's order. It is a chain of
/// `extra.equalsIgnoreCase("X")` calls, so a lowercase code is accepted even
/// though the shipped corpus only ever writes uppercase. See
/// [_equalsIgnoreCaseAsciiLetter] for why case folding is done by hand.
List<ExtraRegion> _parseExtraRegions(int size, String extra) {
  if (extra.isEmpty) return ExtraRegions.none();
  if (_equalsIgnoreCaseAsciiLetter(extra, 'X')) return ExtraRegions.x(size);
  if (_equalsIgnoreCaseAsciiLetter(extra, 'H')) return ExtraRegions.hyper(size);
  if (_equalsIgnoreCaseAsciiLetter(extra, 'P')) {
    return ExtraRegions.percent(size);
  }
  if (_equalsIgnoreCaseAsciiLetter(extra, 'C')) return ExtraRegions.color(size);
  if (_equalsIgnoreCaseAsciiLetter(extra, 'D')) return ExtraRegions.dot(size);
  if (_equalsIgnoreCaseAsciiLetter(extra, 'W')) return ExtraRegions.wheel(size);
  // Message text is part of the trace, so it is byte-identical to Java's
  // `"Unsupported extra regions: " + extra`. A stray carriage return shows up
  // in it, which is the fastest way to diagnose the R-08 mistake.
  throw ArgumentError('Unsupported extra regions: $extra');
}

/// Java: `extra.equalsIgnoreCase(target)` where `target` is a single uppercase
/// ASCII letter.
///
/// `String.equalsIgnoreCase` requires equal *lengths* and then folds each pair
/// of characters, so it is not the same as comparing `toUpperCase()` results —
/// Dart's `toUpperCase` can change a string's length (`'ß'` becomes `'SS'`) and
/// applies full Unicode mappings. Restricting the comparison to "length 1, and
/// the code unit is the target's upper or lower ASCII form" is exact for the six
/// targets used here: no non-ASCII character case-folds onto `C`, `D`, `H`, `P`,
/// `W` or `X` (the near-miss, U+212A KELVIN SIGN, folds to `k`).
///
/// The throwaway twin uses `extra.toUpperCase()` in a `switch` instead. For the
/// shipped corpus the two cannot disagree, but this form is the one that matches
/// the Java semantics.
bool _equalsIgnoreCaseAsciiLetter(String s, String upperTarget) {
  assert(upperTarget.length == 1);
  if (s.length != 1) return false;
  final int c = s.codeUnitAt(0);
  final int upper = upperTarget.codeUnitAt(0);
  return c == upper || c == upper + 0x20; // 'X' or 'x'
}

/// Java: `PuzzleDecoder.decode(char)`.
///
/// `'1'..'9'` map to `0..8`; everything else maps to `>= 9` or throws:
///
/// * `'0'` returns 9 — the format's way of writing "ten" in a grid larger than
///   9, inherited from Andoku.
/// * `'A'..'Z'` and `'a'..'z'` return `10..35` (Java computes
///   `encodedValue + 10 - 'A'`, i.e. `'A'` is 10, not 11).
///
/// **Both of those branches are unreachable as *valid* values.** Every caller
/// immediately rejects `value >= size`, and `decodePuzzle` has already clamped
/// `size` to `5..9`, so any result of 9 or more throws. They are vestigial
/// support for hexadecimal 16x16 boards that this build cannot express. Kept
/// anyway because removing them would move the throw from the caller's range
/// check into here, and the shape of the failure is traced.
///
/// What the corpus actually contains, measured over all 45,166 live records:
/// field 1 uses only `.` and `1`-`9`, field 2 only `1`-`9`, field 3 only the
/// uppercase letters `C D H P W X`. Not one `'0'`, no lowercase, and no `' '`
/// (the space clue char Java also accepts). So the `'0'`/alpha branches and the
/// case-insensitive extra matching are dead weight in practice — they are
/// reproduced because a hand-edited record or a future corpus could hit them.
int _decodeChar(int encodedValue) {
  if (encodedValue >= _char1 && encodedValue <= _char9) {
    return encodedValue - _char1;
  } else if (encodedValue == _char0) {
    return 9;
  } else if (encodedValue >= _charUpperA && encodedValue <= _charUpperZ) {
    return encodedValue + 10 - _charUpperA;
  } else if (encodedValue >= _charLowerA && encodedValue <= _charLowerZ) {
    return encodedValue + 10 - _charLowerA;
  } else {
    throw ArgumentError();
  }
}

/// `floor(sqrt(n))` for `n >= 0`, reproducing Java's `(int) Math.sqrt(n)`.
int _floorSqrt(int n) {
  int s = 0;
  while ((s + 1) * (s + 1) <= n) {
    s++;
  }
  return s;
}

const int _space = 0x20; // ' '
const int _dot = 0x2E; // '.'
const int _char0 = 0x30; // '0'
const int _char1 = 0x31; // '1'
const int _char9 = 0x39; // '9'
const int _charUpperA = 0x41; // 'A'
const int _charUpperZ = 0x5A; // 'Z'
const int _charLowerA = 0x61; // 'a'
const int _charLowerZ = 0x7A; // 'z'
