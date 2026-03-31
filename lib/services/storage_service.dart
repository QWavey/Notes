import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:hive_flutter/hive_flutter.dart';
import '../models/notebook.dart';
import '../models/note_page.dart';
import '../models/canvas_item.dart';

// Only import path_provider and dart:io on non-web platforms
import 'storage_service_io.dart'
    if (dart.library.html) 'storage_service_web.dart' as platform;

class StorageService {
  static final StorageService _instance = StorageService._internal();
  factory StorageService() => _instance;
  StorageService._internal();

  late Box<Notebook> _notebookBox;
  late Box<NotePage> _pageBox;
  // Hive box for drawing JSON and canvas data (works on all platforms)
  late Box<String> _drawingBox;
  late Box<String> _canvasBox;
  late Box<String> _textBox;

  Future<void> init() async {
    if (kIsWeb) {
      // On web, Hive uses IndexedDB — no path needed
      await Hive.initFlutter();
    } else {
      final docsDir = await platform.getDocsDir();
      await Hive.initFlutter(docsDir);
    }
    Hive.registerAdapter(NotebookAdapter());
    Hive.registerAdapter(NotePageAdapter());
    _notebookBox = await Hive.openBox<Notebook>('notebooks');
    _pageBox = await Hive.openBox<NotePage>('pages');
    _drawingBox = await Hive.openBox<String>('drawings');
    _canvasBox = await Hive.openBox<String>('canvas_data');
    _textBox = await Hive.openBox<String>('page_texts');
  }

  // ─── Notebooks ─────────────────────────────────────────────────────────────

  List<Notebook> getAllNotebooks() {
    final list = _notebookBox.values.toList();
    final trashed = getTrashedNotebookIds();
    list.removeWhere((n) => trashed.contains(n.id));
    list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return list;
  }

  Set<String> getTrashedNotebookIds() {
    final raw = _textBox.get('__trashed_notebooks__');
    if (raw == null || raw.isEmpty) return <String>{};
    try {
      final arr = (jsonDecode(raw) as List).cast<String>();
      return arr.toSet();
    } catch (_) {
      return <String>{};
    }
  }

  Future<void> _saveTrashedNotebookIds(Set<String> ids) async {
    await _textBox.put(
      '__trashed_notebooks__',
      jsonEncode(ids.toList()),
    );
  }

  Future<void> moveNotebookToTrash(String id) async {
    final ids = getTrashedNotebookIds();
    ids.add(id);
    await _saveTrashedNotebookIds(ids);
  }

  Future<void> restoreNotebookFromTrash(String id) async {
    final ids = getTrashedNotebookIds();
    ids.remove(id);
    await _saveTrashedNotebookIds(ids);
  }

  List<Notebook> getTrashedNotebooks() {
    final ids = getTrashedNotebookIds();
    final list = _notebookBox.values.where((n) => ids.contains(n.id)).toList();
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  Future<void> saveNotebook(Notebook nb) async {
    await _notebookBox.put(nb.id, nb);
  }

  Future<void> deleteNotebook(String id) async {
    // Ensure it disappears from trash metadata when hard-deleted.
    final ids = getTrashedNotebookIds();
    if (ids.remove(id)) {
      await _saveTrashedNotebookIds(ids);
    }
    final pages = getPagesForNotebook(id);
    for (final p in pages) {
      await deletePage(p.id);
    }
    await _notebookBox.delete(id);
  }

  // ─── Pages ─────────────────────────────────────────────────────────────────

  List<NotePage> getPagesForNotebook(String notebookId) {
    final list =
        _pageBox.values.where((p) => p.notebookId == notebookId).toList();
    list.sort((a, b) => a.order.compareTo(b.order));
    return list;
  }

  Future<void> savePage(NotePage page) async {
    await _pageBox.put(page.id, page);
  }

  Future<void> deletePage(String pageId) async {
    await _pageBox.delete(pageId);
    await _drawingBox.delete(pageId);
    await _canvasBox.delete(pageId);
    await _textBox.delete(pageId);
  }

  // ─── Drawing data (pencil_field JSON) ──────────────────────────────────────

  Future<void> saveDrawingJson(
      String pageId, Map<String, dynamic> json) async {
    await _drawingBox.put(pageId, jsonEncode(json));
  }

  Future<Map<String, dynamic>?> loadDrawingJson(String pageId) async {
    final raw = _drawingBox.get(pageId);
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  // ─── Canvas overlay data (shapes, text boxes, images) ──────────────────────

  Future<void> saveCanvasData(String pageId, CanvasData data) async {
    await _canvasBox.put(pageId, jsonEncode(data.toJson()));
  }

  Future<CanvasData> loadCanvasData(String pageId) async {
    final raw = _canvasBox.get(pageId);
    if (raw == null) return CanvasData();
    try {
      return CanvasData.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return CanvasData();
    }
  }

  // ─── Document text ──────────────────────────────────────────────────────────

  Future<void> saveDocumentText(String pageId, String text) async {
    await _textBox.put(pageId, text);
  }

  Future<String> loadDocumentText(String pageId) async {
    return _textBox.get(pageId) ?? '';
  }

  // ─── Document rich-text span data ───────────────────────────────────────────────
  Future<void> saveDocumentSpans(String pageId, String spansJson) async {
    await _textBox.put(pageId + '_spans', spansJson);
  }

  Future<String?> loadDocumentSpans(String pageId) async {
    return _textBox.get(pageId + '_spans');
  }
}
