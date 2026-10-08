# Deliberate divergences from the Java original

Required by the port's translation rules R-04 and R-10: anything not translated faithfully
is written down here rather than left in a comment for someone to rediscover.

This file lives **in the repository**, not with the planning documents, because the engine
source cites it by D-number — `geometry.dart` says "see D-05 in `DIVERGENCES.md`" — and a
reference a clone cannot resolve is not a reference. It is also the honest companion to the
GPL obligation: whoever receives this source is entitled to know where it stops matching
the program it derives from.

Each entry states what Java does, what the port does, why, and — the part that matters —
**whether the differential oracle can see the difference.** A divergence the oracle cannot
observe is a divergence nothing will catch if it later becomes wrong, so every one of them
is pinned by a unit test that names its D-number.

| id | subject | oracle-visible? |
|---|---|---|
| D-01 | `standardAreas` returns an unmodifiable table | no |
| D-02 | `const` canonicalization collapses the area-table rows | no |
| D-03 | Dart exceptions always carry a message; Java's are often message-less | not yet |

---

## D-01 — `standardAreas()` returns an unmodifiable table

**Java** hands out its shared `static int[][]` uncopied (`StandardAreas.java:40-62`), and
`Puzzle.java:73` stores the reference without copying. So a write through the returned
array corrupts `STD_9` **for the rest of the process**, every later standard puzzle decodes
against the corrupted table, and `AndokuPuzzle.isSquiggly`
(`AndokuPuzzle.java:1369-1380`) then reports standard puzzles as `SQUIGGLY`.

**The port** returns an unmodifiable view, so the write throws at the offending line.

**Why.** The failure mode in Java is global, delayed and silent. Nothing in the Java writes
through the table — every `areaCodes` use in `Puzzle.java` (lines 40, 52, 64-73, 95, 226,
262-273) is a read or a length check — so there is no behaviour to preserve, only a loaded
gun to unload.

**Oracle-visible: no.** The write never happens, on either side.

**Pinned by** `test/standard_areas_test.dart`, the test named `D-01`. That test asserts the
*port's* choice, not Java's behaviour, and says so — the distinction matters, because a
test that claims fidelity while encoding a divergence is worse than no test.

## D-02 — `const` canonicalization collapses the area-table rows

**Java** allocates nine separate `int[9]` rows for `STD_9`, so `STD_9[0] != STD_9[1]`.
Measured: `STD_9` has 9 distinct row objects, `STD_6` has 6, `STD_8` has 8.

**The port** builds the tables as `const`, and Dart canonicalizes equal const lists. So the
9×9 table has **three** distinct row objects, and rows 0, 1 and 2 are literally the same
list. Canonicalization is also program-wide: any other `const <int>[0,0,0,1,1,1,2,2,2]`
anywhere in the port silently becomes that same object.

**Why.** `const` is what makes the table immutable (D-01) and allocation-free. The row
identity carries no information in the Java.

**Oracle-visible: no.** Nothing keys on row identity and the trace prints values. It would
become visible the moment anything does per-row identity work — a `Set<List<int>>`, a
copy-on-write grid keyed on row identity, or an allocation count.

**Pinned by** `test/standard_areas_test.dart`, the test named `D-02`, which asserts the
collapse rather than hiding it. If a later change makes row identity meaningful, that test
fails and points here instead of producing a 45,100-line trace diff.

## D-03 — exception messages differ, and `msg=-` is unreachable from Dart

**Java** throws message-less exceptions in several decode paths — `StandardAreas.java:62`
is a bare `new IllegalArgumentException()`. The oracle renders a decode failure as
`ex=<simple class name> msg=<message>`, and `Oracle.msg()` maps a null message to `-`
(`oracle-jvm-stub/oracle/Oracle.java:387`). So Java emits `ex=IllegalArgumentException
msg=-`.

**The port** cannot produce that: no Dart error has an empty `toString()`, and
`ArgumentError.value(...)` renders as `Invalid argument (size): ...`. The class names differ
too — `ArgumentError` vs `IllegalArgumentException`.

**Why.** Dart has no message-less equivalent, and inventing one wrapper type per Java
exception class would be a large amount of machinery for a path the corpus never takes.

