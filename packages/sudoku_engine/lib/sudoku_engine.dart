// TSudoku - an iOS port of Free Sudoku.
// Copyright (C) 2006 - 2007, Nicolas Juillerat
// Copyright (C) 2009 - 2011, Markus Wiederkehr
// Copyright (C) 2011 - NOW, Cool Android Appz
// Copyright (C) 2026, Sebastian Waschnick (Dart translation)
//
// This program is free software: you can redistribute it and/or modify it under the terms
// of the GNU General Public License as published by the Free Software Foundation, either
// version 3 of the License, or (at your option) any later version.
//
// This program is distributed in the hope that it will be useful, but WITHOUT ANY
// WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
// PARTICULAR PURPOSE. See the GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License along with this
// program. If not, see <https://www.gnu.org/licenses/>.

/// The TSudoku game engine.
///
/// This library is **pure Dart by contract**: no `package:flutter`, no `dart:ui`, no
/// `dart:io`. That is not a style preference. It keeps the engine testable without a
/// device, stops it growing a dependency on how anything looks, and prevents a trace from
/// depending on the machine that produced it. The rule is enforced by
/// `tool/check_engine_purity.dart`, because the analyzer cannot express it -- an illegal
/// `import 'dart:io'` produces no diagnostic at all.
///
/// Nothing is implemented yet. The translation order and the exit criteria for each step
/// are in the port plan; this library is the destination for all of it.
library;

/// Identifies this engine build in traces and in the about screen.
///
/// Kept deliberately separate from the application's version: the engine is compared
/// against a Java oracle and it is useful to be able to say which engine produced a trace.
const String engineVersion = '0.1.0';

/// The upstream application this port reproduces, for attribution in UI and traces.
const String upstreamApplication = 'Free Sudoku 1.060 (com.coolandroidappzfree.freesudoku)';
