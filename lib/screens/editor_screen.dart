import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:share_plus/share_plus.dart';

import '../providers/pdf_provider.dart';
import '../services/pdf_service.dart';
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
  // pdfrx controller — replaces SfPdfViewerController
  final PdfViewerController _pdfController = PdfViewerController();

  bool _showPropertiesPanel = false;
  bool _showThumbnails      = false;
  bool _showAnnotationsList = false;
  bool _isSaving            = false;

  @override
  void dispose() {
    _pdfController.dispose();
    super.dispose();
  }

  // ── Save ───────────────────────────────────────────────────────────────────

  Future<void> _saveDocument() async {
    final doc = ref.read(currentDocumentProvider);
    if (doc == null) return;

    final messenger  = ScaffoldMessenger.of(context);
    final errorColor = Theme.of(context).colorScheme.error;

    setState(() => _isSaving = true);
    try {
      final dir        = await getApplicationDocumentsDirectory();
      final ts         = DateTime.now().millisecondsSinceEpoch;
      final outputPath = '${dir.path}/edited_${ts}_${doc.fileName}';

      // Collect all text block edits made by the user
      final editedBlocks =
          ref.read(textBlockNotifierProvider.notifier).editedBlocks;

      // Fetch any page heights not yet in cache (needed for Y-axis flipping)
      final cachedHeights =
          Map<int, double>.from(ref.read(pageHeightCacheProvider));
      final service = ref.read(pdfServiceProvider);

      final neededPages = {
        ...editedBlocks.map((b) => b.pageNumber),
        ...doc.annotations.map((a) => a.pageNumber),
      };
      for (final p in neededPages) {
        if (!cachedHeights.containsKey(p)) {
          final size = await service.getPageSize(doc.filePath, p);
          cachedHeights[p] = size.height;
        }
      }

      await ref.read(currentDocumentProvider.notifier).saveDocument(
            outputPath,
            editedTextBlocks: editedBlocks,
            pageHeights:      cachedHeights,
          );

      messenger.showSnackBar(
        SnackBar(
          content:  const Text('PDF saved successfully'),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label:     'Share',
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
          content:         Text('Save failed: $e'),
          backgroundColor: errorColor,
          behavior:        SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _handleSave() {
    final doc          = ref.read(currentDocumentProvider);
    final hasTextEdits = ref.read(textBlockNotifierProvider.notifier).hasEdits;
    if (doc == null) return;

    if (!doc.isModified && !hasTextEdits) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:  Text('No unsaved changes'),
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
        title:   const Text('Unsaved changes'),
        content: const Text('You have unsaved changes. Save before leaving?'),
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

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final doc   = ref.watch(currentDocumentProvider);
    final theme = Theme.of(context);

    if (doc == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('PDF Editor')),
        body: const Center(child: Text('No document open')),
      );
    }

    return PopScope(
      canPop: !doc.isModified,
      onPopInvokedWithResult: (bool didPop, _) {
        if (!didPop) _confirmBack(context);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Row(
            children: [
              Icon(Icons.picture_as_pdf_rounded,
                  color: theme.colorScheme.primary, size: 20),
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
                  margin:  const EdgeInsets.only(left: 6),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color:        theme.colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'Modified',
                    style: TextStyle(
                      fontSize:   10,
                      color:      theme.colorScheme.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          actions: [
            IconButton(
              icon: Icon(_showThumbnails
                  ? Icons.view_list_rounded
                  : Icons.grid_view_rounded),
              onPressed: () =>
                  setState(() => _showThumbnails = !_showThumbnails),
              tooltip: 'Page thumbnails',
            ),
            IconButton(
              icon:      const Icon(Icons.layers_rounded),
              onPressed: () => setState(
                  () => _showAnnotationsList = !_showAnnotationsList),
              tooltip: 'Annotations',
            ),
            IconButton(
              icon:      const Icon(Icons.tune_rounded),
              onPressed: () => setState(
                  () => _showPropertiesPanel = !_showPropertiesPanel),
              tooltip: 'Properties',
            ),
            IconButton(
              icon:      const Icon(Icons.share_rounded),
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
                      width:  20,
                      height: 20,
                      child:  CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : FilledButton.icon(
                    onPressed: _handleSave,
                    icon:  const Icon(Icons.save_rounded, size: 18),
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
                  // ── Left: page thumbnails ──────────────────────────────
                  if (_showThumbnails)
                    SizedBox(
                      width: 100,
                      child: ThumbnailPanel(
                        filePath:    doc.filePath,
                        totalPages:  doc.totalPages,
                        currentPage: doc.currentPage,
                        onPageTap:   (page) =>
                            _pdfController.goToPage(pageNumber: page),
                      ),
                    ),

                  // ── Centre: PDF viewer + overlay ───────────────────────
                  Expanded(
                    child: Stack(
                      children: [
                        // pdfrx PdfViewer replaces SfPdfViewer
                        PdfViewer.file(
                          doc.filePath,
                          controller: _pdfController,
                          params: PdfViewerParams(
                            // Single-page layout matches original behaviour
                            layoutPages: (pages, params) =>
                                PdfPageLayout.singlePage(pages, params),

                            // Cache exact page dimensions once document loads.
                            // These are used for:
                            //   1. Computing the overlay scale factor
                            //   2. Y-axis coordinate flipping on save
                            onDocumentChanged: (document) async {
                              if (document == null) return;
                              final service = ref.read(pdfServiceProvider);
                              final heights = <int, double>{};
                              final widths  = <int, double>{};
                              for (int p = 1;
                                  p <= document.pages.length;
                                  p++) {
                                final size = await service.getPageSize(
                                    doc.filePath, p);
                                heights[p] = size.height;
                                widths[p]  = size.width;
                              }
                              ref
                                  .read(pageHeightCacheProvider.notifier)
                                  .state = heights;
                              ref
                                  .read(pageWidthCacheProvider.notifier)
                                  .state = widths;
                            },

                            // Track current page for the overlay & navigator
                            onPageChanged: (pageNumber) {
                              if (pageNumber == null) return;
                              ref
                                  .read(currentDocumentProvider.notifier)
                                  .setPage(pageNumber);
                            },
                          ),
                        ),

                        // Transparent annotation + text-edit overlay
                        AnnotationOverlay(controller: _pdfController),
                      ],
                    ),
                  ),

                  // ── Right panels ───────────────────────────────────────
                  if (_showAnnotationsList)
                    const SizedBox(
                        width: 260, child: AnnotationsList()),
                  if (_showPropertiesPanel)
                    const SizedBox(
                        width: 280, child: PropertiesPanel()),
                ],
              ),
            ),

            // ── Bottom: page navigator ─────────────────────────────────
            PageNavigator(
              currentPage:   doc.currentPage,
              totalPages:    doc.totalPages,
              onPageChanged: (page) =>
                  _pdfController.goToPage(pageNumber: page),
            ),
          ],
        ),
      ),
    );
  }
}
