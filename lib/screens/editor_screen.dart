import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

import '../providers/pdf_provider.dart';
import '../widgets/annotation_overlay.dart';
import '../widgets/annotations_list.dart';
import '../widgets/editor_toolbar.dart';
import '../widgets/page_navigator.dart';
import '../widgets/properties_panel.dart';
import '../widgets/thumbnail_panel.dart';

class EditorScreen extends ConsumerStatefulWidget {
  const EditorScreen({super.key});

  @override
  ConsumerState<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends ConsumerState<EditorScreen> {
  final PdfViewerController _pdfController = PdfViewerController();
  bool _showPropertiesPanel  = false;
  bool _showThumbnails       = false;
  bool _showAnnotationsList  = false;
  bool _isSaving             = false;

  @override
  void dispose() {
    _pdfController.dispose();
    super.dispose();
  }

  Future<void> _saveDocument() async {
    final doc = ref.read(currentDocumentProvider);
    if (doc == null) return;

    // Capture before any await to satisfy use_build_context_synchronously
    final messenger  = ScaffoldMessenger.of(context);
    final errorColor = Theme.of(context).colorScheme.error;

    setState(() => _isSaving = true);
    try {
      final dir = await getApplicationDocumentsDirectory();
      final ts  = DateTime.now().millisecondsSinceEpoch;
      final outputPath = '${dir.path}/edited_${ts}_${doc.fileName}';

      await ref
          .read(currentDocumentProvider.notifier)
          .saveDocument(outputPath);

      messenger.showSnackBar(
        SnackBar(
          content: const Text('PDF saved successfully'),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: 'Share',
            onPressed: () => Share.shareXFiles(
              [XFile(outputPath)],
              subject: 'Edited PDF',
            ),
          ),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Save failed: $e'),
          backgroundColor: errorColor,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _handleSave() {
    final doc = ref.read(currentDocumentProvider);
    if (doc == null) return;
    if (!doc.isModified) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No unsaved changes'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    _saveDocument();
  }

  void _confirmBack(BuildContext ctx) {
    showDialog<void>(
      context: ctx,
      builder: (_) => AlertDialog(
        title: const Text('Unsaved changes'),
        content: const Text(
            'You have unsaved changes. Save before leaving?'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop(ctx);
            },
            child: const Text('Discard'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _saveDocument();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final doc = ref.watch(currentDocumentProvider);
    if (doc == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('PDF Editor')),
        body: const Center(child: Text('No document open')),
      );
    }

    final theme = Theme.of(context);

    // PopScope replaces the deprecated WillPopScope
    return PopScope(
      canPop: !doc.isModified,
      onPopInvokedWithResult: (bool didPop, _) {
        if (!didPop) _confirmBack(context);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Row(
            children: [
              Icon(
                Icons.picture_as_pdf_rounded,
                color: theme.colorScheme.primary,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  doc.fileName,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              if (doc.isModified)
                Container(
                  margin: const EdgeInsets.only(left: 6),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'Modified',
                    style: TextStyle(
                      fontSize: 10,
                      color: theme.colorScheme.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          actions: [
            IconButton(
              icon: Icon(
                _showThumbnails
                    ? Icons.view_list_rounded
                    : Icons.grid_view_rounded,
              ),
              onPressed: () =>
                  setState(() => _showThumbnails = !_showThumbnails),
              tooltip: 'Page thumbnails',
            ),
            IconButton(
              icon: const Icon(Icons.layers_rounded),
              onPressed: () => setState(
                  () => _showAnnotationsList = !_showAnnotationsList),
              tooltip: 'Annotations',
            ),
            IconButton(
              icon: const Icon(Icons.tune_rounded),
              onPressed: () => setState(
                  () => _showPropertiesPanel = !_showPropertiesPanel),
              tooltip: 'Properties',
            ),
            IconButton(
              icon: const Icon(Icons.share_rounded),
              onPressed: () => Share.shareXFiles(
                [XFile(doc.filePath)],
                subject: doc.fileName,
              ),
              tooltip: 'Share original',
            ),
            const SizedBox(width: 4),
            _isSaving
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : FilledButton.icon(
                    onPressed: _handleSave,
                    icon: const Icon(Icons.save_rounded, size: 18),
                    label: const Text('Save'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                    ),
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
                  if (_showThumbnails)
                    SizedBox(
                      width: 100,
                      child: ThumbnailPanel(
                        filePath: doc.filePath,
                        totalPages: doc.totalPages,
                        currentPage: doc.currentPage,
                        onPageTap: (page) =>
                            _pdfController.jumpToPage(page),
                      ),
                    ),
                  Expanded(
                    child: Stack(
                      children: [
                        SfPdfViewer.file(
                          File(doc.filePath),
                          controller: _pdfController,
                          enableDoubleTapZooming: true,
                          pageLayoutMode: PdfPageLayoutMode.single,
                          canShowScrollHead: true,
                          canShowScrollStatus: true,
                          onPageChanged: (details) {
                            ref
                                .read(currentDocumentProvider.notifier)
                                .setPage(details.newPageNumber);
                          },
                        ),
                        AnnotationOverlay(
                            pdfController: _pdfController),
                      ],
                    ),
                  ),
                  if (_showAnnotationsList)
                    const SizedBox(
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
