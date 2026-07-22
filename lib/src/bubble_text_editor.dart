import 'package:flutter/material.dart';

import 'text_context_menu.dart';

/// A bubble text field whose editing state survives parent rebuilds.
///
/// The workspace repaints after every character so the canvas can update in
/// real time. Keeping the controller here prevents those rebuilds from
/// replacing the active input connection or interrupting an IME composition.
class BubbleTextEditor extends StatefulWidget {
  const BubbleTextEditor({
    super.key,
    required this.editorId,
    required this.text,
    required this.compact,
    required this.onChanged,
    this.onTap,
  });

  final String editorId;
  final String text;
  final bool compact;
  final ValueChanged<String> onChanged;
  final VoidCallback? onTap;

  @override
  State<BubbleTextEditor> createState() => _BubbleTextEditorState();
}

class _BubbleTextEditorState extends State<BubbleTextEditor> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.text);
  }

  @override
  void didUpdateWidget(covariant BubbleTextEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_controller.text == widget.text) return;

    final oldSelection = _controller.selection;
    final offset = oldWidget.editorId == widget.editorId
        ? oldSelection.extentOffset.clamp(0, widget.text.length)
        : widget.text.length;
    _controller.value = TextEditingValue(
      text: widget.text,
      selection: TextSelection.collapsed(offset: offset),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextFormField(
        controller: _controller,
        minLines: widget.compact ? 1 : 3,
        maxLines: widget.compact ? 2 : 5,
        maxLength: 200,
        contextMenuBuilder: buildAppTextContextMenu,
        onTap: widget.onTap,
        onChanged: widget.onChanged,
      );
}
