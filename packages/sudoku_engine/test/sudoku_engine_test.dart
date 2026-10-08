// TSudoku - an iOS port of Free Sudoku.
// Copyright (C) 2026, Sebastian Waschnick
// Licensed under the GNU General Public License v3 or later. See LICENSE.

import 'package:sudoku_engine/sudoku_engine.dart';
import 'package:test/test.dart';

void main() {
  group('engine scaffolding', () {
    test('exposes an engine version', () {
      expect(engineVersion, isNotEmpty);
    });

    test('names the upstream application it reproduces', () {
      expect(upstreamApplication, contains('freesudoku'));
    });
  });
}
