import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/pdf_provider.dart';

class PropertiesPanel extends ConsumerWidget {
  const PropertiesPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme         = Theme.of(context);
    final strokeWidth   = ref.watch(strokeWidthProvider);
    final fontSize      = ref.watch(fontSizeProvider);
    final opacity       = ref.watch(opacityProvider);
    final selectedColor = ref.watch(selectedColorProvider);
    final doc           = ref.watch(currentDocumentProvider);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(left: BorderSide(color: theme.dividerColor)),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              border:
                  Border(bottom: BorderSide(color: theme.dividerColor)),
            ),
            child: const Row(
              children: [
                Icon(Icons.tune_rounded, size: 18),
                SizedBox(width: 8),
                Text(
                  'Properties',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ],
            ),
          ),

          // Controls
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const _Label(text: 'Color'),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () =>
                      _showColorPicker(context, ref, selectedColor),
                  child: Container(
                    height: 44,
                    decoration: BoxDecoration(
                      color: Color(selectedColor),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: theme.dividerColor),
                    ),
                    child: Center(
                      child: Text(
                        '#${selectedColor.toRadixString(16).padLeft(8, '0').toUpperCase().substring(2)}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          shadows: [
                            Shadow(blurRadius: 4, color: Colors.black54),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 20),
                const _Label(text: 'Stroke Width'),
                Row(
                  children: [
                    Expanded(
                      child: Slider(
                        value: strokeWidth,
                        min: 1,
                        max: 20,
                        divisions: 19,
                        onChanged: (v) => ref
                            .read(strokeWidthProvider.notifier)
                            .state = v,
                      ),
                    ),
                    SizedBox(
                      width: 36,
                      child: Text('${strokeWidth.round()}',
                          style: theme.textTheme.labelMedium,
                          textAlign: TextAlign.right),
                    ),
                  ],
                ),

                const SizedBox(height: 12),
                const _Label(text: 'Font Size'),
                Row(
                  children: [
                    Expanded(
                      child: Slider(
                        value: fontSize,
                        min: 8,
                        max: 72,
                        divisions: 32,
                        onChanged: (v) =>
                            ref.read(fontSizeProvider.notifier).state = v,
                      ),
                    ),
                    SizedBox(
                      width: 36,
                      child: Text('${fontSize.round()}',
                          style: theme.textTheme.labelMedium,
                          textAlign: TextAlign.right),
                    ),
                  ],
                ),

                const SizedBox(height: 12),
                const _Label(text: 'Opacity'),
                Row(
                  children: [
                    Expanded(
                      child: Slider(
                        value: opacity,
                        min: 0.1,
                        max: 1.0,
                        divisions: 18,
                        onChanged: (v) =>
                            ref.read(opacityProvider.notifier).state = v,
                      ),
                    ),
                    SizedBox(
                      width: 44,
                      child: Text('${(opacity * 100).round()}%',
                          style: theme.textTheme.labelMedium,
                          textAlign: TextAlign.right),
                    ),
                  ],
                ),

                const Divider(height: 32),

                if (doc != null) ...[
                  const _Label(text: 'Document Info'),
                  const SizedBox(height: 8),
                  _InfoRow(label: 'File',        value: doc.fileName),
                  _InfoRow(label: 'Pages',       value: '${doc.totalPages}'),
                  _InfoRow(label: 'Annotations', value: '${doc.annotations.length}'),
                  _InfoRow(label: 'Current',     value: 'Page ${doc.currentPage}'),
                  _InfoRow(label: 'Modified',    value: doc.isModified ? 'Yes' : 'No'),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showColorPicker(
      BuildContext ctx, WidgetRef ref, int currentColor) {
    Color picked = Color(currentColor);
    showDialog<void>(
      context: ctx,
      builder: (_) => AlertDialog(
        title: const Text('Pick a color'),
        content: SizedBox(
          width: 300,
          child: ColorPicker(
            pickerColor: picked,
            onColorChanged: (c) => picked = c,
            pickerAreaHeightPercent: 0.7,
            enableAlpha: true,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              ref.read(selectedColorProvider.notifier).state = picked.value;
              Navigator.pop(ctx);
            },
            child: const Text('Select'),
          ),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
            ),
      );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Text(
              '$label:',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurfaceVariant,
                  ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                value,
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
}
