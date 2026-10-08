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
// Ported from: the JDK class java.util.Random (no file in FreeSodukuSrc; the
//              original simply uses java.util.Random). Its consumers in the
//              upstream tree are:
//                app/src/main/java/com/googlecode/andoku/solver/DlxPuzzleSolver.java:41
//                app/src/main/java/com/googlecode/andoku/solver/BrutePuzzleSolver.java:36
// Translation rules applied: R-06, R-10, R-13

/// `java.util.Random`, transcribed digit for digit.
///
/// ## Why this class exists at all
///
/// Rule R-06. `dart:math`'s `Random` is a *different generator* -- Dart uses a
/// 64-bit xorshift-family algorithm, the JDK a 48-bit linear congruential one. A
/// seeded Dart `Random` and a seeded Java `Random` agree on nothing beyond the
/// value range. Anywhere the original's output depends on a seeded sequence, the
/// only way to keep the Dart port and the JVM oracle byte-identical is to run
/// the JDK's arithmetic, so that is what this class does.
///
/// ## Reachability -- read this before trusting it
///
/// The only construction of `DlxPuzzleSolver` anywhere in the shipped app is
/// `AndokuPuzzle.java:350`:
///
/// ```java
/// PuzzleSolver solver = new DlxPuzzleSolver();
/// ```
///
/// which routes through `DlxPuzzleSolver(Random random)` with `random == null`.
/// Both randomised branches in that class are therefore dead in the shipped
/// game: the column comparator short-circuits on `diff != 0 || random == null`
/// (`DlxPuzzleSolver.java:151`) and the row sorter returns immediately on
/// `random == null` (`DlxPuzzleSolver.java:158`). `BrutePuzzleSolver`, the other
/// consumer, is on the confirmed-dead list entirely.
///
/// The consequence matters: **no call into this class is covered by the
/// differential oracle.** The 45,100-puzzle trace comparison cannot validate one
/// line of it, because nothing in the traced path ever reaches it. The class
/// exists so those branches behave as Java would *if* they are ever reached --
/// for example by a future puzzle generator, which is the thing a seeded shuffle
/// is actually for. Its correctness rests entirely on golden vectors generated
/// by a real JDK 17 and baked into `test/java_random_test.dart`. That is why
/// those vectors are mandatory rather than a nicety: they are the *only*
/// evidence this file is right. If you change anything here, the vectors are the
/// gate.
///
/// ## The three traps
///
/// 1. **48-bit state, 64-bit multiply.** `_seed * 0x5DEECE66D` needs up to 83
///    bits. Dart's native `int` is 64-bit two's complement and *wraps*, so the
///    product's high bits are lost -- which is harmless, because the low 64 bits
///    of a two's-complement product are exact and we immediately keep only the
///    low 48. Java's `long` does exactly the same thing. (This reasoning is
///    specific to native Dart. Compiled to JavaScript, `int` is a double and the
///    multiply loses *low* bits instead, silently. The engine does not target
///    web; see PORT-GUIDELINES R-10.)
///
/// 2. **`next(bits)` returns a signed 32-bit value.** Java's
///    `(int)(seed >>> (48 - bits))` truncates to 32 bits, so `next(32)` can come
///    back negative. Hence `.toSigned(32)`.
///
/// 3. **The rejection loop in [nextInt] relies on 32-bit overflow** -- the trap
///    this whole file is most likely to be got wrong on. See [nextInt].
///
/// Not a cryptographic generator, and not thread-safe; the JDK's version uses an
/// `AtomicLong`, which has no counterpart and no purpose in single-isolate Dart.
class JavaRandom {
  /// Java: `private static final long multiplier = 0x5DEECE66DL`.
  static const int _multiplier = 0x5DEECE66D;

  /// Java: `private static final long addend = 0xBL`.
  static const int _addend = 0xB;

  /// Java: `private static final long mask = (1L << 48) - 1`.
  static const int _mask = (1 << 48) - 1;

  /// The scrambled 48-bit LCG state. Always in `[0, 2^48)`.
  int _seed;

  /// Java: `public Random(long seed)`, whose body is `this.seed = new
  /// AtomicLong(initialScramble(seed))` with
  /// `initialScramble(seed) = (seed ^ multiplier) & mask`.
  ///
  /// [seed] stands in for a Java `long`, which Dart's 64-bit `int` matches
  /// exactly -- including the bit pattern of negative seeds, which is why the
  /// test vectors include `-1`. The XOR with the multiplier is what stops
  /// `Random(0)` from starting at state zero.
  ///
  /// There is deliberately no zero-argument constructor. Java's `new Random()`
  /// seeds from the clock, and a time-seeded generator inside an engine whose
  /// whole correctness story is reproducible traces would be a hazard, not a
  /// convenience. Callers that want unpredictability pass their own seed.
  JavaRandom(int seed) : _seed = (seed ^ _multiplier) & _mask;

