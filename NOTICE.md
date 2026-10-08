# Attribution and licensing

TSudoku is a port of **Free Sudoku** (`com.coolandroidappzfree.freesudoku`) to iOS using
Flutter. It is a **derivative work** of three upstream projects, all GPLv3. The licence of
this repository is therefore **GPL-3.0-or-later**, and cannot be anything else.

## The three upstreams

| Project | Author | Years | What it contributes |
|---|---|---|---|
| **Sudoku Explainer** | Nicolas Juillerat | 2006 – 2007 | The hint/tutor engine (`com.diuf.sudoku`): the human-style solving techniques and their ordering. |
| **Andoku** | Markus Wiederkehr | 2009 – 2011 | The puzzle model, the Dancing Links exact-cover solver, the command/history undo stack and the input-method state machines (`com.googlecode.andoku`). |
| **Free Sudoku** | Cool Android Appz | 2011 – now | The published Android application that merged the two, its 14 puzzle variants, the `.adk` puzzle corpus and 13 localisations. |

Every file carried over from the original retains all three copyright lines, as the
upstream headers do:

```
 * Copyright (C) 2006 - 2007, Nicolas Juillerat
 * Copyright (C) 2009 - 2011, Markus Wiederkehr
 * Copyright (C) 2011 - NOW, Cool Android Appz
```

Translated files additionally carry a line identifying the Dart translation and a
`Ported from:` line naming the exact Java source path, so any claim this port makes about
matching the original can be checked against a specific file.

## Puzzle corpus

`packages/sudoku_app/assets/puzzles/` contains the 96 `.adk` files (45,166 puzzles) from the
original application, unmodified and byte-identical. They are part of the GPLv3 work and are
redistributed under the same licence. They are **deliberately not** line-ending-normalised —
see `.gitattributes`.

## Why this repository is public

GPLv3 obliges anyone who conveys a binary to offer the corresponding source. Publishing the
complete source here is the simplest and most complete way to satisfy that for every build
handed to anyone, including TestFlight builds.

## What is NOT settled by this file

Publication on the Apple App Store is a separate question and is **not** resolved by this
repository being public. Apple's Usage Rules impose terms GPLv3 §6 does not permit a
distributor to add, which is why App Store submission is gated on GPLv3 §7 additional
permissions from the upstream authors. Cool Android Appz have granted permission for their
own code. Juillerat and Wiederkehr have not been reached. TestFlight and personal-device
installation are unaffected.
