import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:uuid/uuid.dart';

import '../models/annotation_model.dart';
import '../providers/pdf_provider.dart';

const _uuid = Uuid();

class AnnotationOverlay extends ConsumerStatefulWidget {
  const AnnotationOverlay({super.key, required this.pdfController});
  final PdfViewerController pdfController;

  @override
  ConsumerState<AnnotationOverlay> createState() => _AnnotationOverlayState();
}

class _AnnotationOverlayState extends ConsumerState<AnnotationOverlay> {
  // Drawing state
  Offset? _drawStart;
  Offset? _drawCurrent;
  List<Offset> _freehandPoints = [];
  bool _isDrawing = false;

  // Drag-to-move state
  String? _draggingId;
  Offset? _dragLastPos;

  // Inline text editing state
  String? _editingId;
  final TextEditingController _textCtrl = TextEditingController();
  final FocusNode _textFocus = FocusNode();

  @override
  void dispose() {
    _textCtrl.dispose();
    _textFocus.dispose();
    super.dispose();
  }

  // ── Hit testing ──────────────────────────────────────────────────────────────
  AnnotationModel? _hitTest(List<AnnotationModel> annotations, Offset pos) {
    // iterate in reverse so topmost annotation wins
    for (final a in annotations.reversed) {
      final rect = Rect.fromLTWH(a.x - 8, a.y - 8, a.width + 16, a.height + 16);
      if (rect.contains(pos)) return a;
    }
    return null;
  }

  // ── Tap logic ────────────────────────────────────────────────────────────────
  void _onTapUp(TapUpDetails details) {
    final tool = ref.read(selectedToolProvider);
    final doc  = ref.read(currentDocumentProvider);
    if (doc == null) return;

    final annotations = doc.annotations
        .where((a) => a.pageNumber == doc.currentPage)
        .toList();

    if (tool == EditorTool.select) {
      // Finish any inline editing first
      _commitInlineEdit();

      final hit = _hitTest(annotations, details.localPosition);
      if (hit != null) {
        ref.read(selectedAnnotationIdProvider.notifier).state = hit.id;
        // Double-tap opens edit for text annotations — handled by onDoubleTap
      } else {
        ref.read(selectedAnnotationIdProvider.notifier).state = null;
      }
      return;
    }

    if (tool == EditorTool.text) {
      _commitInlineEdit();
      _startInlineText(details.localPosition, doc.currentPage);
      return;
    }

    if (tool == EditorTool.eraser) {
      final hit = _hitTest(annotations, details.localPosition);
      if (hit != null) {
        ref.read(currentDocumentProvider.notifier).deleteAnnotation(hit.id);
        final selId = ref.read(selectedAnnotationIdProvider);
        if (selId == hit.id) {
          ref.read(selectedAnnotationIdProvider.notifier).state = null;
        }
      }
    }
  }

  void _onDoubleTap(TapDownDetails details) {
    final tool = ref.read(selectedToolProvider);
    final doc  = ref.read(currentDocumentProvider);
    if (doc == null) return;

    final annotations = doc.annotations
        .where((a) => a.pageNumber == doc.currentPage)
        .toList();

    if (tool == EditorTool.select || tool == EditorTool.text) {
      final hit = _hitTest(annotations, details.localPosition);
      if (hit != null && hit.type == AnnotationType.text) {
        _startInlineEditExisting(hit);
      }
    }
  }

  // ── Inline text editing ──────────────────────────────────────────────────────
  void _startInlineText(Offset pos, int page) {
    setState(() {
      _editingId = '__new__';
      _textCtrl.text = '';
    });
    _textFocus.requestFocus();
    // We store position temporarily in a provider-agnostic way via local state
    _pendingTextPos = pos;
    _pendingTextPage = page;
  }

  Offset? _pendingTextPos;
  int? _pendingTextPage;

  void _startInlineEditExisting(AnnotationModel a) {
    setState(() {
      _editingId = a.id;
      _textCtrl.text = a.content;
      _textCtrl.selection = TextSelection.collapsed(offset: a.content.length);
    });
    _textFocus.requestFocus();
  }

