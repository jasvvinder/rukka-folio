// The veto reason sheet — S6.3's second action (07 §26 🔒: *Approve* / *Veto
// with reason*; a veto cancels and logs).
//
// Consequences before confirm (07 §1 rule 6, 13 §8): one veto closes the
// request for every owner immediately (02 §7.2.1 🔒), and the vetoing owner's
// name and reason join the member-visible admin-actions feed permanently
// (02 §7.2 item 3). It returns the trimmed reason, or null when the owner
// backs out; a blank reason can never leave this sheet — the engine's
// `StructuralVeto` throws on one, and that must never be reachable from a tap.
import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';

/// Asks for the veto reason. Returns the reason, or null if cancelled.
Future<String?> showVetoSheet(BuildContext context) =>
    showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => const _VetoSheet(),
    );

class _VetoSheet extends StatefulWidget {
  const _VetoSheet();

  @override
  State<_VetoSheet> createState() => _VetoSheetState();
}

class _VetoSheetState extends State<_VetoSheet> {
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
            Text(l10n.inboxStructuralVetoTitle, style: text.titleLarge),
            const SizedBox(height: RkSpace.s2),
            Text(l10n.inboxStructuralVetoBody, style: text.bodyLarge),
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
                labelText: l10n.inboxStructuralVetoHint,
                errorText: _showError ? l10n.inboxStructuralVetoRequired : null,
              ),
            ),
            const SizedBox(height: RkSpace.s4),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: status.danger,
                foregroundColor: status.onDanger,
              ),
              onPressed: _submit,
              child: Text(l10n.inboxStructuralVetoConfirm),
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

/// Asks the owner to confirm an approval before it is signed (02 §7.2.1: each
/// approval is authored on that owner's own device and cannot be taken back).
/// Returns true only on an explicit yes.
Future<bool> confirmApproval(BuildContext context) async {
  final l10n = AppLocalizations.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l10n.inboxStructuralApproveTitle),
      content: Text(l10n.inboxStructuralApproveBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(l10n.inboxStepCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(l10n.inboxStructuralApprove),
        ),
      ],
    ),
  );
  return ok ?? false;
}
