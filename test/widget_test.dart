import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_editor/main.dart';
import 'package:pdf_editor/providers/pdf_provider.dart';
import 'package:pdf_editor/screens/home_screen.dart';

void main() {
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

  testWidgets('app renders HomeScreen with call-to-action',
      (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: PdfEditorApp()));

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text('Browse & Open PDF'), findsOneWidget);
  });
}
