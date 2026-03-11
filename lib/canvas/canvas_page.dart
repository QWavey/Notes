import 'dart:async';
import 'package:flutter/material.dart';
import '../app_localizations.dart';
import '../models/note_page.dart';
import '../models/enums.dart';
import '../widgets/paper_painter.dart';
import 'draw_mode.dart';
import 'document_mode.dart';

class CanvasPage extends StatefulWidget {
  final NotePage page;
  const CanvasPage({super.key, required this.page});

  @override
  State<CanvasPage> createState() => _CanvasPageState();
}

class _CanvasPageState extends State<CanvasPage>
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
  void dispose() {
    _autosaveTimer?.cancel();
    // Best-effort synchronous-ish save on dispose.
    _drawKey.currentState?.saveAll();
    _docKey.currentState?.saveText();
    _tabController.dispose();
    super.dispose();
  }

  void _markDirty() => _dirty = true;

  Future<void> _autoSave() async {
    if (!_dirty) return;
    _dirty = false;
    await _drawKey.currentState?.saveAll();
    await _docKey.currentState?.saveText();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final l10n = AppLocalizations.of(context);

    return Column(
      children: [
        // ── Mode Tabs ────────────────────────────────────────────────────────
        Material(
          elevation: 1,
          color: Colors.white,
          child: TabBar(
            controller: _tabController,
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
              // Paper background — always rendered behind everything.
              Positioned.fill(
                child: CustomPaint(
                  painter: PaperPainter(widget.page.paperType),
                ),
              ),

              // ── Tab 0 : Draw mode ──────────────────────────────────────────
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
