import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../app_localizations.dart';
import '../models/notebook.dart';
import '../models/note_page.dart';
import '../models/enums.dart';
import '../services/storage_service.dart';
import '../widgets/notebook_card.dart';
import '../screens/notebook_detail_screen.dart';
import '../screens/settings_screen.dart';

const _kColors = [
  0xFF2563EB, // blue
  0xFF7C3AED, // purple
  0xFF059669, // green
  0xFFDC2626, // red
  0xFFD97706, // amber
  0xFFDB2777, // pink
];

class NotebooksScreen extends StatefulWidget {
  const NotebooksScreen({super.key});

  @override
  State<NotebooksScreen> createState() => _NotebooksScreenState();
}

class _NotebooksScreenState extends State<NotebooksScreen> {
  final _storage = StorageService();
  final _uuid = const Uuid();

  List<Notebook> _notebooks = [];
  DateTime? _lastFabTap;

  @override
  void initState() {
    super.initState();
    _loadNotebooks();
  }

  void _loadNotebooks() {
    setState(() => _notebooks = _storage.getAllNotebooks());
  }

  int _pageCount(String notebookId) =>
      _storage.getPagesForNotebook(notebookId).length;

  // ─── FAB ─────────────────────────────────────────────────────────────────

  void _onFabTap() {
    final now = DateTime.now();
    if (_lastFabTap != null &&
        now.difference(_lastFabTap!).inMilliseconds < 420) {
      _lastFabTap = null;
      _createQuickNote();
    } else {
      _lastFabTap = now;
      Future.delayed(const Duration(milliseconds: 430), () {
        if (_lastFabTap != null &&
            DateTime.now().difference(_lastFabTap!).inMilliseconds >= 420) {
          _lastFabTap = null;
          _showCreateDialog();
        }
      });
    }
  }

  Future<void> _createQuickNote() async {
    final now = DateTime.now();
    final pad2 = (int n) => n.toString().padLeft(2, '0');
    final title =
        'Schnellnotiz ${pad2(now.day)}.${pad2(now.month)}.${now.year} '
        '${pad2(now.hour)}:${pad2(now.minute)}';

    final nb = Notebook(
      id: _uuid.v4(),
      name: title,
      colorValue: 0xFF2563EB,
      paperTypeIndex: 0,
      createdAt: now,
    );
    await _storage.saveNotebook(nb);
    await _addFirstPage(nb);
    _loadNotebooks();
  }

  Future<void> _addFirstPage(Notebook nb) async {
    final page = NotePage(
      id: _uuid.v4(),
      notebookId: nb.id,
      name: 'Page 1',
      order: 0,
      paperTypeIndex: nb.paperTypeIndex,
    );
    await _storage.savePage(page);
  }

  // ─── Create Dialog ────────────────────────────────────────────────────────

