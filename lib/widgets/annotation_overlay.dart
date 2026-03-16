import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:uuid/uuid.dart';
import '../providers/pdf_provider.dart';
import '../models/annotation_model.dart';

const _uuid = Uuid();

class AnnotationOverlay extends ConsumerStatefulWidget {
  final PdfViewerController pdfController;
  const AnnotationOverlay({super.key, required this.pdfController});

  @override
  ConsumerState<AnnotationOverlay> createState() =>
      _AnnotationOverlayState();
}

class _AnnotationOverlayState extends ConsumerState<AnnotationOverlay> {
  Offset? _drawStart;
  Offset? _lastDrag;
  List<Offset> _freehandPoints = [];
  bool _isDrawing = false;

  void _onPanStart(DragStartDetails d) {
    final tool = ref.read(selectedToolProvider);
    if (tool == EditorTool.select) return;
    setState(() {
      _drawStart = d.localPosition;
      _lastDrag = d.localPosition;
      _isDrawing = true;
      if (tool == EditorTool.freehand) {
        _freehandPoints = [d.localPosition];
      }
    });
  }

  void _onPanUpdate(DragUpdateDetails d) {
    if (!_isDrawing) return;
    final tool = ref.read(selectedToolProvider);
    setState(() {
      _lastDrag = d.localPosition;
      if (tool == EditorTool.freehand) {
        _freehandPoints.add(d.localPosition);
      }
    });
  }

  void _onPanEnd(DragEndDetails _) {
    if (!_isDrawing || _drawStart == null) return;
    final tool = ref.read(selectedToolProvider);
    final doc = ref.read(currentDocumentProvider);
    if (doc == null) {
      setState(() {
        _drawStart = null;
        _lastDrag = null;
        _isDrawing = false;
        _freehandPoints = [];
      });
      return;
    }

    final color = ref.read(selectedColorProvider);
    final stroke = ref.read(strokeWidthProvider);
    final page = doc.currentPage;
    AnnotationModel? annotation;

    if (tool == EditorTool.freehand && _freehandPoints.length > 1) {
      final xs = _freehandPoints.map((p) => p.dx);
      final ys = _freehandPoints.map((p) => p.dy);
      annotation = AnnotationModel(
        id: _uuid.v4(),
        type: AnnotationType.freehand,
        pageNumber: page,
        x: xs.reduce((a, b) => a < b ? a : b),
        y: ys.reduce((a, b) => a < b ? a : b),
        width: xs.reduce((a, b) => a > b ? a : b) -
            xs.reduce((a, b) => a < b ? a : b),
        height: ys.reduce((a, b) => a > b ? a : b) -
            ys.reduce((a, b) => a < b ? a : b),
        color: color,
        strokeWidth: stroke,
        pathPoints: _freehandPoints
            .map((p) => {'x': p.dx, 'y': p.dy})
            .toList(),
        createdAt: DateTime.now(),
      );
    } else if ((tool == EditorTool.rectangle || tool == EditorTool.circle) &&
        _lastDrag != null) {
      final rect = Rect.fromPoints(_drawStart!, _lastDrag!);
      if (rect.width > 4 && rect.height > 4) {
        annotation = AnnotationModel(
          id: _uuid.v4(),
          type: tool == EditorTool.rectangle
              ? AnnotationType.rectangle
              : AnnotationType.circle,
          pageNumber: page,
          x: rect.left,
          y: rect.top,
          width: rect.width,
          height: rect.height,
          color: color,
          strokeWidth: stroke,
          createdAt: DateTime.now(),
        );
      }
    } else if ((tool == EditorTool.highlight ||
            tool == EditorTool.underline ||
            tool == EditorTool.strikethrough) &&
        _lastDrag != null) {
      final rect = Rect.fromPoints(_drawStart!, _lastDrag!);
      annotation = AnnotationModel(
        id: _uuid.v4(),
        type: tool == EditorTool.highlight
            ? AnnotationType.highlight
            : tool == EditorTool.underline
                ? AnnotationType.underline
                : AnnotationType.strikethrough,
        pageNumber: page,
        x: rect.left,
        y: rect.top,
        width: rect.width,
        height: rect.height,
        color: color,
        opacity: 0.4,
        strokeWidth: stroke,
        createdAt: DateTime.now(),
      );
    }

    if (annotation != null) {
      ref.read(currentDocumentProvider.notifier).addAnnotation(annotation);
    }

    setState(() {
      _drawStart = null;
      _lastDrag = null;
      _isDrawing = false;
      _freehandPoints = [];
    });
  }

