// image_helper_web.dart — used on web (no dart:io)
import 'package:flutter/material.dart';

Widget buildFileImage(String path) {
  // On web, local file paths are not accessible — show placeholder
  return Container(
    color: Colors.grey.shade200,
    child: const Icon(Icons.broken_image),
  );
}
