import 'dart:ui' show Rect;

/// A single line of existing text extracted from a PDF page via PDFium.
///
/// PDFium gives us:
///   • Exact glyph-level character bounds (not estimated from line height)
///   • Font name as embedded in the PDF
///   • Font size in PDF points
///   • Font flags (bold / italic)
///
/// Coordinates use two systems:
///   [pdfRect]    — PDF-point space, origin top-left (from PdfPageText.fragments)
///   [screenRect] — Screen-pixel space, computed via [applyScale]
class PdfTextBlock {
  PdfTextBlock({
    required this.id,
    required this.pageNumber,
    required this.originalText,
    required this.editedText,
    required this.pdfRect,   // in PDF points, origin top-left Y-down
    required this.screenRect,
    required this.fontSize,
    required this.fontName,
    required this.isBold,
    required this.isItalic,
    required this.colorArgb,
    this.isEdited = false,
  });

  final String id;
  final int    pageNumber;

  /// Text as it exists in the original PDF.
  final String originalText;

  /// User-edited replacement text (starts equal to [originalText]).
  String editedText;

  /// Bounding rect in PDF-point space (origin top-left, Y grows DOWN).
  /// This is what pdfrx's PdfPageText uses — no Y-flip needed for extraction.
  final Rect pdfRect;

  /// Bounding rect in screen-pixel space, set by [applyScale].
  Rect screenRect;

  // ── Text style (from PDFium glyph metadata) ──────────────────────────────
  final double fontSize;
  final String fontName;
  final bool   isBold;
  final bool   isItalic;
  final int    colorArgb;

  /// True when [editedText] differs from [originalText].
  bool isEdited;

  /// Return a copy with new screen rect (used when zoom level changes).
  PdfTextBlock withScreenRect(Rect rect) => PdfTextBlock(
        id:           id,
        pageNumber:   pageNumber,
        originalText: originalText,
        editedText:   editedText,
        pdfRect:      pdfRect,
        screenRect:   rect,
        fontSize:     fontSize,
        fontName:     fontName,
        isBold:       isBold,
        isItalic:     isItalic,
        colorArgb:    colorArgb,
        isEdited:     isEdited,
      );
}