  @override
  Widget build(BuildContext context) {
    final tool = ref.watch(selectedToolProvider);
    final doc = ref.watch(currentDocumentProvider);
    if (doc == null) return const SizedBox.shrink();

    final pageAnnotations = doc.annotations
        .where((a) => a.pageNumber == doc.currentPage)
        .toList();

    final cursor = _cursorForTool(tool);

    return MouseRegion(
      cursor: cursor,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onPanStart: tool != EditorTool.select ? _onPanStart : null,
        onPanUpdate: tool != EditorTool.select ? _onPanUpdate : null,
        onPanEnd: tool != EditorTool.select ? _onPanEnd : null,
        onTapUp: tool == EditorTool.text ? _onTapForText : null,
        child: CustomPaint(
          painter: AnnotationPainter(
            annotations: pageAnnotations,
            freehandPoints: _freehandPoints,
            drawStart: _drawStart,
            lastDrag: _lastDrag,
            currentTool: tool,
            currentColor: Color(ref.watch(selectedColorProvider)),
            strokeWidth: ref.watch(strokeWidthProvider),
          ),
          child: Container(color: Colors.transparent),
        ),
      ),
    );
  }

  MouseCursor _cursorForTool(EditorTool tool) {
    switch (tool) {
      case EditorTool.text:
        return SystemMouseCursors.text;
      case EditorTool.eraser:
        return SystemMouseCursors.precise;
      case EditorTool.select:
        return SystemMouseCursors.basic;
      default:
        return SystemMouseCursors.precise;
    }
  }

  void _onTapForText(TapUpDetails details) {
    final doc = ref.read(currentDocumentProvider);
    if (doc == null) return;
    showDialog(
      context: context,
      builder: (_) => _TextInputDialog(
        position: details.localPosition,
        page: doc.currentPage,
      ),
    );
  }
}

class _TextInputDialog extends ConsumerStatefulWidget {
  final Offset position;
  final int page;
  const _TextInputDialog({required this.position, required this.page});

  @override
  ConsumerState<_TextInputDialog> createState() => _TextInputDialogState();
}

class _TextInputDialogState extends ConsumerState<_TextInputDialog> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Text'),
      content: SizedBox(
        width: 300,
        child: TextField(
          controller: _ctrl,
          autofocus: true,
          maxLines: 5,
          decoration: const InputDecoration(
            hintText: 'Enter text...',
            border: OutlineInputBorder(),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (_ctrl.text.isNotEmpty) {
              final annotation = AnnotationModel(
                id: const Uuid().v4(),
                type: AnnotationType.text,
                pageNumber: widget.page,
                x: widget.position.dx,
                y: widget.position.dy,
                width: 200,
                height: 40,
                content: _ctrl.text,
                color: ref.read(selectedColorProvider),
                fontSize: ref.read(fontSizeProvider),
                isBold: ref.read(isBoldProvider),
                isItalic: ref.read(isItalicProvider),
                createdAt: DateTime.now(),
              );
              ref
                  .read(currentDocumentProvider.notifier)
                  .addAnnotation(annotation);
            }
            Navigator.pop(context);
          },
          child: const Text('Add'),
        ),
      ],
    );
  }
}

class AnnotationPainter extends CustomPainter {
  final List<AnnotationModel> annotations;
  final List<Offset> freehandPoints;
  final Offset? drawStart;
  final Offset? lastDrag;
  final EditorTool currentTool;
  final Color currentColor;
  final double strokeWidth;

