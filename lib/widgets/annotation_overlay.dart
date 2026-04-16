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

  // Per-session overrides (live preview while the popup is open)
  double? _editFontSize;
  bool?   _editIsBold;
  bool?   _editIsItalic;
  int?    _editColorArgb;

  // ── Scale factor (screen pixels per PDF point) ────────────────────────────
  // Updated from the PdfViewerController every build.
  double _scale = 1.0;
  double _lastKnownWidth = 0.0;

  @override
  void initState() {
    super.initState();
    // Load blocks after the first frame so providers are ready.
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

  /// Compute scale from the cached page width.
  /// scale = current overlay widget width (px) / PDF page width (pts).
  /// The overlay fills the same width as PdfViewer in single-page mode.
  double _computeScaleFromCache(int pageNumber, double widgetWidth) {
    final pdfW = ref.read(pageWidthCacheProvider)[pageNumber];
    if (pdfW == null || pdfW <= 0) return _scale;
    final s = widgetWidth / pdfW;
    return s > 0 ? s : _scale;
  }

  Future<void> _loadBlocks() async {
    final doc = ref.read(currentDocumentProvider);
    if (doc == null) return;
    await ref
        .read(textBlockNotifierProvider.notifier)
        .load(doc.filePath, doc.currentPage);
    _updateScale();
  }

  void _updateScale([double? widgetWidth]) {
    final doc = ref.read(currentDocumentProvider);
    if (doc == null) return;
    final w = widgetWidth ?? _lastKnownWidth;
    if (w <= 0) return;
    final newScale = _computeScaleFromCache(doc.currentPage, w);
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

    // ── editText tool: only text blocks respond ───────────────────────────
    if (tool == EditorTool.editText) {
      final hit = _hitBlock(
          ref.read(textBlockNotifierProvider), d.localPosition);
      if (hit != null) _startBlockEdit(hit);
      return;
    }

    // ── select / default tool: click directly on a word to edit it ────────
    // If the tap lands on a PDF text block open the inline editor immediately
    // (just like clicking a word in Word).  Only do this when NO overlay
    // annotation was tapped — annotation interaction takes priority.
    if (tool == EditorTool.select) {
      final hitAnnot = _hitAnnotation(annotations, d.localPosition);
      if (hitAnnot != null) {
        // Tapped an overlay annotation — select it normally.
        ref.read(selectedAnnotationIdProvider.notifier).state = hitAnnot.id;
        return;
      }
      // No annotation hit — check for a PDF text block.
      final hitBlock = _hitBlock(
          ref.read(textBlockNotifierProvider), d.localPosition);
      if (hitBlock != null) {
        _startBlockEdit(hitBlock);
        return;
      }
      // Tapped empty space — deselect.
      ref.read(selectedAnnotationIdProvider.notifier).state = null;
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
      // Seed live-edit values from whatever is already stored on the block.
      _editFontSize   = block.effectiveFontSize;
      _editIsBold     = block.effectiveIsBold;
      _editIsItalic   = block.effectiveIsItalic;
      _editColorArgb  = block.effectiveColorArgb;
    });
    _blockFocus.requestFocus();
    ref.read(currentDocumentProvider.notifier).markModified();
  }

  void _commitBlockEdit() {
    if (_editingBlockId == null) return;
    final notifier = ref.read(textBlockNotifierProvider.notifier);
    notifier.updateBlock(_editingBlockId!, _blockCtrl.text);
    notifier.updateBlockFormatting(
      _editingBlockId!,
      fontSize:   _editFontSize,
      isBold:     _editIsBold,
      isItalic:   _editIsItalic,
      colorArgb:  _editColorArgb,
    );
    if (notifier.hasEdits) {
      ref.read(currentDocumentProvider.notifier).markModified();
    }
    setState(() {
      _editingBlockId = null;
      _editFontSize   = null;
      _editIsBold     = null;
      _editIsItalic   = null;
      _editColorArgb  = null;
    });
    _blockFocus.unfocus();
  }

  void _cancelBlockEdit() {
    setState(() {
      _editingBlockId = null;
      _editFontSize   = null;
      _editIsBold     = null;
      _editIsItalic   = null;
      _editColorArgb  = null;
    });
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

    // Reload blocks whenever the page changes (already handled by the
    // currentDocumentProvider listener above) OR when the editText tool
    // becomes active.  We ALSO keep blocks loaded in select mode so that
    // the user can click directly on any word without switching tools.
    ref.listen(selectedToolProvider, (prev, next) {
      if (next == EditorTool.editText && prev != EditorTool.editText) {
        _loadBlocks();
      }
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

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        if (w > 0 && w != _lastKnownWidth) {
          _lastKnownWidth = w;
          WidgetsBinding.instance.addPostFrameCallback((_) => _updateScale(w));
        }
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
              // ── Annotation canvas ────────────────────────────────────────
              // Must be BELOW block highlights so it doesn't intercept taps.
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
                // Use SizedBox.expand so the CustomPaint fills the area but
                // does NOT create an opaque hit-test target over the highlights.
                child: const SizedBox.expand(),
              ),

              // ── Text block highlight overlays ────────────────────────────
              // Shown in editText mode (bright outlines) AND select mode
              // (subtle dashed outlines so the user knows words are clickable).
              if (tool == EditorTool.editText || tool == EditorTool.select)
                ..._buildBlockHighlights(textBlocks, tool),

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
      },
    );
  }

  // ── Text block highlights ─────────────────────────────────────────────────

  List<Widget> _buildBlockHighlights(
      List<PdfTextBlock> blocks, EditorTool tool) {
    final isEditMode = tool == EditorTool.editText;

    return blocks.map((b) {
      final editing  = b.id == _editingBlockId;
      final modified = b.isEdited;

      return Positioned.fromRect(
        rect: b.screenRect,
        child: MouseRegion(
          // Text cursor when hovering over any word
          cursor: SystemMouseCursors.text,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              _commitAnnotationEdit();
              _commitBlockEdit();
              _startBlockEdit(b);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              decoration: BoxDecoration(
                color: editing
                    ? Colors.blue.withValues(alpha: 0.18)
                    : modified
                        ? Colors.green.withValues(alpha: 0.10)
                        : isEditMode
                            // editText mode: visible blue tint
                            ? Colors.blue.withValues(alpha: 0.04)
                            // select mode: nearly invisible, just enough for hover
                            : Colors.transparent,
                border: Border.all(
                  color: editing
                      ? Colors.blue.withValues(alpha: 0.90)
                      : modified
                          ? Colors.green.withValues(alpha: 0.70)
                          : isEditMode
                              ? Colors.blue.withValues(alpha: 0.28)
                              // select mode: very faint dashed-look via low alpha
                              : Colors.blue.withValues(alpha: 0.08),
                  width: editing ? 2.0 : (isEditMode ? 1.0 : 0.5),
                ),
                borderRadius: BorderRadius.circular(2),
              ),
              child: modified && !editing
                  ? Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: Text(
                          b.editedText,
                          maxLines:  1,
                          overflow:  TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize:   (b.effectiveFontSize * _scale)
                                .clamp(8.0, 36.0),
                            fontWeight: b.effectiveIsBold
                                ? FontWeight.bold
                                : FontWeight.normal,
                            fontStyle:  b.effectiveIsItalic
                                ? FontStyle.italic
                                : FontStyle.normal,
                            color: Color(b.effectiveColorArgb),
                          ),
                        ),
                      ),
                    )
                  : null,
            ),
          ),
        ),
      );
    }).toList();
  }

  // ── Block editor (Word-style in-place editor) ─────────────────────────────

  Widget _buildBlockEditor(List<PdfTextBlock> blocks) {
    PdfTextBlock? block;
    try {
      block = blocks.firstWhere((b) => b.id == _editingBlockId);
    } catch (_) {
      return const SizedBox.shrink();
    }

    // Live values (fall back to block's effective values if not yet set)
    final liveFontSize  = _editFontSize   ?? block.effectiveFontSize;
    final liveIsBold    = _editIsBold     ?? block.effectiveIsBold;
    final liveIsItalic  = _editIsItalic   ?? block.effectiveIsItalic;
    final liveColor     = Color(_editColorArgb ?? block.effectiveColorArgb);

    // ── Position the popup directly over the text block ──────────────────
    // Give enough room for the two-row toolbar (≈68 px) above the block.
    const toolbarH = 68.0;
    const minEditorW = 240.0;

    final blockW   = block.screenRect.width.clamp(minEditorW, 680.0);
    final blockH   = block.screenRect.height.clamp(28.0, 200.0);
    final rawLeft  = block.screenRect.left;
    final rawTop   = block.screenRect.top - toolbarH;

    // Keep within overlay bounds (clamped lazily; LayoutBuilder gives maxWidth)
    final left = rawLeft.clamp(0.0, double.infinity);
    final top  = rawTop .clamp(0.0, double.infinity);

    return Positioned(
      left:  left,
      top:   top,
      width: blockW,
      child: Material(
        elevation: 12,
        borderRadius: BorderRadius.circular(6),
        color: Colors.white,
        shadowColor: Colors.black38,
        child: Column(
          mainAxisSize:       MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [

            // ── Row 1: title + Done/Cancel ─────────────────────────────────
            Container(
              height:  32,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: const BoxDecoration(
                color: Color(0xFF1565C0),
                borderRadius: BorderRadius.vertical(top: Radius.circular(6)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.edit_document, size: 13, color: Colors.white70),
                  const SizedBox(width: 6),
                  const Expanded(
                    child: Text(
                      'Edit PDF Text',
                      style: TextStyle(
                        fontSize:   11,
                        color:      Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  // Find & Replace button
                  _miniIconBtn(Icons.find_replace_rounded, 'Find & Replace',
                      () => _showFindReplace(context)),
                  const SizedBox(width: 4),
                  _miniBtn('Done',   Colors.white,   _commitBlockEdit),
                  const SizedBox(width: 4),
                  _miniBtn('Cancel', Colors.white60, _cancelBlockEdit),
                ],
              ),
            ),

            // ── Row 2: formatting toolbar ──────────────────────────────────
            Container(
              height:  36,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              color:   const Color(0xFFF0F4FF),
              child: Row(
                children: [
                  // Font-size stepper
                  const Text('Size:', style: TextStyle(fontSize: 10, color: Colors.black54)),
                  const SizedBox(width: 4),
                  _sizeBtn(Icons.remove, () {
                    setState(() => _editFontSize = (liveFontSize - 1).clamp(6.0, 144.0));
                  }),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      liveFontSize.round().toString(),
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                  ),
                  _sizeBtn(Icons.add, () {
                    setState(() => _editFontSize = (liveFontSize + 1).clamp(6.0, 144.0));
                  }),

                  const SizedBox(width: 8),

                  // Bold
                  _fmtToggle(
                    label: 'B',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    isActive: liveIsBold,
                    onTap: () => setState(() => _editIsBold = !liveIsBold),
                  ),
                  const SizedBox(width: 2),
                  // Italic
                  _fmtToggle(
                    label: 'I',
                    style: const TextStyle(fontStyle: FontStyle.italic, fontSize: 13),
                    isActive: liveIsItalic,
                    onTap: () => setState(() => _editIsItalic = !liveIsItalic),
                  ),

                  const SizedBox(width: 8),

                  // Color swatch
                  Tooltip(
                    message: 'Text colour',
                    child: GestureDetector(
                      onTap: () => _pickBlockColor(context, liveColor),
                      child: Container(
                        width: 22, height: 22,
                        decoration: BoxDecoration(
                          color:  liveColor,
                          shape:  BoxShape.circle,
                          border: Border.all(color: Colors.black26, width: 1.5),
                        ),
                      ),
                    ),
                  ),

                  const Spacer(),

                  // Reset formatting
                  Tooltip(
                    message: 'Reset formatting',
                    child: GestureDetector(
                      onTap: () => setState(() {
                        _editFontSize  = block!.fontSize;
                        _editIsBold    = block.isBold;
                        _editIsItalic  = block.isItalic;
                        _editColorArgb = block.colorArgb;
                      }),
                      child: const Icon(Icons.format_clear_rounded,
                          size: 16, color: Colors.black45),
                    ),
                  ),
                ],
              ),
            ),

            // ── Inline text field (sits exactly over the PDF text block) ───
            SizedBox(
              height: blockH + 8,
              child: TextField(
                controller: _blockCtrl,
                focusNode:  _blockFocus,
                maxLines:   null,
                expands:    true,
                autofocus:  true,
                style: TextStyle(
                  fontSize:   (liveFontSize * _scale).clamp(9.0, 48.0),
                  fontWeight: liveIsBold   ? FontWeight.bold   : FontWeight.normal,
                  fontStyle:  liveIsItalic ? FontStyle.italic  : FontStyle.normal,
                  color:      liveColor,
                ),
                decoration: InputDecoration(
                  isDense:        true,
                  border:         const OutlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFF1565C0), width: 1.5),
                  ),
                  focusedBorder: const OutlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFF1565C0), width: 2),
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  hintText:  'Type replacement text…',
                  hintStyle: const TextStyle(fontSize: 11, color: Colors.black38),
                  // Show original text as a suffix hint
                  suffixIcon: block.editedText != block.originalText
                      ? Tooltip(
                          message: 'Original: "${block.originalText}"',
                          child: const Icon(Icons.history_rounded,
                              size: 14, color: Colors.black26),
                        )
                      : null,
                ),
                onSubmitted: (_) => _commitBlockEdit(),
              ),
            ),

            // ── Status bar ─────────────────────────────────────────────────
            Container(
              height:  18,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              color:   const Color(0xFFE8EEF8),
              child: Row(
                children: [
                  Text(
                    'Original: "${block.originalText}"',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize:  9,
                      color:     Colors.black45,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                  const Spacer(),
                  if (block.isEdited)
                    const Text('● edited',
                        style: TextStyle(
                          fontSize: 9,
                          color:    Color(0xFF388E3C),
                          fontWeight: FontWeight.w600,
                        )),
                ],
              ),
            ),

          ],
        ),
      ),
    );
  }

  // ── Formatting helper widgets ─────────────────────────────────────────────

  Widget _sizeBtn(IconData icon, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          width:  20, height: 20,
          decoration: BoxDecoration(
            color:        Colors.white,
            borderRadius: BorderRadius.circular(3),
            border:       Border.all(color: Colors.black12),
          ),
          child: Icon(icon, size: 12, color: Colors.black54),
        ),
      );

  Widget _fmtToggle({
    required String   label,
    required TextStyle style,
    required bool     isActive,
    required VoidCallback onTap,
  }) =>
      GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          width:   24, height: 24,
          decoration: BoxDecoration(
            color:        isActive
                ? const Color(0xFF1565C0).withValues(alpha: 0.15)
                : Colors.white,
            borderRadius: BorderRadius.circular(3),
            border:       Border.all(
              color: isActive
                  ? const Color(0xFF1565C0)
                  : Colors.black12,
            ),
          ),
          alignment: Alignment.center,
          child: Text(label, style: style.copyWith(fontSize: 12)),
        ),
      );

  Widget _miniIconBtn(IconData icon, String tooltip, VoidCallback onTap) =>
      Tooltip(
        message: tooltip,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding:    const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color:        Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Icon(icon, size: 13, color: Colors.white),
          ),
        ),
      );

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

  // ── Colour picker for block text ─────────────────────────────────────────

  void _pickBlockColor(BuildContext context, Color current) {
    // Use a simple color panel dialog (flutter_colorpicker is in dependencies)
    Color picked = current;
    showDialog<void>(
      context: context,
      builder: (_) {
        return StatefulBuilder(builder: (ctx, setDlg) {
          return AlertDialog(
            title: const Text('Text Colour', style: TextStyle(fontSize: 14)),
            contentPadding: const EdgeInsets.all(12),
            content: SizedBox(
              width: 280,
              child: Wrap(
                spacing: 8, runSpacing: 8,
                children: [
                  // Quick palette
                  for (final c in [
                    Colors.black,
                    Colors.white,
                    Colors.red,
                    Colors.blue,
                    Colors.green.shade700,
                    Colors.orange,
                    Colors.purple,
                    Colors.brown,
                    Colors.grey,
                    Colors.teal,
                    Colors.pink,
                    Colors.indigo,
                  ])
                    GestureDetector(
                      onTap: () => setDlg(() => picked = c),
                      child: Container(
                        width: 32, height: 32,
                        decoration: BoxDecoration(
                          color:  c,
                          shape:  BoxShape.circle,
                          border: Border.all(
                            color: picked == c
                                ? Colors.blue
                                : Colors.black12,
                            width: picked == c ? 3 : 1,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel')),
              FilledButton(
                onPressed: () {
                  // ignore: deprecated_member_use
                  setState(() => _editColorArgb = picked.value);
                  Navigator.pop(ctx);
                },
                child: const Text('Apply'),
              ),
            ],
          );
        });
      },
    );
  }

  // ── Find & Replace dialog ─────────────────────────────────────────────────

  void _showFindReplace(BuildContext context) {
    final findCtrl    = TextEditingController();
    final replaceCtrl = TextEditingController();
    bool caseSensitive = false;

    showDialog<void>(
      context: context,
      builder: (_) {
        return StatefulBuilder(builder: (ctx, setDlg) {
          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.find_replace_rounded, size: 18, color: Color(0xFF1565C0)),
                SizedBox(width: 8),
                Text('Find & Replace', style: TextStyle(fontSize: 15)),
              ],
            ),
            content: SizedBox(
              width: 340,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: findCtrl,
                    autofocus:  true,
                    decoration: const InputDecoration(
                      labelText:      'Find text',
                      prefixIcon:     Icon(Icons.search_rounded, size: 18),
                      border:         OutlineInputBorder(),
                      isDense:        true,
                      contentPadding: EdgeInsets.all(10),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: replaceCtrl,
                    decoration: const InputDecoration(
                      labelText:      'Replace with',
                      prefixIcon:     Icon(Icons.edit_rounded, size: 18),
                      border:         OutlineInputBorder(),
                      isDense:        true,
                      contentPadding: EdgeInsets.all(10),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Checkbox(
                        value:     caseSensitive,
                        onChanged: (v) => setDlg(() => caseSensitive = v!),
                        visualDensity: VisualDensity.compact,
                      ),
                      const Text('Case sensitive',
                          style: TextStyle(fontSize: 12)),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel')),
              FilledButton.icon(
                icon:  const Icon(Icons.find_replace_rounded, size: 16),
                label: const Text('Replace All'),
                onPressed: () {
                  final count = ref
                      .read(textBlockNotifierProvider.notifier)
                      .findAndReplace(
                        findCtrl.text,
                        replaceCtrl.text,
                        caseSensitive: caseSensitive,
                      );
                  Navigator.pop(ctx);
                  if (count > 0) {
                    ref.read(currentDocumentProvider.notifier).markModified();
                  }
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content:  Text(count > 0
                        ? 'Replaced $count block${count == 1 ? '' : 's'}.'
                        : 'No matches found.'),
                    behavior: SnackBarBehavior.floating,
                    duration: const Duration(seconds: 2),
                  ));
                },
              ),
            ],
          );
        });
      },
    );
  }

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
      for (final p in freehandPoints.skip(1)) { path.lineTo(p.dx, p.dy); }
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
