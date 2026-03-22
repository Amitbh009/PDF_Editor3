import 'dart:io';
import 'dart:ui' show Offset;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/annotation_model.dart';
import '../models/pdf_document_model.dart';
import '../models/pdf_text_block.dart';
import '../services/pdf_service.dart';

const _uuid = Uuid();

// ─── Document provider ────────────────────────────────────────────────────────

final currentDocumentProvider =
    StateNotifierProvider<DocumentNotifier, PdfDocumentModel?>(
  (ref) => DocumentNotifier(ref.watch(pdfServiceProvider)),
);

// ─── Tool enum ────────────────────────────────────────────────────────────────

enum EditorTool {
  select,
  editText,       // ← Click existing PDF text to edit Word-style (PDFium-backed)
  text,           // Add new text annotation
  highlight,
  underline,
  strikethrough,
  freehand,
  rectangle,
  circle,
  arrow,
  eraser,
}

// ─── Style providers ──────────────────────────────────────────────────────────

final selectedToolProvider =
    StateProvider<EditorTool>((ref) => EditorTool.select);
final selectedColorProvider  = StateProvider<int>((ref) => 0xFF000000);
final strokeWidthProvider    = StateProvider<double>((ref) => 2.0);
final fontSizeProvider       = StateProvider<double>((ref) => 14.0);
final opacityProvider        = StateProvider<double>((ref) => 1.0);
final zoomLevelProvider      = StateProvider<double>((ref) => 1.0);
final isBoldProvider         = StateProvider<bool>((ref) => false);
final isItalicProvider       = StateProvider<bool>((ref) => false);
final selectedAnnotationIdProvider = StateProvider<String?>((ref) => null);

// ─── Page size cache (PDF points) ────────────────────────────────────────────
// Populated by EditorScreen once onDocumentLoaded fires, giving us the true
// PDFium page dimensions for exact coordinate conversion.

final pageWidthCacheProvider  = StateProvider<Map<int, double>>((ref) => {});
final pageHeightCacheProvider = StateProvider<Map<int, double>>((ref) => {});

// ─── Text-block state (PDFium-extracted) ──────────────────────────────────────

final textBlockNotifierProvider =
    StateNotifierProvider<TextBlockNotifier, List<PdfTextBlock>>(
  (ref) => TextBlockNotifier(ref.watch(pdfServiceProvider)),
);

class TextBlockNotifier extends StateNotifier<List<PdfTextBlock>> {
  TextBlockNotifier(this._service) : super([]);

  final PdfService _service;

  /// Extract text blocks for [page] from [filePath] via PDFium.
  Future<void> load(String filePath, int page) async {
    final blocks = await _service.extractTextBlocks(filePath, page);
    state = blocks;
  }

  /// Recalculate screen-space rects when the viewer zoom changes.
  /// [scale] = screen pixels per PDF point.
  void applyScale(double scale) {
    if (scale <= 0) return;
    state = state.map((b) => b.withScreenRect(
          b.pdfRect.scale(scale, scale),
        )).toList();
  }

  /// Commit an in-place text edit.
  void updateBlock(String id, String newText) {
    state = state.map((b) {
      if (b.id != id) return b;
      b.editedText = newText;
      b.isEdited   = newText != b.originalText;
      return b;
    }).toList();
    // Notify Riverpod that the list changed
    state = List.from(state);
  }

  void clear() => state = [];

  List<PdfTextBlock> get editedBlocks =>
      state.where((b) => b.isEdited).toList();

  bool get hasEdits => state.any((b) => b.isEdited);
}

// ─── Undo/redo availability ───────────────────────────────────────────────────

final canUndoProvider = Provider<bool>((ref) {
  final notifier = ref.watch(currentDocumentProvider.notifier);
  ref.watch(currentDocumentProvider);
  return notifier.canUndo;
});

final canRedoProvider = Provider<bool>((ref) {
  final notifier = ref.watch(currentDocumentProvider.notifier);
  ref.watch(currentDocumentProvider);
  return notifier.canRedo;
});