  /// Java: `protected int next(int bits)`.
  ///
  /// ```java
  /// seed = (seed * multiplier + addend) & mask;
  /// return (int)(seed >>> (48 - bits));
  /// ```
  ///
  /// The `>>` here is a *logical* shift in effect, not an arithmetic one:
  /// `_seed` is masked to 48 bits and so never negative, so Dart's `>>` and
  /// Java's `>>>` agree. `.toSigned(32)` reproduces the `(int)` cast, and it is
  /// **load-bearing for `bits == 32`**, which [nextInt] (no-arg) asks for: without
  /// it `JavaRandom(0).nextInt()` returns 3139482720 instead of Java's
  /// -1155484576. An earlier version of this comment called it "documentation of
  /// intent" because only `_next(31)` and `_next(1)` were reachable then --
  /// mutation testing confirmed its removal was undetectable by the whole suite.
  /// There is now a golden vector for the 32-bit case specifically to kill that
  /// mutant.
  int _next(int bits) {
    _seed = (_seed * _multiplier + _addend) & _mask;
    return (_seed >> (48 - bits)).toSigned(32);
  }

  /// Java: `public int nextInt()` -- the no-arg form, `next(32)`, which returns a
  /// value spanning the whole signed 32-bit range INCLUDING negatives.
  ///
  /// ```java
  /// public int nextInt() { return next(32); }      // JDK 17 Random.java:259
  /// ```
  ///
  /// This exists because the in-scope Java uses it in twelve places, all of the
  /// shape `new Random().nextInt()`:
  ///
  /// - `AndokuPuzzle.java:799, 800, 835, 836, 890, 891, 913, 914, 935, 936` --
  ///   inside `isActualMarksOk`, `getAll_isActualMarksOk`, `needAnyCellAnotations`,
  ///   `getAll_needAnyCellAnotations` and `anyTrivialSolution`.
  /// - `Solver_Manager.java:558, 591` --
  ///   `index_sol = Math.abs(new Random().nextInt() % list_hints.size())`, i.e.
  ///   *which hint the player is shown*.
  ///
  /// ## Two traps at those call sites
  ///
  /// **1. Dart's `%` is not Java's `%`.** Java truncates toward zero; Dart is
  /// Euclidean and always returns a non-negative result for a positive divisor.
  /// So `Math.abs(new Random().nextInt() % n)` does **not** translate as
  /// `r.nextInt() % n`. Measured on the pinned JDK 17:
  ///
  /// | | `x = JavaRandom(0).nextInt()` = -1155484576 | `y = JavaRandom(42).nextInt()` = -1170105035 |
  /// |---|---|---|
  /// | Java `x % 9` | `-1` | `-5` |
  /// | Java `Math.abs(x % 9)` | **`1`** | **`5`** |
  /// | Dart `x % 9` | `8` | `4` |
  /// | Dart `x.remainder(9).abs()` | **`1`** | **`5`** |
  ///
  /// Use `.remainder(n).abs()`. A different value here is a different starting
  /// cell in `needAnyCellAnotations`, and a different hint in `Solver_Manager` --
  /// user-visible, not internal.
  ///
  /// **2. `new Random()` is time-seeded, and that is deliberately NOT reproduced.**
  /// Java's no-arg constructor seeds from `seedUniquifier() ^ System.nanoTime()`,
  /// so every one of those twelve call sites is nondeterministic *in the original*
  /// -- two runs of the Java app disagree. There is therefore nothing to be
  /// byte-identical to, and this class offers no no-arg constructor on purpose: a
  /// trace that depends on an unseeded `Random` cannot be compared at all. When
  /// those call sites are ported, thread an explicit seed in from the caller and
  /// record the choice, rather than reaching for `dart:math` (which is an R-06
  /// violation that nothing would catch) or inventing a hidden time seed.
  /// Dart has no overloading, so Java's `nextInt()` and `nextInt(int)` collapse
  /// into this one method with an optional bound. Both Java call shapes survive
  /// unchanged: `r.nextInt()` and `r.nextInt(9)`.
  int nextInt([int? bound]) =>
      bound == null ? _next(32) : _nextIntBounded(bound);

