import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_editor/main.dart';
import 'package:pdf_editor/providers/pdf_provider.dart';

void main() {
  group('PdfEditorApp', () {
    testWidgets('home screen renders correctly', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(child: PdfEditorApp()),
      );
      await tester.pumpAndSettle();

      expect(find.text('PDF Editor'), findsOneWidget);
      expect(find.text('Browse & Open PDF'), findsOneWidget);
    });
  });

  group('DocumentNotifier', () {
    test('initial state is null', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(currentDocumentProvider), isNull);
    });

    test('selected tool defaults to select', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(
        container.read(selectedToolProvider),
        equals(EditorTool.select),
      );
    });

    test('color provider defaults to red', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(selectedColorProvider), equals(0xFFFF0000));
    });

    test('stroke width defaults to 2.0', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(strokeWidthProvider), equals(2.0));
    });
  });
}
