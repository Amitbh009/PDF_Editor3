import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class PageNavigator extends StatefulWidget {
  final int currentPage;
  final int totalPages;
  final ValueChanged<int> onPageChanged;

  const PageNavigator({
    super.key,
    required this.currentPage,
    required this.totalPages,
    required this.onPageChanged,
  });

  @override
  State<PageNavigator> createState() => _PageNavigatorState();
}

class _PageNavigatorState extends State<PageNavigator> {
  late TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: '${widget.currentPage}');
  }

  @override
  void didUpdateWidget(PageNavigator old) {
    super.didUpdateWidget(old);
    if (old.currentPage != widget.currentPage) {
      _ctrl.text = '${widget.currentPage}';
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submitPage() {
    final v = int.tryParse(_ctrl.text);
    if (v != null && v >= 1 && v <= widget.totalPages) {
      widget.onPageChanged(v);
    } else {
      _ctrl.text = '${widget.currentPage}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border:
            Border(top: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.first_page_rounded),
            onPressed: widget.currentPage > 1
                ? () => widget.onPageChanged(1)
                : null,
            tooltip: 'First page',
          ),
          IconButton(
            icon: const Icon(Icons.chevron_left_rounded),
            onPressed: widget.currentPage > 1
                ? () => widget.onPageChanged(widget.currentPage - 1)
                : null,
            tooltip: 'Previous page',
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 48,
            height: 32,
            child: TextField(
              controller: _ctrl,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
              decoration: InputDecoration(
                contentPadding: const EdgeInsets.symmetric(vertical: 4),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
                isDense: true,
              ),
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onSubmitted: (_) => _submitPage(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              'of ${widget.totalPages}',
              style: theme.textTheme.bodyMedium,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right_rounded),
            onPressed: widget.currentPage < widget.totalPages
                ? () => widget.onPageChanged(widget.currentPage + 1)
                : null,
            tooltip: 'Next page',
          ),
          IconButton(
            icon: const Icon(Icons.last_page_rounded),
            onPressed: widget.currentPage < widget.totalPages
                ? () => widget.onPageChanged(widget.totalPages)
                : null,
            tooltip: 'Last page',
          ),
        ],
      ),
    );
  }
}
