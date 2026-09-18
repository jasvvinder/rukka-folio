// The *Re-open {month}* confirm sheet — S10.3's scary-styled second action
// (07 §13 🔒: *admin, scary-styled, logged*).
//
// Consequences before confirm (07 §1 rule 6, 13 §8): the month needs closing
// again (02 §8 step 4) and every member's phone re-verifies the figures when
// it is; the re-opener's name and reason join the member-visible admin-actions
// feed (02 §7.2 item 3). The reason is required — `LocalLedger.unlockMonth`
// throws on a blank one, and that must never be reachable from a tap.
import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';

/// Asks for the re-open reason. Returns the trimmed reason, or null when the
/// admin backs out.
Future<String?> showReopenSheet(
  BuildContext context, {
  required String month,
}) => showModalBottomSheet<String>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (ctx) => _ReopenSheet(month: month),
);

class _ReopenSheet extends StatefulWidget {
  const _ReopenSheet({required this.month});

  final String month;

  @override
  State<_ReopenSheet> createState() => _ReopenSheetState();
}

class _ReopenSheetState extends State<_ReopenSheet> {
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
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lock_open, size: 20, color: status.danger),
                const SizedBox(width: RkSpace.s2),
                Expanded(
                  child: Text(
                    l10n.inboxLateReopenTitle(widget.month),
                    style: text.titleLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: RkSpace.s2),
            Text(l10n.inboxLateReopenBody(widget.month), style: text.bodyLarge),
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
                labelText: l10n.inboxLateReopenHint,
                errorText: _showError ? l10n.inboxLateReopenRequired : null,
              ),
            ),
            const SizedBox(height: RkSpace.s4),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: status.danger,
                foregroundColor: status.onDanger,
              ),
              onPressed: _submit,
              child: Text(l10n.inboxLateReopenConfirm(widget.month)),
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
