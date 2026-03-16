import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/annotation_model.dart';
import '../providers/pdf_provider.dart';

class AnnotationsList extends ConsumerWidget {
  const AnnotationsList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final doc   = ref.watch(currentDocumentProvider);
    final theme = Theme.of(context);
    if (doc == null) return const SizedBox.shrink();

    final annotations = doc.annotations
        .where((a) => a.pageNumber == doc.currentPage)
        .toList();

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(left: BorderSide(color: theme.dividerColor)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainer,
              border: Border(bottom: BorderSide(color: theme.dividerColor)),
            ),
            child: Row(
              children: [
                Text(
                  'Annotations',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${annotations.length}',
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const Spacer(),
                if (annotations.isNotEmpty)
                  TextButton(
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: const Text('Clear All'),
                        content: const Text(
                            'Remove all annotations on this page?'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Cancel'),
                          ),
                          FilledButton(
                            onPressed: () {
                              ref
                                  .read(currentDocumentProvider.notifier)
                                  .deleteAllOnPage(doc.currentPage);
                              Navigator.pop(context);
                            },
                            child: const Text('Clear'),
                          ),
                        ],
                      ),
                    ),
                    child: const Text('Clear all',
                        style: TextStyle(fontSize: 12)),
                  ),
              ],
            ),
          ),
          Expanded(
            child: annotations.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.layers_clear_rounded,
                          size: 40,
                          color: theme.colorScheme.onSurfaceVariant
                              // ignore: deprecated_member_use
                              .withValues(alpha: 0.4),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'No annotations',
                          style: theme.textTheme.bodySmall?.copyWith(
                              color:
                                  theme.colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(8),
                    itemCount: annotations.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: 4),
                    itemBuilder: (_, i) =>
                        _AnnotationTile(annotation: annotations[i]),
                  ),
          ),
        ],
      ),
    );
  }
}

class _AnnotationTile extends ConsumerWidget {
  const _AnnotationTile({required this.annotation});

  final AnnotationModel annotation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.dividerColor),
      ),
      child: ListTile(
        dense: true,
        leading: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            // ignore: deprecated_member_use
            color: Color(annotation.color).withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(
            _iconForType(annotation.type),
            size: 16,
            color: Color(annotation.color),
          ),
        ),
        title: Text(
          _labelForType(annotation.type),
          style: theme.textTheme.bodySmall
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        subtitle: annotation.content.isNotEmpty
            ? Text(
                annotation.content,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant),
              )
            : null,
        trailing: IconButton(
          icon: Icon(Icons.delete_rounded,
              size: 18, color: theme.colorScheme.error),
          onPressed: () => ref
              .read(currentDocumentProvider.notifier)
              .deleteAnnotation(annotation.id),
          tooltip: 'Delete',
        ),
      ),
    );
  }

  IconData _iconForType(AnnotationType t) {
    switch (t) {
      case AnnotationType.text:          return Icons.text_fields_rounded;
      case AnnotationType.highlight:     return Icons.highlight_rounded;
      case AnnotationType.underline:     return Icons.format_underline_rounded;
      case AnnotationType.strikethrough: return Icons.strikethrough_s_rounded;
      case AnnotationType.freehand:      return Icons.draw_rounded;
      case AnnotationType.rectangle:     return Icons.crop_square_rounded;
      case AnnotationType.circle:        return Icons.circle_outlined;
      case AnnotationType.arrow:         return Icons.arrow_right_alt_rounded;
      default:                           return Icons.layers_rounded;
    }
  }

  String _labelForType(AnnotationType t) =>
      t.name[0].toUpperCase() + t.name.substring(1);
}
