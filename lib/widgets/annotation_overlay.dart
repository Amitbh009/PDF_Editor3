import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:uuid/uuid.dart';

import '../models/annotation_model.dart';
import '../models/pdf_text_block.dart';
import '../providers/pdf_provider.dart';

const _uuid = Uuid();

/// Transparent overlay that sits on top of [PdfViewer].
///
/// Responsibilities:
///   • Render all [AnnotationModel] overlays (text, shapes, freehand…)
///   • In **Edit Text** mode: show blue outlines over every PDFium-extracted
///     text block; clicking one opens an inline editor (Word-style).
///   • Convert between screen-pixel space and PDF-point space using the
///     exact scale derived from the pdfrx [PdfViewerController].
class AnnotationOverlay extends ConsumerStatefulWidget {
  const AnnotationOverlay({super.key, required this.controller});

  /// The same controller passed to [PdfViewer] — used to read zoom/page info.
  final PdfViewerController controller;

  @override
  ConsumerState<AnnotationOverlay> createState() => _AnnotationOverlayState();
}

class _AnnotationOverlayState extends ConsumerState<AnnotationOverlay> {
  // ── Drawing state ─────────────────────────────────────────────────────────
  Offset? _drawStart;
  Offset? _drawCurrent;
  List<Offset> _freehandPoints = [];
  bool _isDrawing = false;

  // ── Drag-to-move state (overlay annotations) ──────────────────────────────
  String? _draggingId;
  Offset? _dragLastPos;

  // ── Overlay annotation text editor ────────────────────────────────────────
  String? _editingAnnotationId;
  final TextEditingController _annotCtrl  = TextEditingController();
  final FocusNode             _annotFocus = FocusNode();
  Offset? _pendingTextPos;
  int?    _pendingTextPage;

  // ── Existing PDF text block editor ────────────────────────────────────────
  String? _editingBlockId;
  final TextEditingController _blockCtrl  = TextEditingController();
  final FocusNode             _blockFocus = FocusNode();

