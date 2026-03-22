import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart' show FontWeight, FontStyle, Colors;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:uuid/uuid.dart';

import '../models/annotation_model.dart';
import '../models/pdf_text_block.dart';

final pdfServiceProvider = Provider<PdfService>((ref) => PdfService());

const _uuid = Uuid();

/// All PDF reading and writing goes through this service.
/// Uses [pdfrx] (Google PDFium) exclusively — no Syncfusion dependency.
class PdfService {
  // ── Document info ──────────────────────────────────────────────────────────

  Future<int> getPageCount(String filePath) async {
    final doc   = await PdfDocument.openFile(filePath);
    final count = doc.pages.length;
    doc.dispose();
    return count;
  }

  /// Returns the size of [pageNumber] (1-based) in PDF points (72pt = 1 inch).
  Future<({double width, double height})> getPageSize(
      String filePath, int pageNumber) async {
    final doc  = await PdfDocument.openFile(filePath);
    final idx  = (pageNumber - 1).clamp(0, doc.pages.length - 1);
    final page = doc.pages[idx];
    final size = (width: page.width, height: page.height);
    doc.dispose();
    return size;
  }

  // ── Text extraction (PDFium glyph-level) ──────────────────────────────────

  /// Extract all text lines from [pageNumber] (1-based) using PDFium.
  ///
  /// pdfrx's [PdfPage.loadText] returns [PdfPageText] whose [fragments] list
  /// carries exact glyph-level bounds, font name, font size, and bold/italic
  /// flags — directly from the embedded PDF font metadata.
  ///
  /// We group fragments into visual lines (same Y midpoint ± half line height),
  /// sort top-to-bottom, and return one [PdfTextBlock] per line.
  Future<List<PdfTextBlock>> extractTextBlocks(
    String filePath,
    int    pageNumber,
  ) async {
    final doc = await PdfDocument.openFile(filePath);
    if (pageNumber < 1 || pageNumber > doc.pages.length) {
      doc.dispose();
      return [];
    }

    final page     = doc.pages[pageNumber - 1];
    final pageText = await page.loadText();

    final fragments = pageText.fragments
        .where((f) => f.text.trim().isNotEmpty)
        .toList();

    // ── Group into lines ───────────────────────────────────────────────────
    final List<List<PdfPageTextFragment>> lines = [];
    for (final frag in fragments) {
      bool placed = false;
      for (final line in lines) {
        final ref     = line.first;
        final thresh  = (ref.bounds.height * 0.6).clamp(2.0, 20.0);
        if ((frag.bounds.center.dy - ref.bounds.center.dy).abs() <= thresh) {
          line.add(frag);
          placed = true;
          break;
        }
      }
      if (!placed) lines.add([frag]);
    }

    // Sort lines top-to-bottom; fragments left-to-right within each line
    lines.sort((a, b) => a.first.bounds.top.compareTo(b.first.bounds.top));
    for (final line in lines) {
      line.sort((a, b) => a.bounds.left.compareTo(b.bounds.left));
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
      final rect   = ui.Rect.fromLTRB(left, top, right, bottom);

      final first  = line.first;
      blocks.add(PdfTextBlock(
        id:           _uuid.v4(),
        pageNumber:   pageNumber,
        originalText: text,
        editedText:   text,
        pdfRect:      rect,
        screenRect:   rect, // caller applies scale
        fontSize:     first.fontSize.clamp(4.0, 144.0),
        fontName:     first.fontName.isNotEmpty ? first.fontName : 'Helvetica',
        isBold:       first.isBold,
        isItalic:     first.isOblique,
        colorArgb:    0xFF000000,
      ));
    }

    doc.dispose();
    return blocks;
  }

  // ── Save ───────────────────────────────────────────────────────────────────

