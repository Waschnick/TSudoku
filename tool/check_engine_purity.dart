// TSudoku -- engine purity gate (QUALITY.md gate G2).
// Copyright (C) 2026, Sebastian Waschnick
//
// This program is free software: you can redistribute it and/or modify it under the terms
// of the GNU General Public License as published by the Free Software Foundation, either
// version 3 of the License, or (at your option) any later version.
//
// WHY THIS EXISTS, given that we also run `dart analyze --fatal-infos`:
//
// The analyzer catches SOME of the purity rule and silently misses the rest. Measured on
// Dart 3.13.5:
//   import 'package:flutter/material.dart'  -> INFO depend_on_referenced_packages,
//                                              so --fatal-infos DOES fail. Covered.
//   import 'dart:io'                        -> NO DIAGNOSTIC AT ALL. `dart analyze
//                                              --fatal-infos` prints "No issues found!"
//                                              and exits 0.
// dart:io, dart:ffi, dart:isolate and dart:mirrors are core libraries, not packages, so no
// dependency lint can fire for them. The analyzer cannot express this rule. Hence a gate.
//
// The engine must stay free of these so that it is testable without a device, cannot grow a
// dependency on how anything looks, and cannot reach the filesystem or the network -- which
// would make differential traces depend on the machine that produced them.
//
// Usage:  dart tool/check_engine_purity.dart [engineDir]
// Exit:   0 clean, 1 violations found, 2 the gate could not run (counts as failure)
//
// NOTE on the exit code: Dart DISCARDS whatever `main` returns -- an `int main()` that
// returns 1 still exits 0, so the first draft of this gate reported violations and then
// told the caller everything was fine. Measured. Set the top-level `exitCode` instead;
// unlike `exit()`, it lets buffered stdout flush before the process ends.

import 'dart:io';

/// Imports the engine may never contain, with the reason each is banned.
const Map<String, String> forbidden = <String, String>{
  'package:flutter': 'the engine must not depend on the UI framework',
  'package:flutter_test': 'engine tests run under `dart test`, not `flutter test`',
  'dart:ui': 'rendering types belong in sudoku_app',
  'dart:io': 'the engine must not touch the filesystem, process or network',
  'dart:isolate': 'concurrency would make trace ordering nondeterministic',
  'dart:ffi': 'native interop is out of scope and unportable',
  'dart:mirrors': 'reflection is unsupported in AOT and in Flutter',
  'dart:js_interop': 'the engine is not web-targeted',
};

/// Matches `import '...'`, `export '...'` and deferred imports, single or double quoted.
final RegExp _directive = RegExp(
  r'''^\s*(?:import|export)\s+(?:'([^']+)'|"([^"]+)")''',
  multiLine: false,
);

void main(List<String> argv) {
  final String engineDir = argv.isNotEmpty ? argv.first : 'packages/sudoku_engine';
  final Directory root = Directory(engineDir);

  // A gate that cannot find its target must FAIL, not pass. The equivalent mistake in
  // QUALITY.md's G1 and G9a -- globbing a path that no longer exists and exiting 0 -- is
  // precisely how a renamed directory turns a gate into a no-op.
  if (!root.existsSync()) {
    stderr.writeln('PURITY: cannot run -- engine directory not found: $engineDir');
    exitCode = 2;
    return;
  }

  final List<File> sources = root
      .listSync(recursive: true, followLinks: false)
      .whereType<File>()
      .where((File f) => f.path.endsWith('.dart'))
      .where((File f) => !f.path.contains('/.dart_tool/'))
      .toList()
    ..sort((File a, File b) => a.path.compareTo(b.path));

  if (sources.isEmpty) {
    stderr.writeln('PURITY: cannot run -- no .dart files under $engineDir');
    exitCode = 2;
    return;
  }

  int violations = 0;
  for (final File file in sources) {
    final List<String> lines = file.readAsLinesSync();
    for (int i = 0; i < lines.length; i++) {
      final RegExpMatch? m = _directive.firstMatch(lines[i]);
      if (m == null) continue;
      final String uri = m.group(1) ?? m.group(2) ?? '';
      for (final MapEntry<String, String> rule in forbidden.entries) {
        final bool hit = uri == rule.key || uri.startsWith('${rule.key}/');
        if (!hit) continue;
        violations++;
        stderr.writeln('${file.path}:${i + 1}: forbidden import "$uri"');
        stderr.writeln('    ${rule.value}');
      }
    }
  }

  final String scanned = '${sources.length} file${sources.length == 1 ? '' : 's'}';
  if (violations > 0) {
    stderr.writeln('\nPURITY FAIL: $violations violation(s) across $scanned in $engineDir');
    exitCode = 1;
    return;
  }
  stdout.writeln('PURITY PASS: $scanned clean in $engineDir');
}
