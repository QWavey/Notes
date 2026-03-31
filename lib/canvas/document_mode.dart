import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../app_localizations.dart';
import '../models/enums.dart';
import '../models/note_page.dart';
import '../services/storage_service.dart';
import '../screens/notebook_detail_screen.dart' show AppSettings;

// ---------------------------------------------------------------------------
// Rich-text span model
// ---------------------------------------------------------------------------

class _Span {
  int start, end;
  bool bold, italic;
  _Span(this.start, this.end, {required this.bold, required this.italic});

  Map<String, dynamic> toJson() =>
      {'start': start, 'end': end, 'bold': bold, 'italic': italic};

  factory _Span.fromJson(Map<String, dynamic> j) => _Span(
        j['start'] as int,
        j['end'] as int,
        bold: j['bold'] as bool,
        italic: j['italic'] as bool,
      );
}

// ---------------------------------------------------------------------------
// Custom TextEditingController that supports per-selection bold/italic
// ---------------------------------------------------------------------------

class _DocRichController extends TextEditingController {
  final List<_Span> _spans = [];
  String _prevText = '';

  _DocRichController({String text = ''}) : super(text: text) {
    _prevText = text;
    addListener(_onTextChanged);
  }

  // ── Adjust span positions when text is edited ───────────────────────────

  void _onTextChanged() {
    final newText = this.text;
    if (newText == _prevText) return;
    _adjustSpans(_prevText, newText);
  }

  void _adjustSpans(String oldText, String newText) {
    // Find the first differing character (edit point)
    int diffAt = 0;
    while (diffAt < oldText.length &&
        diffAt < newText.length &&
        oldText[diffAt] == newText[diffAt]) {
      diffAt++;
    }
    final delta = newText.length - oldText.length; // +insert, -delete
    final delEnd = diffAt - delta; // end of deleted region in old text (delta<0 only)

    for (int i = _spans.length - 1; i >= 0; i--) {
      int s = _spans[i].start;
      int e = _spans[i].end;

      if (delta < 0) {
        // Deletion: chars [diffAt .. delEnd) were removed
        if (e <= diffAt) {
          // span entirely before deletion → no change
        } else if (s >= delEnd) {
          // span entirely after deletion → shift left
          s += delta;
          e += delta;
        } else {
          // span overlaps deletion region → clip
          if (s > diffAt) s = diffAt;
          if (e > delEnd) e = e + delta;
          else e = diffAt;
        }
      } else {
        // Insertion of [delta] chars at [diffAt]
        if (s >= diffAt) s += delta;
        if (e > diffAt) e += delta;
      }

      s = s.clamp(0, newText.length);
      e = e.clamp(0, newText.length);

      if (s >= e) {
        _spans.removeAt(i);
      } else {
        _spans[i] = _Span(s, e, bold: _spans[i].bold, italic: _spans[i].italic);
      }
    }
    _prevText = newText;
  }

  // ── Toggle bold / italic on selection ───────────────────────────────────

  /// Returns true if the entire selection is already [bold].
  bool isBoldAt(TextSelection sel) {
    if (sel.isCollapsed || sel.start >= sel.end) return false;
    return _spans.any(
        (s) => s.bold && s.start <= sel.start && s.end >= sel.end);
  }

  /// Returns true if the entire selection is already [italic].
  bool isItalicAt(TextSelection sel) {
    if (sel.isCollapsed || sel.start >= sel.end) return false;
    return _spans.any(
        (s) => s.italic && s.start <= sel.start && s.end >= sel.end);
  }

  void toggleBold(TextSelection sel) {
    if (sel.isCollapsed || sel.start >= sel.end) return;
    final wasAll = isBoldAt(sel);
    // Remove any bold spans that overlap the selection
    _spans.removeWhere((s) => s.bold && s.start < sel.end && s.end > sel.start);
    if (!wasAll) {
      _spans.add(_Span(sel.start, sel.end, bold: true, italic: false));
    }
    _spans.sort((a, b) => a.start.compareTo(b.start));
    notifyListeners();
  }

