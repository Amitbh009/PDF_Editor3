import 'dart:ui' show Rect;

/// A single line of text extracted from a PDF page via PDFium (pdfrx).
///
/// Coordinates:
///   [pdfLeft], [pdfTop], [pdfRight], [pdfBottom] — PDF-point space
///     (pdfrx PdfPageTextFragment.bounds uses top-left origin, Y grows DOWN).
///   [screenRect] — screen-pixel space, set by [withScreenRect] after the
///     viewer reports its scale factor.
class PdfTextBlock {
  PdfTextBlock({
    required this.id,
    required this.pageNumber,
    required this.originalText,
    required this.editedText,
    required this.pdfLeft,
    required this.pdfTop,
    required this.pdfRight,
    required this.pdfBottom,
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
  final String originalText;
  String       editedText;

  // PDF-point coordinates (top-left origin, Y grows down — as returned by
  // pdfrx PdfRect after converting via pdfRectToFlutterRect).
  final double pdfLeft;
  final double pdfTop;
  final double pdfRight;
  final double pdfBottom;

  double get pdfWidth  => pdfRight  - pdfLeft;
  double get pdfHeight => pdfBottom - pdfTop;

  /// The dart:ui Rect that covers this block in PDF-point space.
  Rect get pdfRect => Rect.fromLTRB(pdfLeft, pdfTop, pdfRight, pdfBottom);

  /// Screen-pixel rect, updated via [withScreenRect] when zoom changes.
  Rect screenRect;

  final double fontSize;
  final String fontName;
  final bool   isBold;
  final bool   isItalic;
  final int    colorArgb;

  bool isEdited;

  PdfTextBlock withScreenRect(Rect rect) => PdfTextBlock(
        id:           id,
        pageNumber:   pageNumber,
        originalText: originalText,
        editedText:   editedText,
        pdfLeft:      pdfLeft,
        pdfTop:       pdfTop,
        pdfRight:     pdfRight,
        pdfBottom:    pdfBottom,
        screenRect:   rect,
        fontSize:     fontSize,
        fontName:     fontName,
        isBold:       isBold,
        isItalic:     isItalic,
        colorArgb:    colorArgb,
        isEdited:     isEdited,
      );
}
