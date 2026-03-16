import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;
import '../models/annotation_model.dart';

final pdfServiceProvider = Provider<PdfService>((ref) => PdfService());

class PdfService {
  Future<int> getPageCount(String filePath) async {
    final bytes = await File(filePath).readAsBytes();
    final doc = sf.PdfDocument(inputBytes: bytes);
    final count = doc.pages.count;
    doc.dispose();
    return count;
  }

  Future<void> saveWithAnnotations(
    String sourcePath,
    List<AnnotationModel> annotations,
    String outputPath,
  ) async {
    final bytes = await File(sourcePath).readAsBytes();
    final doc = sf.PdfDocument(inputBytes: bytes);

    for (final annotation in annotations) {
      final pageIndex = annotation.pageNumber - 1;
      if (pageIndex < 0 || pageIndex >= doc.pages.count) continue;
      final page = doc.pages[pageIndex];

      final r = sf.Rect.fromLTWH(
        annotation.x, annotation.y,
        annotation.width, annotation.height,
      );
      final sfColor = sf.PdfColor(
        (annotation.color >> 16) & 0xFF,
        (annotation.color >> 8) & 0xFF,
        annotation.color & 0xFF,
      );

      switch (annotation.type) {
        case AnnotationType.text:
          final font = sf.PdfStandardFont(
            sf.PdfFontFamily.helvetica,
            annotation.fontSize,
            style: annotation.isBold
                ? sf.PdfFontStyle.bold
                : sf.PdfFontStyle.regular,
          );
          page.graphics.drawString(
            annotation.content, font,
            brush: sf.PdfSolidBrush(sfColor),
            bounds: r,
          );
          break;

        case AnnotationType.highlight:
          final hl = sf.PdfTextMarkupAnnotation(
            r, annotation.content,
            sf.PdfColor(
              (annotation.color >> 16) & 0xFF,
              (annotation.color >> 8) & 0xFF,
              annotation.color & 0xFF,
              (annotation.opacity * 255).toInt(),
            ),
          );
          hl.annotationType = sf.PdfTextMarkupAnnotationType.highlight;
          page.annotations.add(hl);
          break;

        case AnnotationType.underline:
          final ul = sf.PdfTextMarkupAnnotation(
            r, annotation.content, sfColor,
          );
          ul.annotationType = sf.PdfTextMarkupAnnotationType.underline;
          page.annotations.add(ul);
          break;

        case AnnotationType.strikethrough:
          final st = sf.PdfTextMarkupAnnotation(
            r, annotation.content, sfColor,
          );
          st.annotationType = sf.PdfTextMarkupAnnotationType.strikethrough;
          page.annotations.add(st);
          break;

        case AnnotationType.freehand:
          if (annotation.pathPoints != null &&
              annotation.pathPoints!.isNotEmpty) {
            final ink = sf.PdfInkAnnotation(r);
            ink.color = sfColor;
            ink.borderWidth = annotation.strokeWidth.toInt();
            ink.inkList = [
              annotation.pathPoints!
                  .map((p) => sf.Offset(p['x']!, p['y']!))
                  .toList()
            ];
            page.annotations.add(ink);
          }
          break;

        case AnnotationType.rectangle:
          final rect = sf.PdfRectangleAnnotation(r, annotation.content);
          rect.color = sfColor;
          rect.innerColor = sf.PdfColor(0, 0, 0, 0);
          rect.border.width = annotation.strokeWidth.toInt();
          page.annotations.add(rect);
          break;

        case AnnotationType.circle:
          final ellipse = sf.PdfEllipseAnnotation(r, annotation.content);
          ellipse.color = sfColor;
          ellipse.innerColor = sf.PdfColor(0, 0, 0, 0);
          ellipse.border.width = annotation.strokeWidth.toInt();
          page.annotations.add(ellipse);
          break;

        default:
          break;
      }
    }

    final savedBytes = await doc.save();
    await File(outputPath).writeAsBytes(savedBytes);
    doc.dispose();
  }
}
