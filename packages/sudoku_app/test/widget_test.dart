// TSudoku - an iOS port of Free Sudoku.
// Copyright (C) 2026, Sebastian Waschnick
// Licensed under the GNU General Public License v3 or later. See LICENSE.

import 'package:flutter_test/flutter_test.dart';
import 'package:sudoku_app/main.dart';
import 'package:sudoku_engine/sudoku_engine.dart';

void main() {
  testWidgets('app renders and can read across the package boundary', (
    WidgetTester t,
  ) async {
    await t.pumpWidget(const TSudokuApp());
    expect(find.text('TSudoku'), findsAtLeast(1));
    // The point of this assertion is the boundary, not the string: the value comes from
    // the engine package, so a broken workspace resolution fails here.
    expect(find.text('engine $engineVersion'), findsOneWidget);
  });
}
