// S0.05 Welcome (13 §3.2 row S0.05, 07 §5 flow F1) — first launch, 3
// skippable slides, shown after language so the copy renders in the
// language the user just picked (13 §3.2: "after language so they are in
// the user's language"). Skip and the final slide's primary action both
// advance to S0.2 phone+OTP (07 §5 F1) — this screen has no dead end (07 §1
// rule 2). Progress is shown by dots (never colour alone — paired with a
// live-region "Slide n of 3" announcement, design-system §3.1 rule 3) plus
// the filled/outline dot shapes themselves.
import 'package:flutter/material.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../../../shared/theme.dart';
import '../../../shared/tokens.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key, this.onDone});

  /// Called when the user skips, or finishes the last slide.
  final VoidCallback? onDone;

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final _controller = PageController();
  int _page = 0;

  static const _slideCount = 3;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _next(AppLocalizations l10n) {
    if (_page >= _slideCount - 1) {
      widget.onDone?.call();
      return;
    }
    _controller.animateToPage(
      _page + 1,
      duration: RkMotion.m,
      curve: RkMotion.easeEntries,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final status = RkStatusColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    final slides = <(String, String)>[
      (l10n.onboardingWelcomeSlide1Title, l10n.onboardingWelcomeSlide1Body),
      (l10n.onboardingWelcomeSlide2Title, l10n.onboardingWelcomeSlide2Body),
      (l10n.onboardingWelcomeSlide3Title, l10n.onboardingWelcomeSlide3Body),
    ];
    final isLast = _page == slides.length - 1;
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(RkSpace.s4),
                child: TextButton(
                  onPressed: widget.onDone,
                  child: Text(l10n.onboardingWelcomeSkip),
                ),
              ),
            ),
            Expanded(
              child: PageView(
                controller: _controller,
                onPageChanged: (page) => setState(() => _page = page),
                children: [
                  for (final (title, body) in slides)
                    _WelcomeSlide(title: title, body: body),
                ],
              ),
            ),
            Semantics(
              liveRegion: true,
              label: l10n.onboardingWelcomeSlideOf(_page + 1, slides.length),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < slides.length; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: RkSpace.s1,
                      ),
                      child: Container(
                        width: RkSpace.s2,
                        height: RkSpace.s2,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: i == _page ? scheme.primary : status.muted,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(RkSpace.s6),
              child: FilledButton(
                onPressed: () => _next(l10n),
                child: Text(
                  isLast
                      ? l10n.onboardingWelcomeGetStarted
                      : l10n.onboardingWelcomeNext,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WelcomeSlide extends StatelessWidget {
  const _WelcomeSlide({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: RkSpace.s6),
      child: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                style: text.headlineMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: RkSpace.s3),
              Text(body, style: text.bodyLarge, textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}
