import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import '../providers/pdf_provider.dart';
import 'editor_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  Future<void> _openPdf(BuildContext context, WidgetRef ref) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (result != null && result.files.single.path != null) {
      await ref
          .read(currentDocumentProvider.notifier)
          .openDocument(result.files.single.path!);
      if (context.mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const EditorScreen()),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.picture_as_pdf_rounded,
                        color: theme.colorScheme.primary, size: 28),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('PDF Editor',
                          style: theme.textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      Text('Edit, annotate & sign PDFs',
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant)),
                    ],
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.brightness_6_rounded),
                    onPressed: () {},
                    tooltip: 'Toggle theme',
                  ),
                ],
              ),
              const Spacer(),
              Center(
                child: GestureDetector(
                  onTap: () => _openPdf(context, ref),
                  child: Container(
                    width: double.infinity,
                    height: 260,
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: theme.colorScheme.primary.withOpacity(0.4),
                        width: 2,
                      ),
                      borderRadius: BorderRadius.circular(20),
                      color: theme.colorScheme.primaryContainer.withOpacity(0.2),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.upload_file_rounded,
                            size: 72, color: theme.colorScheme.primary),
                        const SizedBox(height: 16),
                        Text('Open a PDF',
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.primary,
                            )),
                        const SizedBox(height: 8),
                        Text('Tap to browse files',
                            style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 32),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: const [
                  _FeatureChip(icon: Icons.text_fields, label: 'Add Text'),
                  _FeatureChip(icon: Icons.highlight, label: 'Highlight'),
                  _FeatureChip(icon: Icons.draw_rounded, label: 'Draw'),
                  _FeatureChip(icon: Icons.crop_square, label: 'Shapes'),
                  _FeatureChip(icon: Icons.save_alt_rounded, label: 'Export'),
                  _FeatureChip(icon: Icons.format_underline, label: 'Underline'),
                ],
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: FilledButton.icon(
                  onPressed: () => _openPdf(context, ref),
                  icon: const Icon(Icons.folder_open_rounded),
                  label: const Text('Browse Files'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeatureChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _FeatureChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.onSecondaryContainer),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSecondaryContainer,
                fontWeight: FontWeight.w500,
              )),
        ],
      ),
    );
  }
}
