import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/pdf_provider.dart';

class EditorToolbar extends ConsumerWidget {
  const EditorToolbar({super.key});

  static const List<_ToolItem> _tools = <_ToolItem>[
    _ToolItem(Icons.near_me_rounded,         'Select',        EditorTool.select),
    _ToolItem(Icons.text_fields_rounded,     'Text',          EditorTool.text),
    _ToolItem(Icons.highlight_rounded,       'Highlight',     EditorTool.highlight),
    _ToolItem(Icons.format_underline_rounded,'Underline',     EditorTool.underline),
    _ToolItem(Icons.strikethrough_s_rounded, 'Strikethrough', EditorTool.strikethrough),
    _ToolItem(Icons.draw_rounded,            'Freehand',      EditorTool.freehand),
    _ToolItem(Icons.crop_square_rounded,     'Rectangle',     EditorTool.rectangle),
    _ToolItem(Icons.circle_outlined,         'Circle',        EditorTool.circle),
    _ToolItem(Icons.arrow_right_alt_rounded, 'Arrow',         EditorTool.arrow),
    _ToolItem(Icons.auto_fix_normal_rounded, 'Eraser',        EditorTool.eraser),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedTool  = ref.watch(selectedToolProvider);
    final selectedColor = ref.watch(selectedColorProvider);
    final strokeWidth   = ref.watch(strokeWidthProvider);
    final theme         = Theme.of(context);

    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            ..._tools.map(
              (item) => _ToolButton(
                icon:       item.icon,
                label:      item.label,
                tool:       item.tool,
                isSelected: selectedTool == item.tool,
                onTap: () => ref
                    .read(selectedToolProvider.notifier)
                    .state = item.tool,
              ),
            ),

            const _VSep(),

            // ── Color swatch ──────────────────────────────────────────────
            Tooltip(
              message: 'Annotation color',
              child: GestureDetector(
                onTap: () =>
                    _showColorPicker(context, ref, selectedColor),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Color(selectedColor),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                        color: theme.colorScheme.outline, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: Color(selectedColor).withValues(alpha: 0.4),
                        blurRadius: 4,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(width: 10),

            Text(
              '${strokeWidth.round()}px',
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            SizedBox(
              width: 120,
              child: Slider(
                value: strokeWidth,
                min: 1,
                max: 20,
                divisions: 19,
                onChanged: (v) =>
                    ref.read(strokeWidthProvider.notifier).state = v,
              ),
            ),

            const _VSep(),

            // ── Zoom ──────────────────────────────────────────────────────
            IconButton(
              icon: const Icon(Icons.zoom_out_rounded, size: 20),
              tooltip: 'Zoom Out',
              onPressed: () {
                final z = ref.read(zoomLevelProvider) - 0.25;
                ref.read(zoomLevelProvider.notifier).state =
                    z.clamp(0.5, 5.0);
              },
            ),
            Consumer(
              builder: (_, ref, __) {
                final zoom = ref.watch(zoomLevelProvider);
                return SizedBox(
                  width: 44,
                  child: Text(
                    '${(zoom * 100).round()}%',
                    style: theme.textTheme.labelSmall,
                    textAlign: TextAlign.center,
                  ),
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.zoom_in_rounded, size: 20),
              tooltip: 'Zoom In',
              onPressed: () {
                final z = ref.read(zoomLevelProvider) + 0.25;
                ref.read(zoomLevelProvider.notifier).state =
                    z.clamp(0.5, 5.0);
              },
            ),

            const _VSep(),

            const IconButton(
              icon: Icon(Icons.undo_rounded, size: 20),
              tooltip: 'Undo',
              onPressed: null,
            ),
            const IconButton(
              icon: Icon(Icons.redo_rounded, size: 20),
              tooltip: 'Redo',
              onPressed: null,
            ),

            const _VSep(),

            Tooltip(
              message: 'Clear all annotations',
              child: IconButton(
                icon: const Icon(Icons.layers_clear_rounded, size: 20),
                onPressed: () => _confirmClear(context, ref),
              ),
            ),
          ],
        ),
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
              # ignore: deprecated_member_use
              ref.read(selectedColorProvider.notifier).state = picked.value;
              Navigator.pop(ctx);
            },
            child: const Text('Select'),
          ),
        ],
      ),
    );
  }

  void _confirmClear(BuildContext ctx, WidgetRef ref) {
    showDialog<void>(
      context: ctx,
      builder: (_) => AlertDialog(
        title: const Text('Clear annotations?'),
        content: const Text(
          'All annotations on this document will be removed. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              ref
                  .read(currentDocumentProvider.notifier)
                  .deleteAllAnnotations();
              Navigator.pop(ctx);
            },
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );
  }
}

// ── Internal classes ──────────────────────────────────────────────────────────

class _ToolItem {
  const _ToolItem(this.icon, this.label, this.tool);

  final IconData   icon;
  final String     label;
  final EditorTool tool;
}

class _VSep extends StatelessWidget {
  const _VSep();

  @override
  Widget build(BuildContext context) => const SizedBox(
      width: 4,
      child: VerticalDivider(width: 8, indent: 8, endIndent: 8));
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.label,
    required this.tool,
    required this.isSelected,
    required this.onTap,
  });

  final IconData     icon;
  final String       label;
  final EditorTool   tool;
  final bool         isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: label,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin:  const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: isSelected
                ? theme.colorScheme.primaryContainer
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: isSelected
                ? Border.all(
                    color: theme.colorScheme.primary.withValues(alpha: 0.4),
                    width: 1,
                  )
                : null,
          ),
          child: Icon(
            icon,
            size: 22,
            color: isSelected
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
