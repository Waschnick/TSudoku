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

/// Knuth's Dancing Links (DLX) exact-cover solver -- the whole
/// `com.googlecode.andoku.dlx` package as **one** Dart library.
///
/// ## Why one file
///
/// In Java, `Data.column`, `Data.up/down/left/right` and `Header.size` have no access
/// modifier, so they are *package-private*: `Matrix` and `Solver` write them directly
/// while `com.googlecode.andoku.solver.DlxPuzzleSolver` -- in a different package --
/// cannot. Dart's `_` privacy is per **library**, not per class or per directory. Putting
/// all six types in one library therefore reproduces Java's visibility graph exactly:
/// `_column`, `_up`, `_down`, `_left`, `_right` and `_size` are reachable from [Matrix]
/// and [Solver] and from nowhere else. Splitting this into six files would force those
/// fields public and hand every future caller a way to corrupt the links.
///
/// The only members that are public here are the ones Java declares `public`:
/// `Data.getPayload`, `Header.getName`, `Header.getSize`, and the `Matrix`/`Solver` API.
///
/// ## Why the node order matters
///
/// This is the solver on the real gameplay path -- `AndokuPuzzle.computeSolution` uses it
/// both to obtain the ground-truth solution and to decide uniqueness -- and the
/// differential trace prints the **node count** alongside the solution string. Two
/// implementations that both solve every puzzle correctly will still fail the gate if they
/// visit a different number of nodes. Every deviation flagged in the comments below changes
/// that count while leaving the answers intact, which is precisely what makes them
/// dangerous.
library;

/// A node in the sparse-matrix torus; `dlx/Data.java`.
///
/// The four link fields are initialised to `this`, so a fresh node is a one-element
/// circular list in both axes. `Matrix.addRow`/`addColumn` then splice nodes into existing
/// rings. Java relies on the same self-link trick, and it is what lets `appendToRow` and
/// `appendToColumn` be written without a special case for the first element.
class Data {
  /// Java: package-private `Header column`, default `null`.
  ///
  /// A [Header] never has its own `_column` assigned -- Java leaves it `null` too. Nothing
  /// reads it: `Matrix.cover`/`uncover` walk `i.right`/`i.left` starting from a *row* node,
  /// and headers live only in the root ring, never inside a data row. Kept nullable rather
  /// than `late` so that a stray read fails the same way Java's would (a null dereference),
  /// instead of with a `LateInitializationError` that has no Java counterpart.
  Header? _column;

  /// Java: package-private `Data up, down, left, right`.
  ///
  /// `late` because Java's constructor assigns `this` to all four, and Dart forbids `this`
  /// in an initialiser list.
  late Data _up;
  late Data _down;
  late Data _left;
  late Data _right;

  final Object? _payload;

  Data(Object? payload) : _payload = payload {
    _up = this;
    _down = this;
    _left = this;
    _right = this;
  }

  /// Java: `public Object getPayload()`.
  ///
  /// The payload is what identifies a candidate placement to the caller;
  /// `DlxPuzzleSolver.Strategy.select` casts it back to its `RCV` triple. Typed
  /// `Object?` rather than generically, because Java types it `Object` on `Data` even
  /// though `Matrix` is generic in `P` -- narrowing it here would change which casts the
  /// caller has to write and could hide a mismatch the Java version would have thrown on.
  Object? get payload => _payload;
}

/// A column header; `dlx/Header.java`.
///
/// Headers are [Data] nodes that additionally carry a name and a live count of the nodes in
/// their column. The matrix root (`_ROOT_`) is also a `Header`, which is why
/// `Solver.chooseColumn` can cast every node of the root ring to `Header`.
class Header extends Data {
  final String _name;