  /// Saves the PDF with:
  ///   1. Edited existing-text blocks replaced via cover-and-redraw
  ///      (PDFium has no content-stream text-edit API from Dart, so this
  ///       is the same technique Adobe Acrobat uses for text-edit-only saves).
  ///   2. New overlay annotations (highlight, underline, shapes, freehand…)
  ///      added as proper PDF annotation objects via pdfrx.
  ///
  /// [pageHeights] maps page number → height in PDF points, used to flip
  /// the Y-axis (PDFium graphics: bottom-left origin; our coords: top-left).
  Future<void> saveWithAnnotations(
    String sourcePath,
    List<AnnotationModel> annotations,
    String outputPath, {
    List<PdfTextBlock> editedTextBlocks = const [],
    Map<int, double>   pageHeights      = const {},
  }) async {
    final doc = await PdfDocument.openFile(sourcePath);

    // ── 1. Replace edited text blocks ──────────────────────────────────────
    for (final block in editedTextBlocks.where((b) => b.isEdited)) {
      final pageIdx = block.pageNumber - 1;
      if (pageIdx < 0 || pageIdx >= doc.pages.length) continue;

      final page  = doc.pages[pageIdx];
      final pageH = pageHeights[block.pageNumber] ?? page.height;

      // block.pdfRect: top-left origin (Y grows down) — from PdfPageText
      // PDFium page.insertImage rect: bottom-left origin (Y grows up)
      // Conversion: pdfBottom = pageHeight - pdfTop - blockHeight
      final pdfLeft = block.pdfRect.left;
      final pdfBot  = pageH - block.pdfRect.bottom;
      final pdfW    = block.pdfRect.width.clamp(4.0, double.infinity);
      final pdfH    = block.pdfRect.height.clamp(4.0, double.infinity);
      final drawRect = ui.Rect.fromLTWH(pdfLeft, pdfBot, pdfW, pdfH);

      // (a) Erase — paint a white rectangle over the original text
      final eraseImg = await _solidColorImage(0xFFFFFFFF,
          pdfW.ceil(), pdfH.ceil());
      await page.insertImage(eraseImg, drawRect);

      // (b) Redraw — render replacement text as a Flutter raster image
      if (block.editedText.trim().isNotEmpty) {
        final textImg = await _renderTextToImage(
          text:     block.editedText,
          fontSize: block.fontSize,
          isBold:   block.isBold,
          isItalic: block.isItalic,
          color:    ui.Color(block.colorArgb),
          widthPt:  pdfW,
          heightPt: pdfH,
        );
        await page.insertImage(textImg, drawRect);
      }
    }

    // ── 2. Add new overlay annotations ─────────────────────────────────────
    for (final a in annotations) {
      final pageIdx = a.pageNumber - 1;
      if (pageIdx < 0 || pageIdx >= doc.pages.length) continue;

      final page  = doc.pages[pageIdx];
      final pageH = pageHeights[a.pageNumber] ?? page.height;

      // Annotation coords: top-left origin → PDFium bottom-left origin
      final sfBot = pageH - a.y - a.height;
      final rect  = ui.Rect.fromLTWH(a.x, sfBot, a.width, a.height);

      switch (a.type) {
        case AnnotationType.text:
          if (a.content.trim().isNotEmpty) {
            final img = await _renderTextToImage(
              text:     a.content,
              fontSize: a.fontSize,
              isBold:   a.isBold,
              isItalic: a.isItalic,
              color:    ui.Color(a.color),
              widthPt:  a.width,
              heightPt: a.height,
            );
            await page.insertImage(img, rect);
          }
          break;

        case AnnotationType.highlight:
          page.addAnnotation(PdfHighlightAnnotation(
            color: ui.Color(a.color).withValues(alpha: 0.4),
            rects: [rect],
          ));
          break;

        case AnnotationType.underline:
          page.addAnnotation(PdfUnderlineAnnotation(
            color: ui.Color(a.color),
            rects: [rect],
          ));
          break;

        case AnnotationType.strikethrough:
          page.addAnnotation(PdfStrikeoutAnnotation(
            color: ui.Color(a.color),
            rects: [rect],
          ));
          break;

        case AnnotationType.rectangle:
          page.addAnnotation(PdfSquareAnnotation(
            rect:        rect,
            color:       ui.Color(a.color),
            fillColor:   const ui.Color(0x00000000),
            borderWidth: a.strokeWidth,
          ));
          break;

        case AnnotationType.circle:
          page.addAnnotation(PdfCircleAnnotation(
            rect:        rect,
            color:       ui.Color(a.color),
            fillColor:   const ui.Color(0x00000000),
            borderWidth: a.strokeWidth,
          ));
          break;

        case AnnotationType.freehand:
          if (a.pathPoints != null && a.pathPoints!.length > 1) {
            final pts = a.pathPoints!
                .map((p) => ui.Offset(p['x']!, pageH - p['y']!))
                .toList();
            page.addAnnotation(PdfInkAnnotation(
              color:       ui.Color(a.color),
              borderWidth: a.strokeWidth,
              inkList:     [pts],
            ));
          }
          break;

        default:
          break;
      }
    }

    // ── 3. Write output file ────────────────────────────────────────────────
    final Uint8List savedBytes = await doc.save();
    await File(outputPath).writeAsBytes(savedBytes);
    doc.dispose();
  }

