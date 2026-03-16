import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_editor/models/annotation_model.dart';

void main() {
  group('AnnotationModel', () {
    test('creates text annotation with defaults', () {
      const a = AnnotationModel(
        id: 'test-1',
        type: AnnotationType.text,
        pageNumber: 1,
        x: 10,
        y: 20,
        width: 200,
        height: 40,
        content: 'Hello PDF',
      );

      expect(a.id, 'test-1');
      expect(a.type, AnnotationType.text);
      expect(a.content, 'Hello PDF');
      expect(a.fontSize, 14.0);
      expect(a.isBold, false);
      expect(a.isItalic, false);
      expect(a.opacity, 1.0);
    });

    test('creates freehand annotation with path points', () {
      const a = AnnotationModel(
        id: 'test-2',
        type: AnnotationType.freehand,
        pageNumber: 2,
        x: 0,
        y: 0,
        width: 100,
        height: 100,
        pathPoints: [
          {'x': 0.0, 'y': 0.0},
          {'x': 50.0, 'y': 50.0},
          {'x': 100.0, 'y': 100.0},
        ],
      );

      expect(a.pathPoints, isNotNull);
      expect(a.pathPoints!.length, 3);
    });

    test('supports copyWith', () {
      const a = AnnotationModel(
        id: 'test-3',
        type: AnnotationType.highlight,
        pageNumber: 1,
        x: 0,
        y: 0,
        width: 100,
        height: 20,
      );

      final modified = a.copyWith(color: 0xFFFFFF00, opacity: 0.5);
      expect(modified.color, 0xFFFFFF00);
      expect(modified.opacity, 0.5);
      expect(modified.id, 'test-3'); // unchanged
    });

    test('annotation types cover all expected values', () {
      expect(AnnotationType.values.length, greaterThanOrEqualTo(8));
      expect(AnnotationType.values, contains(AnnotationType.text));
      expect(AnnotationType.values, contains(AnnotationType.highlight));
      expect(AnnotationType.values, contains(AnnotationType.freehand));
      expect(AnnotationType.values, contains(AnnotationType.rectangle));
      expect(AnnotationType.values, contains(AnnotationType.circle));
    });
  });
}
