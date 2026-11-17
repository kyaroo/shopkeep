import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// Manual barcode entry, shown as an overlay on the scanner.
///
/// A cashier meets a damaged, missing or worn-off label often enough that
/// typing the digits has to be possible; the camera stays the primary path.
///
/// Submitting hands the raw string to [onSubmit] exactly as a camera detection
/// would, so the caller cannot tell the two apart — the same lookup, the same
/// "absent from inventory" outcome, no second code path to maintain.
class ManualBarcodeEntry extends StatefulWidget {
  const ManualBarcodeEntry({super.key, required this.onSubmit});

  final ValueChanged<String> onSubmit;

  @override
  State<ManualBarcodeEntry> createState() => _ManualBarcodeEntryState();
}

class _ManualBarcodeEntryState extends State<ManualBarcodeEntry> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final code = _controller.text.trim();
    // Empty input is not a scan: stay on the scanner rather than popping a
    // string the caller would only have to reject.
    if (code.isEmpty) return;
    widget.onSubmit(code);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      elevation: 6,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                autofocus: true,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  hintText: 'manualHint'.tr(),
                  border: InputBorder.none,
                  isDense: true,
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.check),
              tooltip: 'manualSubmit'.tr(),
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }
}
