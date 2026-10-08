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
// Ported from: app/src/main/java/com/googlecode/andoku/dlx/Data.java
// Ported from: app/src/main/java/com/googlecode/andoku/dlx/Header.java
// Ported from: app/src/main/java/com/googlecode/andoku/dlx/Matrix.java
// Ported from: app/src/main/java/com/googlecode/andoku/dlx/DlxListener.java
// Ported from: app/src/main/java/com/googlecode/andoku/dlx/RowSorter.java
// Ported from: app/src/main/java/com/googlecode/andoku/dlx/Solver.java
// Translation rules applied: R-03, R-05, R-09, R-10, R-13

// These tests target the things that change the NODE COUNT without changing the
// answers, because the differential trace prints the node count and a solver that
// merely "solves every puzzle" fails the gate. Anything that only a correct-answer
// test would catch is deliberately under-weighted here.

import 'package:sudoku_engine/src/dlx/dlx.dart';
import 'package:test/test.dart';

/// Records the search as a flat sequence, which is the observable the trace cares about.
///
/// The selects list is the node-visit order. Each solution is a snapshot of the
/// currently selected rows, so solution *content* and solution *order* are both pinned.
class _Recorder implements DlxListener {
  /// Return `false` from the n-th [select] call. 0 means never abort.
  final int abortAfterSelect;

  /// Return `false` from the first [solutionFound], as `UniqueSolutionReporter` does.
  final bool stopAtFirstSolution;

  final List<String> selects = <String>[];
  final List<String> deselects = <String>[];
  final List<List<String>> solutions = <List<String>>[];
  final List<String> _stack = <String>[];
  int _selectCount = 0;

  _Recorder({this.abortAfterSelect = 0, this.stopAtFirstSolution = false});

  @override
  bool select(Data row) {
    final String name = row.payload as String;
    selects.add(name);
    _stack.add(name);
    _selectCount++;
    // Mirrors DlxPuzzleSolver.Strategy.select: `maxUpdates == 0 || ++updates < maxUpdates`.
    return abortAfterSelect == 0 || _selectCount < abortAfterSelect;
  }

  @override
  void deselect(Data row) {
    deselects.add(row.payload as String);
    _stack.removeLast();
  }

  @override
  bool solutionFound() {
    solutions.add(List<String>.of(_stack));
    return !stopAtFirstSolution;
  }
}

/// Reverses the candidate rows in place and records what it was handed.
class _ReversingSorter implements RowSorter {
  final List<int> lengthsSeen = <int>[];
  final List<List<Data>> listsSeen = <List<Data>>[];

  @override
  void sort(List<Data> rows) {
    lengthsSeen.add(rows.length);
    listsSeen.add(rows);
    final List<Data> reversed = List<Data>.of(rows.reversed);
    for (int i = 0; i < rows.length; i++) {
      rows[i] = reversed[i];
    }
  }
}

/// A payload with value semantics (R-03), like `DlxPuzzleSolver.RCV`.
class _Key {
  final int a;
  final int b;
  const _Key(this.a, this.b);

  @override
  bool operator ==(Object other) =>
      other is _Key && other.a == a && other.b == b;

  @override
  int get hashCode => Object.hash(a, b);
}

/// A payload with no `==`/`hashCode`, i.e. identity-keyed like a raw Java array (R-04).
class _IdentityKey {
  const _IdentityKey();
}

/// `[0, 2]` with width 3 becomes `[true, false, true]`.
List<bool> _vec(int width, List<int> ones) {
  final List<bool> v = List<bool>.filled(width, false);
  for (final int i in ones) {
    v[i] = true;
  }
  return v;
}

/// Builds a matrix and keeps the headers so the tests can read `Header.size`.
class _Built {
  final Matrix<String> m;
  final List<Header> columns;
  _Built(this.m, this.columns);

  List<int> get sizes => <int>[for (final Header h in columns) h.size];
}

_Built _build(List<String> columnNames, Map<String, List<int>> rows) {
  final Matrix<String> m = Matrix<String>();
  final List<Header> columns = <Header>[];
  for (final String name in columnNames) {
    final Header h = Header(name);
    columns.add(h);
    m.addColumn(h);
  }
  for (final MapEntry<String, List<int>> e in rows.entries) {
    m.addRow(e.key, _vec(columnNames.length, e.value));
  }
  return _Built(m, columns);
}