  // ── Scale factor (screen pixels per PDF point) ────────────────────────────
  // Updated from the PdfViewerController every build.
  double _scale = 1.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadBlocks());
  }

  @override
  void dispose() {
    _annotCtrl.dispose();
    _annotFocus.dispose();
    _blockCtrl.dispose();
    _blockFocus.dispose();
    super.dispose();
  }

  // ── Scale & block loading ─────────────────────────────────────────────────

  /// Read the exact scale from the pdfrx controller.
  /// [PdfViewerController.pages] gives rendered page rects in screen pixels.
  /// [PdfPage.width] gives PDF-point width.
  /// scale = renderedWidthPx / pdfWidthPt
  double _computeScale(int pageNumber) {
    try {
      final pages = widget.controller.pages;
      if (pages == null || pages.isEmpty) return _scale;
      final idx = (pageNumber - 1).clamp(0, pages.length - 1);
      final rendered = pages[idx]; // PdfPageLayout with rect in screen pixels
      final doc = ref.read(currentDocumentProvider);
      if (doc == null) return _scale;
      final widthCache = ref.read(pageWidthCacheProvider);
      final pdfW = widthCache[pageNumber];
      if (pdfW == null || pdfW <= 0) return _scale;
      return rendered.rect.width / pdfW;
    } catch (_) {
      return _scale;
    }
  }

  Future<void> _loadBlocks() async {
    final doc = ref.read(currentDocumentProvider);
    if (doc == null) return;
    await ref
        .read(textBlockNotifierProvider.notifier)
        .load(doc.filePath, doc.currentPage);
    _updateScale();
  }

  void _updateScale() {
    final doc = ref.read(currentDocumentProvider);
    if (doc == null) return;
    final newScale = _computeScale(doc.currentPage);
    if ((newScale - _scale).abs() > 0.005) {
      setState(() => _scale = newScale);
      ref.read(textBlockNotifierProvider.notifier).applyScale(newScale);
    }
  }

  // ── Hit testing ───────────────────────────────────────────────────────────

  AnnotationModel? _hitAnnotation(
      List<AnnotationModel> annotations, Offset screenPos) {
    // Annotations stored in PDF-point space; convert pos to PDF space first.
    final pdfPos = screenPos / _scale;
    for (final a in annotations.reversed) {
      final r = Rect.fromLTWH(a.x - 6, a.y - 6, a.width + 12, a.height + 12);
      if (r.contains(pdfPos)) return a;
    }
    return null;
  }

  PdfTextBlock? _hitBlock(List<PdfTextBlock> blocks, Offset screenPos) {
    for (final b in blocks.reversed) {
      final r = b.screenRect.inflate(4);
      if (r.contains(screenPos)) return b;
    }
    return null;
  }

  // ── Tap handling ──────────────────────────────────────────────────────────

  void _onTapUp(TapUpDetails d) {
    final tool   = ref.read(selectedToolProvider);
    final doc    = ref.read(currentDocumentProvider);
    if (doc == null) return;

    _commitAnnotationEdit();
    _commitBlockEdit();

    final annotations = doc.annotations
        .where((a) => a.pageNumber == doc.currentPage)
        .toList();

    if (tool == EditorTool.editText) {
      final hit = _hitBlock(
          ref.read(textBlockNotifierProvider), d.localPosition);
      if (hit != null) _startBlockEdit(hit);
      return;
    }

    if (tool == EditorTool.select) {
      final hit = _hitAnnotation(annotations, d.localPosition);
      ref.read(selectedAnnotationIdProvider.notifier).state =
          hit?.id;
      return;
    }

    if (tool == EditorTool.text) {
      _startAnnotationText(d.localPosition, doc.currentPage);
      return;
    }

    if (tool == EditorTool.eraser) {
      final hit = _hitAnnotation(annotations, d.localPosition);
      if (hit != null) {
        ref.read(currentDocumentProvider.notifier).deleteAnnotation(hit.id);
        if (ref.read(selectedAnnotationIdProvider) == hit.id) {
          ref.read(selectedAnnotationIdProvider.notifier).state = null;
        }
      }
    }
  }

  void _onDoubleTap(TapDownDetails d) {
    final tool = ref.read(selectedToolProvider);
    final doc  = ref.read(currentDocumentProvider);
    if (doc == null) return;

    if (tool == EditorTool.editText) {
      final hit = _hitBlock(
          ref.read(textBlockNotifierProvider), d.localPosition);
      if (hit != null) _startBlockEdit(hit);
      return;
    }

    if (tool == EditorTool.select || tool == EditorTool.text) {
      final annotations = doc.annotations
          .where((a) => a.pageNumber == doc.currentPage)
          .toList();
      final hit = _hitAnnotation(annotations, d.localPosition);
      if (hit != null && hit.type == AnnotationType.text) {
        _startAnnotationEditExisting(hit);
      }
    }
  }

  // ── Overlay annotation text editing ──────────────────────────────────────

  void _startAnnotationText(Offset screenPos, int page) {
    setState(() {
      _editingAnnotationId = '__new__';
      _annotCtrl.text      = '';
    });
    _annotFocus.requestFocus();
    _pendingTextPos  = screenPos;
    _pendingTextPage = page;
  }

  void _startAnnotationEditExisting(AnnotationModel a) {
    setState(() {
      _editingAnnotationId = a.id;
      _annotCtrl.text      = a.content;
      _annotCtrl.selection =
          TextSelection.collapsed(offset: a.content.length);
    });
    _annotFocus.requestFocus();
  }

  void _commitAnnotationEdit() {
    if (_editingAnnotationId == null) return;
    final text = _annotCtrl.text;

    if (_editingAnnotationId == '__new__') {
      if (text.trim().isNotEmpty && _pendingTextPos != null) {
        final pdfX = _pendingTextPos!.dx / _scale;
        final pdfY = _pendingTextPos!.dy / _scale;
        ref.read(currentDocumentProvider.notifier).addAnnotation(
          AnnotationModel(
            id:         _uuid.v4(),
            type:       AnnotationType.text,
            pageNumber: _pendingTextPage ?? 1,
            x:          pdfX,
            y:          pdfY,
            width:      200 / _scale,
            height:     30  / _scale,
            content:    text.trim(),
            color:      ref.read(selectedColorProvider),
            fontSize:   ref.read(fontSizeProvider),
            isBold:     ref.read(isBoldProvider),
            isItalic:   ref.read(isItalicProvider),
            createdAt:  DateTime.now(),
          ),
        );
      }
    } else {
      final doc = ref.read(currentDocumentProvider);
      if (doc != null) {
        try {
          final existing = doc.annotations
              .firstWhere((a) => a.id == _editingAnnotationId);
          if (text.trim().isEmpty) {
            ref
                .read(currentDocumentProvider.notifier)
                .deleteAnnotation(_editingAnnotationId!);
          } else {
            ref
                .read(currentDocumentProvider.notifier)
                .updateAnnotation(existing.copyWith(content: text.trim()));
          }
        } catch (_) {}
      }
    }

    setState(() {
      _editingAnnotationId = null;
      _pendingTextPos      = null;
      _pendingTextPage     = null;
    });
    _annotFocus.unfocus();
  }

  // ── Existing PDF text block editing (Word-style) ──────────────────────────

  void _startBlockEdit(PdfTextBlock block) {
    setState(() {
      _editingBlockId   = block.id;
      _blockCtrl.text   = block.editedText;
      _blockCtrl.selection = TextSelection(
          baseOffset: 0, extentOffset: block.editedText.length);
    });
    _blockFocus.requestFocus();
    ref.read(currentDocumentProvider.notifier).markModified();
  }

  void _commitBlockEdit() {
    if (_editingBlockId == null) return;
    ref.read(textBlockNotifierProvider.notifier)
        .updateBlock(_editingBlockId!, _blockCtrl.text);
    if (ref.read(textBlockNotifierProvider.notifier).hasEdits) {
      ref.read(currentDocumentProvider.notifier).markModified();
    }
    setState(() => _editingBlockId = null);
    _blockFocus.unfocus();
  }

  void _cancelBlockEdit() {
    setState(() => _editingBlockId = null);
    _blockFocus.unfocus();
  }

  // ── Pan / draw ────────────────────────────────────────────────────────────

  void _onPanStart(DragStartDetails d) {
    final tool = ref.read(selectedToolProvider);
    final doc  = ref.read(currentDocumentProvider);
    if (doc == null) return;

    _commitAnnotationEdit();
    _commitBlockEdit();

    if (tool == EditorTool.editText) return;
    if (tool == EditorTool.eraser)   return;
    if (tool == EditorTool.text)     return;

    if (tool == EditorTool.select) {
      final annotations = doc.annotations
          .where((a) => a.pageNumber == doc.currentPage)
          .toList();
      final hit = _hitAnnotation(annotations, d.localPosition);
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

    setState(() {
      _drawStart      = d.localPosition;
      _drawCurrent    = d.localPosition;
      _isDrawing      = true;
      _freehandPoints = tool == EditorTool.freehand
          ? [d.localPosition]
          : [];
    });
  }

  void _onPanUpdate(DragUpdateDetails d) {
    if (_draggingId != null && _dragLastPos != null) {
      final delta    = d.localPosition - _dragLastPos!;
      final pdfDelta = delta / _scale;
      ref.read(currentDocumentProvider.notifier)
          .moveAnnotationLive(_draggingId!, pdfDelta);
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
    final s           = _scale;

    AnnotationModel? annotation;

    Rect pdfR(Rect screenR) => Rect.fromLTWH(
          screenR.left   / s,
          screenR.top    / s,
          screenR.width  / s,
          screenR.height / s,
        );

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
            id:         _uuid.v4(),
            type:       AnnotationType.freehand,
            pageNumber: page,
            x: minX / s, y: minY / s,
            width:  ((maxX - minX) / s).clamp(1, double.infinity),
            height: ((maxY - minY) / s).clamp(1, double.infinity),
            color:       color,
            strokeWidth: strokeWidth / s,
            pathPoints:  _freehandPoints
                .map((p) => {'x': p.dx / s, 'y': p.dy / s})
                .toList(),
            createdAt: DateTime.now(),
          );
        }
        break;

      case EditorTool.rectangle:
      case EditorTool.circle:
        if (_drawCurrent != null) {
          final sr = Rect.fromPoints(_drawStart!, _drawCurrent!);
          if (sr.width > 4 && sr.height > 4) {
            final pr = pdfR(sr);
            annotation = AnnotationModel(
              id:         _uuid.v4(),
              type:       tool == EditorTool.rectangle
                  ? AnnotationType.rectangle
                  : AnnotationType.circle,
              pageNumber: page,
              x: pr.left, y: pr.top,
              width: pr.width, height: pr.height,
              color:       color,
              strokeWidth: strokeWidth / s,
              createdAt:   DateTime.now(),
            );
          }
        }
        break;

      case EditorTool.highlight:
      case EditorTool.underline:
      case EditorTool.strikethrough:
        if (_drawCurrent != null) {
          final sr = Rect.fromPoints(_drawStart!, _drawCurrent!);
          if (sr.width > 4) {
            final pr = pdfR(sr);
            annotation = AnnotationModel(
              id:   _uuid.v4(),
              type: {
                EditorTool.highlight:     AnnotationType.highlight,
                EditorTool.underline:     AnnotationType.underline,
                EditorTool.strikethrough: AnnotationType.strikethrough,
              }[tool]!,
              pageNumber: page,
              x: pr.left, y: pr.top,
              width:  pr.width,
              height: pr.height.clamp(8 / s, double.infinity),
              color:       color,
              strokeWidth: strokeWidth / s,
              opacity:     tool == EditorTool.highlight ? 0.4 : 1.0,
              createdAt:   DateTime.now(),
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

  // ── Keyboard shortcuts ────────────────────────────────────────────────────

  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      if (_editingBlockId != null) { _cancelBlockEdit(); return KeyEventResult.handled; }
      if (_editingAnnotationId != null) {
        setState(() { _editingAnnotationId = null; _pendingTextPos = null; });
        _annotFocus.unfocus();
        return KeyEventResult.handled;
      }
    }

    if ((event.logicalKey == LogicalKeyboardKey.delete ||
         event.logicalKey == LogicalKeyboardKey.backspace) &&
        _editingAnnotationId == null &&
        _editingBlockId == null) {
      final selId = ref.read(selectedAnnotationIdProvider);
      if (selId != null) {
        ref.read(currentDocumentProvider.notifier).deleteAnnotation(selId);
        ref.read(selectedAnnotationIdProvider.notifier).state = null;
        return KeyEventResult.handled;
      }
    }

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

    return KeyEventResult.ignored;
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final tool       = ref.watch(selectedToolProvider);
    final doc        = ref.watch(currentDocumentProvider);
    final selectedId = ref.watch(selectedAnnotationIdProvider);
    final textBlocks = ref.watch(textBlockNotifierProvider);

    // React to page changes
    ref.listen(currentDocumentProvider, (prev, next) {
      if (prev?.currentPage != next?.currentPage) _loadBlocks();
    });

    if (doc == null) return const SizedBox.shrink();

    // Update scale every build using the pdfrx controller
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateScale());

    final annotations = doc.annotations
        .where((a) => a.pageNumber == doc.currentPage)
        .toList();

    final cursor = switch (tool) {
      EditorTool.editText => SystemMouseCursors.text,
      EditorTool.select   => _draggingId != null
          ? SystemMouseCursors.grabbing
          : SystemMouseCursors.basic,
      EditorTool.text     => SystemMouseCursors.text,
      EditorTool.eraser   => SystemMouseCursors.precise,
      _                   => SystemMouseCursors.precise,
    };

    return Focus(
      onKeyEvent: _onKey,
      autofocus:  true,
      child: MouseRegion(
        cursor: cursor,
        child: GestureDetector(
          onPanStart:      _onPanStart,
          onPanUpdate:     _onPanUpdate,
          onPanEnd:        _onPanEnd,
          onTapUp:         _onTapUp,
          onDoubleTapDown: _onDoubleTap,
          child: Stack(
            children: [
              // ── Text block highlight overlays (editText mode) ────────────
              if (tool == EditorTool.editText)
                ..._buildBlockHighlights(textBlocks),

              // ── Annotation canvas ────────────────────────────────────────
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
                  editingId:      _editingAnnotationId,
                  scale:          _scale,
                ),
                child: Container(color: Colors.transparent),
              ),

              // ── Overlay text annotation editor ───────────────────────────
              if (_editingAnnotationId != null)
                _buildAnnotationEditor(annotations),

              // ── Existing PDF text block editor ───────────────────────────
              if (_editingBlockId != null)
                _buildBlockEditor(textBlocks),

              // ── Selection handle ─────────────────────────────────────────
              if (tool == EditorTool.select &&
                  selectedId != null &&
                  _editingAnnotationId == null)
                _buildSelectionHandle(annotations, selectedId),
            ],
          ),
        ),
      ),
    );
  }

  // ── Text block highlights ─────────────────────────────────────────────────

  List<Widget> _buildBlockHighlights(List<PdfTextBlock> blocks) {
    return blocks.map((b) {
      final editing = b.id == _editingBlockId;
      return Positioned.fromRect(
        rect: b.screenRect,
        child: IgnorePointer(
          child: Container(
            decoration: BoxDecoration(
              color: editing
                  ? Colors.blue.withValues(alpha: 0.12)
                  : b.isEdited
                      ? Colors.green.withValues(alpha: 0.10)
                      : Colors.transparent,
              border: Border.all(
                color: editing
                    ? Colors.blue.withValues(alpha: 0.75)
                    : b.isEdited
                        ? Colors.green.withValues(alpha: 0.6)
                        : Colors.blue.withValues(alpha: 0.22),
                width: editing ? 1.5 : 0.8,
              ),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      );
    }).toList();
  }

  // ── Block editor (Word-style inline editor) ───────────────────────────────

  Widget _buildBlockEditor(List<PdfTextBlock> blocks) {
    PdfTextBlock? block;
    try {
      block = blocks.firstWhere((b) => b.id == _editingBlockId);
    } catch (_) {
      return const SizedBox.shrink();
    }

    final left  = block.screenRect.left;
    final top   = block.screenRect.top - 32; // room for toolbar above
    final width = block.screenRect.width.clamp(220.0, 640.0);

    return Positioned(
      left:  left,
      top:   top.clamp(0.0, double.infinity),
      width: width,
      child: Material(
        elevation:    8,
        borderRadius: BorderRadius.circular(6),
        color:        Colors.white,
        child: Column(
          mainAxisSize:       MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // toolbar
            Container(
              height:  30,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: const BoxDecoration(
                color: Color(0xFF1565C0),
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(6)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.edit_document,
                      size: 13, color: Colors.white70),
                  const SizedBox(width: 6),
                  const Expanded(
                    child: Text('Edit existing text',
                        style: TextStyle(
                            fontSize: 11,
                            color:    Colors.white,
                            fontWeight: FontWeight.w600)),
                  ),
                  _miniBtn('Done',   Colors.white,   _commitBlockEdit),
                  const SizedBox(width: 4),
                  _miniBtn('Cancel', Colors.white60, _cancelBlockEdit),
                ],
              ),
            ),
            // editable field
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
              child: TextField(
                controller: _blockCtrl,
                focusNode:  _blockFocus,
                maxLines:   null,
                autofocus:  true,
                style: TextStyle(
                  fontSize:   (block.fontSize * _scale).clamp(10.0, 28.0),
                  fontWeight: block.isBold   ? FontWeight.bold   : FontWeight.normal,
                  fontStyle:  block.isItalic ? FontStyle.italic  : FontStyle.normal,
                  color:      Color(block.colorArgb),
                ),
                decoration: const InputDecoration(
                  isDense:        true,
                  border:         OutlineInputBorder(),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  hintText: 'Type replacement text…',
                  hintStyle:
                      TextStyle(fontSize: 11, color: Colors.black38),
                ),
                onSubmitted: (_) => _commitBlockEdit(),
              ),
            ),
            // original hint
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
              child: Text(
                'Original: "${block.originalText}"',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 9,
                    color:    Colors.black38,
                    fontStyle: FontStyle.italic),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _miniBtn(String label, Color color, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding:    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color:        Colors.white.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize:   11,
                  color:      color,
                  fontWeight: FontWeight.w600)),
        ),
      );

  // ── Overlay annotation text editor ────────────────────────────────────────

  Widget _buildAnnotationEditor(List<AnnotationModel> annotations) {
    Offset pos;
    double width, fontSize;
    bool isBold, isItalic;
    int color;

    if (_editingAnnotationId == '__new__') {
      pos      = _pendingTextPos ?? Offset.zero;
      width    = 280;
      fontSize = ref.read(fontSizeProvider);
      isBold   = ref.read(isBoldProvider);
      isItalic = ref.read(isItalicProvider);
      color    = ref.read(selectedColorProvider);
    } else {
      final doc = ref.read(currentDocumentProvider);
      AnnotationModel? a;
      try {
        a = doc?.annotations.firstWhere((a) => a.id == _editingAnnotationId);
      } catch (_) {}
      if (a == null) return const SizedBox.shrink();
      pos      = Offset(a.x * _scale, a.y * _scale);
      width    = (a.width * _scale).clamp(150.0, 480.0);
      fontSize = a.fontSize;
      isBold   = a.isBold;
      isItalic = a.isItalic;
      color    = a.color;
    }

    return Positioned(
      left:  pos.dx,
      top:   pos.dy,
      width: width,
      child: Material(
        elevation:    4,
        borderRadius: BorderRadius.circular(4),
        color:        Colors.white,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding:    const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(4)),
              ),
              child: Row(
                children: [
                  const Text('Add text:',
                      style: TextStyle(fontSize: 11, color: Colors.black54)),
                  const Spacer(),
                  TextButton(
                    style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        minimumSize: const Size(0, 24),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                    onPressed: _commitAnnotationEdit,
                    child: const Text('Done',
                        style: TextStyle(fontSize: 11)),
                  ),
                  TextButton(
                    style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        minimumSize: const Size(0, 24),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                    onPressed: () {
                      setState(() {
                        _editingAnnotationId = null;
                        _pendingTextPos      = null;
                      });
                      _annotFocus.unfocus();
                    },
                    child: const Text('Cancel',
                        style: TextStyle(
                            fontSize: 11, color: Colors.red)),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(4),
              child: TextField(
                controller: _annotCtrl,
                focusNode:  _annotFocus,
                maxLines:   null,
                autofocus:  true,
                style: TextStyle(
                  fontSize:   fontSize,
                  fontWeight: isBold   ? FontWeight.bold  : FontWeight.normal,
                  fontStyle:  isItalic ? FontStyle.italic : FontStyle.normal,
                  color:      Color(color),
                ),
                decoration: const InputDecoration(
                  isDense: true,
                  border:  InputBorder.none,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                  hintText: 'Type here…',
                ),
                onSubmitted: (_) => _commitAnnotationEdit(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Selection handle ──────────────────────────────────────────────────────

  Widget _buildSelectionHandle(
      List<AnnotationModel> annotations, String selId) {
    AnnotationModel? a;
    try {
      a = ref.read(currentDocumentProvider)?.annotations
          .firstWhere((ann) => ann.id == selId);
    } catch (_) {}
    if (a == null) return const SizedBox.shrink();

    final r = Rect.fromLTWH(
        a.x * _scale - 8, a.y * _scale - 8,
        a.width  * _scale + 16,
        a.height * _scale + 16);

    return Positioned.fromRect(
      rect: r,
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              border: Border.all(
                  color: Colors.blue.withValues(alpha: 0.8), width: 1.5),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Positioned(
            right: 0,
            top:   0,
            child: GestureDetector(
              onTap: () {
                ref
                    .read(currentDocumentProvider.notifier)
                    .deleteAnnotation(selId);
                ref
                    .read(selectedAnnotationIdProvider.notifier)
                    .state = null;
              },
              child: Container(
                width:       20,
                height:      20,
                decoration:  const BoxDecoration(
                    color: Colors.red, shape: BoxShape.circle),
                child: const Icon(Icons.close, size: 12, color: Colors.white),
              ),
            ),
          ),
          if (a.type == AnnotationType.text)
            Positioned(
              left: 0,
              top:  0,
              child: GestureDetector(
                onTap: () => _startAnnotationEditExisting(a!),
                child: Container(
                  width:  20,
                  height: 20,
                  decoration: const BoxDecoration(
                      color: Colors.blue, shape: BoxShape.circle),
                  child:
                      const Icon(Icons.edit, size: 12, color: Colors.white),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Annotation painter ─────────────────────────────────────────────────────────

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
    required this.scale,
  });

  final List<AnnotationModel> annotations;
  final List<Offset>          freehandPoints;
  final Offset?               drawStart;
  final Offset?               drawCurrent;
  final EditorTool            currentTool;
  final Color                 currentColor;
  final double                strokeWidth;
  final double                opacity;
  final String?               selectedId;
  final String?               editingId;
  final double                scale; // screen px / PDF pt

  @override
  void paint(Canvas canvas, Size size) {
    for (final a in annotations) {
      if (a.id == editingId) continue;
      _drawOne(canvas, a);
    }

    // Live preview
    final prevPaint = Paint()
      ..color       = currentColor.withValues(alpha: 0.8)
      ..strokeWidth = strokeWidth
      ..style       = PaintingStyle.stroke
      ..strokeCap   = StrokeCap.round
      ..strokeJoin  = StrokeJoin.round;

    if (drawStart != null && drawCurrent != null) {
      final r = Rect.fromPoints(drawStart!, drawCurrent!);
      switch (currentTool) {
        case EditorTool.rectangle:
          canvas.drawRect(r, prevPaint);
          break;
        case EditorTool.circle:
          canvas.drawOval(r, prevPaint);
          break;
        case EditorTool.highlight:
          canvas.drawRect(
              r,
              Paint()
                ..color = currentColor.withValues(alpha: 0.3)
                ..style = PaintingStyle.fill);
          break;
        case EditorTool.underline:
          canvas.drawLine(r.bottomLeft, r.bottomRight, prevPaint);
          break;
        case EditorTool.strikethrough:
          canvas.drawLine(r.centerLeft, r.centerRight, prevPaint);
          break;
        default:
          break;
      }
    }

    if (freehandPoints.length > 1) {
      final path = Path()
        ..moveTo(freehandPoints.first.dx, freehandPoints.first.dy);
      for (final p in freehandPoints.skip(1)) path.lineTo(p.dx, p.dy);
      canvas.drawPath(path, prevPaint);
    }
  }

  void _drawOne(Canvas canvas, AnnotationModel a) {
    final s    = scale;
    final sel  = a.id == selectedId;
    final sx   = a.x * s;
    final sy   = a.y * s;
    final sw   = a.width  * s;
    final sh   = a.height * s;
    final rect = Rect.fromLTWH(sx, sy, sw, sh);

    final paint = Paint()
      ..color       = Color(a.color).withValues(alpha: a.opacity)
      ..strokeWidth = a.strokeWidth * s
      ..style       = PaintingStyle.stroke
      ..strokeCap   = StrokeCap.round
      ..strokeJoin  = StrokeJoin.round;

    switch (a.type) {
      case AnnotationType.freehand:
        if (a.pathPoints != null && a.pathPoints!.length > 1) {
          final path = Path()
            ..moveTo(a.pathPoints!.first['x']! * s,
                     a.pathPoints!.first['y']! * s);
          for (final p in a.pathPoints!.skip(1)) {
            path.lineTo(p['x']! * s, p['y']! * s);
          }
          canvas.drawPath(path, paint);
        }
        break;
      case AnnotationType.rectangle:
        canvas.drawRect(rect, paint);
        break;
      case AnnotationType.circle:
        canvas.drawOval(rect, paint);
        break;
      case AnnotationType.text:
        TextPainter(
          text: TextSpan(
            text:  a.content,
            style: TextStyle(
              color:      Color(a.color),
              fontSize:   a.fontSize * s,
              fontWeight: a.isBold   ? FontWeight.bold   : FontWeight.normal,
              fontStyle:  a.isItalic ? FontStyle.italic  : FontStyle.normal,
            ),
          ),
          textDirection: TextDirection.ltr,
        )
          ..layout(maxWidth: sw)
          ..paint(canvas, Offset(sx, sy));
        break;
      case AnnotationType.highlight:
        canvas.drawRect(
          rect,
          Paint()
            ..color = Color(a.color).withValues(alpha: 0.35)
            ..style = PaintingStyle.fill,
        );
        break;
      case AnnotationType.underline:
        canvas.drawLine(rect.bottomLeft, rect.bottomRight, paint);
        break;
      case AnnotationType.strikethrough:
        canvas.drawLine(rect.centerLeft, rect.centerRight, paint);
        break;
      default:
        break;
    }

    if (sel && a.type != AnnotationType.text) {
      canvas.drawRect(
        rect.inflate(4),
        Paint()
          ..color       = Colors.blue.withValues(alpha: 0.25)
          ..style       = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter _) => true;
}
