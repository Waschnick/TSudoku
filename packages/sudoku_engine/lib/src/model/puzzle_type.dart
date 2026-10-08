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

/// The 14 puzzle variants, in the Java declaration order.
///
/// `PuzzleType.java:26` carries the comment `// do not change order of constants
/// - used in db`, and the order really is load-bearing twice over:
///
///  * `PuzzleType.forOrdinal` (`PuzzleType.java:42`) maps a stored integer back to
///    a constant, so `ResumeGameActivity.java:170` reads saved games by ordinal.
///  * the differential trace prints both `type.name()` and `type.ordinal()`
///    (`PUZ ... type=... typeOrd=...`), so a reordered or alphabetised enum passes
///    `dart analyze` and then fails every single trace line.
///
/// The order below is therefore transcribed verbatim and pinned by
/// `test/puzzle_type_test.dart`. Note that it is *not* grouped
/// standard-then-squiggly: `SQUIGGLY`, `SQUIGGLY_X` and `SQUIGGLY_HYPER` sit at
/// ordinals 3-5, in the middle of the standard variants, because PERCENT, COLOR,
/// DOT and WHEEL were appended in pairs as later versions added them. Any
/// "tidier" grouping (including the one summarised in the repo's CLAUDE.md) is
/// wrong for this enum.
enum PuzzleType {
  /// Java `STANDARD` (ordinal 0) - plain 3x3 boxes, no extra regions.
  standard,

  /// Java `STANDARD_X` (ordinal 1) - the two main diagonals are extra regions.
  standardX,

  /// Java `STANDARD_HYPER` (ordinal 2) - four offset "hyper" boxes.
  standardHyper,

  /// Java `SQUIGGLY` (ordinal 3) - irregular regions, no extra regions.
  squiggly,

  /// Java `SQUIGGLY_X` (ordinal 4).
  squigglyX,

  /// Java `SQUIGGLY_HYPER` (ordinal 5).
  squigglyHyper,

  /// Java `STANDARD_PERCENT` (ordinal 6) - two hyper boxes plus a diagonal.
  standardPercent,

  /// Java `SQUIGGLY_PERCENT` (ordinal 7).
  squigglyPercent,

  /// Java `STANDARD_COLOR` (ordinal 8) - nine colour groups as extra regions.
  standardColor,

  /// Java `SQUIGGLY_COLOR` (ordinal 9).
  squigglyColor,

  /// Java `STANDARD_DOT` (ordinal 10) - one extra region holding the CENTRE CELL
  /// OF EVERY BOX: (1,1) (1,4) (1,7) (4,1) (4,4) (4,7) (7,1) (7,4) (7,7).
  ///
  /// Spread across the whole grid; it is not a region in the middle of the
  /// board. `ExtraRegions.java:85-92`.
  standardDot,

  /// Java `STANDARD_WHEEL` (ordinal 11) - one extra region shaped like a
  /// pinwheel: (4,1) (2,2) (6,2) (1,4) (4,4) (7,4) (2,6) (6,6) (4,7).
  /// `ExtraRegions.java:94-108`.
  ///
  /// DOT and WHEEL are indistinguishable by extra-region *count* - both have
  /// exactly one - so the classifier discriminates on the FIRST POSITION'S ROW:
  /// DOT starts at row 1, WHEEL at row 4. Get the two geometries the wrong way
  /// round and a whole `.adk` file mistypes without raising anything.
  standardWheel,

  /// Java `SQUIGGLY_DOT` (ordinal 12).
  ///
  /// Appended after `STANDARD_WHEEL` rather than next to `SQUIGGLY_COLOR` - the
  /// squiggly DOT/WHEEL pair shipped a version later than the standard pair.
  squigglyDot,

  /// Java `SQUIGGLY_WHEEL` (ordinal 13).
  squigglyWheel;