  /// Java: package-private `int size`, maintained by `Matrix`.
  ///
  /// This is the *selection heuristic input*, not just bookkeeping: `cover` decrements it
  /// and `uncover` increments it, and `Solver.chooseColumn` picks the minimum. An off-by-one
  /// here does not break correctness -- it changes which column is branched on, and so the
  /// node count. `Solver.getRows` additionally trusts it to equal the column's chain length.
  int _size;

  /// Java has two constructors, `Header(String)` and `Header(String, Object)`; the
  /// one-argument form passes `super(null)`. One optional positional parameter is exactly
  /// equivalent.
  /// `[super.payload]` forwards to `Data(Object? payload)` with a default of `null`,
  /// which is what the one-argument Java constructor passes explicitly.
  Header(String name, [super.payload]) : _name = name, _size = 0;

  /// Java: `public String getName()`.
  String get name => _name;

  /// Java: `public int getSize()`.
  ///
  /// Public because `DlxPuzzleSolver.Strategy.compare` uses the *getter*, not the field --
  /// it is in another package. The default comparator inside [Solver] reads the field
  /// directly, as Java's does.
  int get size => _size;

  /// Java: `toString()` returns `name + " (" + size + ")"`. Kept verbatim; it appears in no
  /// trace, but a debugger print that differs from the Java one wastes time.
  @override
  String toString() => '$_name ($_size)';
}

/// The callbacks `Solver` fires during the search; `dlx/DlxListener.java`.
///
/// [select] and [solutionFound] return "keep going": returning `false` aborts the search
/// through every frame (see `Solver.search0`'s `proceed` plumbing). `DlxPuzzleSolver` uses
/// that to stop after the second solution when it only needs to know "is it unique".
abstract interface class DlxListener {
  /// Called with the row about to be tried. Return `false` to abort the whole search.
  bool select(Data row);

  /// Called when backtracking out of a row previously passed to [select].
  void deselect(Data row);

  /// Called when the matrix is empty, i.e. a complete cover was found. Return `false` to
  /// stop searching for further solutions.
  bool solutionFound();
}

/// Reorders the candidate rows of the chosen column before they are tried;
/// `dlx/RowSorter.java`.
///
/// Java's signature is `void sort(Data[] rows)` -- it mutates the array in place, and
/// `Solver` keeps using the same array afterwards. `DlxPuzzleSolver`'s implementation is a
/// Fisher-Yates shuffle that returns immediately when its `Random` is `null`, so on the
/// deterministic path (the generator is the only caller that passes a `Random`) this is a
/// no-op -- but it must still be *called* in the same place, because a sorter that reorders
/// rows changes the node count.
///
/// The list handed to [sort] is fixed-length and mutable, like the Java array:
/// `List.sort` and element assignment work; `add`/`removeLast` throw, exactly as they would
/// on a Java array.
abstract interface class RowSorter {
  void sort(List<Data> rows);
}

/// The sparse exact-cover matrix; `dlx/Matrix.java`.
///
/// `P` is the payload type. The payload must implement `==`/`hashCode` as a value type
/// (rule R-03) because [getRow] looks rows up by it; `DlxPuzzleSolver.RCV` does.
class Matrix<P> {
  final Header _root = Header('_ROOT_');

  /// Java: `private final Map<P, Data> rowByPayload = new HashMap<P, Data>()`.
  ///
  /// R-05: a plain Dart `Map` is the correct translation and **no ordering guarantee is
  /// needed**. The Java map is a `HashMap`, so its iteration order is unspecified there
  /// already -- but it is never iterated. The only reads in the entire package are
  /// [getRow]'s single-key lookup and the `put` in [addRow]; `keySet`, `values`,
  /// `entrySet` and `size` are never touched. Hash order therefore cannot escape into the
  /// trace, so Dart's insertion-ordered `Map` is free to differ from Java's bucket order.
  ///
  /// The value type is `Data?`, not `Data`: Java's `put` is reached even when `row` is
  /// `null` (see [addRow]), and a `HashMap` happily stores a null value.
  final Map<P, Data?> _rowByPayload = <P, Data?>{};