  Future<void> _showCreateDialog() async {
    String name = '';
    int selectedColor = _kColors[0];

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(AppLocalizations.of(ctx).newNotebook),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                autofocus: true,
                decoration: InputDecoration(
                    labelText: AppLocalizations.of(ctx).notebookName),
                onChanged: (v) => name = v,
              ),
              const SizedBox(height: 16),
              Text(AppLocalizations.of(ctx).color,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: _kColors
                    .map((c) => GestureDetector(
                          onTap: () => setLocal(() => selectedColor = c),
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: Color(c),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: selectedColor == c
                                    ? Colors.black
                                    : Colors.transparent,
                                width: 3,
                              ),
                            ),
                          ),
                        ))
                    .toList(),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(AppLocalizations.of(ctx).cancel)),
            ElevatedButton(
                onPressed: () {
                  if (name.trim().isNotEmpty) Navigator.pop(ctx, true);
                },
                child: Text(AppLocalizations.of(ctx).create)),
          ],
        ),
      ),
    ).then((result) async {
      if (result == true && name.trim().isNotEmpty) {
        final nb = Notebook(
          id: _uuid.v4(),
          name: name.trim(),
          colorValue: selectedColor,
          paperTypeIndex: 0,
          createdAt: DateTime.now(),
        );
        await _storage.saveNotebook(nb);
        await _addFirstPage(nb);
        _loadNotebooks();
      }
    });
  }

  // ─── Rename Dialog ────────────────────────────────────────────────────────

  Future<void> _showRenameDialog(Notebook nb) async {
    final controller = TextEditingController(text: nb.name);
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(ctx).rename),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration:
              InputDecoration(labelText: AppLocalizations.of(ctx).notebookName),
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
      nb.name = controller.text.trim();
      await _storage.saveNotebook(nb);
      _loadNotebooks();
    }
  }

  // ─── Delete Confirm ───────────────────────────────────────────────────────

  Future<void> _confirmDelete(Notebook nb) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(ctx).delete),
        content:
            Text(AppLocalizations.of(ctx).deleteNotebookConfirm),
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
      await _storage.deleteNotebook(nb.id);
      _loadNotebooks();
    }
  }

  // ─── Paper Type Dialog ────────────────────────────────────────────────────

  Future<void> _showPaperTypeDialog(Notebook nb) async {
    PaperType selected = nb.paperType;
    final result = await showDialog<PaperType>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(AppLocalizations.of(ctx).defaultPaperType),
          content: SizedBox(
            width: 300,
            child: ListView(
              shrinkWrap: true,
              children: PaperType.values
                  .map((pt) => RadioListTile<PaperType>(
                        title: Text(pt.label),
                        value: pt,
                        groupValue: selected,
                        onChanged: (v) => setLocal(() => selected = v!),
                      ))
                  .toList(),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(AppLocalizations.of(ctx).cancel)),
            ElevatedButton(
                onPressed: () => Navigator.pop(ctx, selected),
                child: Text(AppLocalizations.of(ctx).ok)),
          ],
        ),
      ),
    );
    if (result != null) {
      nb.paperType = result;
      await _storage.saveNotebook(nb);
      _loadNotebooks();
    }
  }

  // ─── Open Notebook ────────────────────────────────────────────────────────

  void _openNotebook(Notebook nb) {
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (_, anim, __) =>
            NotebookDetailScreen(notebookId: nb.id),
        transitionsBuilder: (_, anim, __, child) {
          return FadeTransition(
            opacity: anim,
            child: ScaleTransition(
              scale: Tween(begin: 0.92, end: 1.0).animate(
                CurvedAnimation(parent: anim, curve: Curves.easeOutCubic),
              ),
              child: child,
            ),
          );
        },
        transitionDuration: const Duration(milliseconds: 300),
      ),
    ).then((_) => _loadNotebooks());
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.notebooks),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
        ],
      ),
      body: _notebooks.isEmpty
          ? _buildEmpty(l10n)
          : Padding(
              padding: const EdgeInsets.all(16),
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 14,
                  crossAxisSpacing: 14,
                  childAspectRatio: 0.78,
                ),
                itemCount: _notebooks.length,
                itemBuilder: (_, i) {
                  final nb = _notebooks[i];
                  return NotebookCard(
                    notebook: nb,
                    pageCount: _pageCount(nb.id),
                    onTap: () => _openNotebook(nb),
                    onRename: () => _showRenameDialog(nb),
                    onDelete: () => _confirmDelete(nb),
                    onSetPaperType: () => _showPaperTypeDialog(nb),
                    isQuickNote: nb.name.startsWith('Schnellnotiz'),
                  );
                },
              ),
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _onFabTap,
        tooltip: l10n.newNotebook,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildEmpty(AppLocalizations l10n) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.menu_book, size: 80, color: Colors.grey),
          const SizedBox(height: 16),
          Text(l10n.newNotebook,
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text('Tap + to create your first notebook',
              style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }
}
