import 'package:flutter/material.dart';

/// Contextual help with one dismiss action. [content] should have natural height;
/// the dialog provides scrolling for long text and small screens.
class InfoIconButton extends StatefulWidget {
  const InfoIconButton({
    super.key,
    required this.title,
    required this.content,
    required this.tooltip,
    this.closeLabel = 'Entendido',
  });

  final String title;
  final Widget content;
  final String tooltip;
  final String closeLabel;

  @override
  State<InfoIconButton> createState() => _InfoIconButtonState();
}

class _InfoIconButtonState extends State<InfoIconButton> {
  bool _dialogOpen = false;

  Future<void> _showInfo() async {
    if (_dialogOpen) return;
    _dialogOpen = true;
    FocusScope.of(context).unfocus();
    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          scrollable: true,
          title: Text(widget.title),
          content: widget.content,
          actions: [
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(widget.closeLabel),
            ),
          ],
        ),
      );
    } finally {
      _dialogOpen = false;
    }
  }

  @override
Widget build(BuildContext context) => IconButton(
  tooltip: widget.tooltip,
  onPressed: _showInfo,
  padding: EdgeInsets.zero,
  alignment: Alignment.centerLeft,
  constraints: const BoxConstraints(
    minWidth: 48,
    minHeight: 48,
  ),
  icon: const Icon(
    Icons.info_outline,
    size: 22,
  ),
  color: Theme.of(context).colorScheme.primary,
);
}
