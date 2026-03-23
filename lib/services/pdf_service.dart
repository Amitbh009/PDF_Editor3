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
  /// [PdfPageTextFragment.bounds] is a [PdfRect] — a PDFium-native rect with
  /// .left, .top, .right, .bottom in PDF-points (origin top-left, Y grows down).
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

    // Group fragments into visual lines by Y-midpoint proximity.
    final lines = <List<PdfPageTextFragment>>[];
    for (final frag in frags) {
      // PdfRect fields: left, top, right, bottom (top-left origin)
      final midY    = (frag.bounds.top + frag.bounds.bottom) / 2.0;
      final lineH   = (frag.bounds.bottom - frag.bounds.top).abs();
      final thresh  = (lineH * 0.6).clamp(2.0, 20.0);
      bool placed   = false;
      for (final line in lines) {
        final refMid = (line.first.bounds.top + line.first.bounds.bottom) / 2.0;
        if ((midY - refMid).abs() <= thresh) {
          line.add(frag);
          placed = true;
          break;
        }
      }
      if (!placed) lines.add([frag]);
    }

    // Sort top-to-bottom; left-to-right within each line.
    lines.sort((a, b) => a.first.bounds.top.compareTo(b.first.bounds.top));
    for (final l in lines) {
      l.sort((a, b) => a.bounds.left.compareTo(b.bounds.left));
    }

    final blocks = <PdfTextBlock>[];
    for (final line in lines) {
      if (line.isEmpty) continue;
      final text = line.map((f) => f.text).join('');
      if (text.trim().isEmpty) continue;

      final left   = line.map((f) => f.bounds.left  ).reduce((a,b) => a < b ? a : b);
      final top    = line.map((f) => f.bounds.top    ).reduce((a,b) => a < b ? a : b);
      final right  = line.map((f) => f.bounds.right  ).reduce((a,b) => a > b ? a : b);
      final bottom = line.map((f) => f.bounds.bottom ).reduce((a,b) => a > b ? a : b);

      final first    = line.first;
      final lineH    = (bottom - top).abs().clamp(4.0, double.infinity);
      final fontSize = (lineH * 0.75).clamp(4.0, 144.0);

      blocks.add(PdfTextBlock(
        id:           _uuid.v4(),
        pageNumber:   pageNumber,
        originalText: text,
        editedText:   text,
        pdfLeft:      left,
        pdfTop:       top,
        pdfRight:     right,
        pdfBottom:    bottom,
        screenRect:   ui.Rect.fromLTRB(left, top, right, bottom),
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
  /// Syncfusion uses bottom-left origin (Y grows UP), so we flip:
  ///   sfBottom = pageHeight − pdfTop − blockHeight
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
      final pageH = pageHeights[block.pageNumber] ?? page.size.height;

      // Flip Y: Syncfusion graphics uses bottom-left origin.
      final sfBottom = pageH - block.pdfTop  - block.pdfHeight;
      final sfRect   = ui.Rect.fromLTWH(
          block.pdfLeft, sfBottom, block.pdfWidth, block.pdfHeight);

      // (a) Erase — white rectangle over original text.
      page.graphics.drawRectangle(
        brush:  sf.PdfSolidBrush(sf.PdfColor(255, 255, 255)),
        bounds: sfRect,
      );

      // (b) Redraw replacement text.
      if (block.editedText.trim().isNotEmpty) {
        final fontFamily = _matchFont(block.fontName);
        final fontStyle  = block.isBold
            ? (block.isItalic ? sf.PdfFontStyle.boldItalic : sf.PdfFontStyle.bold)
            : (block.isItalic ? sf.PdfFontStyle.italic     : sf.PdfFontStyle.regular);
        final font = sf.PdfStandardFont(fontFamily, block.fontSize,
            style: fontStyle);
        page.graphics.drawString(
          block.editedText,
          font,
          brush:  sf.PdfSolidBrush(_sfColor(block.colorArgb)),
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

  /// Convert annotation coords (top-left origin) to Syncfusion (bottom-left).
  ui.Rect _sfRect(AnnotationModel a, double pageH) {
    final sfBottom = pageH - a.y - a.height;
    return ui.Rect.fromLTWH(a.x, sfBottom, a.width, a.height);
  }

  void _writeAnnotation(sf.PdfPage page, AnnotationModel a, double pageH) {
    final rect = _sfRect(a, pageH);
    switch (a.type) {
      case AnnotationType.text:
        if (a.content.trim().isNotEmpty) {
          final style = a.isBold
              ? (a.isItalic ? sf.PdfFontStyle.boldItalic : sf.PdfFontStyle.bold)
              : (a.isItalic ? sf.PdfFontStyle.italic     : sf.PdfFontStyle.regular);
          final font = sf.PdfStandardFont(
              sf.PdfFontFamily.helvetica, a.fontSize, style: style);
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
          final pen = sf.PdfPen(_sfColor(a.color), width: a.strokeWidth);
          pen.lineCap = sf.PdfLineCap.round;
          final pts = a.pathPoints!;
          for (int i = 0; i < pts.length - 1; i++) {
            page.graphics.drawLine(
              pen,
              ui.Offset(pts[i]['x']!,     pageH - pts[i]['y']!),
              ui.Offset(pts[i+1]['x']!, pageH - pts[i+1]['y']!),
            );
          }
        }
        break;

      default:
        break;
    }
  }
}
