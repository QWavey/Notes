// pencil_field_wrapper.dart
// No longer used for primary drawing — we use our own _InkPainter.
// Kept as a stub so no import errors occur elsewhere.

import 'package:flutter/material.dart';
import 'package:pencil_field/pencil_field.dart';

Widget buildPencilField({
  required PencilFieldController controller,
  required Color strokeColor,
  required double strokeWidth,
  required bool isErasing,
  required VoidCallback onDrawingChanged,
}) {
  controller.setMode(isErasing ? PencilMode.erase : PencilMode.write);
  final pencilPaint = PencilPaint(color: strokeColor, strokeWidth: strokeWidth);
  return PencilField(
    controller: controller,
    pencilOnly: false,
    pencilPaint: pencilPaint,
    onPencilDrawingChanged: (_) => onDrawingChanged(),
  );
}
