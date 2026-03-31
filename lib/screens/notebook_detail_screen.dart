import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import '../app_localizations.dart';
import '../models/notebook.dart';
import '../models/note_page.dart';
import '../models/enums.dart';
import '../models/canvas_item.dart';
import '../services/storage_service.dart';
import '../widgets/paper_painter.dart';
import '../canvas/canvas_page.dart';
import 'package:uuid/uuid.dart';
import '../canvas/draw_mode.dart';
import 'package:notes/main.dart';

// ---------------------------------------------------------------------------
// Language label helper (used by language-selector dropdown)
// ---------------------------------------------------------------------------
String _langLabel(String code) {
  const labels = {
    'en': '🇬🇧  English',
    'de': '🇩🇪  Deutsch',
    'fr': '🇫🇷  Français',
    'es': '🇪🇸  Español',
    'it': '🇮🇹  Italiano',
    'pt': '🇵🇹  Português',
    'nl': '🇳🇱  Nederlands',
    'pl': '🇵🇱  Polski',
    'ru': '🇷🇺  Русский',
    'ja': '🇯🇵  日本語',
    'zh': '🇨🇳  中文',
    'ko': '🇰🇷  한국어',
    'ar': '🇸🇦  العربية',
  };
  return labels[code] ?? code;
}

// ---------------------------------------------------------------------------
// Lightweight page preview (sidebar thumbnails)
// ---------------------------------------------------------------------------

class _StrokePreview {
  final List<Offset> points;
  final Color color;
  final double width;

  const _StrokePreview({
    required this.points,
    required this.color,
    required this.width,
  });

  factory _StrokePreview.fromJson(Map<String, dynamic> j) => _StrokePreview(
        points: (j['points'] as List<dynamic>? ?? [])
            .map((p) => Offset((p['x'] as num).toDouble(),
                (p['y'] as num).toDouble()))
            .toList(),
        color: Color((j['color'] as num).toInt()),
        width: (j['width'] as num).toDouble(),
      );
}

class _PagePreviewData {
  final CanvasData canvasData;
  final List<_StrokePreview> strokes;
  const _PagePreviewData({required this.canvasData, required this.strokes});
}

class _PageItemsPainter extends CustomPainter {
  final CanvasData canvasData;
  final List<_StrokePreview> strokes;

  _PageItemsPainter(this.canvasData, this.strokes);

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = _computeContentBounds();
    if (bounds == null || bounds.width <= 0 || bounds.height <= 0) return;

    const pad = 6.0;
    final scale = math.min(
      (size.width - pad * 2) / bounds.width,
      (size.height - pad * 2) / bounds.height,
    );

    canvas.save();
    canvas.translate(pad - bounds.left * scale, pad - bounds.top * scale);
    canvas.scale(scale);

    // Strokes (simple polyline preview)
    for (final s in strokes) {
      if (s.points.length < 2) continue;
      final paint = Paint()
        ..color = s.color
        ..strokeWidth = s.width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke
        ..isAntiAlias = true;

      for (int i = 1; i < s.points.length; i++) {
        canvas.drawLine(s.points[i - 1], s.points[i], paint);
      }
    }

    // Shapes
    for (final shape in canvasData.shapes) {
      final rect =
          Rect.fromLTWH(shape.x, shape.y, shape.width, shape.height);
      final paint = Paint()
        ..color = Color(shape.colorValue)
        ..isAntiAlias = true;

      if (shape.filled) {
        paint.style = PaintingStyle.fill;
        canvas.drawRect(
          rect,
          paint,
        );
        continue;
      }

      paint.style = PaintingStyle.stroke;
      paint.strokeWidth = shape.strokeWidth;
      switch (shape.shapeType) {
        case 'rectangle':
          canvas.drawRect(rect, paint);
          break;
        case 'circle':
          canvas.drawOval(rect, paint);
          break;
        case 'triangle':
        case 'isoscelesTriangle': {
          final apex = Offset(rect.left + rect.width / 2, rect.top);
          final path = Path()
            ..moveTo(apex.dx, apex.dy)
            ..lineTo(rect.right, rect.bottom)
            ..lineTo(rect.left, rect.bottom)
            ..close();
          canvas.drawPath(path, paint);
          break;
        }
        case 'rightTriangle': {
          final path = Path()
            ..moveTo(rect.left, rect.top)
            ..lineTo(rect.right, rect.bottom)
            ..lineTo(rect.left, rect.bottom)
            ..close();
          canvas.drawPath(path, paint);
          break;
        }
        case 'leftTriangle': {
          final path = Path()
            ..moveTo(rect.right, rect.top)
            ..lineTo(rect.right, rect.bottom)
            ..lineTo(rect.left, rect.bottom)
            ..close();
          canvas.drawPath(path, paint);
          break;
        }
        default:
          canvas.drawRect(rect, paint);
      }
    }

