import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
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
    // Register each adapter once, so init can be retried after a failure.
    final notebookAdapter = NotebookAdapter();
    if (!Hive.isAdapterRegistered(notebookAdapter.typeId)) {
      Hive.registerAdapter(notebookAdapter);
    }
    final pageAdapter = NotePageAdapter();
    if (!Hive.isAdapterRegistered(pageAdapter.typeId)) {
      Hive.registerAdapter(pageAdapter);
    }
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
    } catch (e) {
      // Keep the unreadable list so the next trash change cannot erase it.
      debugPrint('Trashed notebook list could not be read: $e');
      _keepBackup(_textBox, '__trashed_notebooks_backup__', raw);
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
    // Remove the data first and clear the trash marker last. If a step fails,
    // the notebook stays in the trash instead of reappearing in the active grid.
    final pages = getPagesForNotebook(id);
    for (final p in pages) {
      await deletePage(p.id);
    }
    await _notebookBox.delete(id);
    final ids = getTrashedNotebookIds();
    if (ids.remove(id)) {
      await _saveTrashedNotebookIds(ids);
    }
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
    // Rich-text spans and the recovery copies are stored under their own keys
    // and must go with the page.
    await _textBox.delete('${pageId}_spans');
    await _canvasBox.delete('${pageId}_canvas_backup');
    await _drawingBox.delete('${pageId}_drawing_backup');
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
    } catch (e) {
      // Keep the unreadable copy: the caller treats null as a blank page and
      // its next save would otherwise overwrite the stored drawing.
      debugPrint('Drawing data for page $pageId could not be read: $e');
      await _keepBackup(_drawingBox, '${pageId}_drawing_backup', raw);
      return null;
    }
  }

  /// Stores [raw] under [key] unless a copy is already there. Called before a
  /// save could overwrite stored data that failed to decode.
  Future<void> _keepBackup(Box<String> box, String key, String raw) async {
    if (!box.containsKey(key)) {
      await box.put(key, raw);
    }
  }

  // ─── Canvas overlay data (shapes, text boxes, images) ──────────────────────

  Future<void> saveCanvasData(String pageId, CanvasData data) async {
    await _canvasBox.put(pageId, jsonEncode(data.toJson()));
  }

  Future<CanvasData> loadCanvasData(String pageId) async {
    final raw = _canvasBox.get(pageId);
    if (raw == null) return CanvasData();
    final backupKey = '${pageId}_canvas_backup';
    final skipped = <String>[];
    try {
      final data = CanvasData.fromJson(
          jsonDecode(raw) as Map<String, dynamic>,
          skipped: skipped);
      if (skipped.isNotEmpty) {
        // The unreadable entries would be dropped by the next save, so keep the
        // original JSON first. Valid entries on the page still load.
        debugPrint(
            'Canvas data for page $pageId: skipped ${skipped.length} unreadable entries: ${skipped.join('; ')}');
        await _keepBackup(_canvasBox, backupKey, raw);
      }
      return data;
    } catch (e) {
      // The whole blob is unreadable. Keep it before the next save replaces it.
      debugPrint('Canvas data for page $pageId could not be read: $e');
      await _keepBackup(_canvasBox, backupKey, raw);
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
    await _textBox.put('${pageId}_spans', spansJson);
  }

  Future<String?> loadDocumentSpans(String pageId) async {
    return _textBox.get('${pageId}_spans');
  }
}
