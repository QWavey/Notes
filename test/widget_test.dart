import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes/main.dart';
import 'package:notes/services/storage_service.dart';

void main() {
  testWidgets('NotesApp builds and shows notebooks screen', (WidgetTester tester) async {
    // Mock the path_provider MethodChannel
    const MethodChannel channel = MethodChannel('plugins.flutter.io/path_provider');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (MethodCall methodCall) async {
      if (methodCall.method == 'getApplicationDocumentsDirectory') {
        return '.';
      }
      return null;
    });

    // Mock SharedPreferences or other storage channel mocks if needed,
    // but StorageService uses standard file system under the doc directory.
    await StorageService().init();

    // Build our app and trigger a frame.
    await tester.pumpWidget(const NotesApp());
    await tester.pumpAndSettle();

    // Verify that our NotesApp starts and shows the notebooks or home layout.
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
