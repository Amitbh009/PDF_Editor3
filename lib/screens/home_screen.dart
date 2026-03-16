import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/pdf_provider.dart';
import 'editor_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  // Returns void so callers never get an unawaited Future warning.
  void _openPdf(BuildContext context, WidgetRef ref) {
    _doOpen(context, ref);
  }

  Future<void> _doOpen(BuildContext context, WidgetRef ref) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (result == null || result.files.single.path == null) return;
    if (!context.mounted) return;

    await ref
        .read(currentDocumentProvider.notifier)
        .openDocument(result.files.single.path!);

    if (!context.mounted) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(builder: (_) => const EditorScreen()),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final size  = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ──────────────────────────────────────────────────
              Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          theme.colorScheme.primary,
                          theme.colorScheme.secondary,
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.picture_as_pdf_rounded,
                      color: Colors.white,
                      size: 30,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'PDF Editor',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Edit, annotate & sign PDFs',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 32),

              // ── Drop zone ────────────────────────────────────────────────
              Expanded(
                flex: 5,
                child: GestureDetector(
                  onTap: () => _openPdf(context, ref),
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      border: Border.all(
                        // ignore: deprecated_member_use
                        color: theme.colorScheme.primary.withOpacity(0.5),
                        width: 2.5,
                      ),
                      borderRadius: BorderRadius.circular(24),
                      gradient: LinearGradient(
                        colors: [
                          // ignore: deprecated_member_use
                          theme.colorScheme.primaryContainer.withOpacity(0.4),
                          // ignore: deprecated_member_use
                          theme.colorScheme.secondaryContainer.withOpacity(0.2),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 96,
                          height: 96,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primaryContainer,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.upload_file_rounded,
                            size: 52,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'Open a PDF to Edit',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Tap anywhere to browse files',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Supported: .pdf',
                          style: theme.textTheme.bodySmall?.copyWith(
                            // ignore: deprecated_member_use
                            color: theme.colorScheme.onSurfaceVariant
                                .withOpacity(0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // ── Feature grid ─────────────────────────────────────────────
              Expanded(
                flex: 3,
                child: GridView.count(
                  crossAxisCount: size.width > 600 ? 6 : 3,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.1,
                  physics: const NeverScrollableScrollPhysics(),
                  children: const [
                    _FeatureTile(
                      icon: Icons.text_fields_rounded,
                      label: 'Add Text',
                      color: Color(0xFF6C63FF),
                    ),
                    _FeatureTile(
                      icon: Icons.highlight_rounded,
                      label: 'Highlight',
                      color: Color(0xFFFFB300),
                    ),
                    _FeatureTile(
                      icon: Icons.draw_rounded,
                      label: 'Draw',
                      color: Color(0xFF00B894),
                    ),
                    _FeatureTile(
                      icon: Icons.crop_square_rounded,
                      label: 'Shapes',
                      color: Color(0xFFE17055),
                    ),
                    _FeatureTile(
                      icon: Icons.delete_rounded,
                      label: 'Erase',
                      color: Color(0xFFD63031),
                    ),
                    _FeatureTile(
                      icon: Icons.save_alt_rounded,
                      label: 'Export',
                      color: Color(0xFF0984E3),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // ── Open button ──────────────────────────────────────────────
              SizedBox(
                width: double.infinity,
                height: 56,
                child: FilledButton.icon(
                  onPressed: () => _openPdf(context, ref),
                  icon: const Icon(Icons.folder_open_rounded),
                  label: const Text(
                    'Browse & Open PDF',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeatureTile extends StatelessWidget {
  const _FeatureTile({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        // ignore: deprecated_member_use
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(14),
        // ignore: deprecated_member_use
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 6),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
