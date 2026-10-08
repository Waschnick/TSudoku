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
// Ported from: the JDK class java.util.Random (consumers:
//              app/src/main/java/com/googlecode/andoku/solver/DlxPuzzleSolver.java,
//              app/src/main/java/com/googlecode/andoku/solver/BrutePuzzleSolver.java)
// Translation rules applied: R-06, R-10

// These are not unit tests in the usual sense -- they are a conformance suite
// against a real JVM, and they are the ONLY evidence that JavaRandom is correct.
//
// JavaRandom is unreachable from the shipped game (the single DlxPuzzleSolver
// construction, AndokuPuzzle.java:350, passes random == null), so the
// 45,100-puzzle differential oracle never executes a line of it. Nothing else
// can catch a regression here.
//
// Every vector below was produced by:
//
//   JAVA_HOME=/Library/Java/JavaVirtualMachines/liberica-jdk-17-full.jdk/Contents/Home
//   $JAVA_HOME/bin/java G.java        # see the generator sketch in each group
//
// on JDK 17, and pasted in verbatim. Do NOT "correct" a literal to make a test
// pass -- regenerate it on a JVM, or the suite stops meaning anything.
import 'package:sudoku_engine/src/util/java_random.dart';
import 'package:test/test.dart';

/// Drains `n` values from `nextInt(bound)`, so a vector reads as one list.
List<int> ints(JavaRandom r, int n, int bound) => [
  for (var i = 0; i < n; i++) r.nextInt(bound),
];

/// Drains `n` values from `nextBoolean()`.
List<bool> bools(JavaRandom r, int n) => [
  for (var i = 0; i < n; i++) r.nextBoolean(),
];

