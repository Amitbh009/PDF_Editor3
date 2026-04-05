import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/pdf_provider.dart';

class EditorToolbar extends ConsumerWidget {
  const EditorToolbar({super.key});

  // Tool list — editText is inserted as the second tool (after select)
  static const List<_ToolItem> _tools = <_ToolItem>[
    _ToolItem(Icons.near_me_rounded,          'Select (V)',         EditorTool.select),
    _ToolItem(Icons.edit_note_rounded,        'Edit PDF Text (W)',  EditorTool.editText),
    _ToolItem(Icons.text_fields_rounded,      'Add Text (T)',       EditorTool.text),
    _ToolItem(Icons.highlight_rounded,        'Highlight (H)',      EditorTool.highlight),
    _ToolItem(Icons.format_underline_rounded, 'Underline (U)',      EditorTool.underline),
    _ToolItem(Icons.strikethrough_s_rounded,  'Strikethrough',      EditorTool.strikethrough),
    _ToolItem(Icons.draw_rounded,             'Freehand (P)',       EditorTool.freehand),
    _ToolItem(Icons.crop_square_rounded,      'Rectangle (R)',      EditorTool.rectangle),
    _ToolItem(Icons.circle_outlined,          'Circle (C)',         EditorTool.circle),
    _ToolItem(Icons.arrow_right_alt_rounded,  'Arrow (A)',          EditorTool.arrow),
    _ToolItem(Icons.auto_fix_normal_rounded,  'Eraser (E)',         EditorTool.eraser),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedTool  = ref.watch(selectedToolProvider);
    final selectedColor = ref.watch(selectedColorProvider);
    final strokeWidth   = ref.watch(strokeWidthProvider);
    final canUndo       = ref.watch(canUndoProvider);
    final canRedo       = ref.watch(canRedoProvider);
    final theme         = Theme.of(context);
    final isEditText    = selectedTool == EditorTool.editText;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
      // ── Context hint banner (shown only in Edit Text mode) ─────────────
      if (isEditText)
        Container(
          width:   double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          color:   const Color(0xFF1565C0),
          child: Row(
            children: [
              const Icon(Icons.touch_app_rounded, size: 13, color: Colors.white70),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  'Click any blue-outlined text block to edit it in-place  •  '
                  'Use the formatting toolbar to change font size, bold, italic, or colour  •  '
                  'Find & Replace available in the editor popup',
                  style: TextStyle(fontSize: 10, color: Colors.white70),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),

      // ── Main toolbar row ───────────────────────────────────────────────
      Container(
      height: 56,
      decoration: BoxDecoration(
        color:  theme.colorScheme.surfaceContainerHighest,
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            // ── Tool buttons ────────────────────────────────────────────
            ..._tools.map(
              (item) => _ToolButton(
                icon:       item.icon,
                label:      item.label,
                tool:       item.tool,
                isSelected: selectedTool == item.tool,
                // Highlight the editText button in blue when active
                accentColor: item.tool == EditorTool.editText
                    ? Colors.blue
                    : null,
                onTap: () =>
                    ref.read(selectedToolProvider.notifier).state = item.tool,
              ),
            ),

            const _VSep(),

            // ── Color swatch ────────────────────────────────────────────
            Tooltip(
              message: 'Annotation color',
              child: GestureDetector(
                onTap: () => _showColorPicker(context, ref, selectedColor),
                child: Container(
                  width:  32,
                  height: 32,
                  decoration: BoxDecoration(
                    color:        Color(selectedColor),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                        color: theme.colorScheme.outline, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color:       Color(selectedColor).withValues(alpha: 0.4),
                        blurRadius:  4,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(width: 12),

            // ── Stroke width ────────────────────────────────────────────
            SizedBox(
              width: 90,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Width: ${strokeWidth.round()}',
                      style: const TextStyle(fontSize: 9)),
                  Slider(
                    value:    strokeWidth,
                    min:      1,
                    max:      20,
                    divisions: 19,
                    onChanged: (v) =>
                        ref.read(strokeWidthProvider.notifier).state = v,
                  ),
                ],
              ),
            ),

            const _VSep(),

            // ── Bold / Italic ────────────────────────────────────────────
            _ToggleBtn(
              icon:       Icons.format_bold_rounded,
              label:      'Bold',
              isActive:   ref.watch(isBoldProvider),
              onPressed:  () =>
                  ref.read(isBoldProvider.notifier).state =
                      !ref.read(isBoldProvider),
            ),
            _ToggleBtn(
              icon:       Icons.format_italic_rounded,
              label:      'Italic',
              isActive:   ref.watch(isItalicProvider),
              onPressed:  () =>
                  ref.read(isItalicProvider.notifier).state =
                      !ref.read(isItalicProvider),
            ),

            const _VSep(),

            // ── Undo / Redo ──────────────────────────────────────────────
            IconButton(
              icon:      const Icon(Icons.undo_rounded),
              tooltip:   'Undo (Ctrl+Z)',
              onPressed: canUndo
                  ? () => ref
                      .read(currentDocumentProvider.notifier)
                      .undo()
                  : null,
            ),
            IconButton(
              icon:      const Icon(Icons.redo_rounded),
              tooltip:   'Redo (Ctrl+Y)',
              onPressed: canRedo
                  ? () => ref
                      .read(currentDocumentProvider.notifier)
                      .redo()
                  : null,
            ),

            const SizedBox(width: 8),
          ],
        ),
      ),
    ), // end main toolbar Container
    ], // end Column children
    ); // end Column
  }

  void _showColorPicker(
      BuildContext ctx, WidgetRef ref, int currentColor) {
    Color picked = Color(currentColor);
    showDialog<void>(
      context: ctx,
      builder: (_) => AlertDialog(
        title:   const Text('Pick a colour'),
        content: SizedBox(
          width: 300,
          child: ColorPicker(
            pickerColor:            picked,
            onColorChanged:         (c) => picked = c,
            pickerAreaHeightPercent: 0.7,
            enableAlpha:            true,
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
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
}

// ── Private helpers ────────────────────────────────────────────────────────────

class _ToolItem {
  const _ToolItem(this.icon, this.label, this.tool);
  final IconData   icon;
  final String     label;
  final EditorTool tool;
}

class _VSep extends StatelessWidget {
  const _VSep();
  @override
  Widget build(BuildContext context) => Container(
        width:  1,
        height: 32,
        margin: const EdgeInsets.symmetric(horizontal: 6),
        color:  Theme.of(context).dividerColor,
      );
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.label,
    required this.tool,
    required this.isSelected,
    required this.onTap,
    this.accentColor,
  });

  final IconData   icon;
  final String     label;
  final EditorTool tool;
  final bool       isSelected;
  final VoidCallback onTap;
  final Color?     accentColor;

  @override
  Widget build(BuildContext context) {
    final theme    = Theme.of(context);
    final hiColor  = accentColor ?? theme.colorScheme.primary;
    return Tooltip(
      message: label,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration:    const Duration(milliseconds: 150),
          margin:      const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
          padding:     const EdgeInsets.symmetric(horizontal: 10),
          decoration:  BoxDecoration(
            color:        isSelected
                ? hiColor.withValues(alpha: 0.15)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border:       isSelected
                ? Border.all(color: hiColor.withValues(alpha: 0.6))
                : null,
          ),
          child: Icon(
            icon,
            size:  20,
            color: isSelected ? hiColor : theme.colorScheme.onSurface,
          ),
        ),
      ),
    );
  }
}

class _ToggleBtn extends StatelessWidget {
  const _ToggleBtn({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onPressed,
  });

  final IconData    icon;
  final String      label;
  final bool        isActive;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: label,
      child: IconButton(
        icon:     Icon(icon, size: 20),
        color:    isActive ? theme.colorScheme.primary : null,
        onPressed: onPressed,
      ),
    );
  }
}