  int _columnCount = 0;

  /// Java: `public Header getRoot()`.
  Header get root => _root;

  /// Java: `public int getColumnCount()`.
  ///
  /// Invariant worth knowing because [Solver] depends on it: this always equals the length
  /// of the root ring. [addColumn] splices a column in and increments; [cover] unsplices
  /// and decrements; [uncover] re-splices and increments. That is why
  /// `Solver.chooseColumn` can never be reached with an empty ring.
  int get columnCount => _columnCount;

  /// Java: `public void addColumn(Header column)`.
  void addColumn(Header column) {
    _appendToRow(_root, column);

    _columnCount++;
  }

  /// Java: `public Data addRow(P payload, boolean[] values)`.
  ///
  /// Walks the column ring in lockstep with [values] and returns the row's first node, or
  /// `null` when [values] is all-`false`.
  ///
  /// The loop-exit condition is worth spelling out, because it is easy to translate into
  /// something that accepts the wrong lengths:
  ///
  /// * `column` is advanced **before** the `values[i]` test, and the wrap check
  ///   (`column == root` -> "Too many columns") fires even for a `false` entry. So a
  ///   vector longer than [columnCount] is rejected regardless of what its tail contains.
  /// * The "Not enough columns" check runs **after** the loop and tests
  ///   `column.right != root`, i.e. "the cursor did not stop on the last column". With
  ///   `values.length == columnCount` the cursor lands on the last column and
  ///   `column.right == root`, so it passes.
  /// * Degenerate case, reproduced rather than guarded: `values.length == 0` leaves
  ///   `column == root`. If the matrix has any columns, `root.right != root` and this
  ///   throws "Not enough columns". If the matrix has *no* columns it passes, and a `null`
  ///   row is registered for the payload.
  ///
  /// Both messages are Java `IllegalArgumentException`; [ArgumentError] is the Dart
  /// counterpart (R-13: no checked exceptions to carry over).
  Data? addRow(P payload, List<bool> values) {
    Data? row;

    // Java declares this `Header column` and casts on every assignment. The cast is kept
    // so that a non-Header in the root ring throws here, as it does in Java, rather than
    // silently producing a Data with no size counter.
    Header column = _root;
    for (int i = 0; i < values.length; i++) {
      column = column._right as Header;
      if (column == _root) {
        throw ArgumentError('Too many columns');
      }

      if (!values[i]) {
        continue;
      }

      final Data data = Data(payload);
      _appendToColumn(column, data);

      if (row != null) {
        _appendToRow(row, data);
      } else {
        row = data;
      }
    }

    if (column._right != _root) {
      throw ArgumentError('Not enough columns');
    }

    // Java: `if (payload != null) this.rowByPayload.put(payload, row);` -- note it does
    // NOT also test `row != null`. An all-false vector therefore registers a null mapping,
    // and getRow(payload) returns null for a payload that *is* present as a key. Preserved
    // verbatim via a `Data?` value type. (The hand-fused cross-check twin in
    // difftest-harness/oracle-dart/oracle.dart adds `&& row != null` and so skips the put.
    // Indistinguishable through getRow, which is the only reader -- but Java is the
    // definition, so the put stays.)
    if (payload != null) {
      _rowByPayload[payload] = row;
    }

    return row;
  }

  /// Java: `public Data getRow(P payload)`.
  ///
  /// Returns `null` both for an unknown payload and for a payload registered with a null
  /// row; Java cannot tell those apart either.
  Data? getRow(P payload) => _rowByPayload[payload];

  /// Java: `public void cover(Header column)`.
  ///
  /// Removes `column` from the root ring, then removes every row that covers it from all
  /// of its *other* columns. Must be the exact mirror image of [uncover] -- see the note
  /// there, which spells out why the statement order is load-bearing.
  void cover(Header column) {
    column._left._right = column._right;
    column._right._left = column._left;

    for (Data i = column._down; i != column; i = i._down) {
      for (Data j = i._right; j != i; j = j._right) {
        j._up._down = j._down;
        j._down._up = j._up;
        j._column!._size--;
      }
    }

    _columnCount--;
  }

