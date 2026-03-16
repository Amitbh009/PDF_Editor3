import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../models/pdf_document_model.dart';
import '../models/annotation_model.dart';
import '../services/pdf_service.dart';

const _uuid = Uuid();

// ─── Document provider ────────────────────────────────────────────────────
final currentDocumentProvider =
    StateNotifierProvider<DocumentNotifier, PdfDocumentModel?>(
  (ref) => DocumentNotifier(ref.watch(pdfServiceProvider)),
);

// ─── Tool enum ────────────────────────────────────────────────────────────
enum EditorTool {
  select, text, highlight, underline, strikethrough,
  freehand, rectangle, circle, arrow, eraser,
}

// ─── Style / tool providers ───────────────────────────────────────────────
final selectedToolProvider =
    StateProvider<EditorTool>((ref) => EditorTool.select);
final selectedColorProvider = StateProvider<int>((ref) => 0xFFFF0000);
final strokeWidthProvider   = StateProvider<double>((ref) => 2.0);
final fontSizeProvider      = StateProvider<double>((ref) => 14.0);
final opacityProvider       = StateProvider<double>((ref) => 1.0);
final zoomLevelProvider     = StateProvider<double>((ref) => 1.0);
final isBoldProvider        = StateProvider<bool>((ref) => false);
final isItalicProvider      = StateProvider<bool>((ref) => false);

// ─── Undo / redo ──────────────────────────────────────────────────────────
final undoStackProvider =
    StateProvider<List<List<AnnotationModel>>>((ref) => []);
final redoStackProvider =
    StateProvider<List<List<AnnotationModel>>>((ref) => []);

// ─── Notifier ─────────────────────────────────────────────────────────────
class DocumentNotifier extends StateNotifier<PdfDocumentModel?> {
  final PdfService _pdfService;
  DocumentNotifier(this._pdfService) : super(null);

  Future<void> openDocument(String filePath) async {
    final pageCount = await _pdfService.getPageCount(filePath);
    state = PdfDocumentModel(
      id: _uuid.v4(),
      filePath: filePath,
      fileName: filePath.split(Platform.pathSeparator).last,
      totalPages: pageCount,
      lastModified: DateTime.now(),
    );
  }

  void addAnnotation(AnnotationModel annotation) {
    if (state == null) return;
    state = state!.copyWith(
      annotations: [...state!.annotations, annotation],
      isModified: true,
      lastModified: DateTime.now(),
    );
  }

  void updateAnnotation(AnnotationModel annotation) {
    if (state == null) return;
    state = state!.copyWith(
      annotations: state!.annotations
          .map((a) => a.id == annotation.id ? annotation : a)
          .toList(),
      isModified: true,
    );
  }

  void deleteAnnotation(String id) {
    if (state == null) return;
    state = state!.copyWith(
      annotations: state!.annotations.where((a) => a.id != id).toList(),
      isModified: true,
    );
  }

  /// Deletes all annotations across the whole document.
  void deleteAllAnnotations() {
    if (state == null) return;
    state = state!.copyWith(annotations: [], isModified: true);
  }

  /// Deletes all annotations on one specific page.
  void deleteAllOnPage(int page) {
    if (state == null) return;
    state = state!.copyWith(
      annotations:
          state!.annotations.where((a) => a.pageNumber != page).toList(),
      isModified: true,
    );
  }

  void setPage(int page) {
    if (state == null) return;
    state = state!.copyWith(currentPage: page);
  }

  Future<String> saveDocument(String outputPath) async {
    if (state == null) throw Exception('No document open');
    await _pdfService.saveWithAnnotations(
      state!.filePath,
      state!.annotations,
      outputPath,
    );
    state = state!.copyWith(isModified: false);
    return outputPath;
  }

  void closeDocument() => state = null;
}