  /// The Java constant name, verbatim (`SCREAMING_SNAKE`).
  ///
  /// Reproduces `Enum.name()` for this enum. The trace emits this string, so it
  /// must never be derived from the Dart identifier by a general-purpose
  /// camel-to-snake transform: `standardX` would come out as `STANDARD_X` by
  /// luck, but any future constant with adjacent capitals or a digit would not.
  /// A `switch` (rather than a const list indexed by [index]) is deliberate: it
  /// is exhaustiveness-checked, so adding a constant becomes a compile error
  /// instead of a runtime `RangeError` in the trace writer.
  String get javaName => switch (this) {
    PuzzleType.standard => 'STANDARD',
    PuzzleType.standardX => 'STANDARD_X',
    PuzzleType.standardHyper => 'STANDARD_HYPER',
    PuzzleType.squiggly => 'SQUIGGLY',
    PuzzleType.squigglyX => 'SQUIGGLY_X',
    PuzzleType.squigglyHyper => 'SQUIGGLY_HYPER',
    PuzzleType.standardPercent => 'STANDARD_PERCENT',
    PuzzleType.squigglyPercent => 'SQUIGGLY_PERCENT',
    PuzzleType.standardColor => 'STANDARD_COLOR',
    PuzzleType.squigglyColor => 'SQUIGGLY_COLOR',
    PuzzleType.standardDot => 'STANDARD_DOT',
    PuzzleType.standardWheel => 'STANDARD_WHEEL',
    PuzzleType.squigglyDot => 'SQUIGGLY_DOT',
    PuzzleType.squigglyWheel => 'SQUIGGLY_WHEEL',
  };

  /// Java's `Enum.toString()`, which returns `name()`.
  ///
  /// Overridden rather than documented-around. Without it `'$type'` yields
  /// `PuzzleType.standardX` where Java yields `STANDARD_X` - a difference
  /// invisible to the compiler, invisible to `dart analyze --fatal-infos`, and
  /// worth 45,100 diverging trace lines the first time anyone interpolates an
  /// enum instead of reaching for [javaName].
  ///
  /// This does NOT fix Dart's built-in `.name`, which still returns the Dart
  /// identifier (`'standardX'`). Prefer [javaName] explicitly.
  @override
  String toString() => javaName;

  /// Java `PuzzleType.forOrdinal(int)` (`PuzzleType.java:42`).
  ///
  /// Kept for fidelity even though its only Java caller is the saved-game
  /// cursor in `ResumeGameActivity.java:170` and `:183`, and save-data migration is out of
  /// scope: the port's own persistence will store an ordinal too, and the
  /// trace compares ordinals.
  ///
  /// Java raises `ArrayIndexOutOfBoundsException` for an out-of-range ordinal
  /// because it indexes `values()` unguarded; Dart raises `RangeError` from the
  /// same unguarded index. Both are unchecked, so no behaviour is added here -
  /// deliberately no clamping and no `UNKNOWN`-style fallback (R-13: drop the
  /// `throws` plumbing, do not invent wrapper types).
  static PuzzleType forOrdinal(int ordinal) => PuzzleType.values[ordinal];
}

/// The six difficulty labels, in the Java declaration order.
///
/// `Difficulty.java:26` declares all six on one line and adds nothing else - no
/// methods, no fields, no `forOrdinal`. The order matters for the same reason:
///
///  * `AssetsPuzzleSource.getDifficulty()` (`AssetsPuzzleSource.java:102-108`)
///    derives the value arithmetically from the *last character of the folder
///    name* - `folderName.charAt(len - 1) - '0' - 1`, then
///    `Difficulty.values()[difficulty]`. So folder suffix `1` means [easy] and
///    `5` means [fiendish]; anything outside 0..4 throws `IllegalStateException`.
///  * `AndokuDatabase.java:461` and `AndokuContentProvider.java:345` read a
///    stored ordinal through `Difficulty.values()[...]`.
///  * the trace prints `diff=<name>` and `diffOrd=<ordinal>`.
///
/// Consequently [unknown] (ordinal 5) is **unreachable from the asset corpus** -
/// the folder-name formula rejects a `6` suffix. It exists only as the default in
/// `PuzzleInfo.Builder` (`PuzzleInfo.java:49`) and as the "hide the label" signal
/// in `AndokuActivity.java:3859`. Do not drop it: removing it would renumber
/// nothing, but it is a real stored value for handcrafted puzzles.
enum Difficulty {
  /// Java `EASY` (ordinal 0) - asset folder suffix `1`.
  easy,