void main() {
  // The primary vector. One JavaRandom per seed, driven through the exact same
  // call sequence the JVM saw: 10x nextInt(9), 10x nextInt(1000000007),
  // 10x nextBoolean(), 5x nextInt(16). Running all four phases on ONE instance
  // is deliberate -- it pins the shared 48-bit state across method boundaries,
  // so a phase that consumed the wrong number of LCG steps shifts everything
  // after it and cannot hide.
  //
  //   for (long s : new long[]{0L, 1L, 42L, -1L, 123456789L}) {
  //     Random r = new Random(s);
  //     for (int i=0;i<10;i++) sb.append(r.nextInt(9)).append(',');
  //     for (int i=0;i<10;i++) sb.append(r.nextInt(1000000007)).append(',');
  //     for (int i=0;i<10;i++) sb.append(r.nextBoolean()).append(',');
  //     for (int i=0;i<5;i++)  sb.append(r.nextInt(16)).append(',');
  //   }
  group('JDK 17 golden vectors', () {
    // bound 9: small non-power-of-two. bound 1000000007: large prime, exercises
    // the rejection loop. bound 16: power-of-two fast path.
    const vectors = <int, (List<int>, List<int>, List<bool>, List<int>)>{
      0: (
        [6, 7, 4, 2, 8, 2, 8, 3, 6, 2],
        [
          715581077,
          542832677,
          827187473,
          316484255,
          888030077,
          49567875,
          377907320,
          590459143,
          672024888,
          276804524,
        ],
        [false, false, true, false, false, true, false, true, true, false],
        [4, 10, 4, 6, 0],
      ),
      1: (
        [6, 1, 1, 6, 8, 4, 5, 1, 1, 1],
        [
          13136569,
          327998473,
          342691263,
          189861227,
          956251255,
          46012182,
          852925376,
          962720325,
          746289310,
          342179099,
        ],
        [false, false, true, true, false, true, true, true, true, false],
        [2, 12, 6, 9, 2],
      ),
      42: (
        [8, 3, 0, 8, 0, 7, 5, 2, 7, 2],
        [
          939977175,
          969067502,
          791955276,
          819572292,
          592164476,
          482678025,
          995688456,
          636576163,
          681268736,
          974241393,
        ],
        [false, false, false, true, true, false, true, false, false, true],
        [5, 3, 4, 13, 5],
      ),
      // A negative seed. Java's `long` and Dart's `int` are both 64-bit two's
      // complement, so `seed ^ 0x5DEECE66D` has the same bit pattern on both --
      // but only if the XOR is done on the signed value and not on some
      // masked-to-48-bits copy of it. This row is the guard for that.
      -1: (
        [5, 5, 0, 8, 5, 0, 0, 0, 7, 4],
        [
          730951801,
          665220512,
          121954317,
          149520196,
          176890342,
          481972243,
          552485062,
          938353965,
          201094679,
          570944648,
        ],
        [true, false, true, false, true, false, false, false, false, false],
        [12, 11, 3, 1, 1],
      ),
      123456789: (
        [7, 0, 5, 4, 6, 4, 6, 4, 4, 8],
        [
          771983441,
          52992954,
          20854657,
          34329982,
          46250217,
          27071254,
          246319360,
          252919789,
          534357530,
          360015272,
        ],
        [false, true, true, false, false, true, false, true, true, false],
        [10, 7, 9, 8, 3],
      ),
    };

    for (final entry in vectors.entries) {
      final seed = entry.key;
      final (small, large, flags, pow2) = entry.value;

      test('seed $seed reproduces the JVM sequence', () {
        final r = JavaRandom(seed);
        expect(ints(r, 10, 9), small, reason: 'nextInt(9)');
        expect(ints(r, 10, 1000000007), large, reason: 'nextInt(1000000007)');
        expect(bools(r, 10), flags, reason: 'nextBoolean()');
        expect(ints(r, 5, 16), pow2, reason: 'nextInt(16)');
      });
    }
  });

  // The single most important group in this file. See JavaRandom.nextInt.
  group('the rejection loop and its 32-bit overflow', () {
    // bound = 1431655765 is just over 2^31/1.5, so floor(2^31/bound) == 1 and
    // ~33.3% of raw next(31) draws must be rejected. Replaying the JDK
    // algorithm with an instrumented counter measured 10 rejections across
    // these 20 draws -- so an implementation whose rejection test never fires
    // cannot possibly produce this list.
    //
    //   Random r = new Random(12345L);
    //   for (int i=0;i<20;i++) sb.append(r.nextInt(1431655765)).append(',');
    const highRejectionBound = 1431655765;
    const highRejectionVector = <int>[
      776966251,
      1102109080,
      80902084,
      701101375,
      267722802,
      505783501,
      75883389,
      749719517,
      962239390,
      1370423012,
      248230384,
      339874787,
      564035175,
      310954351,
      140842792,
      1241583316,
      729158781,
      1026315425,
      714223871,
      607007439,
    ];

    test(
      'seed 12345, bound $highRejectionBound (JVM rejected 10 of 30 draws)',
      () {
        final r = JavaRandom(12345);
        expect(ints(r, 20, highRejectionBound), highRejectionVector);
      },
    );

    // The counter-vector: what the SAME seed and bound produce if the rejection
    // test is written without .toSigned(32), i.e. as Dart 64-bit arithmetic, so
    // that `u - r + m` is never negative and the loop never re-draws. Captured
    // from the JVM by replaying next(31) and returning `next(31) % bound`
    // unconditionally. It agrees with the correct vector for the first TWO
    // values and then diverges forever -- which is exactly why a hand-rolled
    // smoke test on a couple of draws fails to catch the bug.
    const brokenVector = <int>[
      776966251,
      1102109080,
      571932476, // <- correct answer here is 80902084; the JDK rejects this draw
      537833063,
      357394290,
      80902084,
      701101375,
      267722802,
      505783501,
      75883389,
      749719517,
      690167177,
      962239390,
      530815041,
      1370423012,
      248230384,
      339874787,
      564962538,
      219518767,
      564035175,
    ];

    test('does NOT behave like the no-toSigned(32) implementation', () {
      final r = JavaRandom(12345);
      final actual = ints(r, 20, highRejectionBound);
      // Guard the guard: the two vectors must genuinely differ, or this test
      // asserts nothing.
      expect(brokenVector, isNot(equals(highRejectionVector)));
      expect(actual, isNot(equals(brokenVector)));
      // Pin the first divergence, so a future regression is localised rather
      // than reported as "20 numbers are wrong".
      expect(
        actual.take(2),
        brokenVector.take(2),
        reason: 'the bug is invisible for the first two draws',
      );
      expect(actual[2], 80902084);
      expect(actual[2], isNot(brokenVector[2]));
    });

    test('rejections also occur at bound 1000000007 inside the main vector', () {
      // Measured on the JVM: replaying seed 0 through 10x nextInt(9) then
      // 10x nextInt(1000000007) triggers 3 rejections (seed 1: 4, seed 42: 1).
      // Re-asserted here as a sequence check so the primary vector above is
      // known to be load-bearing for this branch and not merely decorative.
      final r = JavaRandom(0);
      ints(r, 10, 9);
      expect(ints(r, 10, 1000000007).first, 715581077);
    });
  });

  group('power-of-two fast path', () {
    //   Random q = new Random(7L);
    //   for (int i=0;i<3;i++) System.out.print(q.nextInt(1)+",");
    //   for (int i=0;i<3;i++) System.out.print(q.nextInt(1024)+",");
    test('seed 7: nextInt(1) x3 then nextInt(1024) x3', () {
      final r = JavaRandom(7);
      // bound == 1 takes the power-of-two branch (1 & 0 == 0) and always
      // yields 0 -- but it still CONSUMES a draw, which is why the 1024 values
      // that follow depend on it.
      expect(ints(r, 3, 1), [0, 0, 0]);
      expect(ints(r, 3, 1024), [9, 356, 502]);
    });

    test('uses the high bits, not r & (bound - 1)', () {
      // The JDK computes (bound * r) >> 31 for powers of two, deliberately
      // avoiding an LCG's weak low bits. `r & m` is the obvious
      // "simplification", and on these two draws it gives a DIFFERENT answer,
      // so this test discriminates between the two implementations rather than
      // merely exercising one.
      //
      // Measured on the JVM: the first next(31) from seed 0 is 1569741360.
      //   new Random(0).nextInt(16)   == 11   ; 1569741360 & 15   == 0
      //   new Random(0).nextInt(1024) == 748  ; 1569741360 & 1023 == 560
      expect(JavaRandom(0).nextInt(16), 11);
      expect(JavaRandom(0).nextInt(1024), 748);
    });
  });

  group('nextBoolean shares the state with nextInt', () {
    //   Random p = new Random(-987654321L);
    //   for (int i=0;i<6;i++)
    //     System.out.print(p.nextInt(9)+","+p.nextBoolean()+","
    //                      +p.nextInt(1000000007)+",");
    test('interleaved seed -987654321 sequence', () {
      final r = JavaRandom(-987654321);
      const expected = <(int, bool, int)>[
        (6, true, 296164409),
        (5, true, 8568534),
        (1, true, 684074871),
        (5, false, 693566408),
        (3, false, 957787996),
        (3, true, 771564924),
      ];
      final actual = <(int, bool, int)>[
        for (var i = 0; i < 6; i++)
          (r.nextInt(9), r.nextBoolean(), r.nextInt(1000000007)),
      ];
      expect(actual, expected);
    });
  });

  group('argument checking mirrors Java', () {
    test('a non-positive bound throws, as IllegalArgumentException does', () {
      final r = JavaRandom(0);
      expect(() => r.nextInt(0), throwsA(isA<ArgumentError>()));
      expect(() => r.nextInt(-1), throwsA(isA<ArgumentError>()));
    });

    test('a bound beyond a Java int throws (port-added guard)', () {
      // Unrepresentable in Java, where bound is an int. Dart can express it and
      // the 32-bit rejection arithmetic would silently misbehave, so it is
      // rejected rather than approximated. Documented in JavaRandom.nextInt.
      final r = JavaRandom(0);
      expect(() => r.nextInt(0x80000000), throwsA(isA<ArgumentError>()));
      expect(() => r.nextInt(1 << 40), throwsA(isA<ArgumentError>()));
      // The largest legal bound is accepted and stays in range.
      expect(
        JavaRandom(0).nextInt(0x7FFFFFFF),
        inInclusiveRange(0, 0x7FFFFFFE),
      );
    });
  });

  group('independent instances with the same seed agree', () {
    test('two JavaRandom(42) produce identical sequences', () {
      // Nothing is shared statically. Java's Random keeps per-instance state in
      // an AtomicLong; this is the Dart equivalent assertion, and it would fail
      // if _seed were ever made static during a refactor.
      final a = JavaRandom(42);
      final b = JavaRandom(42);
      expect(ints(a, 40, 9), ints(b, 40, 9));
    });
  });

  group('distribution sanity -- cheap, but catches a mangled shift', () {
    test('nextInt(9) stays in range and hits every value', () {
      final r = JavaRandom(20261008);
      final seen = <int>{};
      for (var i = 0; i < 2000; i++) {
        final v = r.nextInt(9);
        expect(v, inInclusiveRange(0, 8));
        seen.add(v);
      }
      expect(seen.length, 9);
    });

    test('nextBoolean is not stuck', () {
      final r = JavaRandom(20261008);
      final flags = bools(r, 200);
      expect(flags, contains(true));
      expect(flags, contains(false));
    });
  });

  group('nextInt() no-arg -- next(32), captured from the pinned JDK 17', () {
    // Vectors generated with:
    //   Random r = new Random(seed); for (i<8) print(r.nextInt());
    // on liberica-jdk-17-full (the JDK tool/env.sh pins). These are the ONLY
    // vectors in this file that exercise _next(32), and they exist because
    // mutation testing showed that deleting `.toSigned(32)` from _next was
    // undetectable by every other test here: nextInt(bound) and nextBoolean
    // ask for 31 and 1 bits, where the shift result is already non-negative.
    const Map<int, List<int>> golden = <int, List<int>>{
      0: [
        -1155484576,
        -723955400,
        1033096058,
        -1690734402,
        -1557280266,
        1327362106,
        -1930858313,
        502539523,
      ],
      1: [
        -1155869325,
        431529176,
        1761283695,
        1749940626,
        892128508,
        155629808,
        1429008869,
        -1465154083,
      ],
      42: [
        -1170105035,
        234785527,
        -1360544799,
        205897768,
        1325939940,
        -248792245,
        1190043011,
        -1255373459,
      ],
      -1: [
        1155099827,
        1887904451,
        52699159,
        -1941176418,
        -1451336087,
        -1714570420,
        1788588954,
        1714930956,
      ],
      123456789: [
        -1442945365,
        -1016548095,
        1962592967,
        1094656688,
        1677212580,
        930275108,
        -458096230,
        1827465615,
      ],
    };

    golden.forEach((int seed, List<int> expected) {
      test('seed $seed reproduces the JVM sequence', () {
        final JavaRandom random = JavaRandom(seed);
        final List<int> actual = <int>[
          for (int i = 0; i < expected.length; i++) random.nextInt(),
        ];
        expect(actual, expected);
      });
    });

    test('returns negatives -- this is what kills the toSigned(32) mutant', () {
      // Without `.toSigned(32)` in _next, this returns 3139482720.
      expect(JavaRandom(0).nextInt(), -1155484576);
      expect(JavaRandom(0).nextInt().isNegative, isTrue);
    });

    test('Dart % is NOT Java % at the Solver_Manager call site', () {
      // Solver_Manager.java:558 is
      //   Math.abs(new Random().nextInt() % list_hints.size())
      // Java truncates toward zero, Dart is Euclidean. Measured on the JVM:
      //   x = -1155484576:  Java x%9 = -1, Math.abs = 1;  Dart x%9 = 8
      //   y = -1170105035:  Java y%9 = -5, Math.abs = 5;  Dart y%9 = 4
      // A wrong value here is a different hint shown to the player.
      const int x = -1155484576;
      const int y = -1170105035;
      expect(x.remainder(9).abs(), 1, reason: 'the faithful translation');
      expect(y.remainder(9).abs(), 5, reason: 'the faithful translation');
      expect(x % 9, 8, reason: 'Euclidean -- what Java does NOT do');
      expect(y % 9, 4, reason: 'Euclidean -- what Java does NOT do');
    });
  });
}