    // Text boxes
    for (final tb in canvasData.textBoxes) {
      if (tb.text.trim().isEmpty) continue;
      final tp = TextPainter(
        text: TextSpan(
          text: tb.text,
          style: TextStyle(
            fontSize: tb.fontSize,
            color: Color(tb.colorValue),
            fontWeight: tb.bold ? FontWeight.bold : FontWeight.normal,
            fontStyle: tb.italic ? FontStyle.italic : FontStyle.normal,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 2,
        ellipsis: '…',
      )..layout();
      tp.paint(canvas, Offset(tb.x, tb.y));
    }

    // Images: draw placeholder rects
    for (final img in canvasData.images) {
      final r = Rect.fromLTWH(img.x, img.y, img.width, img.height);
      final bg = Paint()
        ..color = Colors.grey.withOpacity(0.12)
        ..style = PaintingStyle.fill;
      final border = Paint()
        ..color = Colors.grey.withOpacity(0.55)
        ..strokeWidth = 1.0
        ..style = PaintingStyle.stroke;
      canvas.drawRect(r, bg);
      canvas.drawRect(r, border);
    }

    // Tables: draw bounding rects only
    for (final tbl in canvasData.tables) {
      final r = Rect.fromLTWH(tbl.x, tbl.y, tbl.totalWidth, tbl.totalHeight);
      final border = Paint()
        ..color = Colors.blueGrey.withOpacity(0.4)
        ..strokeWidth = 1.0
        ..style = PaintingStyle.stroke;
      canvas.drawRect(r, border);
    }

    canvas.restore();
  }

  Rect? _computeContentBounds() {
    double? minX, minY, maxX, maxY;
    void expandRect(Rect r) {
      minX = minX == null ? r.left : math.min(minX!, r.left);
      minY = minY == null ? r.top : math.min(minY!, r.top);
      maxX = maxX == null ? r.right : math.max(maxX!, r.right);
      maxY = maxY == null ? r.bottom : math.max(maxY!, r.bottom);
    }

    for (final shape in canvasData.shapes) {
      expandRect(Rect.fromLTWH(shape.x, shape.y, shape.width, shape.height));
    }
    for (final tb in canvasData.textBoxes) {
      expandRect(Rect.fromLTWH(tb.x, tb.y, tb.width, 60));
    }
    for (final img in canvasData.images) {
      expandRect(Rect.fromLTWH(img.x, img.y, img.width, img.height));
    }
    for (final tbl in canvasData.tables) {
      expandRect(
          Rect.fromLTWH(tbl.x, tbl.y, tbl.totalWidth, tbl.totalHeight));
    }
    for (final s in strokes) {
      for (final p in s.points) {
        minX = minX == null ? p.dx : math.min(minX!, p.dx);
        minY = minY == null ? p.dy : math.min(minY!, p.dy);
        maxX = maxX == null ? p.dx : math.max(maxX!, p.dx);
        maxY = maxY == null ? p.dy : math.max(maxY!, p.dy);
      }
    }

    if (minX == null) return null;
    return Rect.fromLTRB(minX!, minY!, maxX!, maxY!);
  }

  @override
  bool shouldRepaint(covariant _PageItemsPainter old) =>
      old.canvasData != canvasData || old.strokes != strokes;
}

// ─────────────────────────────────────────────────────────────────────────────
// Global app-wide settings singleton
// ─────────────────────────────────────────────────────────────────────────────
class AppSettings {
  AppSettings._();
  static final AppSettings instance = AppSettings._();
  PageNavigationMode pageNavMode = PageNavigationMode.swipeHorizontal;
  bool shapeRecognition = false;
  /// Enable pinch-zoom and pan inside Document mode (Settings toggle).
  bool documentZoomEnabled = false;
  /// null = auto-detect from platform locale; non-null = manual override
  Locale? overrideLocale;
}

class NotebookDetailScreen extends StatefulWidget {
  final String notebookId;
  const NotebookDetailScreen({super.key, required this.notebookId});

  @override
  State<NotebookDetailScreen> createState() => _NotebookDetailScreenState();
}

class _NotebookDetailScreenState extends State<NotebookDetailScreen> {
  final _storage = StorageService();
  final _uuid = const Uuid();

  late Notebook _notebook;
  List<NotePage> _pages = [];
  int _currentIndex = 0;
  bool _fullscreen = false;
  bool _sidebarVisible = false;
  late PageController _pageController;

  // GlobalKeys for each CanvasPage so we can trigger import on the active page
  final Map<String, GlobalKey<CanvasPageState>> _canvasKeys = {};

  // Cached futures for left-sidebar thumbnails.
  final Map<String, Future<_PagePreviewData>> _previewFutures = {};

  @override
  void initState() {
    super.initState();
    _notebook = _storage
        .getAllNotebooks()
        .firstWhere((n) => n.id == widget.notebookId);
    _pageController = PageController(initialPage: 0);
    _loadPages();
  }

  @override
  void dispose() {
    _pageController.dispose();
    if (_fullscreen) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    super.dispose();
  }