  /// Java: `public void uncover(Header column)`.
  ///
  /// The precise mirror of [cover], and the mirroring is structural, not cosmetic:
  ///
  /// * [cover] unsplices the header **first**, then walks `down`/`right`;
  ///   [uncover] walks `up`/`left` **first**, then re-splices the header.
  /// * [cover] decrements `_size` **after** rewiring the vertical links;
  ///   [uncover] increments it **before**. (In Java the three statements inside the inner
  ///   loop are literally in reverse order, `size++` first.)
  /// * `_columnCount` goes down in [cover] and back up here.
  ///
  /// Dancing Links restores state by undoing operations in exactly reverse order; a
  /// "tidied up" uncover that walks `down`/`right` instead produces a *different but still
  /// consistent* torus for any column whose rows were partially removed, and the search then
  /// explores a different tree. The puzzles still solve. The node count does not match.
  void uncover(Header column) {
    for (Data i = column._up; i != column; i = i._up) {
      for (Data j = i._left; j != i; j = j._left) {
        j._column!._size++;
        j._up._down = j;
        j._down._up = j;
      }
    }

    column._left._right = column;
    column._right._left = column;

    _columnCount++;
  }

  /// Java: `public void eliminateRow(Data row)`.
  ///
  /// Forces `row` into the solution without entering the search: covers its own column and
  /// every other column it touches. `DlxPuzzleSolver.eliminateGivenClues` uses it for the
  /// givens, which is why the search starts from a reduced matrix (and why `columnCount`
  /// is not 81 + 9*regions when `search` is first called).
  ///
  /// The `assert` is Java's `assert !(row instanceof Header)`. Dart asserts are likewise
  /// debug-only (stripped in release and in `dart compile exe` without `--enable-asserts`),
  /// so this matches Java's `-ea`-dependent behaviour rather than adding a new check.
  void eliminateRow(Data row) {
    assert(row is! Header);

    cover(row._column!);

    for (Data j = row._right; j != row; j = j._right) {
      cover(j._column!);
    }
  }

  /// Java: `private static void appendToRow(Data row, Data data)` -- splice `data` in as
  /// the new last element of `row`'s horizontal ring.
  static void _appendToRow(Data row, Data data) {
    final Data last = row._left;

    last._right = data;
    data._left = last;
    row._left = data;
    data._right = row;
  }

  /// Java: `private static void appendToColumn(Header column, Data data)` -- splice `data`
  /// in as the new last element of `column`'s vertical ring, and point it back at the
  /// header. This is the only place `_size` is incremented outside [uncover].
  static void _appendToColumn(Header column, Data data) {
    final Data last = column._up;

    last._down = data;
    data._up = last;
    column._up = data;
    data._down = column;

    data._column = column;
    column._size++;
  }
}

/// The depth-first exact-cover search; `dlx/Solver.java`.
///
/// Typed `Matrix<Object?>` for Java's `Matrix<?>`: the search never touches the payload, so
/// the type argument is irrelevant to it. Dart class generics are covariant, so a
/// `Matrix<RCV>` is accepted without a cast.
class Solver {
  /// Java: `private static final Comparator<Header> SIZE_COLUMN_COMPARATOR`.
  ///
  /// `h1.size - h2.size`, kept as a subtraction rather than `compareTo`. R-10 would demand
  /// `.toSigned(32)` if this could overflow a Java `int`, but `_size` is a non-negative
  /// node count bounded by the number of rows (729 for a 9x9 board), so the difference can
  /// never leave the 32-bit range. The subtraction is retained anyway because the
  /// *magnitude* is observable to any caller that wraps this comparator.
  ///
  /// Note that `DlxPuzzleSolver` never actually reaches this: it passes its own `Strategy`
  /// as the comparator. With a `null` `Random` that strategy computes the same difference,
  /// so the two agree on the deterministic path -- which is why the hand-fused cross-check
  /// twin can inline `h.size - best.size` and still match.
  static int _sizeColumnComparator(Header h1, Header h2) => h1._size - h2._size;