  // ── Image helpers ──────────────────────────────────────────────────────────

  /// Create a [PdfImage] filled entirely with [argb].
  Future<PdfImage> _solidColorImage(int argb, int w, int h) async {
    final pixels = Uint8List(w * h * 4);
    final r = (argb >> 16) & 0xFF;
    final g = (argb >> 8)  & 0xFF;
    final b = argb & 0xFF;
    final a = (argb >> 24) & 0xFF;
    for (int i = 0; i < w * h; i++) {
      pixels[i * 4]     = r;
      pixels[i * 4 + 1] = g;
      pixels[i * 4 + 2] = b;
      pixels[i * 4 + 3] = a;
    }
    return PdfImage.fromRgba(width: w, height: h, pixels: pixels);
  }

  /// Render [text] to a [PdfImage] using Flutter's canvas at 2× resolution
  /// so glyphs look crisp at any zoom level after embedding in the PDF.
  Future<PdfImage> _renderTextToImage({
    required String   text,
    required double   fontSize,
    required bool     isBold,
    required bool     isItalic,
    required ui.Color color,
    required double   widthPt,
    required double   heightPt,
  }) async {
    const scale = 2.0; // render at 2× for crisp embedding
    final wPx   = (widthPt  * scale).ceil().clamp(1, 4096);
    final hPx   = (heightPt * scale).ceil().clamp(1, 4096);

    final recorder = ui.PictureRecorder();
    final canvas   = ui.Canvas(
        recorder, ui.Rect.fromLTWH(0, 0, wPx.toDouble(), hPx.toDouble()));

    final pb = ui.ParagraphBuilder(
      ui.ParagraphStyle(
        fontWeight: isBold   ? FontWeight.bold   : FontWeight.normal,
        fontStyle:  isItalic ? FontStyle.italic  : FontStyle.normal,
        fontSize:   fontSize * scale,
        maxLines:   null,
      ),
    )
      ..pushStyle(ui.TextStyle(color: color))
      ..addText(text);

    final para = pb.build()
      ..layout(ui.ParagraphConstraints(width: wPx.toDouble()));
    canvas.drawParagraph(para, ui.Offset.zero);

    final picture  = recorder.endRecording();
    final image    = await picture.toImage(wPx, hPx);
    final byteData = await image.toByteData(
        format: ui.ImageByteFormat.rawRgba);

    image.dispose();
    picture.dispose();

    return PdfImage.fromRgba(
      width:  wPx,
      height: hPx,
      pixels: byteData!.buffer.asUint8List(),
    );
  }
}
