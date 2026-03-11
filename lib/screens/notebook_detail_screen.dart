import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import '../app_localizations.dart';
import '../models/notebook.dart';
import '../models/note_page.dart';
import '../models/enums.dart';
import '../services/storage_service.dart';
import '../widgets/paper_painter.dart';
import '../canvas/canvas_page.dart';

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
  late PageController _pageController;

  @override
  void initState() {
    super.initState();
    _notebook = _storage.getAllNotebooks()
        .firstWhere((n) => n.id == widget.notebookId);
    _loadPages();
    _pageController = PageController(initialPage: _currentIndex);
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
      if (_pages.isEmpty) _addPage();
    });
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
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(ctx).renamePage),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
              labelText: AppLocalizations.of(ctx).pageName),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(AppLocalizations.of(ctx).cancel)),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(AppLocalizations.of(ctx).save)),
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
          const SnackBar(content: Text('Cannot delete the last page')));
      return;
    }
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(ctx).deletePage),
        content: Text(AppLocalizations.of(ctx).deletePageConfirm),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(AppLocalizations.of(ctx).cancel)),
          ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(AppLocalizations.of(ctx).delete,
                  style: const TextStyle(color: Colors.white))),
        ],
      ),
    );
    if (result == true) {
      await _storage.deletePage(_pages[index].id);
      final newIdx = (index > 0) ? index - 1 : 0;
      setState(() => _currentIndex = newIdx);
      _loadPages();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _pageController.jumpToPage(_currentIndex);
      });
    }
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
        duration: const Duration(milliseconds: 250), curve: Curves.easeInOut);
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (_pages.isEmpty) {
      return Scaffold(
          appBar: AppBar(title: Text(_notebook.name)),
          body: const Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: _fullscreen
          ? null
          : AppBar(
              title: Text(_notebook.name),
              actions: [
                IconButton(
                  icon: const Icon(Icons.import_export),
                  tooltip: l10n.importExportPages,
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Import/Export coming soon')));
                  },
                ),
                IconButton(
                  icon: Icon(_fullscreen ? Icons.fullscreen_exit : Icons.fullscreen),
                  tooltip: _fullscreen ? l10n.exitFullscreen : l10n.fullscreen,
                  onPressed: _toggleFullscreen,
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  tooltip: l10n.prevPage,
                  onPressed: _currentIndex > 0
                      ? () => _goToPage(_currentIndex - 1)
                      : null,
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  tooltip: l10n.nextPage,
                  onPressed: _currentIndex < _pages.length - 1
                      ? () => _goToPage(_currentIndex + 1)
                      : null,
                ),
                IconButton(
                  icon: const Icon(Icons.add),
                  tooltip: l10n.addPage,
                  onPressed: _addPage,
                ),
              ],
            ),
      // Floating exit-fullscreen button shown on top of everything when fullscreen
      floatingActionButton: _fullscreen
          ? FloatingActionButton.small(
              heroTag: 'exitFS',
              backgroundColor: Colors.black54,
              onPressed: _toggleFullscreen,
              tooltip: 'Exit fullscreen',
              child: const Icon(Icons.fullscreen_exit, color: Colors.white),
            )
          : null,
      body: Row(
        children: [
          // ── Sidebar ────────────────────────────────────────────────────────
          if (!_fullscreen) _buildSidebar(l10n),

          // ── Main Canvas Area ───────────────────────────────────────────────
          Expanded(
            child: Column(
              children: [
                Expanded(
                  // Physics: NeverScrollableScrollPhysics so swiping on the
                  // canvas never accidentally flips pages — use the arrow buttons.
                  child: PageView.builder(
                    controller: _pageController,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _pages.length,
                    onPageChanged: (i) => setState(() => _currentIndex = i),
                    itemBuilder: (_, i) => CanvasPage(
                      key: ValueKey(_pages[i].id),
                      page: _pages[i],
                    ),
                  ),
                ),
                // Bottom bar — paper template selector
                if (!_fullscreen) _buildBottomBar(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar(AppLocalizations l10n) {
    return Container(
      width: 120,
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        border: Border(right: BorderSide(color: Colors.grey.shade300)),
      ),
      child: ListView.builder(
        itemCount: _pages.length,
        padding: const EdgeInsets.symmetric(vertical: 8),
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
                  // Paper mini-preview
                  AspectRatio(
                    aspectRatio: 0.7,
                    child: ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(7)),
                      child: CustomPaint(
                        painter: PaperPainter(page.paperType),
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
                          },
                          itemBuilder: (_) => [
                            PopupMenuItem(
                                value: 'rename',
                                child: Text(l10n.renamePage)),
                            PopupMenuItem(
                                value: 'delete',
                                child: Text(l10n.deletePage,
                                    style:
                                        const TextStyle(color: Colors.red))),
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
    );
  }

  Widget _buildBottomBar() {
    if (_pages.isEmpty) return const SizedBox.shrink();
    final currentPage = _pages[_currentIndex];

    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade300)),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        children: PaperType.values.map((pt) {
          final selected = currentPage.paperTypeIndex == pt.index;
          return GestureDetector(
            onTap: () => _setPaperType(currentPage, pt),
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              padding: const EdgeInsets.symmetric(horizontal: 12),
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
                    fontSize: 12,
                    color: selected ? Colors.blue : Colors.grey.shade700,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.normal),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
