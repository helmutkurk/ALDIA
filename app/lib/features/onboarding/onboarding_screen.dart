import 'package:flutter/material.dart';

import '../../core/strings.dart';
import '../../core/theme.dart';

const _icons = [
  Icons.location_city_outlined,
  Icons.camera_alt_outlined,
  Icons.lock_outlined,
];

/// First-run introduction: what Aldia is, the live-photo rule, privacy.
/// Three slides, always skippable, no form and no permission request.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.onDone});

  /// Called on "Empezar" and on "Omitir".
  final VoidCallback onDone;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pages = PageController();
  int _page = 0;

  static int get _count => S.onboardingTitles.length;
  bool get _last => _page == _count - 1;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _next() {
    if (_last) {
      widget.onDone();
      return;
    }
    final target = _page + 1;
    if (MediaQuery.disableAnimationsOf(context)) {
      _pages.jumpToPage(target);
    } else {
      _pages.animateToPage(
        target,
        duration: const Duration(milliseconds: 220),
        curve: const Cubic(0.23, 1, 0.32, 1),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: widget.onDone,
                    child: const Text(S.onboardingSkip),
                  ),
                ),
                Expanded(
                  child: PageView.builder(
                    controller: _pages,
                    itemCount: _count,
                    onPageChanged: (i) => setState(() => _page = i),
                    itemBuilder: (context, i) => SingleChildScrollView(
                      padding: const EdgeInsets.all(AldiaSpace.xl),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            alignment: Alignment.center,
                            child: ExcludeSemantics(
                              child: Icon(
                                _icons[i],
                                size: 32,
                                color: theme.colorScheme.onPrimaryContainer,
                              ),
                            ),
                          ),
                          const SizedBox(height: AldiaSpace.xl),
                          Semantics(
                            header: true,
                            child: Text(
                              S.onboardingTitles[i],
                              textAlign: TextAlign.center,
                              style: theme.textTheme.headlineSmall,
                            ),
                          ),
                          const SizedBox(height: AldiaSpace.m),
                          Text(
                            S.onboardingBodies[i],
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Semantics(
                  label: S.onboardingPage(_page + 1, _count),
                  excludeSemantics: true,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < _count; i++)
                        Container(
                          width: i == _page ? 24 : 8,
                          height: 8,
                          margin: const EdgeInsets.all(AldiaSpace.xs),
                          decoration: BoxDecoration(
                            color: i == _page
                                ? theme.colorScheme.primary
                                : theme.colorScheme.outline,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(AldiaSpace.l),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _next,
                      child: Text(_last ? S.onboardingStart : S.next),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
