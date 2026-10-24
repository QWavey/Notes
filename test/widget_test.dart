import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:notes/main.dart';
import 'package:notes/screens/notebooks_screen.dart';
import 'package:notes/services/storage_service.dart';

void main() {
  testWidgets('NotesApp builds and shows the notebooks screen', (WidgetTester tester) async {
    // Hive writes to a throwaway directory instead of the working directory.
    final tempDir = Directory.systemTemp.createTempSync('notes_widget_test');
    addTearDown(() async {
      await tester.runAsync(() async {
        await Hive.close();
      });
      tempDir.deleteSync(recursive: true);
    });

    // StorageService gets its documents directory through path_provider.
    const MethodChannel channel = MethodChannel('plugins.flutter.io/path_provider');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (MethodCall methodCall) async {
      if (methodCall.method == 'getApplicationDocumentsDirectory') {
        return tempDir.path;
      }
      return null;
    });

    // Real file I/O has to run outside the fake clock of testWidgets.
    await tester.runAsync(() => StorageService().init());

    await tester.pumpWidget(const NotesApp());
    await tester.pumpAndSettle();

    expect(find.byType(NotebooksScreen), findsOneWidget);
  });
}
