import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';

const List<Color> kBasicColors = [
  Color(0xFF000000), Color(0xFF424242), Color(0xFF9E9E9E), Color(0xFFFFFFFF),
  Color(0xFFD32F2F), Color(0xFFF57C00), Color(0xFFFBC02D), Color(0xFF388E3C),
  Color(0xFF0288D1), Color(0xFF1565C0), Color(0xFF6A1B9A), Color(0xFFAD1457),
  Color(0xFF4E342E), Color(0xFF00695C), Color(0xFF00838F), Color(0xFF37474F),
];

class ColorPalette extends StatelessWidget {
  final Color selectedColor;
  final ValueChanged<Color> onColorChanged;

  const ColorPalette({
    super.key,
    required this.selectedColor,
    required this.onColorChanged,
  });

  @override
  Widget build(BuildContext context) {
    // 2 rows × 8
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildRow(context, kBasicColors.sublist(0, 8)),
        const SizedBox(height: 4),
        Row(
          children: [
            ..._buildColorCircles(context, kBasicColors.sublist(8, 16)),
            const SizedBox(width: 4),
            _buildPlusButton(context),
          ],
        ),
      ],
    );
  }

  Widget _buildRow(BuildContext context, List<Color> colors) {
    return Row(
      children: _buildColorCircles(context, colors),
    );
  }

  List<Widget> _buildColorCircles(BuildContext context, List<Color> colors) {
    return colors
        .map((c) => GestureDetector(
              onTap: () => onColorChanged(c),
              child: Container(
                margin: const EdgeInsets.all(3),
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: c,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selectedColor == c
                        ? Colors.blue
                        : Colors.grey.shade400,
                    width: selectedColor == c ? 3 : 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black26,
                        blurRadius: 2,
                        offset: const Offset(0, 1)),
                  ],
                ),
              ),
            ))
        .toList();
  }

  Widget _buildPlusButton(BuildContext context) {
    return GestureDetector(
      onTap: () => _showExtendedPicker(context),
      child: Container(
        margin: const EdgeInsets.all(3),
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.grey.shade400),
          gradient: const LinearGradient(
            colors: [Colors.red, Colors.green, Colors.blue],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: const Icon(Icons.add, size: 16, color: Colors.white),
      ),
    );
  }

  void _showExtendedPicker(BuildContext context) {
    Color tmp = selectedColor;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Choose Color'),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: selectedColor,
            onColorChanged: (c) => tmp = c,
            enableAlpha: false,
            labelTypes: const [],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () {
                onColorChanged(tmp);
                Navigator.pop(ctx);
              },
              child: const Text('OK')),
        ],
      ),
    );
  }
}

// ─── Floating Color Bubble ─────────────────────────────────────────────────

class FloatingColorBubble extends StatefulWidget {
  final Color color;
  final ValueChanged<Color> onColorChanged;

  const FloatingColorBubble({
    super.key,
    required this.color,
    required this.onColorChanged,
  });

  @override
  State<FloatingColorBubble> createState() => _FloatingColorBubbleState();
}

class _FloatingColorBubbleState extends State<FloatingColorBubble> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 8)],
      ),
      child: _expanded
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: () => setState(() => _expanded = false),
                  child: _colorCircle(widget.color, 28),
                ),
                const SizedBox(height: 6),
                ColorPalette(
                  selectedColor: widget.color,
                  onColorChanged: (c) {
                    widget.onColorChanged(c);
                    setState(() => _expanded = false);
                  },
                ),
              ],
            )
          : GestureDetector(
              onTap: () => setState(() => _expanded = true),
              child: _colorCircle(widget.color, 36),
            ),
    );
  }

  Widget _colorCircle(Color c, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: c,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.grey.shade300, width: 2),
      ),
    );
  }
}
