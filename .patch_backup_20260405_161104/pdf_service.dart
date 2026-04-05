import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;
import 'package:uuid/uuid.dart';

import '../models/annotation_model.dart';
import '../models/pdf_text_block.dart';

final pdfServiceProvider = Provider<PdfService>((ref) => PdfService());

const _uuid = Uuid();

/// All PDF I/O goes through this service.
///
/// Architecture:
///   READ  / VIEW  — pdfrx (PDFium):  PdfDocument.openFile, loadStructuredText
///   WRITE / SAVE  — syncfusion_flutter_pdf: PdfDocument(inputBytes), page.graphics
///
/// Why two libraries?
///   pdfrx provides best-in-class text extraction with glyph-level bounds
///   and PDFium-powered rendering.  It does NOT expose a write/annotation API
///   from Dart.  Syncfusion covers the write side.
class PdfService {
  // ── Page info ───────────────────────────────────────────────────────────────

  Future<int> getPageCount(String filePath) async {
    final doc   = await PdfDocument.openFile(filePath);
    final count = doc.pages.length;
    await doc.dispose();
    return count;
  }

  Future<({double width, double height})> getPageSize(
      String filePath, int pageNumber) async {
    final doc  = await PdfDocument.openFile(filePath);
    final idx  = (pageNumber - 1).clamp(0, doc.pages.length - 1);
    final page = doc.pages[idx];
    final size = (width: page.width, height: page.height);
    await doc.dispose();
    return size;
  }

  // ── Text extraction (pdfrx / PDFium) ────────────────────────────────────────

  /// Extract all text fragments from [pageNumber] (1-based) using PDFium.
  ///
  /// Uses [PdfPage.loadStructuredText] which returns [PdfPageText] whose
  /// [fragments] list carries glyph-level bounding boxes.
  ///
  /// [PdfPageTextFragment.bounds] is a [PdfRect] — PDF-native coords with
  /// bottom-left origin, Y grows UP (top > bottom). Converted to Flutter space
  /// (top-left origin, Y grows down) before storing in [PdfTextBlock].
  Future<List<PdfTextBlock>> extractTextBlocks(
    String filePath,
    int    pageNumber,
  ) async {
    final doc = await PdfDocument.openFile(filePath);
    if (pageNumber < 1 || pageNumber > doc.pages.length) {
      await doc.dispose();
      return [];
    }

    final page     = doc.pages[pageNumber - 1];
    final pageText = await page.loadStructuredText();
    final frags    = pageText.fragments
        .where((f) => f.text.trim().isNotEmpty)
        .toList();

    // ── Coordinate system note ───────────────────────────────────────────────
    // pdfrx PdfRect uses PDF native coords: bottom-left origin, Y grows UP.
    //   frag.bounds.top    = LARGER  Y = visually HIGH on page
    //   frag.bounds.bottom = SMALLER Y = visually LOW on page
    //
    // We convert immediately to Flutter space (top-left origin, Y grows DOWN):
    //   flutterTop    = pageHeight - pdfNativeTop
    //   flutterBottom = pageHeight - pdfNativeBottom
    //
    // All stored pdfLeft/pdfTop/pdfRight/pdfBottom values are already in
    // Flutter space, so applyScale multiplies directly, and saveWithAnnotations
    // converts back to PDF native with:  pdfNativeTop = pageH - flutterTop
    final pageH = page.height;

    // Group fragments into visual lines by Y-midpoint proximity (Flutter space).
    final lines = <List<PdfPageTextFragment>>[];
    for (final frag in frags) {
      final ftTop    = pageH - frag.bounds.top;    // flutter Y (smaller = higher)
      final ftBottom = pageH - frag.bounds.bottom; // flutter Y (larger  = lower)
      final midY     = (ftTop + ftBottom) / 2.0;
      final lineH    = (ftBottom - ftTop).abs();
      final thresh   = (lineH * 0.6).clamp(2.0, 20.0);
      bool placed    = false;
      for (final line in lines) {
        final rftTop    = pageH - line.first.bounds.top;
        final rftBottom = pageH - line.first.bounds.bottom;
        final refMid    = (rftTop + rftBottom) / 2.0;
        if ((midY - refMid).abs() <= thresh) {
          line.add(frag);
          placed = true;
          break;
        }
      }
      if (!placed) lines.add([frag]);
    }

    // Sort top-to-bottom (ascending Flutter Y); left-to-right within each line.
    lines.sort((a, b) {
      final aFtTop = pageH - a.first.bounds.top;
      final bFtTop = pageH - b.first.bounds.top;
      return aFtTop.compareTo(bFtTop);
    });
    for (final l in lines) {
      l.sort((a, b) => a.bounds.left.compareTo(b.bounds.left));
    }

    final blocks = <PdfTextBlock>[];
    for (final line in lines) {
      if (line.isEmpty) continue;
      final text = line.map((f) => f.text).join('');
      if (text.trim().isEmpty) continue;

      final left  = line.map((f) => f.bounds.left ).reduce((a, b) => a < b ? a : b);
      final right = line.map((f) => f.bounds.right).reduce((a, b) => a > b ? a : b);
      // PDF native: top > bottom.  Pick widest spanning native coords.
      final pdfNativeTop    = line.map((f) => f.bounds.top   ).reduce((a, b) => a > b ? a : b);
      final pdfNativeBottom = line.map((f) => f.bounds.bottom).reduce((a, b) => a < b ? a : b);
      // Convert to Flutter Y space.
      final ftTop    = pageH - pdfNativeTop;
      final ftBottom = pageH - pdfNativeBottom;

      final lineH    = (ftBottom - ftTop).clamp(4.0, double.infinity);
      final fontSize = (lineH * 0.75).clamp(4.0, 144.0);

      blocks.add(PdfTextBlock(
        id:           _uuid.v4(),
        pageNumber:   pageNumber,
        originalText: text,
        editedText:   text,
        // All coords stored in Flutter space (top-left origin, Y grows down).
        pdfLeft:      left,
        pdfTop:       ftTop,
        pdfRight:     right,
        pdfBottom:    ftBottom,
        screenRect:   ui.Rect.fromLTRB(left, ftTop, right, ftBottom),
        fontSize:     fontSize,
        fontName:     'Helvetica',
        isBold:       false,
        isItalic:     false,
        colorArgb:    0xFF000000,
      ));
    }

    await doc.dispose();
    return blocks;
  }

