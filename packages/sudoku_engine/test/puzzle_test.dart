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
// Ported from: app/src/main/java/com/googlecode/andoku/model/Puzzle.java
// Translation rules applied: R-03, R-04, R-05

import 'package:sudoku_engine/src/model/geometry.dart';
import 'package:sudoku_engine/src/model/puzzle.dart';
import 'package:sudoku_engine/src/model/value_set.dart';
import 'package:test/test.dart';

/// Standard 3x3-box area map, built locally so these tests pin `Puzzle`'s own
/// behaviour rather than `standardAreas`'.
List<List<int>> standardBoxes() => List<List<int>>.generate(
  9,
  (int row) => List<int>.generate(9, (int col) => (row ~/ 3) * 3 + col ~/ 3),
);

/// The two X-sudoku diagonals, in the order `ExtraRegions.x` produces them
/// (main diagonal first). Built locally for the same reason as [standardBoxes].
List<ExtraRegion> xDiagonals() => <ExtraRegion>[
  ExtraRegion(List<Position>.generate(9, (int i) => Position(i, i))),
  ExtraRegion(List<Position>.generate(9, (int i) => Position(i, 8 - i))),
];

/// Region identity as the geom trace sees it: id plus name.
List<String> regionKeys(Puzzle p) =>
    p.regions.map((Region r) => '${r.id}:${r.name}').toList();

