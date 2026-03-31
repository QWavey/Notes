import 'package:flutter/material.dart';
import '../models/notebook.dart';
import '../services/storage_service.dart';
import 'notebook_detail_screen.dart';

class TrashScreen extends StatefulWidget {
  const TrashScreen({super.key});

  @override
  State<TrashScreen> createState() => _TrashScreenState();
}

class _TrashScreenState extends State<TrashScreen> {
  final _storage = StorageService();
  List<Notebook> _trashed = [];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() => _trashed = _storage.getTrashedNotebooks());
  }

  Future<void> _restore(Notebook nb) async {
    await _storage.restoreNotebookFromTrash(nb.id);
    _reload();
  }

  Future<void> _deleteForever(Notebook nb) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Endgültig löschen'),
        content: Text('„${nb.name}“ dauerhaft löschen?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Löschen', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _storage.deleteNotebook(nb.id);
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Papierkorb')),
      body: _trashed.isEmpty
          ? const Center(
              child: Text('Papierkorb ist leer',
                  style: TextStyle(color: Colors.grey)),
            )
          : ListView.separated(
              itemCount: _trashed.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final nb = _trashed[i];
                return ListTile(
                  leading: const Icon(Icons.menu_book_outlined),
                  title: Text(nb.name),
                  subtitle: const Text('Im Papierkorb'),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => NotebookDetailScreen(notebookId: nb.id),
                      ),
                    );
                  },
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Wiederherstellen',
                        icon: const Icon(Icons.restore, color: Colors.green),
                        onPressed: () => _restore(nb),
                      ),
                      IconButton(
                        tooltip: 'Endgültig löschen',
                        icon: const Icon(Icons.delete_forever, color: Colors.red),
                        onPressed: () => _deleteForever(nb),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

