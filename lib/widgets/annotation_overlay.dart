import 'package:flutter/material.dart';
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
  ConsumerState<AnnotationOverlay> createState() =>
      _AnnotationOverlayState();
}

class _AnnotationOverlayState extends ConsumerState<AnnotationOverlay> {
  Offset? _drawStart;
  Offset? _drawCurrent;
  List<Offset> _freehandPoints = [];
  bool _isDrawing = false;

  void _onPanStart(DragStartDetails d) {
    final tool = ref.read(selectedToolProvider);
    if (tool == EditorTool.select) return;
    setState(() {
      _drawStart  = d.localPosition;
      _drawCurrent = d.localPosition;
      _isDrawing  = true;
      if (tool == EditorTool.freehand) {
        _freehandPoints = [d.localPosition];
      }
    });
  }

  void _onPanUpdate(DragUpdateDetails d) {
    if (!_isDrawing) return;
    setState(() {
      _drawCurrent = d.localPosition;
      if (ref.read(selectedToolProvider) == EditorTool.freehand) {
        _freehandPoints.add(d.localPosition);
      }
    });
  }

  void _onPanEnd(DragEndDetails _) {
    if (!_isDrawing || _drawStart == null) { _reset(); return; }

    final tool        = ref.read(selectedToolProvider);
    final doc         = ref.read(currentDocumentProvider);
    if (doc == null) { _reset(); return; }

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
    _reset();
  }

  void _reset() {
    setState(() {
      _drawStart      = null;
      _drawCurrent    = null;
      _isDrawing      = false;
      _freehandPoints = [];
    });
  }

  void _onTapForText(TapUpDetails details) {
    final doc = ref.read(currentDocumentProvider);
    if (doc == null) return;
    showDialog<void>(
      context: context,
      builder: (_) => _TextInputDialog(
        position: details.localPosition,
        page: doc.currentPage,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tool = ref.watch(selectedToolProvider);
    final doc  = ref.watch(currentDocumentProvider);
    if (doc == null) return const SizedBox.shrink();

    final cursor = tool == EditorTool.select
        ? SystemMouseCursors.basic
        : tool == EditorTool.text
            ? SystemMouseCursors.text
            : SystemMouseCursors.precise;

    final annotations = doc.annotations
        .where((a) => a.pageNumber == doc.currentPage)
        .toList();

    return MouseRegion(
      cursor: cursor,
      child: GestureDetector(
        onPanStart: _onPanStart,
        onPanUpdate: _onPanUpdate,
        onPanEnd: _onPanEnd,
        onTapUp: tool == EditorTool.text ? _onTapForText : null,
        child: CustomPaint(
          painter: _AnnotationPainter(
            annotations:  annotations,
            freehandPoints: _freehandPoints,
            drawStart:    _drawStart,
            drawCurrent:  _drawCurrent,
            currentTool:  tool,
            currentColor: Color(ref.watch(selectedColorProvider)),
            strokeWidth:  ref.watch(strokeWidthProvider),
            opacity:      ref.watch(opacityProvider),
          ),
          child: Container(color: Colors.transparent),
        ),
      ),
    );
  }
}

// ── Text input dialog ─────────────────────────────────────────────────────────

class _TextInputDialog extends ConsumerStatefulWidget {
  const _TextInputDialog({required this.position, required this.page});

  final Offset position;
  final int page;

  @override
  ConsumerState<_TextInputDialog> createState() =>
      _TextInputDialogState();
}

class _TextInputDialogState extends ConsumerState<_TextInputDialog> {
  final _ctrl = TextEditingController();
  bool _bold   = false;
  bool _italic = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fontSize = ref.watch(fontSizeProvider);
    return AlertDialog(
      title: const Text('Add Text Annotation'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _ctrl,
              autofocus: true,
              maxLines: 5,
              decoration: const InputDecoration(
                hintText: 'Enter text here…',
                border: OutlineInputBorder(),
                filled: true,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                FilterChip(
                  label: const Text('Bold'),
                  selected: _bold,
                  onSelected: (v) => setState(() => _bold = v),
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: const Text('Italic'),
                  selected: _italic,
                  onSelected: (v) => setState(() => _italic = v),
                ),
                const Spacer(),
                Text('${fontSize.round()}pt',
                    style: Theme.of(context).textTheme.labelSmall),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (_ctrl.text.trim().isNotEmpty) {
              ref.read(currentDocumentProvider.notifier).addAnnotation(
                    AnnotationModel(
                      id: const Uuid().v4(),
                      type: AnnotationType.text,
                      pageNumber: widget.page,
                      x: widget.position.dx,
                      y: widget.position.dy,
                      width: 240,
                      height: 40,
                      content: _ctrl.text.trim(),
                      color: ref.read(selectedColorProvider),
                      fontSize: ref.read(fontSizeProvider),
                      isBold: _bold,
                      isItalic: _italic,
                      createdAt: DateTime.now(),
                    ),
                  );
            }
            Navigator.pop(context);
          },
          child: const Text('Add Text'),
        ),
      ],
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
  });

  final List<AnnotationModel> annotations;
  final List<Offset> freehandPoints;
  final Offset? drawStart;
  final Offset? drawCurrent;
  final EditorTool currentTool;
  final Color currentColor;
  final double strokeWidth;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    for (final a in annotations) {
      _drawAnnotation(canvas, a);
    }

    // Live preview
    final previewPaint = Paint()
      // ignore: deprecated_member_use
      ..color       = currentColor.withOpacity(0.8)
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
          canvas.drawRect(
            rect,
            Paint()
              // ignore: deprecated_member_use
              ..color = currentColor.withOpacity(0.3)
              ..style = PaintingStyle.fill,
          );
          break;
        case EditorTool.underline:
          canvas.drawLine(
            Offset(rect.left, rect.bottom),
            Offset(rect.right, rect.bottom),
            previewPaint,
          );
          break;
        case EditorTool.strikethrough:
          canvas.drawLine(
            Offset(rect.left, rect.center.dy),
            Offset(rect.right, rect.center.dy),
            previewPaint,
          );
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
    final paint = Paint()
      // ignore: deprecated_member_use
      ..color       = Color(a.color).withOpacity(a.opacity)
      ..strokeWidth = a.strokeWidth
      ..style       = PaintingStyle.stroke
      ..strokeCap   = StrokeCap.round
      ..strokeJoin  = StrokeJoin.round;

    switch (a.type) {
      case AnnotationType.freehand:
        if (a.pathPoints != null && a.pathPoints!.length > 1) {
          final path = Path()
            ..moveTo(
                a.pathPoints!.first['x']!, a.pathPoints!.first['y']!);
          for (final p in a.pathPoints!.skip(1)) {
            path.lineTo(p['x']!, p['y']!);
          }
          canvas.drawPath(path, paint);
        }
        break;
      case AnnotationType.rectangle:
        canvas.drawRect(
            Rect.fromLTWH(a.x, a.y, a.width, a.height), paint);
        break;
      case AnnotationType.circle:
        canvas.drawOval(
            Rect.fromLTWH(a.x, a.y, a.width, a.height), paint);
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
            // ignore: deprecated_member_use
            ..color = Color(a.color).withOpacity(0.35)
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
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
