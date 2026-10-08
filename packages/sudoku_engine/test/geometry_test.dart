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
// Ported from: app/src/main/java/com/googlecode/andoku/model/ExtraRegions.java
// Translation rules applied: R-03

// Tests for lib/src/model/geometry.dart.
//
// These assert the things that diverge *silently*: the count and first cell of
// every extra-region factory (which is the whole of puzzle-type inference), the
// deliberately unnatural hyper ordering, the set-based ExtraRegion equality, and
// Position's value identity as a map key.

import 'package:sudoku_engine/src/model/geometry.dart';
import 'package:test/test.dart';

/// Compact spelling of a cell list, so an expectation reads like the Java it
/// came from. `'11,14,17'` is `(1,1) (1,4) (1,7)`.
String cells(List<Position> ps) => ps.map((p) => '${p.row}${p.col}').join(',');

void main() {
  group('Position', () {
    test('value equality and Java hashCode formula', () {
      expect(const Position(3, 5), equals(const Position(3, 5)));
      expect(const Position(3, 5), isNot(equals(const Position(5, 3))));
      // Java: row * 9901 + col.
      expect(const Position(3, 5).hashCode, 3 * 9901 + 5);
      expect(const Position(0, 0).hashCode, 0);
    });

    test('works as a map key looked up by a fresh instance', () {
      // Exactly the Puzzle.initRegionsAt pattern: insert while walking regions,
      // then read back with `new Position(row, col)`. Identity semantics here
      // would make every lookup miss and Puzzle would throw on construction.
      final map = <Position, String>{};
      for (var r = 0; r < 9; r++) {
        for (var c = 0; c < 9; c++) {
          map[Position(r, c)] = 'r$r c$c';
        }
      }
      expect(map.length, 81);
      expect(map[const Position(8, 8)], 'r8 c8');
      expect(map[Position(4, 2)], 'r4 c2');
    });

    test('no hash collisions anywhere on a 16x16 board', () {
      // 9901 is prime and far larger than maxSize, so the formula is a perfect
      // hash for every board the engine can be asked about.
      final seen = <int>{};
      for (var r = 0; r < 16; r++) {
        for (var c = 0; c < 16; c++) {
          expect(
            seen.add(Position(r, c).hashCode),
            isTrue,
            reason: 'collision at ($r,$c)',
          );
        }
      }
    });

    test('compareTo orders row-major and returns the raw difference', () {
      // Java returns `row - o.row` / `col - o.col`, not a normalised -1/0/1.
      expect(const Position(2, 0).compareTo(const Position(5, 0)), -3);
      expect(const Position(5, 1).compareTo(const Position(5, 7)), -6);
      expect(const Position(5, 1).compareTo(const Position(5, 1)), 0);

      final sorted = <Position>[
        const Position(1, 5),
        const Position(0, 8),
        const Position(1, 0),
      ]..sort();
      expect(cells(sorted), '08,10,15');
    });

    test('samePosition agrees with ==', () {
      expect(const Position(7, 7).samePosition(const Position(7, 7)), isTrue);
      expect(const Position(7, 7).samePosition(const Position(7, 6)), isFalse);
    });

    test('toString is the Java row + "x" + col shape', () {
      // Reachable from the hint trace via the canonicaliser's toString fallback.
      expect(const Position(3, 5).toString(), '3x5');
      expect(const Position(0, 0).toString(), '0x0');
    });
  });

  group('ExtraRegion', () {
    test('equality is set-based: order and duplicates are ignored', () {
      // Java: new HashSet<>(asList(positions)).equals(...). Reproduced because
      // PuzzleEncoder relies on it; note it deliberately does NOT care about
      // the order that puzzle-type inference does care about.
      final a = ExtraRegion([const Position(0, 0), const Position(1, 1)]);
      final b = ExtraRegion([const Position(1, 1), const Position(0, 0)]);
      final withDup = ExtraRegion([
        const Position(0, 0),
        const Position(1, 1),
        const Position(1, 1),
      ]);

      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a, equals(withDup));
      expect(a.hashCode, withDup.hashCode);
    });

    test('hashCode is the sum of distinct Position hash codes', () {
      // Java AbstractSet.hashCode sums its elements; the dedup happens in the
      // HashSet, so a duplicated cell must not be counted twice.
      final r = ExtraRegion([
        const Position(1, 1),
        const Position(2, 3),
        const Position(2, 3),
      ]);
      expect(
        r.hashCode,
        const Position(1, 1).hashCode + const Position(2, 3).hashCode,
      );
    });

    test('different cells are unequal', () {
      expect(
        ExtraRegion([const Position(0, 0)]),
        isNot(equals(ExtraRegion([const Position(0, 1)]))),
      );
    });

    test('a non-ExtraRegion is never equal', () {
      expect(ExtraRegion(const []), isNot(equals('[]')));
    });
  });

  group('Region', () {
    test('name is "type number" with a single space', () {
      // Reaches the player through hint text.
      expect(Region(0, 'row', 4, const []).name, 'row 4');
      expect(Region(27, 'area', 0, const []).name, 'area 0');
    });

    test('each region gets its own ValueSet', () {
      // Puzzle.set/clear mutate region.values per cell; a shared instance would
      // make every region report every placed digit.
      final a = Region(0, 'row', 0, const []);
      final b = Region(1, 'row', 1, const []);
      a.values.add(5);
      expect(a.values.contains(5), isTrue);
      expect(b.values.contains(5), isFalse);
      expect(b.values.isEmpty, isTrue);
    });

    test('toString matches the Java Arrays.asList rendering', () {
      final r = Region(0, 'extra', 1, [
        const Position(1, 1),
        const Position(2, 2),
      ]);
      expect(r.toString(), 'Region extra 1: [1x1, 2x2]');
    });

    test('positions are copied and unmodifiable -- DIVERGENCE D-05', () {
      // Java has TWO constructors per class: the List overload COPIES
      // (positions.toArray, Region.java:35-41) and the Position[] overload
      // aliases (:43-49). Puzzle.createRegions uses the copying one for rows,
      // columns and areas (Puzzle.java:211, 219, 229) and the aliasing one only
      // for extras (:234). Dart has one list type, so the port keeps the
      // copying branch and stores an unmodifiable view -- see D-05 in
      // DIVERGENCES.md.
      //
      // An earlier version of this test asserted `same(extra.positions)` and
      // called aliasing "the faithful choice". That described the half of Java
      // that had been discarded: for the List path Java copies.
      final source = <Position>[const Position(4, 4)];
      final region = Region(30, 'extra', 0, source);
      expect(
        region.positions,
        isNot(same(source)),
        reason: 'the List overload copies, as Java does',
      );
      expect(region.positions, equals(source));

      // The caller's later mutation must not leak in.
      source.add(const Position(5, 5));
      expect(region.positions, hasLength(1));

      // And the region cannot be grown after Puzzle has validated its size.
      expect(
        () => region.positions.add(const Position(6, 6)),
        throwsUnsupportedError,
      );
    });

    test('ExtraRegion positions are copied and unmodifiable too -- D-05', () {
      final source = <Position>[const Position(1, 1), const Position(2, 2)];
      final extra = ExtraRegion(source);
      source.add(const Position(3, 3));
      expect(
        extra.positions,
        hasLength(2),
        reason: 'Java ExtraRegion(List) copies via toArray',
      );
      expect(
        () => extra.positions.add(const Position(7, 7)),
        throwsUnsupportedError,
        reason: 'Java stores a fixed-length Position[]',
      );
    });

    test('every factory allocates fresh Positions, as Java does', () {
      // `wheel` once used const Position literals, so Dart canonicalized them
      // and wheel(9) returned the SAME Position objects on every call while the
      // other five factories returned fresh ones. Java allocates everywhere.
      expect(
        identical(
          ExtraRegions.wheel(9)[0].positions[0],
          ExtraRegions.wheel(9)[0].positions[0],
        ),
        isFalse,
        reason: 'uniform with dot/x/hyper/percent/color',
      );
      expect(
        identical(
          ExtraRegions.dot(9)[0].positions[0],
          ExtraRegions.dot(9)[0].positions[0],
        ),
        isFalse,
      );
    });
  });

  group('ExtraRegions counts drive puzzle-type inference', () {
    // AndokuPuzzle.determinePuzzleType (model/AndokuPuzzle.java:1323) switches
    // on nothing but these counts. Each number below is a puzzle type.
    test('one count per variant, and none of them collide', () {
      expect(ExtraRegions.none().length, 0, reason: 'STANDARD/SQUIGGLY');
      expect(ExtraRegions.x(9).length, 2, reason: 'X');
      expect(ExtraRegions.percent(9).length, 3, reason: 'PERCENT');
      expect(ExtraRegions.hyper(9).length, 4, reason: 'HYPER');
      expect(ExtraRegions.color(9).length, 9, reason: 'COLOR');
      expect(ExtraRegions.dot(9).length, 1, reason: 'DOT');
      expect(ExtraRegions.wheel(9).length, 1, reason: 'WHEEL');
    });

    test('DOT vs WHEEL hangs on the first cell of the single region', () {
      // Java: `if (getExtraRegions()[0].positions[0].row == 1) -> DOT else WHEEL`.
      // Sorting either list, or building the wheel in reading order, retypes
      // every wheel puzzle as a dot puzzle with no error anywhere.
      expect(ExtraRegions.dot(9)[0].positions[0].row, 1);
      expect(ExtraRegions.wheel(9)[0].positions[0].row, 4);
    });
  });

  group('ExtraRegions cell geometry', () {
    test('x: main diagonal then anti-diagonal', () {
      final x = ExtraRegions.x(9);
      expect(cells(x[0].positions), '00,11,22,33,44,55,66,77,88');
      expect(cells(x[1].positions), '08,17,26,35,44,53,62,71,80');
    });

    test('hyper: four inset boxes in Java order, NOT reading order', () {
      // square(1,1), square(5,1), square(1,5), square(5,5) -- the row offset
      // varies first, so index 1 is the BOTTOM-left box and index 2 the
      // TOP-right one. getExtraRegionCode returns this index, and the theme
      // paints by it, so the order is visible on screen and in the trace.
      final h = ExtraRegions.hyper(9);
      expect(cells(h[0].positions), '11,12,13,21,22,23,31,32,33');
      expect(cells(h[1].positions), '51,52,53,61,62,63,71,72,73');
      expect(cells(h[2].positions), '15,16,17,25,26,27,35,36,37');
      expect(cells(h[3].positions), '55,56,57,65,66,67,75,76,77');
    });

    test('percent: inset box, ANTI-diagonal, inset box', () {
      // The middle region is diag2. Swapping in diag1 would still yield three
      // regions and still type as PERCENT.
      final p = ExtraRegions.percent(9);
      expect(cells(p[0].positions), '11,12,13,21,22,23,31,32,33');
      expect(cells(p[1].positions), '08,17,26,35,44,53,62,71,80');
      expect(cells(p[2].positions), '55,56,57,65,66,67,75,76,77');
    });

    test('color: same offset within every box, box-reading order', () {
      final c = ExtraRegions.color(9);
      expect(cells(c[0].positions), '00,03,06,30,33,36,60,63,66');
      expect(cells(c[4].positions), '11,14,17,41,44,47,71,74,77');
      expect(cells(c[8].positions), '22,25,28,52,55,58,82,85,88');
    });

    test('color: the nine regions partition all 81 cells', () {
      final seen = <Position>{};
      for (final region in ExtraRegions.color(9)) {
        expect(region.positions.length, 9);
        for (final p in region.positions) {
          expect(seen.add(p), isTrue, reason: 'cell $p covered twice');
        }
      }
      expect(seen.length, 81);
    });

    test('dot: the nine box centres', () {
      expect(
        cells(ExtraRegions.dot(9)[0].positions),
        '11,14,17,41,44,47,71,74,77',
      );
    });

    test('wheel: the nine pinwheel cells in Java source order', () {
      expect(
        cells(ExtraRegions.wheel(9)[0].positions),
        '41,22,62,14,44,74,26,66,47',
      );
    });

    test('hyper boxes are disjoint and 9 cells each', () {
      final seen = <Position>{};
      for (final region in ExtraRegions.hyper(9)) {
        expect(region.positions.length, 9);
        for (final p in region.positions) {
          expect(seen.add(p), isTrue);
        }
      }
      expect(seen.length, 36);
    });
  });

  group('ExtraRegions size handling is uneven, on purpose', () {
    test('hyper, percent and color reject anything but 9x9', () {
      // Java throws IllegalArgumentException with these exact messages.
      expect(() => ExtraRegions.hyper(4), throwsArgumentError);
      expect(() => ExtraRegions.percent(4), throwsArgumentError);
      expect(() => ExtraRegions.color(4), throwsArgumentError);
    });

    test('x honours size and has no 9x9 guard', () {
      final x = ExtraRegions.x(4);
      expect(cells(x[0].positions), '00,11,22,33');
      expect(cells(x[1].positions), '03,12,21,30');
    });

    test('dot honours size with no guard, wheel ignores size entirely', () {
      // Java `dot_region` loops to `size` using 9x9 arithmetic; `wheel_region`
      // hard-codes nine cells and never reads its parameter. Neither validates.
      expect(ExtraRegions.dot(4)[0].positions.length, 4);
      expect(cells(ExtraRegions.dot(4)[0].positions), '11,14,17,41');
      expect(ExtraRegions.wheel(4)[0].positions.length, 9);
      expect(
        cells(ExtraRegions.wheel(4)[0].positions),
        '41,22,62,14,44,74,26,66,47',
      );
    });
  });

  group('ExtraRegions aliasing', () {
    test('none() is empty and immutable', () {
      // Java hands out one shared mutable `static final ExtraRegion[] NONE` to
      // every standard puzzle. Returning a const list keeps the sharing and
      // removes the hazard: a stray mutation throws instead of corrupting
      // every other puzzle in the session.
      expect(ExtraRegions.none(), isEmpty);
      expect(
        () => ExtraRegions.none().add(ExtraRegion(const [])),
        throwsUnsupportedError,
      );
    });

    test('each factory call returns fresh ExtraRegion instances', () {
      // Java allocates a new ArrayList per call. Region.values is live state
      // and extra regions become Regions, so sharing an instance between two
      // puzzles would let one board's placements leak into another.
      final a = ExtraRegions.wheel(9);
      final b = ExtraRegions.wheel(9);
      expect(a[0], equals(b[0]), reason: 'same cells');
      expect(identical(a[0], b[0]), isFalse);
      expect(identical(a[0].positions, b[0].positions), isFalse);

      final h1 = ExtraRegions.hyper(9);
      final h2 = ExtraRegions.hyper(9);
      expect(identical(h1[0], h2[0]), isFalse);
    });
  });
}
