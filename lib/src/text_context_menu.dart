import 'package:flutter/material.dart';

/// A predictable Chinese text menu for desktop right-click and mobile long-press.
Widget buildAppTextContextMenu(
  BuildContext context,
  EditableTextState editableTextState,
) {
  final value = editableTextState.textEditingValue;
  final selection = value.selection;
  final hasSelection = selection.isValid && !selection.isCollapsed;
  final isReadOnly = editableTextState.widget.readOnly;
  final isAllSelected = value.text.isNotEmpty &&
      selection.isValid &&
      selection.start == 0 &&
      selection.end == value.text.length;

  void closeThen(VoidCallback action) {
    ContextMenuController.removeAny();
    action();
  }

  return AdaptiveTextSelectionToolbar.buttonItems(
    anchors: editableTextState.contextMenuAnchors,
    buttonItems: [
      if (!isReadOnly)
        ContextMenuButtonItem(
          type: ContextMenuButtonType.cut,
          label: '剪切',
          onPressed: hasSelection
              ? () => closeThen(
                    () => editableTextState.cutSelection(
                      SelectionChangedCause.toolbar,
                    ),
                  )
              : null,
        ),
      ContextMenuButtonItem(
        type: ContextMenuButtonType.copy,
        label: '复制',
        onPressed: hasSelection
            ? () => closeThen(
                  () => editableTextState.copySelection(
                    SelectionChangedCause.toolbar,
                  ),
                )
            : null,
      ),
      if (!isReadOnly)
        ContextMenuButtonItem(
          type: ContextMenuButtonType.paste,
          label: '粘贴',
          onPressed: () => closeThen(
            () => editableTextState.pasteText(
              SelectionChangedCause.toolbar,
            ),
          ),
        ),
      ContextMenuButtonItem(
        type: ContextMenuButtonType.selectAll,
        label: '全选',
        onPressed: value.text.isNotEmpty && !isAllSelected
            ? () => closeThen(
                  () => editableTextState.selectAll(
                    SelectionChangedCause.toolbar,
                  ),
                )
            : null,
      ),
    ],
  );
}