  void _loadPages() {
    setState(() {
      _pages = _storage.getPagesForNotebook(widget.notebookId);
      final validIds = _pages.map((p) => p.id).toSet();
      _previewFutures.removeWhere((k, _) => !validIds.contains(k));
      if (_pages.isEmpty) _addPage();
    });
  }

  Future<_PagePreviewData> _loadPagePreviewData(String pageId) async {
    final canvasData = await _storage.loadCanvasData(pageId);
    final drawingJson = await _storage.loadDrawingJson(pageId);

    final strokesJson = (drawingJson?['strokes'] as List<dynamic>?) ?? const [];
    final strokes = strokesJson
        .map((s) => _StrokePreview.fromJson(s as Map<String, dynamic>))
        .toList();

    return _PagePreviewData(canvasData: canvasData, strokes: strokes);
  }

  Future<void> _addPage() async {
    final page = NotePage(
      id: _uuid.v4(),
      notebookId: widget.notebookId,
      name: 'Page ${_pages.length + 1}',
      order: _pages.length,
      paperTypeIndex: _notebook.paperTypeIndex,
    );
    await _storage.savePage(page);
    setState(() {
      _pages = _storage.getPagesForNotebook(widget.notebookId);
      _currentIndex = _pages.length - 1;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pageController.jumpToPage(_currentIndex);
    });
  }

