// image_helper_io.dart — used on desktop/mobile
import 'dart:io';
import 'package:flutter/material.dart';

Widget buildFileImage(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    return Container(
      color: Colors.grey.shade200,
      child: const Icon(Icons.broken_image),
    );
  }
  return Image.file(file, fit: BoxFit.contain);
}
