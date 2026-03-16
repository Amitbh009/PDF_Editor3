import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;

import '../models/annotation_model.dart';

final pdfServiceProvider = Provider<PdfService>((ref) => PdfService());

class PdfService {
  // ── Public API ─────────────────────────────────────────────────────────────

  /// Returns the total page count of a PDF file.
  Future<int> getPageCount(String filePath) async {
    final bytes = await File(filePath).readAsBytes();
    final doc = sf.PdfDocument(inputBytes: bytes);
    final count = doc.pages.count;
    doc.dispose();
    return count;
  }

  /// Saves the PDF with all annotations burned in to [outputPath].
  Future<void> saveWithAnnotations(
    String sourcePath,
    List<AnnotationModel> annotations,
    String outputPath,
  ) async {
    final bytes = await File(sourcePath).readAsBytes();
    final doc = sf.PdfDocument(inputBytes: bytes);

    for (final a in annotations) {
      if (a.pageNumber < 1 || a.pageNumber > doc.pages.count) continue;
      final page = doc.pages[a.pageNumber - 1];

      switch (a.type) {
        case AnnotationType.text:
          _addText(page, a);
        case AnnotationType.highlight:
          _addHighlight(page, a);
        case AnnotationType.underline:
          _addUnderline(page, a);
        case AnnotationType.strikethrough:
          _addStrikethrough(page, a);
        case AnnotationType.freehand:
          _addFreehand(page, a);
        case AnnotationType.rectangle:
          _addRectangle(page, a);
        case AnnotationType.circle:
          _addCircle(page, a);
        default:
          break;
      }
    }

    final savedBytes = await doc.save();
    await File(outputPath).writeAsBytes(savedBytes);
    doc.dispose();
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  /// Converts ARGB int → Syncfusion PdfColor, with optional opacity override.
  sf.PdfColor _sfColor(int argb, {double? opacity}) {
    final a = opacity != null
        ? (opacity * 255).round()
        : (argb >> 24) & 0xFF;
    return sf.PdfColor(
      (argb >> 16) & 0xFF,
      (argb >> 8) & 0xFF,
      argb & 0xFF,
      a,
    );
  }

  /// Builds a Syncfusion Rect from annotation bounds.
  sf.Rect _sfRect(AnnotationModel a) =>
      sf.Rect.fromLTWH(a.x, a.y, a.width, a.height);

  // ── Writers ────────────────────────────────────────────────────────────────

  void _addText(sf.PdfPage page, AnnotationModel a) {
    final style = a.isBold
        ? sf.PdfFontStyle.bold
        : a.isItalic
            ? sf.PdfFontStyle.italic
            : sf.PdfFontStyle.regular;

    final font = sf.PdfStandardFont(
      sf.PdfFontFamily.helvetica,
      a.fontSize,
      style: style,
    );

    page.graphics.drawString(
      a.content,
      font,
      brush: sf.PdfSolidBrush(_sfColor(a.color)),
      bounds: _sfRect(a),
    );
  }

  void _addHighlight(sf.PdfPage page, AnnotationModel a) {
    final annot = sf.PdfTextMarkupAnnotation(
      _sfRect(a),
      a.content.isEmpty ? 'Highlight' : a.content,
      _sfColor(a.color, opacity: 0.4),
      textMarkupAnnotationType: sf.PdfTextMarkupAnnotationType.highlight,
    );
    page.annotations.add(annot);
  }

  void _addUnderline(sf.PdfPage page, AnnotationModel a) {
    final annot = sf.PdfTextMarkupAnnotation(
      _sfRect(a),
      a.content.isEmpty ? 'Underline' : a.content,
      _sfColor(a.color),
      textMarkupAnnotationType: sf.PdfTextMarkupAnnotationType.underline,
    );
    page.annotations.add(annot);
  }

  void _addStrikethrough(sf.PdfPage page, AnnotationModel a) {
    final annot = sf.PdfTextMarkupAnnotation(
      _sfRect(a),
      a.content.isEmpty ? 'Strikethrough' : a.content,
      _sfColor(a.color),
      textMarkupAnnotationType:
          sf.PdfTextMarkupAnnotationType.strikethrough,
    );
    page.annotations.add(annot);
  }

  void _addFreehand(sf.PdfPage page, AnnotationModel a) {
    if (a.pathPoints == null || a.pathPoints!.length < 2) return;
    final pen = sf.PdfPen(_sfColor(a.color), width: a.strokeWidth);
    pen.lineCap = sf.PdfLineCap.round;
    final pts = a.pathPoints!;
    for (int i = 0; i < pts.length - 1; i++) {
      page.graphics.drawLine(
        pen,
        sf.Offset(pts[i]['x']!, pts[i]['y']!),
        sf.Offset(pts[i + 1]['x']!, pts[i + 1]['y']!),
      );
    }
  }

  void _addRectangle(sf.PdfPage page, AnnotationModel a) {
    final annot = sf.PdfRectangleAnnotation(
      _sfRect(a),
      a.content.isEmpty ? 'Rectangle' : a.content,
    );
    annot.color = _sfColor(a.color);
    annot.innerColor = sf.PdfColor(0, 0, 0, 0);
    annot.border.width = a.strokeWidth.toInt().toDouble();
    page.annotations.add(annot);
  }

  void _addCircle(sf.PdfPage page, AnnotationModel a) {
    final annot = sf.PdfEllipseAnnotation(
      _sfRect(a),
      a.content.isEmpty ? 'Circle' : a.content,
    );
    annot.color = _sfColor(a.color);
    annot.innerColor = sf.PdfColor(0, 0, 0, 0);
    annot.border.width = a.strokeWidth.toInt().toDouble();
    page.annotations.add(annot);
  }
}
