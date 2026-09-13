// The rejection reason sheet, shared by the S6.1 per-row quick reject and the
// S6.2 stepper (07 §9 🔒: *Reject (reason required → auto-reversal posts)*).
//
// Consequences before confirm: the sheet says a reversal posts immediately and
// that both entries stay visible (02 §3, §5 🔒 — the audit trail never hides a
// dispute). It returns the trimmed reason, or null when the reviewer backs
// out; a blank reason can never leave this sheet.
import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';

/// Asks for the rejection reason. Returns the reason, or null if cancelled.
Future<String?> showRejectSheet(BuildContext context, {String? authorName}) =>
    showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => _RejectSheet(authorName: authorName),
    );

class _RejectSheet extends StatefulWidget {
  const _RejectSheet({this.authorName});

  final String? authorName;

  @override
  State<_RejectSheet> createState() => _RejectSheetState();
}

class _RejectSheetState extends State<_RejectSheet> {
  final _controller = TextEditingController();
  bool _showError = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final reason = _controller.text.trim();
    if (reason.isEmpty) {
      setState(() => _showError = true);
      return;
    }
    Navigator.of(context).pop(reason);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final status = RkStatusColors.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: RkSpace.gutter,
        right: RkSpace.gutter,
        bottom: MediaQuery.viewInsetsOf(context).bottom + RkSpace.gutter,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.inboxStepRejectTitle, style: text.titleLarge),
            const SizedBox(height: RkSpace.s2),
            Text(l10n.inboxStepRejectBody, style: text.bodyLarge),
            const SizedBox(height: RkSpace.s4),
            TextField(
              controller: _controller,
              autofocus: true,
              minLines: 2,
              maxLines: 4,
              textInputAction: TextInputAction.done,
              onChanged: (_) {
                if (_showError) setState(() => _showError = false);
              },
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: l10n.inboxStepRejectHint,
                errorText: _showError ? l10n.inboxStepRejectRequired : null,
              ),
            ),
            const SizedBox(height: RkSpace.s4),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: status.danger,
                foregroundColor: status.onDanger,
              ),
              onPressed: _submit,
              child: Text(l10n.inboxStepRejectConfirm),
            ),
            const SizedBox(height: RkSpace.s2),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                l10n.inboxStepCancel,
                style: text.bodyLarge?.copyWith(color: scheme.onSurface),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
