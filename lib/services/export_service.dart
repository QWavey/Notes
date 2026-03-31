import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'dart:ui' as ui;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;

// ---------------------------------------------------------------------------
// ExportService — PDF, image export with actual rendering
// ---------------------------------------------------------------------------

class ExportService {
  static Future<void> showExportDialog(
      BuildContext context, String pageTitle,
      {GlobalKey? repaintKey}) async {
    await showDialog(
      context: context,
      builder: (ctx) => _ExportDialog(pageTitle: pageTitle, repaintKey: repaintKey),
    );
  }

  static Future<void> showImportDialog(
      BuildContext context,
      Future<void> Function(String filePath, String fileType) onImport) async {
    await showDialog(
      context: context,
      builder: (ctx) => _ImportDialog(onImport: onImport),
    );
  }

  /// Capture a RepaintBoundary to PNG bytes
  static Future<Uint8List?> captureWidget(GlobalKey key) async {
    try {
      final boundary = key.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return null;
      final image = await boundary.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } catch (e) {
      debugPrint('Export capture error: $e');
      return null;
    }
  }

  /// Export current canvas as PDF using flutter/printing
  static Future<void> exportAsPdf(
      BuildContext context, String title,
      Future<Uint8List> Function() renderPage) async {
    try {
      final imageBytes = await renderPage();
      final doc = pw.Document();
      final image = pw.MemoryImage(imageBytes);
      doc.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.zero,
        build: (_) => pw.Image(image, fit: pw.BoxFit.contain),
      ));
      final bytes = await doc.save();
      if (context.mounted) {
        await Printing.sharePdf(bytes: bytes, filename: '$title.pdf');
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('PDF export fehlgeschlagen: $e')));
      }
    }
  }

  /// Export as PNG/JPG image
  static Future<void> exportAsImage(
      BuildContext context, String title,
      GlobalKey repaintKey, String ext) async {
    try {
      final bytes = await captureWidget(repaintKey);
      if (bytes == null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Export: Konnte Seite nicht erfassen')));
        }
        return;
      }
      if (kIsWeb) {
        // On web: share via printing package
        await Printing.sharePdf(
          bytes: bytes, filename: '$title.$ext');
      } else {
        // On native: save via file_picker
        final path = await FilePicker.platform.saveFile(
          dialogTitle: 'Bild speichern',
          fileName: '$title.$ext',
          bytes: bytes,
        );
        if (path != null && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Gespeichert: $path')));
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Bild-Export fehlgeschlagen: $e')));
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Export dialog
// ---------------------------------------------------------------------------

class _ExportDialog extends StatelessWidget {
  final String pageTitle;
  final GlobalKey? repaintKey;
  const _ExportDialog({required this.pageTitle, this.repaintKey});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Exportieren'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _formatTile(context, Icons.picture_as_pdf, 'PDF (.pdf)', 'pdf'),
          _formatTile(context, Icons.image, 'Bild (.png)', 'png'),
          _formatTile(context, Icons.image, 'Bild (.jpg)', 'jpg'),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Abbrechen')),
      ],
    );
  }

  Widget _formatTile(
      BuildContext context, IconData icon, String label, String format) {
    return ListTile(
      leading: Icon(icon, color: Colors.blue.shade700),
      title: Text(label, style: const TextStyle(fontSize: 14)),
      dense: true,
      onTap: () {
        Navigator.pop(context);
        _doExport(context, format);
      },
    );
  }

  void _doExport(BuildContext context, String format) async {
    final key = repaintKey;
    if (key == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export als .$format — kein RepaintBoundary verfügbar')),
      );
      return;
    }

    if (format == 'pdf') {
      final bytes = await ExportService.captureWidget(key);
      if (bytes == null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Export: Seite konnte nicht erfasst werden')));
        }
        return;
      }
      if (context.mounted) {
        await ExportService.exportAsPdf(context, pageTitle, () async => bytes);
      }
    } else {
      if (context.mounted) {
        await ExportService.exportAsImage(context, pageTitle, key, format);
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Import dialog
// ---------------------------------------------------------------------------

class _ImportDialog extends StatelessWidget {
  final Future<void> Function(String filePath, String fileType) onImport;
  const _ImportDialog({required this.onImport});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Importieren'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _formatTile(context, Icons.picture_as_pdf, 'PDF (.pdf)', ['pdf']),
          _formatTile(context, Icons.image, 'Bild (.jpg, .png)', ['jpg', 'jpeg', 'png']),
          _formatTile(context, Icons.article, 'Word (.doc, .docx)', ['doc', 'docx']),
          _formatTile(context, Icons.slideshow, 'PowerPoint (.ppt, .pptx)', ['ppt', 'pptx']),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Abbrechen')),
      ],
    );
  }

  Widget _formatTile(
      BuildContext context, IconData icon, String label, List<String> exts) {
    return ListTile(
      leading: Icon(icon, color: Colors.green.shade700),
      title: Text(label, style: const TextStyle(fontSize: 14)),
      dense: true,
      onTap: () async {
        // Capture the navigator/scaffold context BEFORE popping the dialog.
        // After Navigator.pop the dialog's own BuildContext is unmounted, so
        // we must NOT use it for mounted-checks or showSnackBar.
        final nav = Navigator.of(context);
        final messenger = ScaffoldMessenger.of(context);
        nav.pop();
        await _pickAndImport(messenger, exts);
      },
    );
  }

  Future<void> _pickAndImport(
      ScaffoldMessengerState messenger, List<String> extensions) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: extensions,
        allowMultiple: false,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      final path = file.path;
      if (path == null) return;
      final ext = p.extension(path).toLowerCase().replaceAll('.', '');

      // Call the import callback — this runs on the DrawModeState which is
      // still alive (it was never popped), so no mounted-check needed here.
      await onImport(path, ext);

      messenger.showSnackBar(
        SnackBar(content: Text('Importiert: ${p.basename(path)}')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Import fehlgeschlagen: $e')),
      );
    }
  }
}