  final Matrix<Object?> _m;
  final DlxListener _listener;
  final Comparator<Header> _columnComparator;
  final RowSorter? _rowSorter;

  /// Java's constructor applies **two different null policies**, and both are reproduced:
  ///
  /// * `columnComparator == null` is *substituted* with `SIZE_COLUMN_COMPARATOR` here, so
  ///   the field is never null and `chooseColumn` can call it unconditionally.
  /// * `rowSorter == null` is *left* null and tested at the call site in [_getRows].
  ///
  /// There is no reason for the asymmetry other than how it was written, and collapsing it
  /// either way (a no-op default sorter, or a nullable comparator checked per comparison)
  /// is behaviourally identical -- but it is the kind of "while I'm here" edit that makes a
  /// later diff against the Java unreadable, so the shape stays.
  ///
  /// Java also throws `NullPointerException` for a null `m` or `listener`. Dart's sound
  /// null safety makes both parameters non-nullable, so those checks are unrepresentable
  /// and therefore dropped: the analyzer rejects at compile time what Java rejected at
  /// run time.
  Solver(
    Matrix<Object?> m,
    DlxListener listener,
    Comparator<Header>? columnComparator,
    RowSorter? rowSorter,
  ) : _m = m,
      _listener = listener,
      _columnComparator = columnComparator ?? _sizeColumnComparator,
      _rowSorter = rowSorter;

  /// Java: `public void search()` -- discards `search0`'s return value.
  void search() {
    _search0();
  }

  /// Java: `private boolean search0()`. The returned `boolean` is "proceed"; `false`
  /// propagates an abort up through every frame.
  ///
  /// Two details that are not obvious from the shape:
  ///
  /// * The row loop breaks on `!proceed` **twice** -- once right after `select`, before any
  ///   covering, and once after `deselect`. The first break leaves the row uncovered; the
  ///   second has already uncovered it. Both paths then fall through to `uncover(c)`, so
  ///   the matrix is always restored even on an abort. An early `return` instead of the
  ///   break would skip that and leave the matrix corrupted for any later call.
  /// * Covering walks the row rightwards and uncovering walks it **leftwards**, so the
  ///   columns are restored in reverse order -- the same mirroring requirement as
  ///   `Matrix.cover`/`uncover`.
  bool _search0() {
    final Header root = _m.root;
    if (_m.columnCount == 0) {
      return _listener.solutionFound();
    }

    bool proceed = true;

    final Header c = _chooseColumn(root);
    _m.cover(c);

    for (final Data row in _getRows(c)) {
      proceed = _listener.select(row);

      if (!proceed) {
        break;
      }

      for (Data j = row._right; j != row; j = j._right) {
        _m.cover(j._column!);
      }

      proceed = _search0();

      for (Data j = row._left; j != row; j = j._left) {
        _m.uncover(j._column!);
      }

      _listener.deselect(row);

      if (!proceed) {
        break;
      }
    }

    _m.uncover(c);

    return proceed;
  }