  AnnotationPainter({
    required this.annotations,
    required this.freehandPoints,
    required this.drawStart,
    required this.lastDrag,
    required this.currentTool,
    required this.currentColor,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final a in annotations) {
      _drawAnnotation(canvas, a);
    }
    _drawLivePreview(canvas);
  }

  void _drawAnnotation(Canvas canvas, AnnotationModel a) {
    final paint = Paint()
      ..color = Color(a.color).withOpacity(a.opacity)
      ..strokeWidth = a.strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final bounds = Rect.fromLTWH(a.x, a.y, a.width, a.height);

    switch (a.type) {
      case AnnotationType.freehand:
        if (a.pathPoints != null && a.pathPoints!.length > 1) {
          final path = Path();
          final pts = a.pathPoints!;
          path.moveTo(pts.first['x']!, pts.first['y']!);
          for (final p in pts.skip(1)) {
            path.lineTo(p['x']!, p['y']!);
          }
          canvas.drawPath(path, paint);
        }
        break;

      case AnnotationType.rectangle:
        canvas.drawRect(bounds, paint);
        break;

      case AnnotationType.circle:
        canvas.drawOval(bounds, paint);
        break;

      case AnnotationType.highlight:
        canvas.drawRect(
          bounds,
          Paint()
            ..color = Color(a.color).withOpacity(0.3)
            ..style = PaintingStyle.fill,
        );
        break;

      case AnnotationType.underline:
        final linePaint = Paint()
          ..color = Color(a.color)
          ..strokeWidth = 2;
        canvas.drawLine(
          Offset(a.x, a.y + a.height),
          Offset(a.x + a.width, a.y + a.height),
          linePaint,
        );
        break;

      case AnnotationType.strikethrough:
        final linePaint = Paint()
          ..color = Color(a.color)
          ..strokeWidth = 2;
        final midY = a.y + a.height / 2;
        canvas.drawLine(
          Offset(a.x, midY),
          Offset(a.x + a.width, midY),
          linePaint,
        );
        break;

      case AnnotationType.text:
        final tp = TextPainter(
          text: TextSpan(
            text: a.content,
            style: TextStyle(
              color: Color(a.color),
              fontSize: a.fontSize,
              fontWeight:
                  a.isBold ? FontWeight.bold : FontWeight.normal,
              fontStyle:
                  a.isItalic ? FontStyle.italic : FontStyle.normal,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: a.width);
        tp.paint(canvas, Offset(a.x, a.y));

        // Show selection border
        canvas.drawRect(
          bounds.inflate(2),
          Paint()
            ..color = Colors.blue.withOpacity(0.3)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1,
        );
        break;

      default:
        break;
    }
  }

  void _drawLivePreview(Canvas canvas) {
    if (drawStart == null) return;
    final paint = Paint()
      ..color = currentColor.withOpacity(0.7)
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    if (currentTool == EditorTool.freehand && freehandPoints.length > 1) {
      final path = Path();
      path.moveTo(freehandPoints.first.dx, freehandPoints.first.dy);
      for (final p in freehandPoints.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(path, paint);
      return;
    }

    if (lastDrag == null) return;
    final rect = Rect.fromPoints(drawStart!, lastDrag!);

    if (currentTool == EditorTool.rectangle) {
      canvas.drawRect(rect, paint);
    } else if (currentTool == EditorTool.circle) {
      canvas.drawOval(rect, paint);
    } else if (currentTool == EditorTool.highlight) {
      canvas.drawRect(
        rect,
        Paint()
          ..color = currentColor.withOpacity(0.3)
          ..style = PaintingStyle.fill,
      );
    } else if (currentTool == EditorTool.underline ||
        currentTool == EditorTool.strikethrough) {
      canvas.drawRect(
        rect,
        Paint()
          ..color = currentColor.withOpacity(0.15)
          ..style = PaintingStyle.fill,
      );
      canvas.drawRect(rect, paint..style = PaintingStyle.stroke);
    }
  }

  @override
  bool shouldRepaint(AnnotationPainter old) => true;
}