void main() {
  group('region construction order', () {
    // The DLX matrix derives a column from `regionOffset + region.id * size + v`
    // (DlxPuzzleSolver.createMatrix), so these ids ARE the solver's column order.
    // A reordering here changes the min-column heuristic's choice and the dlx
    // trace's node count without changing the solution -- exactly the kind of
    // silent divergence the oracle exists to catch.
    test(
      'is rows, then columns, then areas, then extras, with running ids',
      () {
        final Puzzle p = Puzzle(standardBoxes(), xDiagonals());

        expect(p.regions.length, 9 + 9 + 9 + 2);
        expect(regionKeys(p).take(9), <String>[
          '0:row 0',
          '1:row 1',
          '2:row 2',
          '3:row 3',
          '4:row 4',
          '5:row 5',
          '6:row 6',
          '7:row 7',
          '8:row 8',
        ]);
        expect(regionKeys(p).skip(9).take(9).first, '9:col 0');
        expect(regionKeys(p).skip(17).first, '17:col 8');
        expect(regionKeys(p).skip(18).first, '18:area 0');
        expect(regionKeys(p).skip(26).first, '26:area 8');
        expect(regionKeys(p).skip(27).toList(), <String>[
          '27:extra 0',
          '28:extra 1',
        ]);
      },
    );

    test('extra regions are numbered from 0, not continuing the area numbers', () {
      // Java: `new Region(id++, REGION_TYPE_EXTRA, extraNumber, ...)` where
      // extraNumber restarts at 0. So id and number diverge for extras, and the
      // name is "extra 0" while the id is 27.
      final Puzzle p = Puzzle(standardBoxes(), xDiagonals());
      final Region firstExtra = p.regions[27];

      expect(firstExtra.id, 27);
      expect(firstExtra.number, 0);
      expect(firstExtra.type, Puzzle.typeExtra);
      expect(firstExtra.name, 'extra 0');
    });

    test('row and column region positions are in index order', () {
      final Puzzle p = Puzzle(standardBoxes(), const <ExtraRegion>[]);

      expect(
        p.regions[3].positions,
        List<Position>.generate(9, (int c) => Position(3, c)),
      );
      expect(
        p.regions[9 + 4].positions,
        List<Position>.generate(9, (int r) => Position(r, 4)),
      );
    });

    test('area positions are collected row-major by scanning the whole board', () {
      // Java scans row-major and keeps matching cells, so even an irregular
      // (squiggly) area comes out row-major rather than in any adjacency order.
      final Puzzle p = Puzzle(standardBoxes(), const <ExtraRegion>[]);

      expect(p.regions[18 + 4].positions, <Position>[
        const Position(3, 3),
        const Position(3, 4),
        const Position(3, 5),
        const Position(4, 3),
        const Position(4, 4),
        const Position(4, 5),
        const Position(5, 3),
        const Position(5, 4),
        const Position(5, 5),
      ]);
    });

    test('a squiggly area map still yields row-major area positions', () {
      // Area 0 deliberately interleaves rows so a column-major or
      // insertion-order bug would show up.
      final List<List<int>> squiggly = List<List<int>>.generate(
        9,
        (int row) => List<int>.generate(9, (int col) => col),
      );
      final Puzzle p = Puzzle(squiggly, const <ExtraRegion>[]);

      expect(
        p.regions[18].positions,
        List<Position>.generate(9, (int r) => Position(r, 0)),
      );
    });
  });

  // NOTE ON ORACLE COVERAGE, so nobody trims these as redundant with T2:
  // the differential trace does NOT check the per-cell region ORDER.
  // DlxPuzzleSolver.createMatrix writes
  //   values[regionOffset + region.id * size + v] = true
  // (DlxPuzzleSolver.java:110) -- indexed by region.id -- so permuting a cell's
  // region list produces a BIT-IDENTICAL matrix row and an identical node count.
  // Only the CONTENT of each cell's list is oracled. These assertions are the
  // only check on the ordering.
  group('regionsAt', () {
    // Java builds this from a HashMap<Position, List<Region>>. The map is never
    // iterated, only looked up per cell, so the per-cell order is `regions`
    // order. This group is the regression test for that claim: if a port ever
    // starts leaking map order the ids stop ascending.
    test('lists ids in ascending order for every cell, extras included', () {
      final Puzzle p = Puzzle(standardBoxes(), xDiagonals());

      for (int row = 0; row < 9; row++) {
        for (int col = 0; col < 9; col++) {
          final List<Region> at = p.regionsAt(row, col);
          final List<int> ids = at.map((Region r) => r.id).toList();
          expect(ids, List<int>.of(ids)..sort(), reason: 'cell $row x $col');
        }
      }
    });

    test('is row, column, area for an ordinary cell', () {
      final Puzzle p = Puzzle(standardBoxes(), const <ExtraRegion>[]);

      expect(p.regionsAt(4, 7).map((Region r) => r.name).toList(), <String>[
        'row 4',
        'col 7',
        'area 5',
      ]);
    });

    test('appends the extra region last for a diagonal cell', () {
      final Puzzle p = Puzzle(standardBoxes(), xDiagonals());

      expect(p.regionsAt(0, 0).map((Region r) => r.name).toList(), <String>[
        'row 0',
        'col 0',
        'area 0',
        'extra 0',
      ]);
      expect(p.regionsAt(0, 8).map((Region r) => r.name).toList(), <String>[
        'row 0',
        'col 8',
        'area 2',
        'extra 1',
      ]);
      // The centre cell sits on both diagonals, so both extras attach, in
      // ExtraRegions order.
      expect(p.regionsAt(4, 4).map((Region r) => r.name).toList(), <String>[
        'row 4',
        'col 4',
        'area 4',
        'extra 0',
        'extra 1',
      ]);
    });

    test('returns the live list and the same Region objects as regions', () {
      // Java returns the internal array from both getRegions() and
      // getRegionsAt(), and `set` mutates the Region objects reached through
      // regionsAt -- so the two views must be the same instances, not copies.
      final Puzzle p = Puzzle(standardBoxes(), const <ExtraRegion>[]);

      expect(identical(p.regionsAt(2, 2), p.regionsAt(2, 2)), isTrue);
      expect(identical(p.regionsAt(2, 2)[0], p.regions[2]), isTrue);
    });
  });

  group('set and clear', () {
    test(
      'set adds the value to every region at the cell and bumps the count',
      () {
        final Puzzle p = Puzzle(standardBoxes(), xDiagonals());

        // Values are 0-based: 4 is the digit 5 on screen.
        p.set(0, 0, 4);

        expect(p.getValue(0, 0), 4);
        expect(p.valuesCount, 1);
        for (final Region r in p.regionsAt(0, 0)) {
          expect(r.values.contains(4), isTrue, reason: r.name);
        }
        // A region the cell does not belong to must not have seen it.
        expect(p.regions[1].values.contains(4), isFalse);
        expect(p.regions[28].values.contains(4), isFalse);
      },
    );

    test('clear removes the value again and restores the count', () {
      final Puzzle p = Puzzle(standardBoxes(), const <ExtraRegion>[]);

      p.set(3, 3, 7);
      p.clear(3, 3);

      expect(p.getValue(3, 3), Puzzle.undefined);
      expect(p.valuesCount, 0);
      for (final Region r in p.regionsAt(3, 3)) {
        expect(r.values.isEmpty, isTrue, reason: r.name);
      }
    });

    test('clear is unguarded against a duplicate value in the same region', () {
      // Reproduces the Java: `clear` removes the value from the region set with
      // no check for another cell in that region still holding it. Unreachable
      // through the public API, but it is why `set`'s precondition matters.
      final Puzzle p = Puzzle(standardBoxes(), const <ExtraRegion>[]);

      p.set(0, 0, 2);
      p.set(0, 1, 2); // illegal placement, same row -- nothing rejects it
      p.clear(0, 0);

      expect(p.getValue(0, 1), 2);
      expect(
        p.regions[0].values.contains(2),
        isFalse,
        reason: 'row 0 lost the value although (0,1) still holds it',
      );
    });

    test('set asserts the cell is empty', () {
      // Java has `assert values[row][col] == UNDEFINED`, inert on Android
      // because assertions are never enabled there; Dart asserts are live under
      // `dart test`. See the doc comment on Puzzle.set.
      final Puzzle p = Puzzle(standardBoxes(), const <ExtraRegion>[]);
      p.set(0, 0, 1);

      expect(() => p.set(0, 0, 2), throwsA(isA<AssertionError>()));
    });

    test('clear asserts the cell is filled', () {
      final Puzzle p = Puzzle(standardBoxes(), const <ExtraRegion>[]);

      expect(() => p.clear(0, 0), throwsA(isA<AssertionError>()));
    });
  });

  group('force', () {
    // No call site exists in the shipped Java app, so this is pinned by unit
    // test only -- the oracle never exercises it.
    test('clears conflicting cells in every region before placing', () {
      final Puzzle p = Puzzle(standardBoxes(), xDiagonals());

      p.set(0, 5, 3); // same row
      p.set(5, 0, 3); // same column
      p.set(1, 1, 3); // same area and on the main diagonal
      p.set(8, 8, 3); // on the main diagonal only
      p.set(4, 4, 6); // unrelated value, must survive

      p.force(0, 0, 3);

      expect(p.getValue(0, 0), 3);
      expect(p.getValue(0, 5), Puzzle.undefined);
      expect(p.getValue(5, 0), Puzzle.undefined);
      expect(p.getValue(1, 1), Puzzle.undefined);
      expect(p.getValue(8, 8), Puzzle.undefined);
      expect(p.getValue(4, 4), 6);
      expect(p.valuesCount, 2);
    });

    test('replaces the value already in the target cell', () {
      final Puzzle p = Puzzle(standardBoxes(), const <ExtraRegion>[]);

      p.set(2, 2, 1);
      p.force(2, 2, 8);

      expect(p.getValue(2, 2), 8);
      expect(p.valuesCount, 1);
      expect(p.regions[2].values.contains(1), isFalse);
      expect(p.regions[2].values.contains(8), isTrue);
    });
  });

  group('eliminated candidates', () {
    test('eliminateValue and eliminateValues accumulate into the live set', () {
      final Puzzle p = Puzzle(standardBoxes(), const <ExtraRegion>[]);

      p.eliminateValue(1, 1, 0);
      p.eliminateValues(
        1,
        1,
        ValueSet()
          ..add(5)
          ..add(8),
      );

      expect(p.eliminated(1, 1).contains(0), isTrue);
      expect(p.eliminated(1, 1).contains(5), isTrue);
      expect(p.eliminated(1, 1).contains(8), isTrue);
      expect(p.eliminated(1, 1).size, 3);
      // Java reads the private field directly; the accessor must hand back the
      // same mutable instance, not a snapshot.
      expect(identical(p.eliminated(1, 1), p.eliminated(1, 1)), isTrue);
    });

    test('getPossibleValues subtracts regions and eliminations', () {
      final Puzzle p = Puzzle(standardBoxes(), const <ExtraRegion>[]);

      p.set(0, 1, 0); // row 0
      p.set(5, 0, 1); // col 0
      p.set(1, 1, 2); // area 0
      p.eliminateValue(0, 0, 3);

      final ValueSet possible = p.getPossibleValues(0, 0);

      expect(possible.contains(0), isFalse);
      expect(possible.contains(1), isFalse);
      expect(possible.contains(2), isFalse);
      expect(possible.contains(3), isFalse);
      expect(possible.size, 5);
    });

    test('getPossibleValues of a filled cell is empty, not its own value', () {
      final Puzzle p = Puzzle(standardBoxes(), const <ExtraRegion>[]);
      p.set(0, 0, 4);

      expect(p.getPossibleValues(0, 0).isEmpty, isTrue);
    });
  });

  group('Puzzle.copy', () {
    test('shares the geometry inputs but rebuilds the Region objects', () {
      final List<List<int>> areas = standardBoxes();
      final List<ExtraRegion> extras = xDiagonals();
      final Puzzle source = Puzzle(areas, extras);
      final Puzzle copy = Puzzle.copy(source);

      // Java: `this(other.areaCodes, other.extraRegions, false)` -- no cloning.
      expect(identical(copy.areaCodes, areas), isTrue);
      expect(identical(copy.extraRegions, extras), isTrue);
      // ... but createRegions() runs again, so the mutable Region.values sets
      // must not be shared with the source.
      expect(identical(copy.regions, source.regions), isFalse);
      expect(identical(copy.regions[0], source.regions[0]), isFalse);
      expect(regionKeys(copy), regionKeys(source));
    });

    test(
      'recomputes valuesCount and the region value sets by replaying set()',
      () {
        final Puzzle source = Puzzle(standardBoxes(), xDiagonals());
        source.set(0, 0, 0);
        source.set(1, 4, 5);
        source.set(8, 8, 2);

        final Puzzle copy = Puzzle.copy(source);

        expect(copy.valuesCount, 3);
        expect(copy.getValue(0, 0), 0);
        expect(copy.getValue(1, 4), 5);
        expect(copy.getValue(8, 8), 2);
        for (int i = 0; i < source.regions.length; i++) {
          expect(
            copy.regions[i].values.toInt(),
            source.regions[i].values.toInt(),
            reason: source.regions[i].name,
          );
        }
        // Mutating the copy must leave the source alone -- the proof that the
        // Region objects really were rebuilt.
        copy.clear(0, 0);
        expect(source.regions[0].values.contains(0), isTrue);
        expect(copy.regions[0].values.contains(0), isFalse);
      },
    );

    test('copies the eliminated sets by value, not by reference', () {
      final Puzzle source = Puzzle(standardBoxes(), const <ExtraRegion>[]);
      source.eliminateValue(2, 3, 7);

      final Puzzle copy = Puzzle.copy(source);

      expect(copy.eliminated(2, 3).contains(7), isTrue);
      expect(
        identical(copy.eliminated(2, 3), source.eliminated(2, 3)),
        isFalse,
      );

      copy.eliminateValue(2, 3, 1);
      expect(source.eliminated(2, 3).contains(1), isFalse);
    });

    test('copies eliminations of filled cells too', () {
      // The Java loop calls eliminateValues() unconditionally, outside the
      // `if (value != UNDEFINED)` branch. A plausible "optimisation" that skips
      // filled cells loses eliminations that become visible again after a clear.
      final Puzzle source = Puzzle(standardBoxes(), const <ExtraRegion>[]);
      source.set(0, 0, 4);
      source.eliminateValue(0, 0, 6);

      final Puzzle copy = Puzzle.copy(source);
      expect(copy.eliminated(0, 0).contains(6), isTrue);

      copy.clear(0, 0);
      expect(copy.getPossibleValues(0, 0).contains(6), isFalse);
    });

    // REMOVED: a test named 'skips validation, so copying is not a second
    // geometry check' used to sit here asserting `returnsNormally` on a valid
    // source puzzle. A Puzzle.copy that DID re-validate would also return
    // normally for a valid source, so the assertion observed nothing and could
    // not fail. `_unchecked` is private, so the claim is genuinely untestable
    // from outside; it is documented on the constructor instead.
  });

  group('isSolved and toString', () {
    test('isSolved counts cells and ignores validity', () {
      final Puzzle p = Puzzle(standardBoxes(), const <ExtraRegion>[]);

      for (int row = 0; row < 9; row++) {
        for (int col = 0; col < 9; col++) {
          p.set(row, col, 0); // every cell the same value: wildly invalid
        }
      }

      expect(p.valuesCount, 81);
      expect(p.isSolved, isTrue);
    });

    test('toString renders 0-based values as 1-based digits', () {
      final Puzzle p = Puzzle(standardBoxes(), const <ExtraRegion>[]);
      p.set(0, 0, 0);
      p.set(0, 8, 8);

      final String s = p.toString();
      expect(s.length, 9 * 9 + 8); // single space between rows, none trailing
      expect(s.startsWith('1.......9 '), isTrue);
      expect(s.endsWith('.........'), isTrue);
      expect(s.split(' ').length, 9);
    });
  });

  group('parameter validation', () {
    String messageOf(void Function() f) {
      try {
        f();
      } on ArgumentError catch (e) {
        return e.message.toString();
      }
      return 'did not throw';
    }

    test('rejects a board smaller than 3 or larger than ValueSet.maxSize', () {
      expect(
        messageOf(
          () => Puzzle(<List<int>>[
            <int>[0, 0],
            <int>[0, 0],
          ], const <ExtraRegion>[]),
        ),
        'Invalid size: 2',
      );

      final int tooBig = ValueSet.maxSize + 1;
      expect(
        messageOf(
          () => Puzzle(
            List<List<int>>.generate(
              tooBig,
              (_) => List<int>.filled(tooBig, 0),
            ),
            const <ExtraRegion>[],
          ),
        ),
        'Invalid size: $tooBig',
      );
    });

    test('checks row width before area code range', () {
      // Order matters: the first failure's message is what the caller sees.
      final List<List<int>> areas = standardBoxes();
      areas[4] = <int>[99, 99];

      expect(
        messageOf(() => Puzzle(areas, const <ExtraRegion>[])),
        'Invalid number of area code columns',
      );
    });

    test('rejects an out-of-range area code', () {
      final List<List<int>> areas = standardBoxes();
      areas[4][4] = 9;

      expect(
        messageOf(() => Puzzle(areas, const <ExtraRegion>[])),
        'Invalid area code: 9',
      );
    });

    test("rejects an area that does not have exactly size cells", () {
      final List<List<int>> areas = standardBoxes();
      areas[0][0] = 1; // area 0 now has 8 cells, area 1 has 10

      expect(
        messageOf(() => Puzzle(areas, const <ExtraRegion>[])),
        "Invalid number of 0's: 8",
      );
    });

    test('rejects a wrongly sized extra region', () {
      expect(
        messageOf(
          () => Puzzle(standardBoxes(), <ExtraRegion>[
            ExtraRegion(List<Position>.generate(8, (int i) => Position(i, i))),
          ]),
        ),
        'Invalid extra region size: 8',
      );
    });

    test('rejects duplicate positions inside an extra region', () {
      // R-03: this check only works because Position overrides == and hashCode.
      // With identity semantics the set would keep both copies and the board
      // would silently get a 9-cell region covering 8 cells.
      final List<Position> positions = List<Position>.generate(
        9,
        (int i) => Position(i, i),
      );
      positions[8] = const Position(0, 0);

      expect(
        messageOf(
          () => Puzzle(standardBoxes(), <ExtraRegion>[ExtraRegion(positions)]),
        ),
        'Invalid number of unique positions in extra region',
      );
    });

    test('rejects an extra region position outside the grid', () {
      final List<Position> positions = List<Position>.generate(
        9,
        (int i) => Position(i, i),
      );
      positions[8] = const Position(9, 9);

      expect(
        messageOf(
          () => Puzzle(standardBoxes(), <ExtraRegion>[ExtraRegion(positions)]),
        ),
        'Extra region position outside grid',
      );
    });

    test('accepts overlapping and non-contiguous extra regions', () {
      // Not a gap in the validation: percent and colour variants rely on it.
      expect(() => Puzzle(standardBoxes(), xDiagonals()), returnsNormally);
    });
  });
}
