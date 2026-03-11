import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;

// ---------------------------------------------------------------------------
// ExportService — PDF, image, and basic format stubs
// ---------------------------------------------------------------------------

class ExportService {
  static Future<void> showExportDialog(
      BuildContext context, String pageTitle) async {
    await showDialog(
      context: context,
      builder: (ctx) => _ExportDialog(pageTitle: pageTitle),
    );
  }

  static Future<void> showImportDialog(
      BuildContext context,
      Function(String filePath, String fileType) onImport) async {
    await showDialog(
      context: context,
      builder: (ctx) => _ImportDialog(onImport: onImport),
    );
  }

  /// Export current canvas as PDF using flutter/printing
  static Future<void> exportAsPdf(
      BuildContext context, String title, Future<Uint8List> Function() renderPage) async {
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
            .showSnackBar(SnackBar(content: Text('PDF export failed: $e')));
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Export dialog
// ---------------------------------------------------------------------------

class _ExportDialog extends StatelessWidget {
  final String pageTitle;
  const _ExportDialog({required this.pageTitle});

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
          _formatTile(context, Icons.article, 'Word (.docx)', 'docx',
              subtitle: 'Wird als PDF exportiert'),
          _formatTile(context, Icons.slideshow, 'PowerPoint (.pptx)', 'pptx',
              subtitle: 'Wird als PDF exportiert'),
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
      BuildContext context, IconData icon, String label, String format,
      {String? subtitle}) {
    return ListTile(
      leading: Icon(icon, color: Colors.blue.shade700),
      title: Text(label, style: const TextStyle(fontSize: 14)),
      subtitle: subtitle != null
          ? Text(subtitle, style: TextStyle(fontSize: 11, color: Colors.grey.shade600))
          : null,
      dense: true,
      onTap: () {
        Navigator.pop(context);
        _doExport(context, format);
      },
    );
  }

  void _doExport(BuildContext context, String format) {
    // Notify parent — actual rendering must be triggered from the canvas
    // We use a simple snackbar for now; full rendering is in draw_mode via RepaintBoundary
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Export als .$format wird vorbereitet…'),
        duration: const Duration(seconds: 2),
      ),
    );
    // The actual export is triggered via the GlobalKey<DrawModeState> in the parent
  }
}

// ---------------------------------------------------------------------------
// Import dialog
// ---------------------------------------------------------------------------

class _ImportDialog extends StatelessWidget {
  final Function(String filePath, String fileType) onImport;
  const _ImportDialog({required this.onImport});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Importieren'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _formatTile(context, Icons.picture_as_pdf, 'PDF (.pdf)',
              ['pdf']),
          _formatTile(context, Icons.image, 'Bild (.jpg, .png)',
              ['jpg', 'jpeg', 'png']),
          _formatTile(context, Icons.article, 'Word (.doc, .docx)',
              ['doc', 'docx']),
          _formatTile(context, Icons.slideshow, 'PowerPoint (.ppt, .pptx)',
              ['ppt', 'pptx']),
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
        Navigator.pop(context);
        await _pickAndImport(context, exts);
      },
    );
  }

  Future<void> _pickAndImport(
      BuildContext context, List<String> extensions) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: extensions,
      );
      if (result == null || result.files.single.path == null) return;
      final path = result.files.single.path!;
      final ext = p.extension(path).toLowerCase().replaceAll('.', '');

      if (context.mounted) {
        onImport(path, ext);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Importiert: ${p.basename(path)}')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Import fehlgeschlagen: $e')));
      }
    }
  }
}
