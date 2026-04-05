import 'dart:io';
import 'dart:ui' show Offset, Rect;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/annotation_model.dart';
import '../models/pdf_document_model.dart';
import '../models/pdf_text_block.dart';
import '../services/pdf_service.dart';

const _uuid = Uuid();

// ── Document provider ─────────────────────────────────────────────────────────
final currentDocumentProvider =
    StateNotifierProvider<DocumentNotifier, PdfDocumentModel?>(
  (ref) => DocumentNotifier(ref.watch(pdfServiceProvider)),
);

// ── Tool enum ─────────────────────────────────────────────────────────────────
enum EditorTool {
  select,
  editText,       // click existing PDF text to edit Word-style
  text,           // add new text overlay annotation
  highlight,
  underline,
  strikethrough,
  freehand,
  rectangle,
  circle,
  arrow,
  eraser,
}

// ── Style providers ───────────────────────────────────────────────────────────
final selectedToolProvider     = StateProvider<EditorTool>((ref) => EditorTool.select);
final selectedColorProvider    = StateProvider<int>((ref) => 0xFFFF0000);
final strokeWidthProvider      = StateProvider<double>((ref) => 2.0);
final fontSizeProvider         = StateProvider<double>((ref) => 14.0);
final opacityProvider          = StateProvider<double>((ref) => 1.0);
final zoomLevelProvider        = StateProvider<double>((ref) => 1.0);
final isBoldProvider           = StateProvider<bool>((ref) => false);
final isItalicProvider         = StateProvider<bool>((ref) => false);
final selectedAnnotationIdProvider = StateProvider<String?>((ref) => null);

// ── Page-size cache (PDF points) ──────────────────────────────────────────────
// Populated by EditorScreen once the document loads via PdfViewerParams.
// Used for exact Y-axis flipping on save and exact scale calculation.
final pageWidthCacheProvider  = StateProvider<Map<int, double>>((ref) => {});
final pageHeightCacheProvider = StateProvider<Map<int, double>>((ref) => {});

// ── Text-block state ──────────────────────────────────────────────────────────
final textBlockNotifierProvider =
    StateNotifierProvider<TextBlockNotifier, List<PdfTextBlock>>(
  (ref) => TextBlockNotifier(ref.watch(pdfServiceProvider)),
);

class TextBlockNotifier extends StateNotifier<List<PdfTextBlock>> {
  TextBlockNotifier(this._service) : super([]);

  final PdfService _service;

  Future<void> load(String filePath, int page) async {
    state = await _service.extractTextBlocks(filePath, page);
  }

  /// Apply viewer scale (screen-px per PDF-pt) to all blocks.
  void applyScale(double scale) {
    if (scale <= 0) return;
    state = state.map((b) => b.withScreenRect(
          Rect.fromLTWH(
            b.pdfLeft   * scale,
            b.pdfTop    * scale,
            b.pdfWidth  * scale,
            b.pdfHeight * scale,
          ),
        )).toList();
  }

  void updateBlock(String id, String newText) {
    state = state.map((b) {
      if (b.id != id) return b;
      b.editedText = newText;
      b.isEdited   = newText != b.originalText ||
                     b.overrideFontSize  != null ||
                     b.overrideIsBold    != null ||
                     b.overrideIsItalic  != null ||
                     b.overrideColorArgb != null;
      return b;
    }).toList();
    state = List.from(state);
  }

  void updateBlockFormatting(
    String id, {
    double? fontSize,
    bool?   isBold,
    bool?   isItalic,
    int?    colorArgb,
  }) {
    state = state.map((b) {
      if (b.id != id) return b;
      if (fontSize  != null) b.overrideFontSize   = fontSize;
      if (isBold    != null) b.overrideIsBold      = isBold;
      if (isItalic  != null) b.overrideIsItalic    = isItalic;
      if (colorArgb != null) b.overrideColorArgb   = colorArgb;
      b.isEdited = true;
      return b;
    }).toList();
    state = List.from(state);
  }

  /// Find and replace across all loaded blocks on the current page.
  int findAndReplace(String find, String replace, {bool caseSensitive = false}) {
    if (find.isEmpty) return 0;
    int count = 0;
    state = state.map((b) {
      final source  = caseSensitive ? b.editedText : b.editedText.toLowerCase();
      final pattern = caseSensitive ? find          : find.toLowerCase();
      if (!source.contains(pattern)) return b;
      final replaced = caseSensitive
          ? b.editedText.replaceAll(find, replace)
          : b.editedText.replaceAllMapped(
              RegExp(RegExp.escape(find), caseSensitive: false),
              (_) => replace);
      b.editedText = replaced;
      b.isEdited   = replaced != b.originalText;
      count++;
      return b;
    }).toList();
    state = List.from(state);
    return count;
  }

  void clear() => state = [];

  List<PdfTextBlock> get editedBlocks => state.where((b) => b.isEdited).toList();
  bool               get hasEdits      => state.any((b) => b.isEdited);
}

// ── Undo / redo ───────────────────────────────────────────────────────────────
final canUndoProvider = Provider<bool>((ref) {
  ref.watch(currentDocumentProvider);
  return ref.watch(currentDocumentProvider.notifier).canUndo;
});

final canRedoProvider = Provider<bool>((ref) {
  ref.watch(currentDocumentProvider);
  return ref.watch(currentDocumentProvider.notifier).canRedo;
});

// ── Document notifier ─────────────────────────────────────────────────────────
class DocumentNotifier extends StateNotifier<PdfDocumentModel?> {
  DocumentNotifier(this._pdfService) : super(null);

  final PdfService _pdfService;
  final _undoStack = <List<AnnotationModel>>[];
  final _redoStack = <List<AnnotationModel>>[];

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  void _snapshot() {
    if (state == null) return;
    _undoStack.add(List.from(state!.annotations));
    _redoStack.clear();
  }

  void undo() {
    if (state == null || _undoStack.isEmpty) return;
    _redoStack.add(List.from(state!.annotations));
    state = state!.copyWith(
      annotations:  List.from(_undoStack.removeLast()),
      isModified:   true,
      lastModified: DateTime.now(),
    );
  }

  void redo() {
    if (state == null || _redoStack.isEmpty) return;
    _undoStack.add(List.from(state!.annotations));
    state = state!.copyWith(
      annotations:  List.from(_redoStack.removeLast()),
      isModified:   true,
      lastModified: DateTime.now(),
    );
  }

  Future<void> openDocument(String filePath) async {
    _undoStack.clear();
    _redoStack.clear();
    final count = await _pdfService.getPageCount(filePath);
    state = PdfDocumentModel(
      id:           _uuid.v4(),
      filePath:     filePath,
      fileName:     filePath.split(Platform.pathSeparator).last,
      totalPages:   count,
      lastModified: DateTime.now(),
    );
  }

  void addAnnotation(AnnotationModel a) {
    if (state == null) return;
    _snapshot();
    state = state!.copyWith(
      annotations:  [...state!.annotations, a],
      isModified:   true,
      lastModified: DateTime.now(),
    );
  }

  void updateAnnotation(AnnotationModel a) {
    if (state == null) return;
    _snapshot();
    state = state!.copyWith(
      annotations: state!.annotations.map((x) => x.id == a.id ? a : x).toList(),
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

  void deleteAllOnPage(int page) {
    if (state == null) return;
    _snapshot();
    state = state!.copyWith(
      annotations: state!.annotations.where((a) => a.pageNumber != page).toList(),
      isModified:  true,
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
