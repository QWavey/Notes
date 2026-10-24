import 'dart:async';
import 'package:flutter/material.dart';
import '../app_localizations.dart';
import '../models/note_page.dart';
import '../models/enums.dart';
import 'draw_mode.dart';
import 'document_mode.dart';

class CanvasPage extends StatefulWidget {
  final NotePage page;
  const CanvasPage({super.key, required this.page});

  @override
  State<CanvasPage> createState() => CanvasPageState();
}

// Exposed so NotebookDetailScreen can trigger import/export via GlobalKey
class CanvasPageState extends State<CanvasPage>
    with AutomaticKeepAliveClientMixin, TickerProviderStateMixin {
  late TabController _tabController;
  CanvasMode _mode = CanvasMode.draw;

  Timer? _autosaveTimer;
  bool _dirty = false;

  // Separate GlobalKeys for the draw-mode instance and the textbox-mode instance.
  // (They are different Offstage children, so both can live in the tree, but only
  //  one is visible at a time.  Using separate keys lets us save each independently.)
  final GlobalKey<DrawModeState> _drawKey = GlobalKey<DrawModeState>();
  final GlobalKey<DocumentModeState> _docKey = GlobalKey<DocumentModeState>();

  @override
  bool get wantKeepAlive => true;

  /// Called from NotebookDetailScreen to open the import/export dialog on the
  /// currently-active draw canvas.
  Future<void> triggerImport() =>
      _drawKey.currentState?.showImportExportDialog() ?? Future.value();

  Future<void> triggerClearPage() =>
      _drawKey.currentState?.clearPageFromOutside() ?? Future.value();

  Future<void> triggerRotatePage({required bool clockwise}) =>
      _drawKey.currentState?.rotatePageContent90(clockwise: clockwise) ??
      Future.value();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        final newMode = CanvasMode.values[_tabController.index];
        if (newMode != _mode) {
          setState(() => _mode = newMode);
        }
      }
    });
    _autosaveTimer =
        Timer.periodic(const Duration(seconds: 3), (_) => _autoSave());
  }

  @override
  void deactivate() {
    // Save here rather than in dispose(): by the time dispose() runs, the child
    // states behind _drawKey and _docKey are already unmounted, so the save
    // would silently do nothing and recent edits would be lost.
    _saveNow().catchError((Object e) {
      debugPrint('Saving the page on leave failed: $e');
    });
    super.deactivate();
  }

  @override
  void dispose() {
    _autosaveTimer?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  void _markDirty() => _dirty = true;

  /// Saves both editors. Both states are read before the first await, so a
  /// child that unmounts while the drawing is saved still gets its save.
  Future<void> _saveNow() async {
    final draw = _drawKey.currentState;
    final doc = _docKey.currentState;
    await draw?.saveAll();
    await doc?.saveText();
  }

  Future<void> _autoSave() async {
    if (!_dirty) return;
    _dirty = false;
    try {
      await _saveNow();
    } catch (e) {
      // Keep the edits marked as unsaved so the next tick retries them.
      _dirty = true;
      debugPrint('Autosave failed, will retry: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final l10n = AppLocalizations.of(context);

    return Column(
      children: [
        // ── Mode Tabs ────────────────────────────────────────────────────────
        // GoodNotes-style indicator
        Material(
          elevation: 1,
          color: Colors.white,
          child: TabBar(
            controller: _tabController,
            indicator: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: const Color(0xFF2E6DA4),
            ),
            indicatorSize: TabBarIndicatorSize.tab,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.grey.shade600,
            tabs: [
              Tab(icon: const Icon(Icons.draw, size: 18), text: l10n.draw),
              Tab(
                icon: const Icon(Icons.article, size: 18),
                text: l10n.document,
              ),
            ],
            labelStyle:
                const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
            unselectedLabelStyle: const TextStyle(fontSize: 11),
          ),
        ),

        // ── Canvas area ──────────────────────────────────────────────────────
        Expanded(
          child: Stack(
            children: [
              // ── Tab 0 : Draw mode ──────────────────────────────────────────
              // Paper is rendered INSIDE DrawMode so it zooms together with content
              Offstage(
                offstage: _mode != CanvasMode.draw,
                child: DrawMode(
                  key: _drawKey,
                  page: widget.page,
                  onDirty: _markDirty,
                  forceTextBoxTool: false,
                ),
              ),

              // ── Tab 1 : Document mode ──────────────────────────────────────
              Offstage(
                offstage: _mode != CanvasMode.document,
                child: DocumentMode(
                  key: _docKey,
                  page: widget.page,
                  onDirty: _markDirty,
                ),
              ),


            ],
          ),
        ),
      ],
    );
  }
}