  /// Java: `private Header chooseColumn(Header root)`.
  ///
  /// **The strict `< 0` is the single most fragile line in this file.** Java reads
  /// `if (best == null || columnComparator.compare(c, best) < 0)`, so among columns of
  /// equal minimal size it keeps the **first** one in root-ring order. A `<= 0` would also
  /// find a minimum, also solve every puzzle, and silently branch on the *last* tied
  /// column instead -- a different search tree and a different node count on essentially
  /// every puzzle with a tie, which is nearly all of them.
  ///
  /// The cast `(Header) root.right` is kept: Java throws `ClassCastException` if a non-
  /// header is ever spliced into the root ring, and the Dart cast throws `TypeError` in the
  /// same place. Silently skipping such a node would mask a corrupted matrix.
  ///
  /// Java returns `null` when the ring is empty, and the caller would then NPE on
  /// `m.cover(c)`. That is unreachable because [_search0] has already returned when
  /// `columnCount == 0` and `columnCount` equals the ring length; `best!` keeps it just as
  /// loud if the invariant is ever broken.
  ///
  /// One caveat on the comparator contract: with a `Random`, `DlxPuzzleSolver.Strategy`
  /// breaks size ties by coin flip, which makes `compare` non-transitive and not a valid
  /// total order. This linear scan tolerates that -- it only ever asks "is `c` better than
  /// the incumbent" -- but it also means each tie consumes one `nextBoolean()`, so the
  /// number of comparisons performed here is part of the random stream's consumption
  /// pattern. Do not reorder or short-circuit this loop.
  Header _chooseColumn(Header root) {
    Header? best;

    for (Header c = root._right as Header; c != root; c = c._right as Header) {
      if (best == null || _columnComparator(c, best) < 0) {
        best = c;
      }
    }

    return best!;
  }

  /// Java: `private Data[] getRows(Header c)` -- snapshot the column's rows, optionally
  /// reorder them, and hand them to [_search0]'s loop.
  ///
  /// Java allocates `new Data[c.size]` and then fills it by walking `down` from the header,
  /// i.e. it **trusts `Header.size` to equal the chain length**. If the two ever disagreed:
  ///
  /// * chain longer than `size` -> `ArrayIndexOutOfBoundsException` on `rows[idx++]`;
  /// * chain shorter than `size` -> trailing `null`s, no exception, and then a
  ///   `NullPointerException` deep inside `listener.select(null)` or `row.right` -- far
  ///   from the cause.
  ///
  /// The second case is the dangerous one, so the translation makes it loud. The fixed-
  /// length nullable buffer mirrors `new Data[c.size]` and keeps the range error for the
  /// "too long" case; the explicit `idx != length` check turns the "too short" case into an
  /// immediate [StateError] naming the broken invariant instead of a null dereference
  /// somewhere downstream. Neither branch can fire while `Matrix` maintains `_size`
  /// correctly -- which is exactly why a silent failure here would be so hard to find.
  ///
  /// The result is fixed-length (like the Java array) and mutable, because [RowSorter]
  /// sorts it in place.
  List<Data> _getRows(Header c) {
    final List<Data?> rows = List<Data?>.filled(c._size, null, growable: false);

    int idx = 0;
    for (Data row = c._down; row != c; row = row._down) {
      // RangeError here is Java's ArrayIndexOutOfBoundsException.
      rows[idx++] = row;
    }
    if (idx != rows.length) {
      throw StateError(
        'Header.size (${rows.length}) disagrees with the column chain length ($idx) '
        'for column "${c._name}"; the matrix links are corrupt. Java would have left '
        'trailing nulls here and failed later with a NullPointerException.',
      );
    }

    final List<Data> result = List<Data>.generate(
      idx,
      (int i) => rows[i]!,
      growable: false,
    );

    // R-09 does not apply to this call: the sorter is not a comparison sort. Java's
    // implementation is an in-place Fisher-Yates shuffle, so there are no ties to break and
    // no stability requirement -- but there is a *sequence* requirement, since it draws
    // from the shared Random. Hence the null test is here, at the call site, and not folded
    // into a default no-op sorter in the constructor: skipping the call must skip it
    // exactly where Java skips it.
    final RowSorter? rowSorter = _rowSorter;
    if (rowSorter != null) {
      rowSorter.sort(result);
    }

    return result;
  }
}
