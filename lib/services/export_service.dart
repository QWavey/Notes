import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'dart:ui' as ui;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path/path.dart' as p;

// ---------------------------------------------------------------------------
// ExportService — PDF, image export with actual rendering
// ---------------------------------------------------------------------------

/// Turns a page or notebook title into a safe file name. Path separators and
/// reserved characters become "_", leading dots and spaces are removed, and the
/// length is capped, so a title cannot escape the chosen folder or break a name.
String _safeFileName(String title) {
  var name = title
      .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '_')
      .replaceFirst(RegExp(r'^[\s.]+'), '')
      .trim();
  if (name.length > 100) name = name.substring(0, 100).trim();
  return name.isEmpty ? 'export' : name;
}

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

  /// Export current canvas as PDF using flutter/printing.
  ///
  /// Takes the [ScaffoldMessengerState] captured before the export dialog was
  /// closed. The dialog's own BuildContext is unmounted by then, so using it
  /// here would silently drop the share sheet and any error message.
  static Future<void> exportAsPdf(
      ScaffoldMessengerState messenger, String title,
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
      await Printing.sharePdf(
          bytes: bytes, filename: '${_safeFileName(title)}.pdf');
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text('PDF export fehlgeschlagen: $e')));
    }
  }

  /// Export as PNG image (see [exportAsPdf] for why a messenger is passed in).
  static Future<void> exportAsImage(
      ScaffoldMessengerState messenger, String title,
      GlobalKey repaintKey, String ext) async {
    try {
      final bytes = await captureWidget(repaintKey);
      if (bytes == null) {
        messenger.showSnackBar(
            const SnackBar(content: Text('Export: Konnte Seite nicht erfassen')));
        return;
      }
      if (kIsWeb) {
        // On web: share the PNG bytes as an image (not as a PDF).
        await SharePlus.instance.share(
          ShareParams(
            files: [
              XFile.fromData(bytes,
                  name: '${_safeFileName(title)}.$ext', mimeType: 'image/png'),
            ],
          ),
        );
      } else {
        // On native: save via file_picker
        final path = await FilePicker.platform.saveFile(
          dialogTitle: 'Bild speichern',
          fileName: '${_safeFileName(title)}.$ext',
          bytes: bytes,
        );
        if (path != null) {
          messenger.showSnackBar(
              SnackBar(content: Text('Gespeichert: $path')));
        }
      }
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text('Bild-Export fehlgeschlagen: $e')));
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
          // The image option always produces PNG bytes, so it is offered only as .png.
          _formatTile(context, Icons.image, 'Bild (.png)', 'png'),
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
        // Capture the messenger BEFORE popping the dialog: once it is closed,
        // its BuildContext is unmounted and can no longer show messages.
        final messenger = ScaffoldMessenger.of(context);
        Navigator.pop(context);
        _doExport(messenger, format);
      },
    );
  }

  Future<void> _doExport(ScaffoldMessengerState messenger, String format) async {
    final key = repaintKey;
    if (key == null) {
      messenger.showSnackBar(
        SnackBar(content: Text('Export als .$format — kein RepaintBoundary verfügbar')),
      );
      return;
    }

    if (format == 'pdf') {
      final bytes = await ExportService.captureWidget(key);
      if (bytes == null) {
        messenger.showSnackBar(
            const SnackBar(content: Text('Export: Seite konnte nicht erfasst werden')));
        return;
      }
      await ExportService.exportAsPdf(messenger, pageTitle, () async => bytes);
    } else {
      await ExportService.exportAsImage(messenger, pageTitle, key, format);
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