  // ── Save (Syncfusion write path) ─────────────────────────────────────────────

  /// Save the PDF with:
  ///   1. Edited text blocks replaced (erase original → draw replacement).
  ///   2. New overlay annotations burned in.
  ///
  /// [pageHeights] maps 1-based page number → PDF page height in points.
  /// Syncfusion page.graphics uses top-left origin (Y grows DOWN), matching
  /// Flutter's coordinate space — no Y-flip needed for text blocks or overlays.
  Future<void> saveWithAnnotations(
    String sourcePath,
    List<AnnotationModel> annotations,
    String outputPath, {
    List<PdfTextBlock> editedTextBlocks = const [],
    Map<int, double>   pageHeights      = const {},
  }) async {
    final bytes = await File(sourcePath).readAsBytes();
    final doc   = sf.PdfDocument(inputBytes: bytes);

    // ── 1. Replace edited text ──────────────────────────────────────────────
    for (final block in editedTextBlocks.where((b) => b.isEdited)) {
      final pageIdx = block.pageNumber - 1;
      if (pageIdx < 0 || pageIdx >= doc.pages.count) continue;

      final page  = doc.pages[pageIdx];

      // pdfLeft/pdfTop/pdfRight/pdfBottom are stored in Flutter space
      // (top-left origin, Y grows DOWN) by extractTextBlocks.
      // Syncfusion page.graphics also uses top-left origin — use directly.
      final sfRect = ui.Rect.fromLTWH(
          block.pdfLeft, block.pdfTop, block.pdfWidth, block.pdfHeight);

      // (a) Erase — white rectangle over original text.
      page.graphics.drawRectangle(
        brush:  sf.PdfSolidBrush(sf.PdfColor(255, 255, 255)),
        bounds: sfRect,
      );

      // (b) Redraw replacement text.
      if (block.editedText.trim().isNotEmpty) {
        final fontFamily = _matchFont(block.fontName);
        final font = _makeFont(fontFamily, block.effectiveFontSize,
            isBold: block.effectiveIsBold, isItalic: block.effectiveIsItalic);
        page.graphics.drawString(
          block.editedText,
          font,
          brush:  sf.PdfSolidBrush(_sfColor(block.effectiveColorArgb)),
          bounds: sfRect,
        );
      }
    }

    // ── 2. Burn in overlay annotations ─────────────────────────────────────
    for (final a in annotations) {
      final pageIdx = a.pageNumber - 1;
      if (pageIdx < 0 || pageIdx >= doc.pages.count) continue;
      final page  = doc.pages[pageIdx];
      final pageH = pageHeights[a.pageNumber] ?? page.size.height;
      _writeAnnotation(page, a, pageH);
    }

    final saved = await doc.save();
    await File(outputPath).writeAsBytes(saved);
    doc.dispose();
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────

  sf.PdfColor _sfColor(int argb, {double? opacity}) {
    final a = opacity != null
        ? (opacity * 255).round()
        : (argb >> 24) & 0xFF;
    return sf.PdfColor(
      (argb >> 16) & 0xFF,
      (argb >> 8)  & 0xFF,
       argb        & 0xFF,
      a,
    );
  }

  /// Creates a PdfStandardFont supporting bold, italic, or both.
  ///
  /// PdfFontStyle has no combined boldItalic constant.
  /// When both bold and italic are requested we create a bold font and
  /// layer an italic-slant effect via a PdfStringFormat skew — but the
  /// simplest cross-platform approach Syncfusion supports is:
  ///   bold=true  italic=false → PdfFontStyle.bold
  ///   bold=false italic=true  → PdfFontStyle.italic
  ///   bold=true  italic=true  → PdfFontStyle.bold (bold takes precedence;
  ///                              Syncfusion has no single boldItalic value)
  ///   both false              → PdfFontStyle.regular
  sf.PdfStandardFont _makeFont(
    sf.PdfFontFamily family,
    double size, {
    required bool isBold,
    required bool isItalic,
  }) {
    final style = isBold
        ? sf.PdfFontStyle.bold
        : (isItalic ? sf.PdfFontStyle.italic : sf.PdfFontStyle.regular);
    return sf.PdfStandardFont(family, size, style: style);
  }

  sf.PdfFontFamily _matchFont(String name) {
    final l = name.toLowerCase();
    if (l.contains('times') || l.contains('serif') || l.contains('georgia')) {
      return sf.PdfFontFamily.timesRoman;
    }
    if (l.contains('courier') || l.contains('mono')) {
      return sf.PdfFontFamily.courier;
    }
    return sf.PdfFontFamily.helvetica;
  }

  /// Annotation coords are stored in Flutter space (top-left origin, Y grows DOWN).
  /// Syncfusion page.graphics also uses top-left origin — pass coords directly.
  ui.Rect _sfRect(AnnotationModel a, double pageH) {
    return ui.Rect.fromLTWH(a.x, a.y, a.width, a.height);
  }

  void _writeAnnotation(sf.PdfPage page, AnnotationModel a, double pageH) {
    final rect = _sfRect(a, pageH);
    switch (a.type) {
      case AnnotationType.text:
        if (a.content.trim().isNotEmpty) {
          final font = _makeFont(sf.PdfFontFamily.helvetica, a.fontSize,
              isBold: a.isBold, isItalic: a.isItalic);
          page.graphics.drawString(
            a.content, font,
            brush:  sf.PdfSolidBrush(_sfColor(a.color)),
            bounds: rect,
          );
        }
        break;

      case AnnotationType.highlight:
        page.annotations.add(sf.PdfTextMarkupAnnotation(
          rect,
          a.content.isEmpty ? 'Highlight' : a.content,
          _sfColor(a.color, opacity: 0.4),
          textMarkupAnnotationType: sf.PdfTextMarkupAnnotationType.highlight,
        ));
        break;

      case AnnotationType.underline:
        page.annotations.add(sf.PdfTextMarkupAnnotation(
          rect,
          a.content.isEmpty ? 'Underline' : a.content,
          _sfColor(a.color),
          textMarkupAnnotationType: sf.PdfTextMarkupAnnotationType.underline,
        ));
        break;

      case AnnotationType.strikethrough:
        page.annotations.add(sf.PdfTextMarkupAnnotation(
          rect,
          a.content.isEmpty ? 'Strikethrough' : a.content,
          _sfColor(a.color),
          textMarkupAnnotationType:
              sf.PdfTextMarkupAnnotationType.strikethrough,
        ));
        break;

      case AnnotationType.rectangle:
        final ann = sf.PdfRectangleAnnotation(
          rect,
          a.content.isEmpty ? 'Rectangle' : a.content,
        );
        ann.color        = _sfColor(a.color);
        ann.innerColor   = sf.PdfColor(0, 0, 0, 0);
        ann.border.width = a.strokeWidth;
        page.annotations.add(ann);
        break;

      case AnnotationType.circle:
        final ann = sf.PdfEllipseAnnotation(
          rect,
          a.content.isEmpty ? 'Circle' : a.content,
        );
        ann.color        = _sfColor(a.color);
        ann.innerColor   = sf.PdfColor(0, 0, 0, 0);
        ann.border.width = a.strokeWidth;
        page.annotations.add(ann);
        break;

      case AnnotationType.freehand:
        if (a.pathPoints != null && a.pathPoints!.length > 1) {
          // pathPoints are stored in Flutter space (top-left origin, Y grows DOWN).
          // Syncfusion page.graphics also uses top-left origin — no Y-flip needed.
          final pen = sf.PdfPen(_sfColor(a.color), width: a.strokeWidth);
          pen.lineCap = sf.PdfLineCap.round;
          final pts = a.pathPoints!;
          for (int i = 0; i < pts.length - 1; i++) {
            page.graphics.drawLine(
              pen,
              ui.Offset(pts[i]['x']!,   pts[i]['y']!),
              ui.Offset(pts[i+1]['x']!, pts[i+1]['y']!),
            );
          }
        }
        break;

      default:
        break;
    }
  }
}
