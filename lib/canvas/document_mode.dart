import 'package:flutter/material.dart';
import '../app_localizations.dart';
import '../models/enums.dart';
import '../models/note_page.dart';
import '../services/storage_service.dart';

class DocumentMode extends StatefulWidget {
  final NotePage page;
  final VoidCallback onDirty;

  const DocumentMode({
    super.key,
    required this.page,
    required this.onDirty,
  });

  @override
  State<DocumentMode> createState() => DocumentModeState();
}

class DocumentModeState extends State<DocumentMode> {
  final _storage = StorageService();
  late TextEditingController _controller;
  late FocusNode _focusNode;

  PageSize _pageSize = PageSize.a4;
  String _fontFamily = 'Roboto';
  double _fontSize = 16.0;
  bool _bold = false;
  bool _italic = false;

  static const _fonts = ['Roboto', 'serif', 'monospace'];

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _focusNode = FocusNode();
    _loadText();
    _controller.addListener(() => widget.onDirty());
  }

  @override
  void dispose() {
    // Save on dispose (snapshot)
    _saveTextSync();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _saveTextSync() {
    _storage.saveDocumentText(widget.page.id, _controller.text);
  }

  Future<void> saveText() async {
    await _storage.saveDocumentText(widget.page.id, _controller.text);
  }

  Future<void> _loadText() async {
    final text = await _storage.loadDocumentText(widget.page.id);
    if (mounted) {
      _controller.text = text;
      _controller.selection = TextSelection.fromPosition(
          TextPosition(offset: _controller.text.length));
    }
  }

  double get _pageWidth {
    switch (_pageSize) {
      case PageSize.a4:
        return 794;
      case PageSize.a5:
        return 559;
      case PageSize.letter:
        return 816;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      children: [
        _buildToolbar(l10n),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: Container(
                width: _pageWidth,
                constraints: BoxConstraints(
                    minHeight: MediaQuery.of(context).size.height * 0.8),
                padding: const EdgeInsets.all(48),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 8,
                        offset: const Offset(0, 2))
                  ],
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  maxLines: null,
                  style: TextStyle(
                    fontFamily: _fontFamily,
                    fontSize: _fontSize,
                    fontWeight: _bold ? FontWeight.bold : FontWeight.normal,
                    fontStyle:
                        _italic ? FontStyle.italic : FontStyle.normal,
                    height: 1.6,
                    color: Colors.black87,
                  ),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    hintText: 'Start typing...',
                  ),
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildToolbar(AppLocalizations l10n) {
    return Container(
      height: 48,
      color: Colors.white,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            // Page size
            const Text('Size:', style: TextStyle(fontSize: 12)),
            const SizedBox(width: 4),
            DropdownButton<PageSize>(
              value: _pageSize,
              isDense: true,
              onChanged: (v) => setState(() => _pageSize = v!),
              items: PageSize.values
                  .map((ps) => DropdownMenuItem(
                      value: ps, child: Text(ps.label)))
                  .toList(),
            ),
            const VerticalDivider(width: 16),
            // Font family
            const Text('Font:', style: TextStyle(fontSize: 12)),
            const SizedBox(width: 4),
            DropdownButton<String>(
              value: _fontFamily,
              isDense: true,
              onChanged: (v) => setState(() => _fontFamily = v!),
              items: _fonts
                  .map((f) => DropdownMenuItem(
                        value: f,
                        child: Text(f,
                            style: TextStyle(fontFamily: f, fontSize: 13)),
                      ))
                  .toList(),
            ),
            const VerticalDivider(width: 16),
            // Font size
            const Text('Size:', style: TextStyle(fontSize: 12)),
            SizedBox(
              width: 100,
              child: Slider(
                value: _fontSize,
                min: 10,
                max: 32,
                divisions: 22,
                label: _fontSize.round().toString(),
                onChanged: (v) => setState(() => _fontSize = v),
              ),
            ),
            Text('${_fontSize.round()}pt',
                style: const TextStyle(fontSize: 12)),
            const VerticalDivider(width: 8),
            // Bold
            _toggleBtn(
                'B', _bold, () => setState(() => _bold = !_bold),
                bold: true),
            // Italic
            _toggleBtn(
                'I', _italic, () => setState(() => _italic = !_italic),
                italic: true),
          ],
        ),
      ),
    );
  }

  Widget _toggleBtn(String label, bool active, VoidCallback onTap,
      {bool bold = false, bool italic = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: active ? Colors.blue.shade100 : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
              color: active ? Colors.blue : Colors.grey.shade300),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            fontStyle: italic ? FontStyle.italic : FontStyle.normal,
            color: active ? Colors.blue : Colors.grey.shade700,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}
