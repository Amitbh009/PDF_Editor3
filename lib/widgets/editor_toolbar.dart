import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import '../providers/pdf_provider.dart';

class EditorToolbar extends ConsumerWidget {
  const EditorToolbar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedTool = ref.watch(selectedToolProvider);
    final selectedColor = ref.watch(selectedColorProvider);
    final strokeWidth = ref.watch(strokeWidthProvider);
    final isBold = ref.watch(isBoldProvider);
    final isItalic = ref.watch(isItalicProvider);
    final theme = Theme.of(context);

    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border:
            Border(bottom: BorderSide(color: theme.dividerColor, width: 1)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            // Tool groups
            _toolGroup(ref, selectedTool, [
              _ToolDef(Icons.near_me_rounded, 'Select', EditorTool.select),
            ]),
            _divider(),
            _toolGroup(ref, selectedTool, [
              _ToolDef(Icons.text_fields_rounded, 'Text', EditorTool.text),
              _ToolDef(Icons.highlight_rounded, 'Highlight', EditorTool.highlight),
              _ToolDef(Icons.format_underline_rounded, 'Underline', EditorTool.underline),
              _ToolDef(Icons.strikethrough_s_rounded, 'Strikethrough', EditorTool.strikethrough),
            ]),
            _divider(),
            _toolGroup(ref, selectedTool, [
              _ToolDef(Icons.draw_rounded, 'Draw', EditorTool.freehand),
              _ToolDef(Icons.crop_square_rounded, 'Rectangle', EditorTool.rectangle),
              _ToolDef(Icons.circle_outlined, 'Circle', EditorTool.circle),
              _ToolDef(Icons.arrow_right_alt_rounded, 'Arrow', EditorTool.arrow),
            ]),
            _divider(),
            _toolGroup(ref, selectedTool, [
              _ToolDef(Icons.auto_fix_normal_rounded, 'Eraser', EditorTool.eraser),
            ]),
            _divider(),

            // Color picker
            Tooltip(
              message: 'Color',
              child: GestureDetector(
                onTap: () => _showColorPicker(context, ref, selectedColor),
                child: Container(
                  width: 30,
                  height: 30,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: Color(selectedColor),
                    borderRadius: BorderRadius.circular(6),
                    border:
                        Border.all(color: theme.dividerColor, width: 2),
                  ),
                ),
              ),
            ),

            _divider(),

            // Stroke width
            const Icon(Icons.line_weight_rounded, size: 18),
            SizedBox(
              width: 100,
              child: Slider(
                value: strokeWidth,
                min: 1,
                max: 20,
                divisions: 19,
                label: '${strokeWidth.round()}px',
                onChanged: (v) =>
                    ref.read(strokeWidthProvider.notifier).state = v,
              ),
            ),

            _divider(),

            // Bold / Italic (text tool only)
            _ToggleButton(
              icon: Icons.format_bold_rounded,
              label: 'Bold',
              active: isBold,
              onTap: () =>
                  ref.read(isBoldProvider.notifier).state = !isBold,
            ),
            _ToggleButton(
              icon: Icons.format_italic_rounded,
              label: 'Italic',
              active: isItalic,
              onTap: () =>
                  ref.read(isItalicProvider.notifier).state = !isItalic,
            ),

            _divider(),

            // Zoom
            IconButton(
              icon: const Icon(Icons.zoom_out_rounded, size: 20),
              onPressed: () {
                final z = ref.read(zoomLevelProvider) - 0.25;
                ref.read(zoomLevelProvider.notifier).state =
                    z.clamp(0.5, 5.0);
              },
              tooltip: 'Zoom Out',
            ),
            Consumer(builder: (_, ref, __) {
              final zoom = ref.watch(zoomLevelProvider);
              return SizedBox(
                width: 44,
                child: Text(
                  '${(zoom * 100).round()}%',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
              );
            }),
            IconButton(
              icon: const Icon(Icons.zoom_in_rounded, size: 20),
              onPressed: () {
                final z = ref.read(zoomLevelProvider) + 0.25;
                ref.read(zoomLevelProvider.notifier).state =
                    z.clamp(0.5, 5.0);
              },
              tooltip: 'Zoom In',
            ),
            IconButton(
              icon: const Icon(Icons.fit_screen_rounded, size: 20),
              onPressed: () =>
                  ref.read(zoomLevelProvider.notifier).state = 1.0,
              tooltip: 'Fit to screen',
            ),
          ],
        ),
      ),
    );
  }

  Widget _divider() => const VerticalDivider(width: 16, indent: 8, endIndent: 8);

  Widget _toolGroup(WidgetRef ref, EditorTool selected, List<_ToolDef> tools) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: tools.map((t) => _ToolBtn(
        icon: t.icon,
        label: t.label,
        isSelected: selected == t.tool,
        onTap: () => ref.read(selectedToolProvider.notifier).state = t.tool,
      )).toList(),
    );
  }

  void _showColorPicker(
      BuildContext ctx, WidgetRef ref, int currentColor) {
    Color pickerColor = Color(currentColor);
    showDialog(
      context: ctx,
      builder: (_) => AlertDialog(
        title: const Text('Pick a color'),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: pickerColor,
            onColorChanged: (c) => pickerColor = c,
            pickerAreaHeightPercent: 0.7,
            enableAlpha: true,
            displayThumbColor: true,
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              ref.read(selectedColorProvider.notifier).state =
                  pickerColor.value;
              Navigator.pop(ctx);
            },
            child: const Text('Select'),
          ),
        ],
      ),
    );
  }
}

class _ToolDef {
  final IconData icon;
  final String label;
  final EditorTool tool;
  const _ToolDef(this.icon, this.label, this.tool);
}

class _ToolBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _ToolBtn({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: label,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: isSelected
                ? theme.colorScheme.primaryContainer
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon,
              size: 22,
              color: isSelected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }
}

class _ToggleButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _ToggleButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: label,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: active
                ? theme.colorScheme.tertiaryContainer
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon,
              size: 22,
              color: active
                  ? theme.colorScheme.tertiary
                  : theme.colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }
}
