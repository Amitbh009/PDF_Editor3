import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../providers/pdf_provider.dart';
import '../widgets/editor_toolbar.dart';
import '../widgets/annotation_overlay.dart';
import '../widgets/properties_panel.dart';
import '../widgets/page_navigator.dart';
import '../widgets/annotations_list.dart';

class EditorScreen extends ConsumerStatefulWidget {
  const EditorScreen({super.key});

  @override
  ConsumerState<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends ConsumerState<EditorScreen> {
  final PdfViewerController _pdfController = PdfViewerController();
  bool _showPropertiesPanel = false;
  bool _showAnnotationsList = false;
  bool _isSaving = false;

  @override
  void dispose() {
    _pdfController.dispose();
    super.dispose();
  }

  Future<void> _saveDocument() async {
    final doc = ref.read(currentDocumentProvider);
    if (doc == null) return;
    setState(() => _isSaving = true);
    try {
      final dir = await getApplicationDocumentsDirectory();
      final outputPath = '${dir.path}/edited_${doc.fileName}';
      await ref
          .read(currentDocumentProvider.notifier)
          .saveDocument(outputPath);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Saved: ${doc.fileName}'),
            action: SnackBarAction(
              label: 'Share',
              onPressed: () => Share.shareXFiles([XFile(outputPath)]),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<bool> _onWillPop() async {
    final doc = ref.read(currentDocumentProvider);
    if (doc == null || !doc.isModified) return true;
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Unsaved Changes'),
        content: const Text(
            'You have unsaved changes. Do you want to save before leaving?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Discard'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              await _saveDocument();
              if (context.mounted) Navigator.pop(context, true);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result == null) return false;
    if (result == false) {
      ref.read(currentDocumentProvider.notifier).closeDocument();
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final doc = ref.watch(currentDocumentProvider);
    if (doc == null) return const SizedBox.shrink();
    final theme = Theme.of(context);

    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        appBar: AppBar(
          title: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(doc.fileName,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    Text(
                        'Page ${doc.currentPage} / ${doc.totalPages}  •  '
                        '${doc.annotations.length} annotation(s)',
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
              if (doc.isModified)
                Container(
                  margin: const EdgeInsets.only(left: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text('Modified',
                      style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.onErrorContainer)),
                ),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.list_alt_rounded),
              onPressed: () =>
                  setState(() => _showAnnotationsList = !_showAnnotationsList),
              tooltip: 'Annotations list',
            ),
            IconButton(
              icon: const Icon(Icons.tune_rounded),
              onPressed: () =>
                  setState(() => _showPropertiesPanel = !_showPropertiesPanel),
              tooltip: 'Properties',
            ),
            const SizedBox(width: 4),
            _isSaving
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                : FilledButton.icon(
                    onPressed: _saveDocument,
                    icon: const Icon(Icons.save_rounded, size: 18),
                    label: const Text('Save'),
                  ),
            const SizedBox(width: 8),
          ],
        ),
        body: Column(
          children: [
            const EditorToolbar(),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: Stack(
                      children: [
                        SfPdfViewer.file(
                          File(doc.filePath),
                          controller: _pdfController,
                          enableDoubleTapZooming: true,
                          pageLayoutMode: PdfPageLayoutMode.single,
                          onPageChanged: (details) {
                            ref
                                .read(currentDocumentProvider.notifier)
                                .setPage(details.newPageNumber);
                          },
                        ),
                        AnnotationOverlay(pdfController: _pdfController),
                      ],
                    ),
                  ),
                  if (_showAnnotationsList)
                    SizedBox(
                      width: 260,
                      child: AnnotationsList(),
                    ),
                  if (_showPropertiesPanel)
                    const SizedBox(
                      width: 280,
                      child: PropertiesPanel(),
                    ),
                ],
              ),
            ),
            PageNavigator(
              currentPage: doc.currentPage,
              totalPages: doc.totalPages,
              onPageChanged: (page) => _pdfController.jumpToPage(page),
            ),
          ],
        ),
      ),
    );
  }
}