  void _commitInlineEdit() {
    if (_editingId == null) return;
    final text = _textCtrl.text;

    if (_editingId == '__new__') {
      if (text.trim().isNotEmpty && _pendingTextPos != null) {
        final page = _pendingTextPage ?? 1;
        ref.read(currentDocumentProvider.notifier).addAnnotation(
          AnnotationModel(
            id: _uuid.v4(),
            type: AnnotationType.text,
            pageNumber: page,
            x: _pendingTextPos!.dx,
            y: _pendingTextPos!.dy,
            width: 300,
            height: 40,
            content: text.trim(),
            color: ref.read(selectedColorProvider),
            fontSize: ref.read(fontSizeProvider),
            isBold: ref.read(isBoldProvider),
            isItalic: ref.read(isItalicProvider),
            createdAt: DateTime.now(),
          ),
        );
      }
    } else {
      final doc = ref.read(currentDocumentProvider);
      if (doc != null) {
        final existing = doc.annotations.firstWhere(
          (a) => a.id == _editingId,
          orElse: () => doc.annotations.first,
        );
        if (existing.id == _editingId) {
          if (text.trim().isEmpty) {
            ref.read(currentDocumentProvider.notifier).deleteAnnotation(_editingId!);
          } else {
            ref.read(currentDocumentProvider.notifier).updateAnnotation(
              existing.copyWith(content: text.trim()),
            );
          }
        }
      }
    }

    setState(() {
      _editingId = null;
      _pendingTextPos = null;
      _pendingTextPage = null;
    });
    _textFocus.unfocus();
  }

  // ── Pan / draw logic ─────────────────────────────────────────────────────────
  void _onPanStart(DragStartDetails d) {
    final tool = ref.read(selectedToolProvider);
    final doc  = ref.read(currentDocumentProvider);
    if (doc == null) return;

    // Commit any pending text edit
    _commitInlineEdit();

    if (tool == EditorTool.select) {
      final annotations = doc.annotations
          .where((a) => a.pageNumber == doc.currentPage)
          .toList();
      final hit = _hitTest(annotations, d.localPosition);
      if (hit != null) {
        ref.read(selectedAnnotationIdProvider.notifier).state = hit.id;
        ref.read(currentDocumentProvider.notifier).snapshotForDrag();
        setState(() {
          _draggingId  = hit.id;
          _dragLastPos = d.localPosition;
        });
      }
      return;
    }

    if (tool == EditorTool.eraser) return;
    if (tool == EditorTool.text) return;

    setState(() {
      _drawStart   = d.localPosition;
      _drawCurrent = d.localPosition;
      _isDrawing   = true;
      if (tool == EditorTool.freehand) {
        _freehandPoints = [d.localPosition];
      }
    });
  }

  void _onPanUpdate(DragUpdateDetails d) {
    if (_draggingId != null && _dragLastPos != null) {
      final delta = d.localPosition - _dragLastPos!;
      ref.read(currentDocumentProvider.notifier)
          .moveAnnotationLive(_draggingId!, delta);
      setState(() => _dragLastPos = d.localPosition);
      return;
    }

    if (!_isDrawing) return;
    setState(() {
      _drawCurrent = d.localPosition;
      if (ref.read(selectedToolProvider) == EditorTool.freehand) {
        _freehandPoints.add(d.localPosition);
      }
    });
  }

