// S0.4 Name & photo (13 §3.2 row S0.4, 07 §3.1 step 4) — name is required,
// photo is optional; both are for approvals and the verification ceremony
// (07 §3.1 step 4, 06 §1), stated in the screen's own copy so nobody wonders
// why a ledger app wants a photo.
//
// Photo picking goes through a seam ([onPickPhoto]), never a plugin
// dependency here — the caller (a later lane, once a real picker exists)
// supplies the callback; this screen only holds whatever opaque value comes
// back and shows that a photo was added (icon + label, colour never alone,
// 07 §1 rule 3). It never inspects or renders the value.
import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';

/// Invokes whatever photo-picker exists on the host platform and returns an
/// opaque handle to the picked photo, or `null` if the user cancelled.
typedef PhotoPicker = Future<Object?> Function();

class NamePhotoScreen extends StatefulWidget {
  const NamePhotoScreen({
    super.key,
    this.onPickPhoto,
    this.onSubmit,
    this.initialName = '',
  });

  /// The seam to a real photo picker; null in tests/hosts that don't wire one
  /// yet — the avatar tap then does nothing (no dead end: the field stays
  /// optional and Continue is unaffected).
  final PhotoPicker? onPickPhoto;

  /// Called with the trimmed name and whatever [onPickPhoto] last returned
  /// (`null` if no photo was picked) when Continue is pressed.
  final void Function(String name, Object? photo)? onSubmit;

  /// Pre-fills the name field (e.g. returning to this step from the
  /// checklist — 07 §3.1.1: every branch step is resumable).
  final String initialName;

  @override
  State<NamePhotoScreen> createState() => _NamePhotoScreenState();
}

class _NamePhotoScreenState extends State<NamePhotoScreen> {
  late final _name = TextEditingController(text: widget.initialName);
  Object? _photo;
  bool _picking = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final picker = widget.onPickPhoto;
    if (picker == null) return;
    setState(() => _picking = true);
    final photo = await picker();
    if (!mounted) return;
    setState(() {
      _picking = false;
      _photo = photo;
    });
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    widget.onSubmit?.call(name, _photo);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final status = RkStatusColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final hasPhoto = _photo != null;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(RkSpace.s6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        l10n.onboardingNamePhotoTitle,
                        style: text.headlineMedium,
                      ),
                      const SizedBox(height: RkSpace.s2),
                      Text(
                        l10n.onboardingNamePhotoSubtitle,
                        style: text.bodyLarge,
                      ),
                      const SizedBox(height: RkSpace.s6),
                      Center(
                        child: Semantics(
                          button: widget.onPickPhoto != null,
                          label: hasPhoto
                              ? l10n.onboardingNamePhotoPhotoAdded
                              : l10n.onboardingNamePhotoPhotoLabel,
                          child: InkWell(
                            onTap: widget.onPickPhoto == null || _picking
                                ? null
                                : _pickPhoto,
                            customBorder: const CircleBorder(),
                            child: CircleAvatar(
                              radius: RkSpace.s10,
                              backgroundColor: status.hairline,
                              child: Icon(
                                hasPhoto
                                    ? Icons.check_circle
                                    : Icons.add_a_photo_outlined,
                                color: hasPhoto ? scheme.primary : status.muted,
                                size: RkIcon.grid,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: RkSpace.s2),
                      Center(
                        child: Text(
                          hasPhoto
                              ? l10n.onboardingNamePhotoPhotoAdded
                              : l10n.onboardingNamePhotoPhotoLabel,
                          style: text.bodySmall?.copyWith(color: status.muted),
                        ),
                      ),
                      const SizedBox(height: RkSpace.s6),
                      TextField(
                        controller: _name,
                        autofocus: true,
                        textCapitalization: TextCapitalization.words,
                        decoration: InputDecoration(
                          labelText: l10n.onboardingNamePhotoNameLabel,
                          hintText: l10n.onboardingNamePhotoNameHint,
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ],
                  ),
                ),
              ),
              // Disabled-with-reason (13 §4.3): while the name is empty,
              // Continue is disabled and the helper line beneath it says why.
              if (_name.text.trim().isEmpty) ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: RkSpace.s2),
                  child: Text(
                    l10n.onboardingNamePhotoNameError,
                    style: text.bodySmall?.copyWith(color: status.muted),
                  ),
                ),
              ],
              FilledButton(
                onPressed: _name.text.trim().isEmpty ? null : _submit,
                child: Text(l10n.onboardingNamePhotoContinueLabel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