**Oracle-visible: not yet, and this is the one to watch.** No `ERR` record is produced by
any of the 45,166 records — `PuzzleDecoder` rejects `size < 5 || size > 9`
(`PuzzleDecoder.java:49-50`) before any of these throws can fire, and both T2 traces
contain zero `ERR` lines. The asymmetry is therefore invisible **today**. It stops being
invisible the moment the trace format grows a case that can actually fail, at which point
whoever extends it needs an explicit Java-exception-name/message mapping layer rather than
passing a Dart exception through. Noted here so that work is a known cost rather than a
surprise.

## D-04 — out-of-domain bit operations: Java wraps the shift distance, Dart throws

**Java** masks a shift distance to its low 5 bits (JLS 15.19), so `1 << -5` is `1 << 27`
and `1 << 64` is `1 << 0`. `ValueSet.contains` additionally `return`s from a `finally`
block (`ValueSet.java:95-105`), which swallows any throwable and yields the `false`
initialiser. Measured on the pinned JDK 17:

| expression | Java | the port |
|---|---|---|
| `ValueSet(0xFFFF).contains(-1)` | `false` | `false` — agrees, but only because bit 31 of `0xFFFF` is clear |
| `ValueSet(-1).contains(-5)` | **`true`** (tests bit 27) | `false` |
| `ValueSet(0x0001).contains(64)` | **`true`** (tests bit 0) | `false` |
| `ValueSet(0).add(-1)` | sets bit 31 | throws `ArgumentError` |
| `ValueSet(0).add(32)` | sets bit 0 | sets bit 32 |
| `ValueSet(0x0010).nextValue(-1)` | `4` | throws `ArgumentError` |

**Why.** Reproducing Java's shift masking would mean writing `1 << (v & 31)` everywhere and
carrying a 32-bit truncation through a 64-bit integer type, to preserve answers that are
meaningless in every case. Throwing surfaces the bad argument at the call that made it.

**Oracle-visible: no.** Every `contains`, `add`, `remove` and `nextValue` call site in
`FreeSodukuSrc` passes a digit in `0..9`, a loop index below `size`, `l - 1`,
`hint.getValue() - 1`, or the literal `11`. Verified across all 32 `nextValue` call sites;
the only `nextValue(k)` pair (`AndokuPuzzle.java:967-968`) sits inside a commented-out
block.

**One live path to watch in Phase 3.** `AndokuPuzzle.java:988` and `:1033` do
`values_remain.add(solution.getValue(pos.row, pos.col))`, and `Puzzle.getValue` returns
`Puzzle.UNDEFINED == -1` for an unset cell. Both are guarded by `solution != null` but
**not** by "solution is complete". With a complete solution this cannot fire. If it ever
does, Java silently sets bit 31 and the port throws — which is the better failure, but it
is a *different* one, so it belongs here rather than in a surprise crash report.

**Pinned by** `test/value_set_test.dart`, the test named `D-04`, which carries the measured
Java value next to each assertion.

## D-05 — `Region.positions` and `ExtraRegion.positions` are unmodifiable copies

**Java** gives each class two constructors: the `List<Position>` overload **copies**
(`positions.toArray(...)`, `Region.java:35-41`, `ExtraRegion.java:32-34`) and the
`Position[]` overload **aliases** (`Region.java:43-49`, `ExtraRegion.java:36-38`). The
stored field is a fixed-length `Position[]`. `Puzzle.createRegions` uses the copying
overload for rows, columns and areas (`Puzzle.java:211, 219, 229`) and the aliasing one
only for the extra regions (`:234`).

**The port** has one constructor per class. It copies, and stores
`List<Position>.unmodifiable`.

**Why.** Dart has a single list type, so one of the two overloads had to go. Copying plus
unmodifiable is the stricter choice and it closes a gap the first version of `geometry.dart`
had opened: it aliased a *growable* list, which was less faithful than Java in two ways at
once — a caller's later mutation leaked into the region, and `positions.add(...)` could
grow an extra region *after* `Puzzle._checkParameters` had already validated its size
(`puzzle.dart:529`).

**Oracle-visible: no.** Every `ExtraRegions` factory passes a throwaway literal and
`Puzzle.createRegions` allocates a fresh list per region, so no caller retains a reference
to mutate. The only residual difference from Java is on the extras path, where Java aliases
and the port copies — unobservable, because the source list is never touched again.

**Pinned by** `test/geometry_test.dart`.