  void _onPanEnd(DragEndDetails _) {
    // Finish drag-move
    if (_draggingId != null) {
      setState(() {
        _draggingId  = null;
        _dragLastPos = null;
      });
      return;
    }

    if (!_isDrawing || _drawStart == null) { _resetDraw(); return; }

    final tool = ref.read(selectedToolProvider);
    final doc  = ref.read(currentDocumentProvider);
    if (doc == null) { _resetDraw(); return; }

    final color       = ref.read(selectedColorProvider);
    final strokeWidth = ref.read(strokeWidthProvider);
    final page        = doc.currentPage;
    AnnotationModel? annotation;

    switch (tool) {
      case EditorTool.freehand:
        if (_freehandPoints.length > 1) {
          final xs   = _freehandPoints.map((p) => p.dx);
          final ys   = _freehandPoints.map((p) => p.dy);
          final minX = xs.reduce((a, b) => a < b ? a : b);
          final minY = ys.reduce((a, b) => a < b ? a : b);
          final maxX = xs.reduce((a, b) => a > b ? a : b);
          final maxY = ys.reduce((a, b) => a > b ? a : b);
          annotation = AnnotationModel(
            id: _uuid.v4(),
            type: AnnotationType.freehand,
            pageNumber: page,
            x: minX, y: minY,
            width:  (maxX - minX).clamp(1, double.infinity),
            height: (maxY - minY).clamp(1, double.infinity),
            color: color,
            strokeWidth: strokeWidth,
            pathPoints: _freehandPoints
                .map((p) => {'x': p.dx, 'y': p.dy})
                .toList(),
            createdAt: DateTime.now(),
          );
        }
        break;

      case EditorTool.rectangle:
      case EditorTool.circle:
        if (_drawCurrent != null) {
          final r = Rect.fromPoints(_drawStart!, _drawCurrent!);
          if (r.width > 4 && r.height > 4) {
            annotation = AnnotationModel(
              id: _uuid.v4(),
              type: tool == EditorTool.rectangle
                  ? AnnotationType.rectangle
                  : AnnotationType.circle,
              pageNumber: page,
              x: r.left, y: r.top,
              width: r.width, height: r.height,
              color: color,
              strokeWidth: strokeWidth,
              createdAt: DateTime.now(),
            );
          }
        }
        break;

      case EditorTool.highlight:
      case EditorTool.underline:
      case EditorTool.strikethrough:
        if (_drawCurrent != null) {
          final r = Rect.fromPoints(_drawStart!, _drawCurrent!);
          if (r.width > 4) {
            final typeMap = {
              EditorTool.highlight:     AnnotationType.highlight,
              EditorTool.underline:     AnnotationType.underline,
              EditorTool.strikethrough: AnnotationType.strikethrough,
            };
            annotation = AnnotationModel(
              id: _uuid.v4(),
              type: typeMap[tool]!,
              pageNumber: page,
              x: r.left, y: r.top,
              width: r.width,
              height: r.height.clamp(10, double.infinity),
              color: color,
              strokeWidth: strokeWidth,
              opacity: tool == EditorTool.highlight ? 0.4 : 1.0,
              createdAt: DateTime.now(),
            );
          }
        }
        break;

      default:
        break;
    }

    if (annotation != null) {
      ref.read(currentDocumentProvider.notifier).addAnnotation(annotation);
    }
    _resetDraw();
  }

  void _resetDraw() {
    setState(() {
      _drawStart      = null;
      _drawCurrent    = null;
      _isDrawing      = false;
      _freehandPoints = [];
    });
  }