  void toggleItalic(TextSelection sel) {
    if (sel.isCollapsed || sel.start >= sel.end) return;
    final wasAll = isItalicAt(sel);
    _spans.removeWhere((s) => s.italic && s.start < sel.end && s.end > sel.start);
    if (!wasAll) {
      _spans.add(_Span(sel.start, sel.end, bold: false, italic: true));
    }
    _spans.sort((a, b) => a.start.compareTo(b.start));
    notifyListeners();
  }

  // ── Serialisation ────────────────────────────────────────────────────────

  String spansToJson() =>
      jsonEncode({'spans': _spans.map((s) => s.toJson()).toList()});

  void spansFromJson(String raw) {
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      _spans.clear();
      for (final s in (j['spans'] as List)) {
        _spans.add(_Span.fromJson(s as Map<String, dynamic>));
      }
      _prevText = text;
    } catch (_) {}
  }

  // ── Build TextSpan with formatting ───────────────────────────────────────

  @override
  TextSpan buildTextSpan(
      {required BuildContext context,
      TextStyle? style,
      required bool withComposing}) {
    if (_spans.isEmpty) return TextSpan(text: text, style: style);

    final sorted = List<_Span>.from(_spans)
      ..sort((a, b) => a.start.compareTo(b.start));
    final children = <InlineSpan>[];
    int pos = 0;

    for (final span in sorted) {
      final s = span.start.clamp(0, text.length);
      final e = span.end.clamp(0, text.length);
      if (s >= e) continue;

      if (s > pos) {
        children.add(TextSpan(text: text.substring(pos, s), style: style));
      }
      children.add(TextSpan(
        text: text.substring(s, e),
        style: (style ?? const TextStyle()).copyWith(
          fontWeight: span.bold ? FontWeight.bold : FontWeight.normal,
          fontStyle: span.italic ? FontStyle.italic : FontStyle.normal,
        ),
      ));
      pos = e;
    }

    if (pos < text.length) {
      children.add(TextSpan(text: text.substring(pos), style: style));
    }

    return TextSpan(children: children, style: style);
  }
}

