# TSudoku

An iOS port of **Free Sudoku**, built with Flutter.

The goal is narrow and concrete: one player who knows the Android original should be able to
keep playing the same game on an iPhone. "The same game" means the same puzzles, the same
difficulty ratings, the same input methods and the same hints — in the same order.

## Licence

**GPL-3.0-or-later.** This is a derivative of three GPLv3 projects by Nicolas Juillerat,
Markus Wiederkehr and Cool Android Appz. See [`LICENSE`](LICENSE) for the full text and
[`NOTICE.md`](NOTICE.md) for what each upstream contributes and how attribution is carried.

## Layout

```
TSudoku/
├── pubspec.yaml                  pub workspace root (declares members only)
├── packages/
│   ├── sudoku_engine/            pure Dart. ZERO Flutter imports, enforced by a gate.
│   └── sudoku_app/               the Flutter application and all rendering
├── tool/
│   ├── env.sh                    the toolchain contract -- source this, trust nothing else
│   └── check_engine_purity.dart  fails the build if the engine imports Flutter or dart:io
└── docs/
```

`sudoku_engine` holds the game rules, the solver and the hint engine. It may not import
Flutter, `dart:ui` or `dart:io`, so it stays testable without a device and cannot grow a
dependency on how anything looks. `sudoku_app` holds everything the player sees.

## Getting started

The toolchain is pinned. `tool/env.sh` is the single source of truth; do not rely on your
login shell.

```bash
source tool/env.sh          # exports the pins and puts the right SDKs on PATH
bash tool/env.sh --check    # assert every pinned tool resolves at the right version
fvm flutter pub get         # resolves the whole workspace from the root

cd packages/sudoku_engine && dart test      # engine tests, no device needed
cd packages/sudoku_app    && flutter run    # run on a simulator or device
```

Flutter is pinned with [fvm](https://fvm.app) via `.fvmrc` (3.47.6). Commands run from the
**workspace root** resolve dependencies; commands that build or test run from inside a
package. Running `flutter build` at the root fails by design — there is no `lib/main.dart`
there.

## Correctness

Correctness is defined as **matching the Java original**, not as passing tests written
against this port. The original is used as a differential oracle: both implementations emit a
canonical trace per puzzle — technique, cells, candidates, eliminations and order — and the
traces are compared byte-for-byte across the full 45,166-puzzle corpus.

Where this port knowingly differs from the original, the divergence is recorded rather than
left for someone to discover while playing.

## State

Early. The toolchain and the verification harness are in place; the translation is not.

## Where the port deliberately differs from the original

Correctness here is defined by the Java original and verified by byte-identical trace
comparison against a JVM oracle over all 45,100 in-scope puzzles. Where the port
*deliberately* departs from the Java anyway, it is recorded in
[DIVERGENCES.md](DIVERGENCES.md) with a D-number, and each entry is pinned by a unit test
naming that number — because a divergence the oracle cannot observe is one that nothing
will catch when it later becomes wrong.
