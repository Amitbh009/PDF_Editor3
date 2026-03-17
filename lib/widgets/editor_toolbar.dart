import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/pdf_provider.dart';

class EditorToolbar extends ConsumerWidget {
  const EditorToolbar({super.key});

  static const List<_ToolItem> _tools = <_ToolItem>[
    _ToolItem(Icons.near_me_rounded,          'Select (V)',       EditorTool.select),
    _ToolItem(Icons.text_fields_rounded,      'Text (T)',         EditorTool.text),
    _ToolItem(Icons.highlight_rounded,        'Highlight (H)',    EditorTool.highlight),
    _ToolItem(Icons.format_underline_rounded, 'Underline (U)',    EditorTool.underline),
    _ToolItem(Icons.strikethrough_s_rounded,  'Strikethrough',    EditorTool.strikethrough),
    _ToolItem(Icons.draw_rounded,             'Freehand (P)',     EditorTool.freehand),
    _ToolItem(Icons.crop_square_rounded,      'Rectangle (R)',    EditorTool.rectangle),
    _ToolItem(Icons.circle_outlined,          'Circle (C)',       EditorTool.circle),
    _ToolItem(Icons.arrow_right_alt_rounded,  'Arrow (A)',        EditorTool.arrow),
    _ToolItem(Icons.auto_fix_normal_rounded,  'Eraser (E)',       EditorTool.eraser),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedTool  = ref.watch(selectedToolProvider);
    final selectedColor = ref.watch(selectedColorProvider);
    final strokeWidth   = ref.watch(strokeWidthProvider);
    final canUndo       = ref.watch(canUndoProvider);
    final canRedo       = ref.watch(canRedoProvider);
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
                onTap: () =>
                    ref.read(selectedToolProvider.notifier).state = item.tool,
              ),
            ),

            const _VSep(),

            // ── Color swatch ───────────────────────────────────────────────
            Tooltip(
              message: 'Annotation color',
              child: GestureDetector(
                onTap: () => _showColorPicker(context, ref, selectedColor),
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

            // ── Font bold / italic (shown when text tool active) ───────────
            if (selectedTool == EditorTool.text) ...[
              _TextStyleToggle(
                icon: Icons.format_bold,
                tooltip: 'Bold',
                provider: isBoldProvider,
              ),
              _TextStyleToggle(
                icon: Icons.format_italic,
                tooltip: 'Italic',
                provider: isItalicProvider,
              ),
              const SizedBox(width: 4),
              Consumer(builder: (_, ref, __) {
                final fs = ref.watch(fontSizeProvider);
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.text_decrease, size: 18),
                      tooltip: 'Decrease font size',
                      onPressed: () {
                        final v = (fs - 2).clamp(8.0, 72.0);
                        ref.read(fontSizeProvider.notifier).state = v;
                      },
                    ),
                    Text('${fs.round()}pt',
                        style: theme.textTheme.labelSmall),
                    IconButton(
                      icon: const Icon(Icons.text_increase, size: 18),
                      tooltip: 'Increase font size',
                      onPressed: () {
                        final v = (fs + 2).clamp(8.0, 72.0);
                        ref.read(fontSizeProvider.notifier).state = v;
                      },
                    ),
                  ],
                );
              }),
              const _VSep(),
            ],

            // ── Stroke width ───────────────────────────────────────────────
            if (selectedTool != EditorTool.text &&
                selectedTool != EditorTool.select) ...[
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
            ],

            // ── Zoom ───────────────────────────────────────────────────────
            IconButton(
              icon: const Icon(Icons.zoom_out_rounded, size: 20),
              tooltip: 'Zoom Out',
              onPressed: () {
                final z = ref.read(zoomLevelProvider) - 0.25;
                ref.read(zoomLevelProvider.notifier).state = z.clamp(0.5, 5.0);
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
                ref.read(zoomLevelProvider.notifier).state = z.clamp(0.5, 5.0);
              },
            ),

            const _VSep(),

            // ── Undo / Redo — FULLY WIRED ────────────────────────────────
            IconButton(
              icon: Icon(
                Icons.undo_rounded,
                size: 20,
                color: canUndo
                    ? theme.colorScheme.onSurface
                    : theme.colorScheme.onSurface.withValues(alpha: 0.3),
              ),
              tooltip: canUndo ? 'Undo (Ctrl+Z)' : 'Nothing to undo',
              onPressed: canUndo
                  ? () => ref.read(currentDocumentProvider.notifier).undo()
                  : null,
            ),
            IconButton(
              icon: Icon(
                Icons.redo_rounded,
                size: 20,
                color: canRedo
                    ? theme.colorScheme.onSurface
                    : theme.colorScheme.onSurface.withValues(alpha: 0.3),
              ),
              tooltip: canRedo ? 'Redo (Ctrl+Y)' : 'Nothing to redo',
              onPressed: canRedo
                  ? () => ref.read(currentDocumentProvider.notifier).redo()
                  : null,
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

  void _showColorPicker(BuildContext ctx, WidgetRef ref, int currentColor) {
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
              // ignore: deprecated_member_use
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
          'You can Undo afterwards.',
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

// ── Internal widgets ──────────────────────────────────────────────────────────

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

/// Toggle button that reads/writes a bool StateProvider.
class _TextStyleToggle extends ConsumerWidget {
  const _TextStyleToggle({
    required this.icon,
    required this.tooltip,
    required this.provider,
  });

  final IconData              icon;
  final String                tooltip;
  final StateProvider<bool>   provider;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(provider);
    final theme  = Theme.of(context);
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: () => ref.read(provider.notifier).state = !active,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          margin:  const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: active
                ? theme.colorScheme.primaryContainer
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: active
                ? Border.all(
                    color: theme.colorScheme.primary.withValues(alpha: 0.4))
                : null,
          ),
          child: Icon(icon,
              size: 20,
              color: active
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }
}
