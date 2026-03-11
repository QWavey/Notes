import 'package:flutter/material.dart';
import '../models/notebook.dart';
import '../models/enums.dart';
import '../widgets/paper_painter.dart';

class NotebookCard extends StatelessWidget {
  final Notebook notebook;
  final int pageCount;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final VoidCallback onSetPaperType;
  /// If true, render as a quick-note style card (paper preview as cover)
  final bool isQuickNote;

  const NotebookCard({
    super.key,
    required this.notebook,
    required this.pageCount,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
    required this.onSetPaperType,
    this.isQuickNote = false,
  });

  List<Color> _gradientColors(int colorValue) {
    final base = Color(colorValue);
    final hsl = HSLColor.fromColor(base);
    return [
      hsl.withLightness((hsl.lightness + 0.15).clamp(0.0, 1.0)).toColor(),
      base,
      hsl.withLightness((hsl.lightness - 0.12).clamp(0.0, 1.0)).toColor(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onSetPaperType,
      child: Card(
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        elevation: 2,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Cover — only 45% of card height ─────────────────────────
            Expanded(
              flex: 45,
              child: isQuickNote ? _buildPaperCover() : _buildColorCover(),
            ),

            // ── Title section ────────────────────────────────────────────
            Expanded(
              flex: 55,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      notebook.name,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Icon(isQuickNote ? Icons.bolt : Icons.menu_book,
                            size: 12, color: Colors.grey.shade500),
                        const SizedBox(width: 4),
                        Text(
                          '$pageCount ${pageCount == 1 ? 'Seite' : 'Seiten'}',
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey.shade500),
                        ),
                        const Spacer(),
                        PopupMenuButton<String>(
                          padding: EdgeInsets.zero,
                          iconSize: 16,
                          icon: Icon(Icons.more_vert,
                              size: 16, color: Colors.grey.shade400),
                          onSelected: (v) {
                            if (v == 'rename') onRename();
                            if (v == 'delete') onDelete();
                            if (v == 'paper') onSetPaperType();
                          },
                          itemBuilder: (_) => [
                            const PopupMenuItem(
                                value: 'rename',
                                child: Row(children: [
                                  Icon(Icons.edit, size: 16),
                                  SizedBox(width: 8),
                                  Text('Umbenennen'),
                                ])),
                            const PopupMenuItem(
                                value: 'paper',
                                child: Row(children: [
                                  Icon(Icons.description, size: 16),
                                  SizedBox(width: 8),
                                  Text('Papiertyp'),
                                ])),
                            const PopupMenuItem(
                                value: 'delete',
                                child: Row(children: [
                                  Icon(Icons.delete,
                                      size: 16, color: Colors.red),
                                  SizedBox(width: 8),
                                  Text('Löschen',
                                      style:
                                          TextStyle(color: Colors.red)),
                                ])),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Colour gradient cover for regular notebooks
  Widget _buildColorCover() {
    final colors = _gradientColors(notebook.colorValue);
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: _CoverLinePainter())),
          const Center(
            child: Icon(Icons.menu_book, size: 28, color: Colors.white60),
          ),
        ],
      ),
    );
  }

  /// Paper preview cover for quick notes
  Widget _buildPaperCover() {
    return Stack(
      children: [
        Positioned.fill(
          child: CustomPaint(
            painter: PaperPainter(notebook.paperType),
          ),
        ),
        // Quick-note lightning bolt badge
        Positioned(
          top: 6,
          right: 6,
          child: Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: Colors.amber.shade700,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.bolt, size: 12, color: Colors.white),
          ),
        ),
      ],
    );
  }
}

class _CoverLinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.12)
      ..strokeWidth = 1;
    const spacing = 12.0;
    for (double y = spacing; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
