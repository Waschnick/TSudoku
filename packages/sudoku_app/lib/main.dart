// TSudoku - an iOS port of Free Sudoku.
// Copyright (C) 2006 - 2007, Nicolas Juillerat
// Copyright (C) 2009 - 2011, Markus Wiederkehr
// Copyright (C) 2011 - NOW, Cool Android Appz
// Copyright (C) 2026, Sebastian Waschnick (Dart translation)
//
// This program is free software: you can redistribute it and/or modify it under the terms
// of the GNU General Public License as published by the Free Software Foundation, either
// version 3 of the License, or (at your option) any later version. See LICENSE.

import 'package:flutter/material.dart';
import 'package:sudoku_engine/sudoku_engine.dart';

void main() => runApp(const TSudokuApp());

/// Scaffolding only. This exists to prove the workspace boundary resolves -- the app
/// package importing the engine package -- and to give the first real screen somewhere to
/// land. The board, input methods and hint presentation all replace this.
class TSudokuApp extends StatelessWidget {
  const TSudokuApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TSudoku',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2B3A67)),
        useMaterial3: true,
      ),
      home: const _PlaceholderHome(),
    );
  }
}

class _PlaceholderHome extends StatelessWidget {
  const _PlaceholderHome();

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('TSudoku')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Text('TSudoku', style: text.headlineMedium),
              const SizedBox(height: 8),
              // Read through the engine package: if this renders, the workspace
              // dependency resolved and the package boundary works.
              Text('engine $engineVersion', style: text.bodyMedium),
              const SizedBox(height: 24),
              Text(
                'Porting $upstreamApplication',
                style: text.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