// ---------------------------------------------------------------------------
// DocumentMode widget
// ---------------------------------------------------------------------------

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
  late _DocRichController _controller;
  late FocusNode _focusNode;

  PageSize _pageSize = PageSize.a4;
  String _fontFamily = 'Roboto';
  double _fontSize = 16.0;
  // [BETA] Auto-expanding document
  bool _autoExpand = false;
  double _customPageHeight = 1123;

  static const _fonts = ['Roboto', 'serif', 'monospace'];

  @override
  void initState() {
    super.initState();
    _controller = _DocRichController();
    _focusNode = FocusNode();
    _loadText();
    _controller.addListener(() => widget.onDirty());
  }

  @override
  void dispose() {
    _saveTextSync();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _saveTextSync() {
    _storage.saveDocumentText(widget.page.id, _controller.text);
    _storage.saveDocumentSpans(widget.page.id, _controller.spansToJson());
  }

  Future<void> saveText() async {
    await _storage.saveDocumentText(widget.page.id, _controller.text);
    await _storage.saveDocumentSpans(widget.page.id, _controller.spansToJson());
  }

  void _maybeExpand() {
    const charsPerLine = 70;
    const lineHeightPx = 28.0;
    const vPadding = 96.0;
    final lineCount =
        (_controller.text.length / charsPerLine).ceil().clamp(1, 9999);
    final needed = lineCount * lineHeightPx + vPadding + 80;
    final maxH = _pageSize.pixelHeight * 4;
    final target = needed.clamp(_pageSize.pixelHeight, maxH);
    if (target > _customPageHeight) {
      setState(() => _customPageHeight = target);
    }
  }

  Future<void> _loadText() async {
    final text = await _storage.loadDocumentText(widget.page.id);
    final spansRaw = await _storage.loadDocumentSpans(widget.page.id);
    if (mounted) {
      _controller.text = text;
      if (spansRaw != null) _controller.spansFromJson(spansRaw);
      _controller.selection = TextSelection.fromPosition(
          TextPosition(offset: _controller.text.length));
    }
  }

  double get _pageWidth => _pageSize.pixelWidth;

  double get _effectivePageHeight {
    if (_autoExpand) return _customPageHeight;
    return _pageSize.pixelHeight;
  }

  // ── Toggle bold/italic on current selection ──────────────────────────────

  void _toggleBold() {
    final sel = _controller.selection;
    if (sel.isCollapsed) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Select text first to apply bold'),
        duration: Duration(seconds: 2),
      ));
      return;
    }
    setState(() => _controller.toggleBold(sel));
    widget.onDirty();
  }

  void _toggleItalic() {
    final sel = _controller.selection;
    if (sel.isCollapsed) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Select text first to apply italic'),
        duration: Duration(seconds: 2),
      ));
      return;
    }
    setState(() => _controller.toggleItalic(sel));
    widget.onDirty();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final zoomEnabled = AppSettings.instance.documentZoomEnabled;

    final pageContainer = Container(
      width: _pageWidth,
      constraints: BoxConstraints(
        minHeight: _autoExpand ? 400 : _effectivePageHeight,
        maxHeight: _autoExpand ? double.infinity : _effectivePageHeight,
      ),
      padding: const EdgeInsets.all(48),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
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
          height: 1.6,
          color: Colors.black87,
        ),
        decoration: const InputDecoration(
          border: InputBorder.none,
          hintText: 'Start typing...',
        ),
        keyboardType: TextInputType.multiline,
        textInputAction: TextInputAction.newline,
        onChanged: _autoExpand ? (_) => _maybeExpand() : null,
      ),
    );

    return Column(
      children: [
        _buildToolbar(l10n),
        Expanded(
          child: zoomEnabled
              ? InteractiveViewer(
                  constrained: false,
                  minScale: 0.3,
                  maxScale: 4.0,
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(child: pageContainer),
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Center(child: pageContainer),
                ),
        ),
      ],
    );
  }

  Widget _buildToolbar(AppLocalizations l10n) {
    final sel = _controller.selection;
    final hasSel = !sel.isCollapsed;
    final boldActive = hasSel && _controller.isBoldAt(sel);
    final italicActive = hasSel && _controller.isItalicAt(sel);

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
              onChanged: (v) {
                if (v != null) setState(() {
                  _pageSize = v;
                  if (!_autoExpand) _customPageHeight = v.pixelHeight;
                });
              },
              items: PageSize.values
                  .map((ps) => DropdownMenuItem(
                      value: ps, child: Text(ps.label)))
                  .toList(),
            ),
            const VerticalDivider(width: 12),
            // [BETA] Auto-expand toggle
            Tooltip(
              message: '[BETA] Auto Expanding Document',
              child: GestureDetector(
                onTap: () => setState(() => _autoExpand = !_autoExpand),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _autoExpand ? Colors.blue.shade100 : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                        color: _autoExpand ? Colors.blue : Colors.grey.shade300),
                  ),
                  child: Text(
                    '[BETA] Auto ↕',
                    style: TextStyle(
                      fontSize: 11,
                      color: _autoExpand ? Colors.blue : Colors.grey.shade600,
                      fontWeight: _autoExpand ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ),
              ),
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
            // Bold — applies to SELECTION only
            Tooltip(
              message: hasSel
                  ? (boldActive ? 'Remove bold' : 'Bold selection')
                  : 'Select text first to bold',
              child: _toggleBtn(
                'B',
                boldActive,
                _toggleBold,
                bold: true,
                enabled: hasSel,
              ),
            ),
            // Italic — applies to SELECTION only
            Tooltip(
              message: hasSel
                  ? (italicActive ? 'Remove italic' : 'Italic selection')
                  : 'Select text first to italicise',
              child: _toggleBtn(
                'I',
                italicActive,
                _toggleItalic,
                italic: true,
                enabled: hasSel,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _toggleBtn(String label, bool active, VoidCallback onTap,
      {bool bold = false, bool italic = false, bool enabled = true}) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: active
              ? Colors.blue.shade100
              : enabled
                  ? Colors.transparent
                  : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
              color: active
                  ? Colors.blue
                  : enabled
                      ? Colors.grey.shade300
                      : Colors.grey.shade200),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            fontStyle: italic ? FontStyle.italic : FontStyle.normal,
            color: active
                ? Colors.blue
                : enabled
                    ? Colors.grey.shade700
                    : Colors.grey.shade400,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}
