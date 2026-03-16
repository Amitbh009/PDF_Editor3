import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/pdf_provider.dart';

class PropertiesPanel extends ConsumerWidget {
  const PropertiesPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final strokeWidth = ref.watch(strokeWidthProvider);
    final fontSize = ref.watch(fontSizeProvider);
    final color = ref.watch(selectedColorProvider);

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
              border:
                  Border(bottom: BorderSide(color: theme.dividerColor)),
            ),
            child: Row(
              children: [
                Text('Properties',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const Spacer(),
                Icon(Icons.tune_rounded,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _Section(
                  label: 'Stroke Width',
                  child: Column(
                    children: [
                      Slider(
                        value: strokeWidth,
                        min: 1,
                        max: 20,
                        divisions: 19,
                        label: '${strokeWidth.round()}px',
                        onChanged: (v) =>
                            ref.read(strokeWidthProvider.notifier).state = v,
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('1px',
                              style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant)),
                          Text('${strokeWidth.round()}px',
                              style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.primary,
                                  fontWeight: FontWeight.bold)),
                          Text('20px',
                              style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant)),
                        ],
                      ),
                    ],
                  ),
                ),
                _Section(
                  label: 'Font Size',
                  child: Column(
                    children: [
                      Slider(
                        value: fontSize,
                        min: 8,
                        max: 96,
                        divisions: 44,
                        label: '${fontSize.round()}pt',
                        onChanged: (v) =>
                            ref.read(fontSizeProvider.notifier).state = v,
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('8pt',
                              style: theme.textTheme.bodySmall),
                          Text('${fontSize.round()}pt',
                              style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.primary,
                                  fontWeight: FontWeight.bold)),
                          Text('96pt',
                              style: theme.textTheme.bodySmall),
                        ],
                      ),
                    ],
                  ),
                ),
                _Section(
                  label: 'Text Style',
                  child: Row(
                    children: [
                      Consumer(builder: (_, ref, __) {
                        final isBold = ref.watch(isBoldProvider);
                        return _StyleChip(
                          label: 'B',
                          active: isBold,
                          bold: true,
                          onTap: () => ref
                              .read(isBoldProvider.notifier)
                              .state = !isBold,
                        );
                      }),
                      const SizedBox(width: 8),
                      Consumer(builder: (_, ref, __) {
                        final isItalic = ref.watch(isItalicProvider);
                        return _StyleChip(
                          label: 'I',
                          active: isItalic,
                          italic: true,
                          onTap: () => ref
                              .read(isItalicProvider.notifier)
                              .state = !isItalic,
                        );
                      }),
                    ],
                  ),
                ),
                _Section(
                  label: 'Current Color',
                  child: Container(
                    height: 40,
                    decoration: BoxDecoration(
                      color: Color(color),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: theme.dividerColor),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _Section(
                  label: 'Quick Colors',
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      0xFFFF0000, 0xFF00AA00, 0xFF0000FF,
                      0xFFFFAA00, 0xFF9C27B0, 0xFF000000,
                      0xFFFFFFFF, 0xFF607D8B,
                    ].map((c) => GestureDetector(
                      onTap: () =>
                          ref.read(selectedColorProvider.notifier).state = c,
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: Color(c),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: color == c
                                ? theme.colorScheme.primary
                                : theme.dividerColor,
                            width: color == c ? 3 : 1,
                          ),
                        ),
                      ),
                    )).toList(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String label;
  final Widget child;
  const _Section({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class _StyleChip extends StatelessWidget {
  final String label;
  final bool active;
  final bool bold;
  final bool italic;
  final VoidCallback onTap;

  const _StyleChip({
    required this.label,
    required this.active,
    this.bold = false,
    this.italic = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: active
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: active
                ? theme.colorScheme.primary
                : theme.dividerColor,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            fontStyle: italic ? FontStyle.italic : FontStyle.normal,
            color: active
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurface,
          ),
        ),
      ),
    );
  }
}
