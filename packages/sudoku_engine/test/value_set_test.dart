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
// Ported from: app/src/main/java/com/googlecode/andoku/model/ValueSet.java
// Translation rules applied: R-02, R-03, R-10

// Characterisation tests for ValueSet. Every case here exists because getting it wrong
// produces code that compiles, looks right, and diverges from the Java oracle -- not
// because a setter might fail to set.
//
// Import by path rather than through the barrel: lib/sudoku_engine.dart is owned by the
// orchestrator and may not export this type yet.
import 'package:sudoku_engine/src/model/value_set.dart';
import 'package:test/test.dart';

void main() {
  group('constants match the Java literals', () {
    test('maxSize is 16 and the sentinel sits inside it', () {
      // The sentinel being *inside* the range that size() and toString() scan is the whole
      // reason those two methods report it. If maxSize ever dropped to 11 the sentinel
      // would become invisible to size() and ValuesThenCellInputMethod.onTap would break.
      expect(ValueSet.maxSize, 16);
      expect(ValueSet.tentativeBit, 11);
      expect(ValueSet.tentativeBit, lessThan(ValueSet.maxSize));
    });
  });

  group('values are zero-based', () {
    test('the digit 1 lives in bit 0, so all(9) is 0x01FF', () {
      // PuzzleDecoder.java:150 stores a given as `encodedValue - '1'`. A ValueSet modelling
      // bits 1..9 would still produce a full-looking mask (0x03FE) and still iterate nine
      // values -- it would just be off by one everywhere, including in the trace.
      expect(ValueSet.all(9).toInt(), 0x01FF);
      expect(ValueSet.all(9).contains(0), isTrue);
      expect(ValueSet.all(9).contains(9), isFalse);
      expect(ValueSet.all(9).size, 9);
    });

    test('iteration starts at bit 0', () {
      // Guards against the `for (b = 1; b < 11; b++)` shape, which silently drops the
      // lowest value from every cell.
      final set = ValueSet()..add(0);
      expect(set.nextValue(0), 0);
      expect(ValueSet.all(9).nextValue(0), 0);
    });
  });

  group('all()', () {
    test('rejects the same sizes Java rejects', () {
      expect(() => ValueSet.all(0), throwsArgumentError);
      expect(() => ValueSet.all(-1), throwsArgumentError);
      expect(() => ValueSet.all(17), throwsArgumentError);
      expect(ValueSet.all(1).toInt(), 0x0001);
      expect(ValueSet.all(16).toInt(), 0xFFFF);
    });

    test('all(16) swallows the sentinel bit -- the hole is in Java too', () {
      // Unreachable while every board is 9x9, but pinned so that a future larger-board
      // variant trips this test instead of mysteriously showing pencil marks.
      expect(ValueSet.all(16).isTentativeSingle, isTrue);
      expect(ValueSet.all(11).isTentativeSingle, isFalse);
      expect(ValueSet.all(12).isTentativeSingle, isTrue);
    });
  });

  group('the bit-11 sentinel (R-02)', () {
    test('size() COUNTS the sentinel: one value plus a mark is 2', () {
      // ValueSet.java:115 -- "debe devolver un 2 para anotaciones unicas - NINGUN CAMBIO
      // NECESARIO". The trace prints size() next to the raw mask, so excluding the
      // sentinel here diffs on the first tentative mark the fixtures contain.
      final set = ValueSet()..add(4);
      expect(set.size, 1);
      set.add(ValueSet.tentativeBit);
      expect(set.size, 2);
    });

    test('nextValue() HIDES the sentinel -- the only method that does', () {
      // ValueSet.java:133, the hand-added `(bit < 11) &&` guard.
      final set = ValueSet()..add(ValueSet.tentativeBit);
      expect(set.nextValue(0), -1);
      expect(set.nextValue(ValueSet.tentativeBit), -1);

      // Iterating a marked cell yields the value and stops; the mark is never painted.
      final marked = ValueSet()
        ..add(4)
        ..add(ValueSet.tentativeBit);
      final iterated = <int>[];
      for (var v = marked.nextValue(0); v != -1; v = marked.nextValue(v + 1)) {
        iterated.add(v);
      }
      expect(iterated, [4]);
    });

    test('the guard also hides values 12..15 that size() still counts', () {
      // A consequence of hard-coding 11 rather than MAX_SIZE in the guard. Keep it: a
      // "tidied" guard of `bit < maxSize` would restore the original pre-2015 behaviour
      // and paint sentinels.
      final set = ValueSet()
        ..add(12)
        ..add(15);
      expect(set.size, 2);
      expect(set.nextValue(0), -1);
      expect(set.toString(), '[12, 15]');
    });

    test(
      'contains() does NOT hide the sentinel -- it is the sentinel test',
      () {
        final set = ValueSet()..add(ValueSet.tentativeBit);
        expect(set.contains(ValueSet.tentativeBit), isTrue);
        expect(set.isTentativeSingle, isTrue);
        expect(ValueSet(0x01FF).isTentativeSingle, isFalse);
      },
    );

    test(
      'isTentativeSingle reports the flag only, not "exactly one value"',
      () {
        // Java never tests the two together either: onTap checks size()==1 and the flag
        // separately. A getter that also demanded a single value would change onTap's
        // branch choice.
        final many = ValueSet()
          ..add(0)
          ..add(1)
          ..add(ValueSet.tentativeBit);
        expect(many.isTentativeSingle, isTrue);
        expect(many.size, 3);
      },
    );

    test('isEmpty() is false for a set holding only the sentinel', () {
      // Nothing to paint (nextValue == -1) yet the cell is not blank. Java has the same
      // hole; routing emptiness through nextValue would "fix" it and diverge.
      final ghost = ValueSet()..add(ValueSet.tentativeBit);
      expect(ghost.isEmpty, isFalse);
      expect(ghost.size, 1);
      expect(ghost.nextValue(0), -1);
    });

    test('toString() prints the sentinel as a member named 11', () {
      final set = ValueSet()
        ..add(4)
        ..add(ValueSet.tentativeBit);
      expect(set.toString(), '[4, 11]');
      expect(ValueSet().toString(), '[]');
      expect(ValueSet(0x01FF).toString(), '[0, 1, 2, 3, 4, 5, 6, 7, 8]');
    });
  });

  group('ValuesThenCellInputMethod.onTap, replayed', () {
    // The state machine from im/ValuesThenCellInputMethod.java:110-135. These four cases
    // are the behaviour that a digits-only ValueSet destroys.

    test(
      'a single keypad value matching a single cell value becomes tentative',
      () {
        // Branch 1: values.size()==1 && !cellValues.contains(11) && cellValues.size()==1
        //           && cellValues.containsAny(values)
        final keypad = ValueSet()..add(4);
        final cell = ValueSet()..add(4);

        expect(keypad.size == 1, isTrue);
        expect(cell.contains(ValueSet.tentativeBit), isFalse);
        expect(cell.size == 1, isTrue);
        expect(cell.containsAny(keypad), isTrue);

        cell.add(ValueSet.tentativeBit);
        expect(cell.size, 2);
        expect(cell.isTentativeSingle, isTrue);
        expect(cell.nextValue(0), 4);
      },
    );

    test(
      'tapping again clears the mark and the value, leaving the cell empty',
      () {
        // Branch 2 on an already-marked cell: size() is now 2, so branch 1 cannot be taken
        // a second time -- the sentinel being counted is exactly what makes this a cycle
        // rather than a dead end.
        final keypad = ValueSet()..add(4);
        final cell = ValueSet()
          ..add(4)
          ..add(ValueSet.tentativeBit);

        expect(cell.size == 1, isFalse, reason: 'branch 1 must not re-fire');

        if (cell.contains(ValueSet.tentativeBit)) {
          cell.remove(ValueSet.tentativeBit);
        }
        expect(cell.containsAny(keypad), isTrue);
        cell.removeAll(keypad);

        expect(cell.isEmpty, isTrue);
        expect(cell.toInt(), 0);
      },
    );

    test('a multi-value keypad never takes the tentative branch', () {
      final keypad = ValueSet()
        ..add(2)
        ..add(4);
      final cell = ValueSet()..add(4);
      expect(keypad.size == 1, isFalse);

      // Branch 2: overlapping, so the keypad values are subtracted.
      expect(cell.containsAny(keypad), isTrue);
      cell.removeAll(keypad);
      expect(cell.isEmpty, isTrue);
    });

    test('a non-overlapping keypad unions in and drops any existing mark', () {
      final keypad = ValueSet()..add(2);
      final cell = ValueSet()
        ..add(4)
        ..add(ValueSet.tentativeBit);

      if (cell.contains(ValueSet.tentativeBit)) {
        cell.remove(ValueSet.tentativeBit);
      }
      expect(cell.containsAny(keypad), isFalse);
      cell.addAll(keypad);

      expect(cell.isTentativeSingle, isFalse);
      expect(cell.toString(), '[2, 4]');
    });
  });

  group('mask operations are sentinel-blind', () {
    test('addAll/from copy the sentinel, removeAll and retainAll clear it', () {
      final marked = ValueSet()
        ..add(4)
        ..add(ValueSet.tentativeBit);

      expect(ValueSet.from(marked).isTentativeSingle, isTrue);
      expect((ValueSet()..addAll(marked)).isTentativeSingle, isTrue);

      // retainAll against a values-only set drops the mark: a tentative mark does not
      // survive an intersection.
      final retained = ValueSet.from(marked)..retainAll(ValueSet(0x01FF));
      expect(retained.isTentativeSingle, isFalse);
      expect(retained.toInt(), 1 << 4);

      final subtracted = ValueSet.from(marked)..removeAll(marked);
      expect(subtracted.isEmpty, isTrue);

      expect((ValueSet.from(marked)..clear()).toInt(), 0);
    });

    test('containsAny overlaps on the sentinel alone', () {
      final a = ValueSet()..add(ValueSet.tentativeBit);
      final b = ValueSet()
        ..add(7)
        ..add(ValueSet.tentativeBit);
      expect(a.containsAny(b), isTrue);
      expect(a.containsAny(ValueSet(0x01FF)), isFalse);
    });

    test('from() is a snapshot, not an alias', () {
      // AndokuPuzzle hands out live ValueSet instances that the input methods mutate in
      // place; the copy constructor is the only thing standing between that and aliasing
      // bugs, so pin it.
      final original = ValueSet()..add(3);
      final copy = ValueSet.from(original);
      original.add(5);
      expect(copy.toInt(), 1 << 3);
    });
  });

  group('raw mask round trip', () {
    test(
      'setFromInt/toInt preserve the sentinel, as the Bundle save path needs',
      () {
        // ValuesThenCellInputMethod.onSaveInstanceState stores toInt() and restores through
        // setValues -> setFromInt. AndokuPuzzle.setValues writes through the same pair.
        final marked = ValueSet()
          ..add(4)
          ..add(ValueSet.tentativeBit);
        final restored = ValueSet()..setFromInt(marked.toInt());
        expect(restored, marked);
        expect(restored.isTentativeSingle, isTrue);
        expect(marked.toInt(), (1 << 4) | (1 << 11));
        expect(marked.toInt(), 0x0810);
      },
    );

    test('the public mask field is the whole state', () {
      final set = ValueSet();
      set.values = 0x0810;
      expect(set.size, 2);
      expect(set.nextValue(0), 4);
    });
  });

  group('equality and hashCode (R-03)', () {
    test('a tentative mark makes two otherwise equal sets unequal', () {
      final plain = ValueSet()..add(4);
      final marked = ValueSet()
        ..add(4)
        ..add(ValueSet.tentativeBit);
      expect(plain == marked, isFalse);
      expect(plain == ValueSet(1 << 4), isTrue);
      expect(plain.hashCode, ValueSet(1 << 4).hashCode);
      expect(
        plain.hashCode,
        plain.toInt(),
        reason: 'Java returns the raw mask',
      );
    });

    test('equality is by mask, not identity, and survives Set/Map keying', () {
      // Java never keys a collection on ValueSet, but == is overridden there, so hashCode
      // has to agree with it on this side as well (R-03).
      final keys = <ValueSet>{
        ValueSet(0x0810),
        ValueSet(0x0810),
        ValueSet(0x0010),
      };
      expect(keys.length, 2);
      // ignore: unrelated_type_equality_checks
      expect(ValueSet(1) == 1, isFalse);
    });
  });

  group('out-of-domain inputs (R-10)', () {
    test('contains() never throws -- RECORDED DIVERGENCE D-04', () {
      // ValueSet.java:95-105 returns from a finally block, which eats every throwable and
      // yields the `false` initialiser. In Dart the swallow is load-bearing: `1 << -1`
      // throws ArgumentError where Java tests a wrapped high bit.
      //
      // Two of these three assertions DISAGREE WITH JAVA, and that is the point of the
      // D-04 record. Java masks a shift distance to its low 5 bits, so it tests a
      // different bit instead of throwing. Measured on the JDK 17 in tool/env.sh:
      //
      //   ValueSet(0xFFFF).contains(-1)  Java false  Dart false   agree (bit 31 is clear)
      //   ValueSet(-1).contains(-5)      Java TRUE   Dart false   1 << -5 tests bit 27
      //   ValueSet(0x0001).contains(64)  Java TRUE   Dart false   1 << 64 tests bit 0
      //
      // An earlier version of this test asserted all three as false while its comment
      // claimed to mirror Java -- so it read as a fidelity test and was the opposite.
      // Unreachable from the corpus: every contains() call site in FreeSodukuSrc passes
      // 0..9, a loop index below size, `l - 1`, `hint.getValue() - 1`, or the literal 11.
      expect(
        ValueSet(0xFFFF).contains(-1),
        isFalse,
        reason: 'agrees with Java here only because bit 31 of 0xFFFF is clear',
      );
      expect(
        ValueSet(-1).contains(-5),
        isFalse,
        reason: 'D-04: Java returns true, testing wrapped bit 27',
      );
      expect(
        ValueSet(0x0001).contains(64),
        isFalse,
        reason: 'D-04: Java returns true, testing wrapped bit 0',
      );
    });

    test('nextValue past the end returns -1 without scanning', () {
      final full = ValueSet(0xFFFF);
      expect(full.nextValue(99), -1);
      expect(full.nextValue(ValueSet.maxSize), -1);
      expect(full.nextValue(10), 10);
      expect(full.nextValue(11), -1, reason: 'the guard stops at the sentinel');
    });
  });
}