  /// Java: `public int nextInt(int bound)`.
  ///
  /// ```java
  /// int r = next(31);
  /// int m = bound - 1;
  /// if ((bound & m) == 0)          // bound is a power of two
  ///   r = (int)((bound * (long)r) >> 31);
  /// else                           // reject over-represented candidates
  ///   for (int u = r; u - (r = u % bound) + m < 0; u = next(31));
  /// return r;
  /// ```
  ///
  /// Two branches, and each has a trap.
  ///
  /// **Power-of-two fast path.** Java widens to `long` before multiplying
  /// (`bound * (long) r`) precisely so the product does not overflow; the
  /// subsequent `(int)` cast is a no-op because `(bound * r) >> 31 < bound`.
  /// Dart's `int` is already 64-bit, so the plain multiply is the faithful
  /// translation and needs no `.toSigned(32)`. Note this path uses the *high*
  /// bits of `r`, not `r % bound` -- the low bits of an LCG are the weak ones,
  /// and the JDK deliberately avoids them here. A "simplification" to
  /// `r & m` produces different numbers.
  ///
  /// **The rejection loop, and the `.toSigned(32)` that makes it work.** The
  /// guard `u - (r = u % bound) + m < 0` detects, by *deliberate 32-bit signed
  /// overflow*, that `u` fell in the short final partial bucket of `[0, 2^31)`
  /// and must be discarded to keep the distribution uniform. Dart's `int` is
  /// 64-bit, so without `.toSigned(32)` that sum never goes negative, the loop
  /// **never** rejects, and `nextInt` returns the over-represented value Java
  /// would have thrown away -- after which the shared seed is one draw behind
  /// and every subsequent number differs too.
  ///
  /// This is the failure mode that passes casual testing. The branch is
  /// unreachable for small bounds -- for `bound == 9` a rejection needs
  /// `u >= 2147483643`, about 1 draw in 420 million -- so a broken
  /// implementation looks perfect on dice-sized bounds and diverges only where
  /// the bound is a large non-power-of-two. The baked vectors include
  /// `bound = 1000000007` (rejects ~6.9% of draws) and `bound = 1431655765`
  /// (~33.3%) for exactly this reason; the measured JVM rejection counts are
  /// recorded alongside them.
  ///
  /// Throws [ArgumentError] for a non-positive [bound], as Java throws
  /// `IllegalArgumentException("bound must be positive")`.
  int _nextIntBounded(int bound) {
    if (bound <= 0) {
      throw ArgumentError.value(bound, 'bound', 'bound must be positive');
    }
    // Port-added guard, not present in Java: there, `bound` is an `int` and
    // cannot exceed 2^31-1 by construction. In Dart it can, and the rejection
    // arithmetic above is only correct inside 32 bits, so a larger bound would
    // silently compute nonsense. Rejecting it is not a behaviour change -- the
    // input is unrepresentable on the Java side.
    if (bound > 0x7FFFFFFF) {
      throw ArgumentError.value(
        bound,
        'bound',
        'bound must fit in a Java int (<= 2^31-1)',
      );
    }

    int r = _next(31);
    final int m = bound - 1;

    if ((bound & m) == 0) {
      // bound is a power of two
      return (bound * r) >> 31;
    }

    // Java's `for (int u = r; u - (r = u % bound) + m < 0; u = next(31));`,
    // unrolled into a while loop. The assignment-inside-the-condition is the
    // only thing lost; the sequence of draws and the returned value are
    // identical.
    int u = r;
    r = u % bound;
    while ((u - r + m).toSigned(32) < 0) {
      u = _next(31);
      r = u % bound;
    }
    return r;
  }

  /// Java: `public boolean nextBoolean() { return next(1) != 0; }`.
  ///
  /// One bit per call, taken from the *top* of the state -- so it consumes a
  /// full LCG step, exactly like [nextInt]. That shared, advancing state is why
  /// the vectors interleave `nextInt` and `nextBoolean`: a generator that was
  /// right on each method in isolation but drew its boolean from a side channel
  /// would pass single-method tests and fail the interleaved one.
  ///
  /// The relevant call site is `DlxPuzzleSolver.java:154`, where the column
  /// comparator breaks a tie in column size with `random.nextBoolean() ? -1 : 1`
  /// -- an inconsistent comparator the JDK's sort is free to react to in its own
  /// way, which is one more reason that path is better left unreached.
  bool nextBoolean() => _next(1) != 0;
}