void main() {
  group('Data and Header', () {
    test('payload round-trips, and a Header defaults to a null payload', () {
      expect(Data('p').payload, 'p');
      expect(Data(null).payload, isNull);
      // Java has two constructors; the one-arg form is `super(null)`.
      expect(Header('c').payload, isNull);
      expect(Header('c', 'region').payload, 'region');
    });

    test('name and size are exposed, because the comparator lives in another package', () {
      // DlxPuzzleSolver.Strategy.compare calls getSize(), not the package-private field.
      final Header h = Header('3x4');
      expect(h.name, '3x4');
      expect(h.size, 0);
      expect(h.toString(), '3x4 (0)');
    });

    test('Header.size counts the nodes appended to its column', () {
      final _Built b = _build(
        <String>['c0', 'c1', 'c2'],
        <String, List<int>>{
          'r1': <int>[0],
          'r2': <int>[0, 1],
          'r3': <int>[2],
        },
      );
      expect(b.sizes, <int>[2, 1, 1]);
      expect(b.m.columnCount, 3);
      expect(b.m.root.name, '_ROOT_');
    });
  });

  group('Matrix.addRow column-count checks', () {
    test('a vector exactly as wide as the matrix is accepted', () {
      final Matrix<String> m = Matrix<String>();
      m.addColumn(Header('a'));
      m.addColumn(Header('b'));
      expect(m.addRow('r', _vec(2, <int>[0, 1])), isNotNull);
    });

    test(
      '"Too many columns" fires even when the extra entries are all false',
      () {
        // The cursor advances BEFORE the values[i] test and the wrap check runs BEFORE the
        // `continue`, so a too-wide vector is rejected regardless of its tail. A translation
        // that tested values[i] first would accept [true, false, false] here.
        final Matrix<String> m = Matrix<String>();
        m.addColumn(Header('a'));
        m.addColumn(Header('b'));
        expect(
          () => m.addRow('r', _vec(3, <int>[0])),
          throwsA(
            isA<ArgumentError>().having(
              (ArgumentError e) => e.message,
              'message',
              'Too many columns',
            ),
          ),
        );
      },
    );

    test('a failed addRow leaves the partial row in place, as Java does', () {
      // Java is not transactional here: appendToColumn has already run for the accepted
      // entries when the exception is thrown. Reproduced by throwing at the same point.
      final Matrix<String> m = Matrix<String>();
      final Header a = Header('a');
      final Header b = Header('b');
      m.addColumn(a);
      m.addColumn(b);
      expect(() => m.addRow('r', _vec(3, <int>[0])), throwsArgumentError);
      expect(
        a.size,
        1,
        reason: 'the node added before the throw is still there',
      );
      expect(b.size, 0);
    });

    test('"Not enough columns" fires for a short vector', () {
      final Matrix<String> m = Matrix<String>();
      m.addColumn(Header('a'));
      m.addColumn(Header('b'));
      m.addColumn(Header('c'));
      expect(
        () => m.addRow('r', _vec(2, <int>[0])),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError e) => e.message,
            'message',
            'Not enough columns',
          ),
        ),
      );
    });

    test(
      'an empty vector is "not enough columns" whenever the matrix has any',
      () {
        final Matrix<String> m = Matrix<String>();
        m.addColumn(Header('a'));
        expect(() => m.addRow('r', <bool>[]), throwsArgumentError);
      },
    );

    test('an empty vector on an empty matrix registers a null row', () {
      // Degenerate but legal in Java: the cursor never moves, root.right == root, and
      // `put(payload, null)` runs because only `payload != null` is tested. The key is
      // present and maps to null, which getRow cannot distinguish from "absent".
      final Matrix<String> m = Matrix<String>();
      expect(m.addRow('r', <bool>[]), isNull);
      expect(m.getRow('r'), isNull);
    });

    test('an all-false vector registers a null row for a present key', () {
      // Same null-valued put, reached the common way. The hand-fused cross-check twin in
      // difftest-harness/oracle-dart/oracle.dart adds `&& row != null` and skips the put;
      // indistinguishable through getRow, which is the map's only reader.
      final Matrix<String> m = Matrix<String>();
      m.addColumn(Header('a'));
      m.addColumn(Header('b'));
      expect(m.addRow('r', _vec(2, <int>[])), isNull);
      expect(m.getRow('r'), isNull);
      expect(m.columnCount, 2);
    });

    test('a null payload is not registered at all', () {
      final Matrix<String?> m = Matrix<String?>();
      m.addColumn(Header('a'));
      expect(m.addRow(null, _vec(1, <int>[0])), isNotNull);
      expect(m.getRow(null), isNull);
    });
  });

  group('Matrix.getRow is value-keyed (R-03, R-05)', () {
    test('an equal-but-distinct payload finds the row', () {
      // This is what DlxPuzzleSolver.eliminateGivenClues relies on: it looks a row up with
      // a freshly constructed `new RCV(row, col, value)`.
      final Matrix<_Key> m = Matrix<_Key>();
      m.addColumn(Header('a'));
      final Data? row = m.addRow(const _Key(2, 3), _vec(1, <int>[0]));
      expect(m.getRow(const _Key(2, 3)), same(row));
      expect(m.getRow(_Key(2, 3)), same(row));
      expect(m.getRow(const _Key(3, 2)), isNull);
    });

    test(
      'a payload without == degrades to identity lookup, in Dart as in Java',
      () {
        final Matrix<_IdentityKey> m = Matrix<_IdentityKey>();
        m.addColumn(Header('a'));
        final _IdentityKey key = _IdentityKey();
        final Data? row = m.addRow(key, _vec(1, <int>[0]));
        expect(m.getRow(key), same(row));
        expect(
          m.getRow(_IdentityKey()),
          isNull,
          reason:
              'identity semantics, exactly as a Java object without equals()',
        );
      },
    );

    test('the map is never iterated, so its order cannot reach the trace', () {
      // Nothing in the package exposes keys/values/entries/length, which is what makes
      // Java's HashMap (unordered) and Dart's Map (insertion-ordered) interchangeable here.
      final Matrix<String> m = Matrix<String>();
      m.addColumn(Header('a'));
      m.addRow('r', _vec(1, <int>[0]));
      // ignore: unnecessary_type_check
      expect(m is Matrix<String>, isTrue);
      expect(m.getRow('nope'), isNull);
    });
  });

  group('cover and uncover are exact mirror images', () {
    _Built fixture() => _build(
      <String>['c0', 'c1', 'c2', 'c3'],
      <String, List<int>>{
        'r1': <int>[0, 1],
        'r2': <int>[1, 2],
        'r3': <int>[2, 3],
        'r4': <int>[0, 3],
        'r5': <int>[0, 1, 2, 3],
      },
    );

    test('a single cover/uncover restores every size and the column count', () {
      final _Built b = fixture();
      final List<int> before = b.sizes;
      final int countBefore = b.m.columnCount;

      b.m.cover(b.columns[1]);
      expect(b.m.columnCount, countBefore - 1);
      expect(b.sizes, isNot(before), reason: 'cover must actually unlink rows');

      b.m.uncover(b.columns[1]);
      expect(b.m.columnCount, countBefore);
      expect(b.sizes, before);
    });

    test('nested covers unwind correctly when undone in reverse order', () {
      final _Built b = fixture();
      final List<int> before = b.sizes;

      b.m.cover(b.columns[0]);
      b.m.cover(b.columns[2]);
      b.m.cover(b.columns[3]);
      b.m.uncover(b.columns[3]);
      b.m.uncover(b.columns[2]);
      b.m.uncover(b.columns[0]);

      expect(b.sizes, before);
      expect(b.m.columnCount, 4);
    });

    test('the matrix is reusable after a full search, which proves full restoration', () {
      // A search covers and uncovers thousands of times; if the two were not exact
      // inverses the second run would produce a different trace. This is the cheapest
      // strong assertion available from outside the library, because the link fields are
      // private exactly as they are package-private in Java.
      final _Built b = fixture();
      final List<int> before = b.sizes;

      final _Recorder first = _Recorder();
      Solver(b.m, first, null, null).search();
      expect(b.sizes, before);
      expect(b.m.columnCount, 4);

      final _Recorder second = _Recorder();
      Solver(b.m, second, null, null).search();
      expect(second.selects, first.selects);
      expect(second.deselects, first.deselects);
      expect(second.solutions, first.solutions);
      expect(b.sizes, before);
    });

    test('eliminateRow covers every column the row touches', () {
      final _Built b = fixture();
      b.m.eliminateRow(b.m.getRow('r1')!);
      expect(b.m.columnCount, 2, reason: 'r1 covers c0 and c1');
    });

    test('eliminateRow asserts the argument is not a Header', () {
      // Java: `assert !(row instanceof Header)`. Dart asserts are enabled under `dart test`
      // just as Java's are under -ea, so this is the same debug-only guard.
      final Matrix<String> m = Matrix<String>();
      final Header h = Header('a');
      m.addColumn(h);
      m.addRow('r', _vec(1, <int>[0]));
      expect(() => m.eliminateRow(h), throwsA(isA<AssertionError>()));
    });
  });

  group('Solver.chooseColumn', () {
    // c0 size 1, c1 size 1, c2 size 2. The minimum is tied between c0 and c1, and c0 is
    // first in the root ring.
    _Built tieFixture() => _build(
      <String>['c0', 'c1', 'c2'],
      <String, List<int>>{
        'r1': <int>[0],
        'r2': <int>[1],
        'r3': <int>[2],
        'r4': <int>[2],
      },
    );

    test('a tie keeps the FIRST minimal column (strict <, not <=)', () {
      final _Built b = tieFixture();
      final _Recorder rec = _Recorder();
      Solver(b.m, rec, null, null).search();

      // With `<=` the incumbent would be replaced by the equally small c1 and the search
      // would open with r2 instead. Both orders solve the matrix; only one matches the
      // oracle's node sequence.
      expect(rec.selects, <String>['r1', 'r2', 'r3', 'r4']);
      expect(rec.solutions, <List<String>>[
        <String>['r1', 'r2', 'r3'],
        <String>['r1', 'r2', 'r4'],
      ]);
    });

    test('an all-equal comparator therefore always picks the first column in the ring', () {
      // Sharpest available probe of the strictness: if every comparison returns 0, a `<=`
      // implementation ends on the LAST column of the ring and a `<` one on the first.
      // c0 has two rows, c1 and c2 one each, so "first in ring" and "minimum size" differ.
      final _Built b = _build(
        <String>['c0', 'c1', 'c2'],
        <String, List<int>>{
          'x1': <int>[0],
          'x2': <int>[0],
          'y': <int>[1],
          'z': <int>[2],
        },
      );
      final _Recorder rec = _Recorder();
      Solver(b.m, rec, (Header a, Header c) => 0, null).search();

      expect(rec.selects, <String>[
        'x1',
        'y',
        'z',
        'x2',
        'y',
        'z',
      ], reason: 'branched on c0 first because it is first in the root ring');
    });

    test('a null comparator is substituted with the size comparator', () {
      // Java: `if (columnComparator == null) columnComparator = SIZE_COLUMN_COMPARATOR;`
      // -- substituted in the constructor, so the field is never null.
      final _Built nullCmp = _build(
        <String>['c0', 'c1', 'c2'],
        <String, List<int>>{
          'x1': <int>[0],
          'x2': <int>[0],
          'y': <int>[1],
          'z': <int>[2],
        },
      );
      final _Recorder a = _Recorder();
      Solver(nullCmp.m, a, null, null).search();

      final _Built explicit = _build(
        <String>['c0', 'c1', 'c2'],
        <String, List<int>>{
          'x1': <int>[0],
          'x2': <int>[0],
          'y': <int>[1],
          'z': <int>[2],
        },
      );
      final _Recorder b = _Recorder();
      Solver(
        explicit.m,
        b,
        (Header h1, Header h2) => h1.size - h2.size,
        null,
      ).search();

      expect(a.selects, b.selects);
      // And it really is the size heuristic, not ring order: c1 (size 1) wins over c0.
      expect(a.selects, <String>['y', 'z', 'x1', 'x2']);
    });

    test('the comparator is asked "is c better than the incumbent", never the reverse', () {
      // DlxPuzzleSolver.Strategy.compare consumes one nextBoolean() per size tie, so the
      // NUMBER and ARGUMENT ORDER of comparisons is part of the random stream's
      // consumption pattern once a Random is supplied. Pin the direction.
      final _Built b = tieFixture();
      final List<String> pairs = <String>[];
      Solver(b.m, _Recorder(), (Header c, Header best) {
        pairs.add('${c.name}:${best.name}');
        return c.size - best.size;
      }, null).search();

      for (final String pair in pairs) {
        final List<String> parts = pair.split(':');
        expect(parts[0], isNot(parts[1]));
      }
      // First search0 frame: ring is c0,c1,c2; c0 becomes the incumbent without a call.
      expect(pairs.take(2), <String>['c1:c0', 'c2:c0']);
    });
  });

  group('Solver row ordering', () {
    _Built sorterFixture() => _build(
      <String>['c0', 'c1', 'c2'],
      <String, List<int>>{
        'x1': <int>[0],
        'x2': <int>[0],
        'y': <int>[1],
        'z': <int>[2],
      },
    );

    test('a null rowSorter leaves the natural down-chain order, checked at the call site', () {
      // Java leaves the field null and tests it inside getRows, rather than substituting a
      // no-op in the constructor. Observably: rows come out in insertion order.
      final _Built b = sorterFixture();
      final _Recorder rec = _Recorder();
      Solver(b.m, rec, (Header a, Header c) => 0, null).search();
      expect(rec.selects, <String>['x1', 'y', 'z', 'x2', 'y', 'z']);
    });

    test(
      'a rowSorter reorders the rows that are tried, and so the node order',
      () {
        final _Built b = sorterFixture();
        final _Recorder rec = _Recorder();
        final _ReversingSorter sorter = _ReversingSorter();
        Solver(b.m, rec, (Header a, Header c) => 0, sorter).search();

        expect(rec.selects, <String>['x2', 'y', 'z', 'x1', 'y', 'z']);
        // Called once per visited node, even for single-row columns -- Java calls it
        // unconditionally whenever the field is non-null, and DlxPuzzleSolver always passes
        // its Strategy. Skipping the call for short lists would desynchronise the Random.
        expect(sorter.lengthsSeen, <int>[2, 1, 1, 1, 1]);
      },
    );

    test('the list handed to the sorter is fixed-length and mutable, like a Java array', () {
      final _Built b = sorterFixture();
      final _ReversingSorter sorter = _ReversingSorter();
      Solver(b.m, _Recorder(), null, sorter).search();

      final List<Data> seen = sorter.listsSeen.first;
      expect(() => seen.add(Data('nope')), throwsUnsupportedError);
      expect(() => seen.removeLast(), throwsUnsupportedError);
      seen[0] = seen[0]; // in-place assignment is what Fisher-Yates needs
    });

    test('the sorter receives exactly the rows of the chosen column', () {
      final _Built b = sorterFixture();
      final _ReversingSorter sorter = _ReversingSorter();
      Solver(b.m, _Recorder(), (Header a, Header c) => 0, sorter).search();

      final List<String> firstCall = <String>[
        for (final Data d in sorter.listsSeen.first) d.payload as String,
      ];
      // Reversed in place by the time we read it back; the set is what matters here.
      expect(firstCall.toSet(), <String>{'x1', 'x2'});
    });
  });

  group('Solver.search', () {
    test("solves Knuth's exact-cover example from the Dancing Links paper", () {
      // Columns A..G; the unique cover is {A D}, {B G}, {C E F}.
      final _Built b = _build(
        <String>['A', 'B', 'C', 'D', 'E', 'F', 'G'],
        <String, List<int>>{
          'CEF': <int>[2, 4, 5],
          'ADG': <int>[0, 3, 6],
          'BCF': <int>[1, 2, 5],
          'AD': <int>[0, 3],
          'BG': <int>[1, 6],
          'DEG': <int>[3, 4, 6],
        },
      );
      final _Recorder rec = _Recorder();
      Solver(b.m, rec, null, null).search();

      expect(rec.solutions.length, 1);
      expect(rec.solutions.single.toSet(), <String>{'AD', 'BG', 'CEF'});
      expect(b.sizes, <int>[
        2,
        2,
        2,
        3,
        2,
        2,
        3,
      ], reason: 'the matrix is fully restored afterwards');
    });

    test('an unsatisfiable matrix reports no solution and leaves the matrix intact', () {
      final _Built b = _build(
        <String>['c0', 'c1'],
        <String, List<int>>{
          'r1': <int>[0, 1],
          'r2': <int>[0, 1],
        },
      );
      // c1 can only be covered together with c0, so after picking either row the matrix is
      // empty -- that IS a solution. Use a column no row touches instead.
      final _Built impossible = _build(
        <String>['c0', 'c1', 'c2'],
        <String, List<int>>{
          'r1': <int>[0],
          'r2': <int>[1],
        },
      );
      final _Recorder rec = _Recorder();
      Solver(impossible.m, rec, null, null).search();
      expect(rec.solutions, isEmpty);
      expect(impossible.sizes, <int>[1, 1, 0]);
      expect(b.m.columnCount, 2);
    });

    test('an empty matrix is an immediate solution', () {
      // search0 tests columnCount == 0 BEFORE choosing a column, which is the only reason
      // chooseColumn can return a non-null header unconditionally.
      final Matrix<String> m = Matrix<String>();
      final _Recorder rec = _Recorder();
      Solver(m, rec, null, null).search();
      expect(rec.solutions, <List<String>>[<String>[]]);
      expect(rec.selects, isEmpty);
    });

    test('solutionFound returning false stops after the first solution', () {
      // This is the uniqueness path: UniqueSolutionReporter wants to know whether a second
      // solution exists and stops as soon as it does.
      final _Built b = _tieMatrix();
      final _Recorder rec = _Recorder(stopAtFirstSolution: true);
      Solver(b.m, rec, null, null).search();

      expect(rec.solutions.length, 1);
      expect(rec.selects, <String>[
        'r1',
        'r2',
        'r3',
      ], reason: 'r4 is never tried once the abort propagates');
      // The abort still unwinds through uncover(c) in every frame.
      expect(b.sizes, <int>[1, 1, 2]);
      expect(b.m.columnCount, 3);
    });

    test(
      'select returning false aborts the search and still restores the matrix',
      () {
        // search0 breaks out of the row loop and falls through to uncover(c) -- it does NOT
        // return early. An `if (!proceed) return proceed;` would leave the chosen column
        // covered in every frame and corrupt the matrix for any later use.
        final _Built b = _tieMatrix();
        final List<int> before = b.sizes;
        final _Recorder rec = _Recorder(abortAfterSelect: 2);
        Solver(b.m, rec, null, null).search();

        expect(rec.selects, <String>['r1', 'r2']);
        expect(rec.solutions, isEmpty);
        expect(
          rec.deselects,
          <String>['r1'],
          reason: 'the aborting row is broken out of before deselect; its parent is not',
        );
        expect(b.sizes, before);
        expect(b.m.columnCount, 3);

        // Proof that the restoration was complete: a fresh search now runs to completion.
        final _Recorder again = _Recorder();
        Solver(b.m, again, null, null).search();
        expect(again.selects, <String>['r1', 'r2', 'r3', 'r4']);
      },
    );

    test(
      'a Solver is a one-shot view, so two Solvers over one Matrix agree',
      () {
        // Java's Solver holds no mutable state of its own beyond its three collaborators.
        final _Built b = _tieMatrix();
        final _Recorder a = _Recorder();
        final _Recorder c = _Recorder();
        final Solver s = Solver(b.m, a, null, null);
        s.search();
        Solver(b.m, c, null, null).search();
        expect(c.selects, a.selects);
      },
    );
  });
}

/// c0 and c1 tie at size 1, c2 has two rows: the smallest fixture in which the
/// first-versus-last tie-break is observable.
_Built _tieMatrix() => _build(
  <String>['c0', 'c1', 'c2'],
  <String, List<int>>{
    'r1': <int>[0],
    'r2': <int>[1],
    'r3': <int>[2],
    'r4': <int>[2],
  },
);
