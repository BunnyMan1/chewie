import 'package:flutter/cupertino.dart';
import 'package:in_app_picture_in_picture/in_app_picture_in_picture.dart';

class CupertinoOptionsDialog extends StatefulWidget {
  const CupertinoOptionsDialog({
    super.key,
    required this.options,
    this.cancelButtonText,
  });

  final List<OptionItem> options;
  final String? cancelButtonText;

  @override
  State<CupertinoOptionsDialog> createState() {
    return _CupertinoOptionsDialogState();
  }
}

class _CupertinoOptionsDialogState extends State<CupertinoOptionsDialog> {
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: CupertinoActionSheet(
        actions:
            widget.options
                .map(
                  (option) => CupertinoActionSheetAction(
                    onPressed: () => option.onTap(context),
                    child: Text(option.title),
                  ),
                )
                .toList(),
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          isDestructiveAction: true,
          child: Text(widget.cancelButtonText ?? 'Cancel'),
        ),
      ),
    );
  }
}