  /// Java `MEDIUM` (ordinal 1) - asset folder suffix `2`.
  medium,

  /// Java `CHALLENGING` (ordinal 2) - asset folder suffix `3`.
  challenging,

  /// Java `HARD` (ordinal 3) - asset folder suffix `4`.
  hard,

  /// Java `FIENDISH` (ordinal 4) - asset folder suffix `5`.
  fiendish,

  /// Java `UNKNOWN` (ordinal 5) - never produced by the asset corpus; see the
  /// enum's own documentation.
  unknown;

  /// The Java constant name, verbatim (`SCREAMING_SNAKE`).
  ///
  /// This getter has no Java counterpart - Java gets it from `Enum.name()` for
  /// free. It exists so the trace writer can print the Java spelling without
  /// knowing about Dart's naming convention.
  String get javaName => switch (this) {
    Difficulty.easy => 'EASY',
    Difficulty.medium => 'MEDIUM',
    Difficulty.challenging => 'CHALLENGING',
    Difficulty.hard => 'HARD',
    Difficulty.fiendish => 'FIENDISH',
    Difficulty.unknown => 'UNKNOWN',
  };

  /// Java's `Enum.toString()`, which returns `name()`.
  ///
  /// Without this `'$difficulty'` yields `Difficulty.easy` where Java yields
  /// `EASY`. Live Java call sites interpolate a `Difficulty` directly -
  /// `AndokuActivity.java:4752, 4754, 4773, 4779, 4879` concatenate it straight
  /// into a string - so the Java spelling has to be what `toString` produces.
  ///
  /// This does NOT fix Dart's built-in `.name` (`'easy'`). Prefer [javaName].
  @override
  String toString() => javaName;
}

/// The difficulty encoded in an asset folder name, e.g. `standard_n_1` -> [Difficulty.easy].
///
/// Java: `AssetsPuzzleSource.getDifficulty()` (`AssetsPuzzleSource.java:102-108`), which is
/// the ONLY place the corpus's difficulty comes from - there is no difficulty field in the
/// `.adk` records themselves.
///
/// ```java
/// final int difficulty = folderName.charAt(folderName.length() - 1) - '0' - 1;
/// if (difficulty < 0 || difficulty > 4) throw new IllegalStateException();
/// return Difficulty.values()[difficulty];
/// ```
///
/// Three details, all load-bearing because `diff=` and `diffOrd=` appear on every trace
/// line of every folder:
///
/// 1. The `- 1` after `- '0'` is what maps folder suffix `1` to ordinal 0. Dropping it
///    shifts every difficulty in the corpus by one - `EASY` becomes `MEDIUM` - and does so
///    uniformly, so the result still looks plausible.
/// 2. The accepted range is 0..4, so [Difficulty.unknown] (ordinal 5) is deliberately
///    unreachable from a folder name. Suffix `6` throws rather than yielding `UNKNOWN`.
/// 3. Java reads a UTF-16 code unit with `charAt`; [String.codeUnitAt] is the same thing,
///    so no rune handling is needed.
///
/// Lives here rather than in the eventual asset-source class because the differential
/// oracle needs it before that class exists, and a formula duplicated between a test and a
/// driver is a formula nothing verifies.
Difficulty difficultyFromFolderName(String folderName) {
  if (folderName.isEmpty) {
    // Java would throw StringIndexOutOfBoundsException from charAt(-1).
    throw ArgumentError.value(folderName, 'folderName', 'must not be empty');
  }
  final int difficulty =
      folderName.codeUnitAt(folderName.length - 1) - 0x30 - 1;
  if (difficulty < 0 || difficulty > 4) {
    // Java: IllegalStateException, message-less.
    throw StateError(folderName);
  }
  return Difficulty.values[difficulty];
}