  Future<void> _renamePage(NotePage page) async {
    final controller = TextEditingController(text: page.name);
    final l10n = AppLocalizations.of(context);
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.renamePage),
        content: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(labelText: l10n.pageName)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l10n.cancel)),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: Text(l10n.save)),
        ],
      ),
    );
    if (result == true && controller.text.trim().isNotEmpty) {
      page.name = controller.text.trim();
      await _storage.savePage(page);
      _loadPages();
    }
  }

  Future<void> _deletePage(int index) async {
    if (_pages.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cannot delete last page')));
      return;
    }
    final l10n = AppLocalizations.of(context);
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.deletePage),
        content: Text(l10n.deletePageConfirm),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l10n.cancel)),
          ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l10n.delete, style: const TextStyle(color: Colors.white))),
        ],
      ),
    );
    if (result == true) {
      await _storage.deletePage(_pages[index].id);
      final newIdx = (index > 0) ? index - 1 : 0;
      setState(() => _currentIndex = newIdx);
      _loadPages();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_pages.isNotEmpty) _pageController.jumpToPage(_currentIndex);
      });
    }
  }

  Future<void> _clearCurrentPage() async {
    if (_pages.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Seite leeren'),
        content: const Text('Alle Inhalte auf dieser Seite löschen?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Leeren'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final pageId = _pages[_currentIndex].id;
    final canvasKey = _canvasKeys[pageId];
    await canvasKey?.currentState?.triggerClearPage();
    _previewFutures.remove(pageId);
    if (mounted) setState(() {});
  }

  Future<void> _rotateCurrentPage() async {
    if (_pages.isEmpty) return;
    final pageId = _pages[_currentIndex].id;
    final canvasKey = _canvasKeys[pageId];
    if (canvasKey?.currentState == null) return;

    final clockwise = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Seite drehen'),
        content: const Text('Richtung wählen'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('↺ Links'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('↻ Rechts'),
          ),
        ],
      ),
    );
    if (clockwise == null) return;
    await canvasKey!.currentState!.triggerRotatePage(clockwise: clockwise);
    _previewFutures.remove(pageId);
    if (mounted) setState(() {});
  }

  Future<void> _showGoToPageDialog() async {
    if (_pages.isEmpty) return;
    final controller =
        TextEditingController(text: '${_currentIndex + 1}');
    final selected = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Gehe zu Seite'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
              labelText: 'Seite (1-${_pages.length})'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
          ElevatedButton(
            onPressed: () {
              final n = int.tryParse(controller.text.trim());
              Navigator.pop(ctx, n);
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (selected == null) return;
    _goToPage((selected - 1).clamp(0, _pages.length - 1));
  }

  Future<void> _moveNotebookToTrash() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('In den Papierkorb'),
        content: Text('„${_notebook.name}“ in den Papierkorb verschieben?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Verschieben'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _storage.moveNotebookToTrash(_notebook.id);
    if (mounted) Navigator.pop(context);
  }

  void _setPaperType(NotePage page, PaperType pt) async {
    page.paperType = pt;
    await _storage.savePage(page);
    setState(() {});
  }

  void _toggleFullscreen() {
    setState(() => _fullscreen = !_fullscreen);
    if (_fullscreen) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  void _goToPage(int i) {
    if (i < 0 || i >= _pages.length) return;
    setState(() => _currentIndex = i);
    _pageController.animateToPage(i,
        duration: const Duration(milliseconds: 280), curve: Curves.easeInOut);
  }

  void _showAppSettings() {
    final l10n = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(l10n.settings),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SwitchListTile(
                  title: Text(l10n.fingerDrawing),
                  subtitle: const Text('Default: pen & mouse only'),
                  value: DrawSettings.instance.allowFingerDrawing,
                  onChanged: (v) {
                    setLocal(() => DrawSettings.instance.allowFingerDrawing = v);
                    setState(() {});
                  },
                ),
                const Divider(),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Text('Page navigation',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
                RadioListTile<PageNavigationMode>(
                  title: const Text('Swipe left/right'),
                  subtitle: const Text('(2 fingers when finger drawing is on)'),
                  value: PageNavigationMode.swipeHorizontal,
                  groupValue: AppSettings.instance.pageNavMode,
                  onChanged: (v) {
                    if (v != null) {
                      setLocal(() => AppSettings.instance.pageNavMode = v);
                      setState(() {});
                    }
                  },
                ),
                RadioListTile<PageNavigationMode>(
                  title: const Text('Scroll up/down'),
                  value: PageNavigationMode.scrollVertical,
                  groupValue: AppSettings.instance.pageNavMode,
                  onChanged: (v) {
                    if (v != null) {
                      setLocal(() => AppSettings.instance.pageNavMode = v);
                      setState(() {});
                    }
                  },
                ),
                const Divider(),
                SwitchListTile(
                  title: const Text('[BETA] Shape recognition'),
                  subtitle: const Text('Hold pen → snap line/shape'),
                  value: DrawSettings.instance.enableShapeRecognition,
                  onChanged: (v) {
                    setLocal(() => DrawSettings.instance.enableShapeRecognition = v);
                    setState(() {});
                  },
                ),
                const Divider(),
                SwitchListTile(
                  title: const Text('[BETA] Ultra-low pen latency'),
                  subtitle: const Text(
                      'Reduces lag when drawing fast\n'
                      'Note: on Android APK the gain is smaller than in debug mode.'),
                  value: DrawSettings.instance.ultraLowLatency,
                  onChanged: (v) {
                    setLocal(() => DrawSettings.instance.ultraLowLatency = v);
                    setState(() {});
                  },
                ),
                const Divider(),
                SwitchListTile(
                  title: const Text('Document zoom'),
                  subtitle: const Text('Enable pinch-to-zoom in Document mode'),
                  value: AppSettings.instance.documentZoomEnabled,
                  onChanged: (v) {
                    setLocal(() => AppSettings.instance.documentZoomEnabled = v);
                    setState(() {});
                  },
                ),
                const Divider(),
                SwitchListTile(
                  title: const Text('Tablet pen mode'),
                  subtitle: const Text(
                      'Treat touch events as pen strokes\n'
                      'Use when your tablet pen is not detected as stylus'),
                  value: DrawSettings.instance.allowFingerDrawing,
                  onChanged: (v) {
                    setLocal(() => DrawSettings.instance.allowFingerDrawing = v);
                    setState(() {});
                  },
                ),
                const Divider(),
                // ── Language selector ──────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 4),
                  child: const Text('Language / Sprache',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: DropdownButton<Locale?>(
                    isExpanded: true,
                    value: AppSettings.instance.overrideLocale,
                    hint: const Text('🌐  Auto-detect'),
                    onChanged: (locale) {
                      setLocal(() =>
                          AppSettings.instance.overrideLocale = locale);
                      setState(() {});
                      // Trigger a hot rebuild of MaterialApp so the new
                      // locale takes effect immediately (no restart needed).
                      NotesApp.rebuildApp();
                    },
                    items: [
                      const DropdownMenuItem<Locale?>(
                        value: null,
                        child: Text('🌐  Auto-detect'),
                      ),
                      ...[
                        Locale('en'), Locale('de'), Locale('fr'),
                        Locale('es'), Locale('it'), Locale('pt'),
                        Locale('nl'), Locale('pl'), Locale('ru'),
                        Locale('ja'), Locale('zh'), Locale('ko'),
                        Locale('ar'),
                      ].map((l) => DropdownMenuItem<Locale?>(
                        value: l,
                        child: Text(_langLabel(l.languageCode)),
                      )),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Close')),
          ],
        ),
      ),
    );
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    if (_pages.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(_notebook.name)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final isHorizontal = AppSettings.instance.pageNavMode ==
        PageNavigationMode.swipeHorizontal;

    Widget pageContent;
    if (isHorizontal) {
      pageContent = _SwipePageWrapper(
        // Swipe is allowed ONLY when finger drawing is OFF.
        // When finger drawing is ON, fingers draw on the canvas and
        // 2-finger zoom must never be misread as a page swipe.
        canSwipe: () => !DrawSettings.instance.allowFingerDrawing,
        onSwipeLeft: () => _goToPage(_currentIndex + 1),
        onSwipeRight: () => _goToPage(_currentIndex - 1),
        child: PageView.builder(
          controller: _pageController,
          physics: const NeverScrollableScrollPhysics(),
          scrollDirection: Axis.horizontal,
          itemCount: _pages.length,
          onPageChanged: (i) => setState(() => _currentIndex = i),
          itemBuilder: (_, i) {
            final pageId = _pages[i].id;
            final canvasKey = _canvasKeys.putIfAbsent(
                pageId, () => GlobalKey<CanvasPageState>());
            return CanvasPage(key: canvasKey, page: _pages[i]);
          },
        ),
      );
    } else {
      pageContent = PageView.builder(
        controller: _pageController,
        physics: const ClampingScrollPhysics(),
        scrollDirection: Axis.vertical,
        itemCount: _pages.length,
        onPageChanged: (i) => setState(() => _currentIndex = i),
        itemBuilder: (_, i) {
          final pageId = _pages[i].id;
          final canvasKey = _canvasKeys.putIfAbsent(
              pageId, () => GlobalKey<CanvasPageState>());
          return CanvasPage(key: canvasKey, page: _pages[i]);
        },
      );
    }

    return Scaffold(
      appBar: _fullscreen
          ? null
          : AppBar(
              // ── Sidebar toggle in LEADING (top-left) ──────────────────────
              leadingWidth: 96,
              leading: Row(
                children: [
                  // Back to home (notebooks list)
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    tooltip: 'Back to notebooks',
                    onPressed: () => Navigator.pop(context),
                    padding: EdgeInsets.zero,
                  ),
                  // Toggle page sidebar
                  IconButton(
                    icon: Icon(_sidebarVisible ? Icons.menu_open : Icons.list),
                    tooltip: _sidebarVisible ? l10n.hidePages : l10n.showPages,
                    onPressed: () =>
                        setState(() => _sidebarVisible = !_sidebarVisible),
                    padding: EdgeInsets.zero,
                  ),
                ],
              ),
              title: Text(_notebook.name, style: const TextStyle(fontSize: 16)),
              actions: [
                // Add page (GoodNotes-style page+ button)
                IconButton(
                  icon: const Icon(Icons.note_add_outlined),
                  tooltip: 'Seite hinzuf\u00fcgen',
                  onPressed: _showAddPageSheet,
                ),
                // Import/Export
                IconButton(
                  icon: const Icon(Icons.ios_share),
                  tooltip: l10n.importExportPages,
                  onPressed: _showImportExportSheet,
                ),
                // Fullscreen / three-dots menu
                IconButton(
                  icon: const Icon(Icons.more_horiz),
                  tooltip: 'Mehr',
                  onPressed: _showPageOptionsSheet,
                ),
              ],
            ),
      floatingActionButton: _fullscreen
          ? FloatingActionButton.small(
              heroTag: 'exitFS',
              backgroundColor: Colors.black54,
              onPressed: _toggleFullscreen,
              tooltip: l10n.exitFullscreen,
              child: const Icon(Icons.fullscreen_exit, color: Colors.white),
            )
          : null,
      body: Row(
        children: [
          // ── Collapsible Sidebar (left side) ───────────────────────────────
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeInOut,
            width: (_sidebarVisible && !_fullscreen) ? 120 : 0,
            child: (_sidebarVisible && !_fullscreen)
                ? _buildSidebar()
                : const SizedBox.shrink(),
          ),

          // ── Main Canvas Area ───────────────────────────────────────────────
          Expanded(
            child: Column(
              children: [
                Expanded(child: pageContent),
                if (!_fullscreen) _buildBottomBar(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── GoodNotes-style Add Page bottom sheet ─────────────────────────────────

  void _showAddPageSheet() {
    int insertMode = 1; // 0 = before, 1 = after, 2 = last
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey.shade900,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Seite hinzuf\u00fcgen',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              // Position selector
              Row(
                children: [
                  _addPagePosBtn(ctx, setLocal, 'Vor dieser', 0, insertMode),
                  const SizedBox(width: 8),
                  _addPagePosBtn(ctx, setLocal, 'Nach dieser', 1, insertMode),
                  const SizedBox(width: 8),
                  _addPagePosBtn(ctx, setLocal, 'Letzte Seite', 2, insertMode),
                ],
              ),
              const SizedBox(height: 16),
              const Text('Neue Vorlagen',
                  style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text('Die hier gezeigten Vorlagen \u00fcbernehmen wenn m\u00f6glich die\nEigenschaften der aktuellen Seite.',
                  style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
              const SizedBox(height: 12),
              // Templates row
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: PaperType.values.map((pt) =>
                    GestureDetector(
                      onTap: () async {
                        Navigator.pop(ctx);
                        await _addPageWithType(pt, insertMode);
                      },
                      child: Container(
                        margin: const EdgeInsets.only(right: 12),
                        child: Column(
                          children: [
                            Container(
                              width: 64, height: 80,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: Colors.grey.shade600),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(5),
                                child: CustomPaint(
                                  painter: PaperPainter(pt),
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(pt.label,
                                style: TextStyle(color: Colors.grey.shade300, fontSize: 11)),
                          ],
                        ),
                      ),
                    ),
                  ).toList(),
                ),
              ),
              const SizedBox(height: 8),
              const Divider(color: Colors.white24),
              // Mehr Vorlagen
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.grid_view, color: Colors.white),
                title: const Text('Mehr Vorlagen...', style: TextStyle(color: Colors.white)),
                onTap: () => Navigator.pop(ctx),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.image, color: Colors.white),
                title: const Text('Bild', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(ctx);
                  _showImportExportSheet();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _addPagePosBtn(BuildContext ctx, StateSetter setLocal,
      String label, int mode, int current) {
    final selected = current == mode;
    return Expanded(
      child: GestureDetector(
        onTap: () => setLocal(() {}),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.grey.shade800,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: selected ? Colors.black : Colors.white,
              fontSize: 12,
              fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _addPageWithType(PaperType pt, int insertMode) async {
    final newPage = NotePage(
      id: const Uuid().v4(),
      notebookId: widget.notebookId,
      name: 'Seite ${_pages.length + 1}',
      order: _pages.length,
      paperTypeIndex: pt.index,
    );
    await _storage.savePage(newPage);
    _loadPages();
    // Navigate to appropriate page
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = insertMode == 0
          ? _currentIndex
          : insertMode == 1
              ? _currentIndex + 1
              : _pages.length - 1;
      if (target < _pages.length) _goToPage(target.clamp(0, _pages.length - 1));
    });
  }

  // ── GoodNotes-style three-dot page options sheet ────────────────────────────

  void _showPageOptionsSheet() {
    if (_pages.isEmpty) return;
    final page = _pages[_currentIndex];
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey.shade900,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(
                'Seite ${_currentIndex + 1}',
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ),
            _optionTile(ctx, Icons.bookmark_border, 'Lesezeichen hinzuf\u00fcgen', () {}),
            _optionTile(ctx, Icons.copy_outlined, 'Seite kopieren', () {}),
            _optionTile(ctx, Icons.control_point_duplicate, 'Seite duplizieren', () {
              Navigator.pop(ctx);
              _addPageWithType(page.paperType, 1);
            }),
            _optionTile(ctx, Icons.rotate_right, 'Seite drehen', () {
              Navigator.pop(ctx);
              _rotateCurrentPage();
            }, trailing: Icons.chevron_right),
            _optionTile(ctx, Icons.description_outlined, 'Vorlage wechseln', () {
              Navigator.pop(ctx);
              _showPaperTypeMenu();
            }),
            _optionTile(ctx, Icons.open_in_new, 'Gehe zu Seite',
                () {
                  Navigator.pop(ctx);
                  _showGoToPageDialog();
                }, trailing: Icons.chevron_right, subtitle: '${_currentIndex + 1} von ${_pages.length}'),
            const Divider(color: Colors.white12),
            _optionTile(ctx, Icons.delete_sweep_outlined, 'Seite leeren',
                () {
                  Navigator.pop(ctx);
                  _clearCurrentPage();
                }, isDestructive: true),
            _optionTile(ctx, Icons.delete_outline, 'In den Papierkorb',
                () { Navigator.pop(ctx); _moveNotebookToTrash(); }, isDestructive: true),
            const Divider(color: Colors.white12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text('Einstellungen',
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
            ),
            ListTile(
              leading: const Icon(Icons.chat_bubble_outline, color: Colors.white),
              title: const Text('Gel\u00f6ste Kommentare anzeigen', style: TextStyle(color: Colors.white)),
              trailing: Switch(
                value: false,
                onChanged: null,
                activeColor: const Color(0xFF2E6DA4),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.swap_horiz, color: Colors.white),
              title: const Text('Scrollrichtung', style: TextStyle(color: Colors.white)),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Horizontal', style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
                  Icon(Icons.chevron_right, color: Colors.grey.shade500),
                ],
              ),
              onTap: () {},
            ),
            ListTile(
              leading: const Icon(Icons.settings_outlined, color: Colors.white),
              title: const Text('Werkzeugleiste anpassen', style: TextStyle(color: Colors.white)),
              onTap: () { Navigator.pop(ctx); _showAppSettings(); },
            ),
          ],
        ),
      ),
    );
  }

  void _showPaperTypeMenu() {
    if (_pages.isEmpty) return;
    final page = _pages[_currentIndex];
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          PaperType selected = page.paperType;
          return AlertDialog(
            title: const Text('Vorlage wechseln'),
            content: SizedBox(
              width: 300,
              child: ListView(
                shrinkWrap: true,
                children: PaperType.values.map((pt) => RadioListTile<PaperType>(
                  title: Text(pt.label),
                  value: pt,
                  groupValue: selected,
                  onChanged: (v) => setLocal(() => selected = v!),
                )).toList(),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _setPaperType(page, selected);
                },
                child: const Text('OK'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _optionTile(BuildContext ctx, IconData icon, String label,
      VoidCallback onTap, {
      bool isDestructive = false,
      IconData? trailing,
      String? subtitle,
  }) {
    final color = isDestructive ? Colors.red.shade400 : Colors.white;
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(label, style: TextStyle(color: color, fontSize: 14)),
      subtitle: subtitle != null
          ? Text(subtitle, style: TextStyle(color: Colors.grey.shade500, fontSize: 12))
          : null,
      trailing: trailing != null ? Icon(trailing, color: Colors.grey.shade500) : null,
      onTap: onTap,
    );
  }

  void _showImportExportSheet() {
    // Delegate directly to the active canvas page's import/export dialog
    if (_pages.isNotEmpty) {
      final pageId = _pages[_currentIndex].id;
      final canvasKey = _canvasKeys[pageId];
      if (canvasKey?.currentState != null) {
        canvasKey!.currentState!.triggerImport().then((_) {
          if (!mounted) return;
          setState(() {
            _pages = _storage.getPagesForNotebook(widget.notebookId);
            final idx = _pages.indexWhere((p) => p.id == pageId);
            if (idx >= 0) _currentIndex = idx;
          });
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            if (_currentIndex >= 0 && _currentIndex < _pages.length) {
              _pageController.jumpToPage(_currentIndex);
            }
          });
        });
        return;
      }
    }
    // Fallback — should not normally be reached
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Seite wird noch geladen, bitte kurz warten.')),
    );
  }

  // ─── Sidebar ──────────────────────────────────────────────────────────────
  Widget _buildSidebar() {
    return Container(
      width: 120,
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        border: Border(right: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.add, size: 14),
                label: const Text('New', style: TextStyle(fontSize: 11)),
                onPressed: _addPage,
                style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 6)),
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _pages.length,
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemBuilder: (_, i) {
                final page = _pages[i];
                final selected = i == _currentIndex;
                return GestureDetector(
                  onTap: () => _goToPage(i),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: selected ? Colors.blue : Colors.grey.shade300,
                          width: selected ? 2 : 1),
                      color: selected ? Colors.blue.shade50 : Colors.white,
                    ),
                    child: Column(
                      children: [
                        AspectRatio(
                          aspectRatio: 0.7,
                          child: ClipRRect(
                            borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(7)),
                            child: FutureBuilder<_PagePreviewData>(
                              future: _loadPagePreviewData(page.id),
                              builder: (ctx, snapshot) {
                                if (!snapshot.hasData) {
                                  return CustomPaint(
                                    painter: PaperPainter(page.paperType),
                                  );
                                }
                                final data = snapshot.data!;
                                return Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    Positioned.fill(
                                      child: CustomPaint(
                                        painter: PaperPainter(page.paperType),
                                      ),
                                    ),
                                    Positioned.fill(
                                      child: CustomPaint(
                                        painter:
                                            _PageItemsPainter(data.canvasData, data.strokes),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(4),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  page.name,
                                  style: const TextStyle(fontSize: 10),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              PopupMenuButton<String>(
                                padding: EdgeInsets.zero,
                                icon: const Icon(Icons.more_vert, size: 14),
                                onSelected: (v) {
                                  if (v == 'rename') _renamePage(page);
                                  if (v == 'delete') _deletePage(i);
                                  if (v == 'paper') _setPaperType(page, page.paperType == PaperType.values.last ? PaperType.values.first : PaperType.values[(page.paperType.index + 1) % PaperType.values.length]);
                                },
                                itemBuilder: (_) => [
                                  const PopupMenuItem(value: 'rename', child: Row(children: [Icon(Icons.edit, size: 15), SizedBox(width: 8), Text('Umbenennen')])),
                                  const PopupMenuItem(value: 'paper', child: Row(children: [Icon(Icons.description_outlined, size: 15), SizedBox(width: 8), Text('Vorlage wechseln')])),
                                  const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete_outline, size: 15, color: Colors.red), SizedBox(width: 8), Text('L\u00f6schen', style: TextStyle(color: Colors.red))])),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ─── Bottom bar ───────────────────────────────────────────────────────────
  Widget _buildBottomBar() {
    if (_pages.isEmpty) return const SizedBox.shrink();
    final currentPage = _pages[_currentIndex];
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Row(
        children: [
          // Page counter — compact
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              '${_currentIndex + 1}/${_pages.length}',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ),
          // Paper type chips — scrollable, flexible
          Expanded(
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 2),
              children: PaperType.values.map((pt) {
                final selected = currentPage.paperTypeIndex == pt.index;
                return GestureDetector(
                  onTap: () => _setPaperType(currentPage, pt),
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 3),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: selected ? Colors.blue : Colors.grey.shade300),
                      color: selected ? Colors.blue.shade50 : Colors.transparent,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      pt.label,
                      style: TextStyle(
                          fontSize: 11,
                          color: selected ? Colors.blue : Colors.grey.shade700,
                          fontWeight: selected ? FontWeight.w600 : FontWeight.normal),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          // Prev / Next / Add — compact
          SizedBox(
            width: 32,
            child: IconButton(
              icon: const Icon(Icons.chevron_left, size: 20),
              padding: EdgeInsets.zero,
              onPressed: _currentIndex > 0 ? () => _goToPage(_currentIndex - 1) : null,
            ),
          ),
          SizedBox(
            width: 32,
            child: IconButton(
              icon: const Icon(Icons.chevron_right, size: 20),
              padding: EdgeInsets.zero,
              onPressed: _currentIndex < _pages.length - 1
                  ? () => _goToPage(_currentIndex + 1)
                  : null,
            ),
          ),
          SizedBox(
            width: 32,
            child: IconButton(
              icon: const Icon(Icons.add, size: 20),
              padding: EdgeInsets.zero,
              tooltip: 'Add page',
              onPressed: _addPage,
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Swipe wrapper — robust gesture detection
//
// Rules:
//  • Stylus NEVER triggers page swipe (it draws)
//  • 2+ simultaneous touch pointers NEVER trigger swipe (that is pinch-zoom)
//  • When finger drawing is ON: 1-finger swipe is also disabled (finger draws)
//  • When finger drawing is OFF: 1-finger touch horizontal swipe changes page
//  • Swipe must start below the toolbar (y > kToolbarDeadZone)
//  • Swipe threshold: ≥80 px horizontal AND ≥3× more horizontal than vertical
// ─────────────────────────────────────────────────────────────────────────────
class _SwipePageWrapper extends StatefulWidget {
  final Widget child;
  /// Return true if a 1-finger touch swipe should trigger page navigation.
  /// (false when finger drawing is ON — fingers draw, not swipe)
  final bool Function() canSwipe;
  final VoidCallback onSwipeLeft;
  final VoidCallback onSwipeRight;

  const _SwipePageWrapper({
    required this.child,
    required this.canSwipe,
    required this.onSwipeLeft,
    required this.onSwipeRight,
  });

  @override
  State<_SwipePageWrapper> createState() => _SwipePageWrapperState();
}

class _SwipePageWrapperState extends State<_SwipePageWrapper> {
  // Track every active pointer and its kind
  final Map<int, PointerDeviceKind> _pointers = {};

  // Swipe tracking — only valid for exactly-1-touch-finger scenarios
  Offset? _swipeStart;
  bool _swipeCancelled = false;

  // Toolbar dead-zone height — don't swipe when touch starts in the toolbar
  static const double _kToolbarDeadZone = 64.0;
  // Minimum horizontal displacement before the swipe fires
  static const double _kMinSwipeDx = 80.0;
  // Swipe must be at least this much more horizontal than vertical
  static const double _kDominanceRatio = 3.0;

  void _reset() {
    _swipeStart = null;
    _swipeCancelled = false;
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (e) {
        _pointers[e.pointer] = e.kind;

        // ── Any stylus contact → kill swipe entirely ──────────────────────
        if (_pointers.values.any((k) => k == PointerDeviceKind.stylus)) {
          _swipeStart = null;
          _swipeCancelled = true;
          return;
        }

        // ── 2nd (or more) finger → this is a pinch, cancel swipe ─────────
        if (_pointers.length > 1) {
          _swipeStart = null;
          _swipeCancelled = true;
          return;
        }

        // ── 1st finger down ───────────────────────────────────────────────
        // Only start tracking if swiping is allowed and the touch is below
        // the toolbar dead-zone (so toolbar scrolling never triggers a swipe).
        if (e.kind == PointerDeviceKind.touch &&
            widget.canSwipe() &&
            e.localPosition.dy > _kToolbarDeadZone) {
          _swipeStart = e.position;
          _swipeCancelled = false;
        } else {
          _swipeStart = null;
          _swipeCancelled = true;
        }
      },
      onPointerMove: (e) {
        // If a 2nd pointer arrived after this one started, cancel
        if (_pointers.length > 1) {
          _swipeStart = null;
          _swipeCancelled = true;
          return;
        }
        if (_swipeCancelled || _swipeStart == null) return;
        if (e.kind != PointerDeviceKind.touch) return;

        final dx = e.position.dx - _swipeStart!.dx;
        final dy = (e.position.dy - _swipeStart!.dy).abs();

        // If vertical movement dominates first, cancel (user is scrolling down)
        if (dy > _kMinSwipeDx / 2 && dy > dx.abs()) {
          _swipeCancelled = true;
          return;
        }

        if (dx.abs() >= _kMinSwipeDx && dx.abs() >= dy * _kDominanceRatio) {
          _swipeCancelled = true; // prevent re-fire
          _swipeStart = null;
          if (dx < 0) {
            widget.onSwipeLeft();
          } else {
            widget.onSwipeRight();
          }
        }
      },
      onPointerUp: (e) {
        _pointers.remove(e.pointer);
        if (_pointers.isEmpty) _reset();
      },
      onPointerCancel: (e) {
        _pointers.remove(e.pointer);
        if (_pointers.isEmpty) _reset();
      },
      child: widget.child,
    );
  }
}
