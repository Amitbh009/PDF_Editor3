import 'package:flutter/material.dart';

class PageNavigator extends StatelessWidget {
  const PageNavigator({
    super.key,
    required this.currentPage,
    required this.totalPages,
    required this.onPageChanged,
  });

  final int currentPage;
  final int totalPages;
  final ValueChanged<int> onPageChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.first_page_rounded),
            onPressed:
                currentPage > 1 ? () => onPageChanged(1) : null,
            tooltip: 'First page',
          ),
          IconButton(
            icon: const Icon(Icons.chevron_left_rounded),
            onPressed: currentPage > 1
                ? () => onPageChanged(currentPage - 1)
                : null,
            tooltip: 'Previous page',
          ),
          const SizedBox(width: 8),
          Text('Page ', style: theme.textTheme.bodyMedium),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '$currentPage',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          Text(' of $totalPages', style: theme.textTheme.bodyMedium),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.chevron_right_rounded),
            onPressed: currentPage < totalPages
                ? () => onPageChanged(currentPage + 1)
                : null,
            tooltip: 'Next page',
          ),
          IconButton(
            icon: const Icon(Icons.last_page_rounded),
            onPressed: currentPage < totalPages
                ? () => onPageChanged(totalPages)
                : null,
            tooltip: 'Last page',
          ),
        ],
      ),
    );
  }
}