// ─── Document notifier ────────────────────────────────────────────────────────

class DocumentNotifier extends StateNotifier<PdfDocumentModel?> {
  DocumentNotifier(this._pdfService) : super(null);

  final PdfService _pdfService;

  final List<List<AnnotationModel>> _undoStack = [];
  final List<List<AnnotationModel>> _redoStack = [];

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  void _snapshot() {
    if (state == null) return;
    _undoStack.add(List<AnnotationModel>.from(state!.annotations));
    _redoStack.clear();
  }

  void undo() {
    if (state == null || _undoStack.isEmpty) return;
    _redoStack.add(List<AnnotationModel>.from(state!.annotations));
    state = state!.copyWith(
      annotations:  List<AnnotationModel>.from(_undoStack.removeLast()),
      isModified:   true,
      lastModified: DateTime.now(),
    );
  }

  void redo() {
    if (state == null || _redoStack.isEmpty) return;
    _undoStack.add(List<AnnotationModel>.from(state!.annotations));
    state = state!.copyWith(
      annotations:  List<AnnotationModel>.from(_redoStack.removeLast()),
      isModified:   true,
      lastModified: DateTime.now(),
    );
  }

  Future<void> openDocument(String filePath) async {
    _undoStack.clear();
    _redoStack.clear();
    final pageCount = await _pdfService.getPageCount(filePath);
    state = PdfDocumentModel(
      id:           _uuid.v4(),
      filePath:     filePath,
      fileName:     filePath.split(Platform.pathSeparator).last,
      totalPages:   pageCount,
      lastModified: DateTime.now(),
    );
  }

  void addAnnotation(AnnotationModel annotation) {
    if (state == null) return;
    _snapshot();
    state = state!.copyWith(
      annotations:  [...state!.annotations, annotation],
      isModified:   true,
      lastModified: DateTime.now(),
    );
  }

  void updateAnnotation(AnnotationModel annotation) {
    if (state == null) return;
    _snapshot();
    state = state!.copyWith(
      annotations: state!.annotations
          .map((a) => a.id == annotation.id ? annotation : a)
          .toList(),
      isModified:   true,
      lastModified: DateTime.now(),
    );
  }

  void deleteAnnotation(String id) {
    if (state == null) return;
    _snapshot();
    state = state!.copyWith(
      annotations:  state!.annotations.where((a) => a.id != id).toList(),
      isModified:   true,
      lastModified: DateTime.now(),
    );
  }

  void deleteAllAnnotations() {
    if (state == null) return;
    _snapshot();
    state = state!.copyWith(annotations: [], isModified: true);
  }

  void deleteAllOnPage(int page) {
    if (state == null) return;
    _snapshot();
    state = state!.copyWith(
      annotations: state!.annotations
          .where((a) => a.pageNumber != page)
          .toList(),
      isModified: true,
    );
  }

  void setPage(int page) {
    if (state == null) return;
    state = state!.copyWith(currentPage: page);
  }

  void markModified() {
    if (state == null) return;
    state = state!.copyWith(isModified: true, lastModified: DateTime.now());
  }

  void moveAnnotationLive(String id, Offset delta) {
    if (state == null) return;
    state = state!.copyWith(
      annotations: state!.annotations.map((a) {
        if (a.id != id) return a;
        return a.copyWith(x: a.x + delta.dx, y: a.y + delta.dy);
      }).toList(),
      isModified: true,
    );
  }

  void snapshotForDrag() => _snapshot();

  Future<String> saveDocument(
    String outputPath, {
    List<PdfTextBlock> editedTextBlocks = const [],
    Map<int, double>   pageHeights      = const {},
  }) async {
    if (state == null) throw Exception('No document open');
    await _pdfService.saveWithAnnotations(
      state!.filePath,
      state!.annotations,
      outputPath,
      editedTextBlocks: editedTextBlocks,
      pageHeights:      pageHeights,
    );
    state = state!.copyWith(isModified: false);
    return outputPath;
  }

  void closeDocument() {
    _undoStack.clear();
    _redoStack.clear();
    state = null;
  }
}