  // ── Keyboard: Delete key removes selected annotation ─────────────────────────
  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.delete ||
          event.logicalKey == LogicalKeyboardKey.backspace) {
        final selId = ref.read(selectedAnnotationIdProvider);
        if (selId != null && _editingId == null) {
          ref.read(currentDocumentProvider.notifier).deleteAnnotation(selId);
          ref.read(selectedAnnotationIdProvider.notifier).state = null;
          return KeyEventResult.handled;
        }
      }
      // Ctrl+Z / Ctrl+Y
      if (HardwareKeyboard.instance.isControlPressed) {
        if (event.logicalKey == LogicalKeyboardKey.keyZ) {
          ref.read(currentDocumentProvider.notifier).undo();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.keyY) {
          ref.read(currentDocumentProvider.notifier).redo();
          return KeyEventResult.handled;
        }
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final tool       = ref.watch(selectedToolProvider);
    final doc        = ref.watch(currentDocumentProvider);
    final selectedId = ref.watch(selectedAnnotationIdProvider);
    if (doc == null) return const SizedBox.shrink();

    final annotations = doc.annotations
        .where((a) => a.pageNumber == doc.currentPage)
        .toList();

    final cursor = tool == EditorTool.select
        ? (_draggingId != null
            ? SystemMouseCursors.grabbing
            : SystemMouseCursors.basic)
        : tool == EditorTool.text
            ? SystemMouseCursors.text
            : tool == EditorTool.eraser
                ? SystemMouseCursors.precise
                : SystemMouseCursors.precise;

    return Focus(
      onKeyEvent: _handleKeyEvent,
      autofocus: true,
      child: MouseRegion(
        cursor: cursor,
        child: GestureDetector(
          onPanStart:  _onPanStart,
          onPanUpdate: _onPanUpdate,
          onPanEnd:    _onPanEnd,
          onTapUp:     _onTapUp,
          onDoubleTapDown: _onDoubleTap,
          child: Stack(
            children: [
              // ── Canvas layer ───────────────────────────────────────────
              CustomPaint(
                painter: _AnnotationPainter(
                  annotations:    annotations,
                  freehandPoints: _freehandPoints,
                  drawStart:      _drawStart,
                  drawCurrent:    _drawCurrent,
                  currentTool:    tool,
                  currentColor:   Color(ref.watch(selectedColorProvider)),
                  strokeWidth:    ref.watch(strokeWidthProvider),
                  opacity:        ref.watch(opacityProvider),
                  selectedId:     selectedId,
                  editingId:      _editingId,
                ),
                child: Container(color: Colors.transparent),
              ),

              // ── Inline text editor ─────────────────────────────────────
              if (_editingId != null)
                _buildInlineEditor(annotations),

              // ── Selection handles ──────────────────────────────────────
              if (tool == EditorTool.select && selectedId != null && _editingId == null)
                _buildSelectionHandle(annotations, selectedId!),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInlineEditor(List<AnnotationModel> annotations) {
    // Determine position
    Offset pos;
    double width;
    double fontSize;
    bool isBold;
    bool isItalic;
    int color;

    if (_editingId == '__new__') {
      pos      = _pendingTextPos ?? Offset.zero;
      width    = 300;
      fontSize = ref.read(fontSizeProvider);
      isBold   = ref.read(isBoldProvider);
      isItalic = ref.read(isItalicProvider);
      color    = ref.read(selectedColorProvider);
    } else {
      final doc = ref.read(currentDocumentProvider);
      final found = doc?.annotations.where((a) => a.id == _editingId);
      if (found == null || found.isEmpty) return const SizedBox.shrink();
      final a = found.first;
      pos      = Offset(a.x, a.y);
      width    = a.width.clamp(150.0, 500.0);
      fontSize = a.fontSize;
      isBold   = a.isBold;
      isItalic = a.isItalic;
      color    = a.color;
    }

    return Positioned(
      left: pos.dx,
      top:  pos.dy,
      width: width,
      child: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(4),
        color: Colors.white.withValues(alpha: 0.95),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Mini toolbar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Edit text:', style: TextStyle(fontSize: 11, color: Colors.black54)),
                  const Spacer(),
                  TextButton(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      minimumSize: const Size(0, 24),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: _commitInlineEdit,
                    child: const Text('Done', style: TextStyle(fontSize: 11)),
                  ),
                  TextButton(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      minimumSize: const Size(0, 24),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: () {
                      setState(() {
                        _editingId = null;
                        _pendingTextPos = null;
                      });
                      _textFocus.unfocus();
                    },
                    child: const Text('Cancel', style: TextStyle(fontSize: 11, color: Colors.red)),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(4),
              child: TextField(
                controller: _textCtrl,
                focusNode: _textFocus,
                maxLines: null,
                autofocus: true,
                style: TextStyle(
                  fontSize: fontSize,
                  fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
                  fontStyle: isItalic ? FontStyle.italic : FontStyle.normal,
                  color: Color(color),
                ),
                decoration: const InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                  hintText: 'Type here…',
                ),
                onSubmitted: (_) => _commitInlineEdit(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectionHandle(List<AnnotationModel> annotations, String selectedId) {
    final doc = ref.read(currentDocumentProvider);
    final found = doc?.annotations.where((a) => a.id == selectedId);
    if (found == null || found.isEmpty) return const SizedBox.shrink();
    final a = found.first;

    return Positioned(
      left: a.x - 8,
      top:  a.y - 8,
      width:  a.width + 16,
      height: a.height + 16,
      child: Stack(
        children: [
          // Dashed selection border
          Container(
            decoration: BoxDecoration(
              border: Border.all(
                color: Colors.blue.withValues(alpha: 0.8),
                width: 1.5,
              ),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Delete button top-right
          Positioned(
            right: 0,
            top: 0,
            child: GestureDetector(
              onTap: () {
                ref.read(currentDocumentProvider.notifier).deleteAnnotation(selectedId);
                ref.read(selectedAnnotationIdProvider.notifier).state = null;
              },
              child: Container(
                width: 20,
                height: 20,
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, size: 12, color: Colors.white),
              ),
            ),
          ),
          // Edit button (for text annotations)
          if (a.type == AnnotationType.text)
            Positioned(
              left: 0,
              top: 0,
              child: GestureDetector(
                onTap: () => _startInlineEditExisting(a),
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: const BoxDecoration(
                    color: Colors.blue,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.edit, size: 12, color: Colors.white),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Annotation painter ────────────────────────────────────────────────────────

class _AnnotationPainter extends CustomPainter {
  const _AnnotationPainter({
    required this.annotations,
    required this.freehandPoints,
    required this.drawStart,
    required this.drawCurrent,
    required this.currentTool,
    required this.currentColor,
    required this.strokeWidth,
    required this.opacity,
    required this.selectedId,
    required this.editingId,
  });

  final List<AnnotationModel> annotations;
  final List<Offset> freehandPoints;
  final Offset? drawStart;
  final Offset? drawCurrent;
  final EditorTool currentTool;
  final Color currentColor;
  final double strokeWidth;
  final double opacity;
  final String? selectedId;
  final String? editingId;

  @override
  void paint(Canvas canvas, Size size) {
    for (final a in annotations) {
      // Skip text that is currently being edited inline (the TextField shows it)
      if (a.id == editingId) continue;
      _drawAnnotation(canvas, a);
    }

    // Live preview while drawing
    final previewPaint = Paint()
      ..color       = currentColor.withValues(alpha: 0.8)
      ..strokeWidth = strokeWidth
      ..style       = PaintingStyle.stroke
      ..strokeCap   = StrokeCap.round
      ..strokeJoin  = StrokeJoin.round;

    if (drawStart != null && drawCurrent != null) {
      final rect = Rect.fromPoints(drawStart!, drawCurrent!);
      switch (currentTool) {
        case EditorTool.rectangle:
          canvas.drawRect(rect, previewPaint);
          break;
        case EditorTool.circle:
          canvas.drawOval(rect, previewPaint);
          break;
        case EditorTool.highlight:
          canvas.drawRect(rect,
              Paint()
                ..color = currentColor.withValues(alpha: 0.3)
                ..style = PaintingStyle.fill);
          break;
        case EditorTool.underline:
          canvas.drawLine(Offset(rect.left, rect.bottom),
              Offset(rect.right, rect.bottom), previewPaint);
          break;
        case EditorTool.strikethrough:
          canvas.drawLine(Offset(rect.left, rect.center.dy),
              Offset(rect.right, rect.center.dy), previewPaint);
          break;
        default:
          break;
      }
    }

    if (freehandPoints.length > 1) {
      final path = Path()
        ..moveTo(freehandPoints.first.dx, freehandPoints.first.dy);
      for (final p in freehandPoints.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(path, previewPaint);
    }
  }

  void _drawAnnotation(Canvas canvas, AnnotationModel a) {
    final isSelected = a.id == selectedId;
    final paint = Paint()
      ..color       = Color(a.color).withValues(alpha: a.opacity)
      ..strokeWidth = a.strokeWidth
      ..style       = PaintingStyle.stroke
      ..strokeCap   = StrokeCap.round
      ..strokeJoin  = StrokeJoin.round;

    switch (a.type) {
      case AnnotationType.freehand:
        if (a.pathPoints != null && a.pathPoints!.length > 1) {
          final path = Path()
            ..moveTo(a.pathPoints!.first['x']!, a.pathPoints!.first['y']!);
          for (final p in a.pathPoints!.skip(1)) {
            path.lineTo(p['x']!, p['y']!);
          }
          canvas.drawPath(path, paint);
        }
        break;
      case AnnotationType.rectangle:
        canvas.drawRect(Rect.fromLTWH(a.x, a.y, a.width, a.height), paint);
        break;
      case AnnotationType.circle:
        canvas.drawOval(Rect.fromLTWH(a.x, a.y, a.width, a.height), paint);
        break;
      case AnnotationType.text:
        TextPainter(
          text: TextSpan(
            text: a.content,
            style: TextStyle(
              color:      Color(a.color),
              fontSize:   a.fontSize,
              fontWeight: a.isBold ? FontWeight.bold : FontWeight.normal,
              fontStyle:  a.isItalic ? FontStyle.italic : FontStyle.normal,
            ),
          ),
          textDirection: TextDirection.ltr,
        )
          ..layout(maxWidth: a.width)
          ..paint(canvas, Offset(a.x, a.y));
        break;
      case AnnotationType.highlight:
        canvas.drawRect(
          Rect.fromLTWH(a.x, a.y, a.width, a.height),
          Paint()
            ..color = Color(a.color).withValues(alpha: 0.35)
            ..style = PaintingStyle.fill,
        );
        break;
      case AnnotationType.underline:
        canvas.drawLine(Offset(a.x, a.y + a.height),
            Offset(a.x + a.width, a.y + a.height), paint);
        break;
      case AnnotationType.strikethrough:
        canvas.drawLine(Offset(a.x, a.y + a.height / 2),
            Offset(a.x + a.width, a.y + a.height / 2), paint);
        break;
      default:
        break;
    }

    // Draw selection highlight outline (subtle blue glow)
    if (isSelected && a.type != AnnotationType.text) {
      canvas.drawRect(
        Rect.fromLTWH(a.x - 4, a.y - 4, a.width + 8, a.height + 8),
        Paint()
          ..color = Colors.blue.withValues(alpha: 0.25)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
