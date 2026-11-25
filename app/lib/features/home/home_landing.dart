import 'package:flutter/material.dart';

import '../../core/categories.dart';
import '../../core/number_format.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../drafts/draft_record.dart';
import 'bottom_navigation_reselect.dart';

class Landing extends StatelessWidget {
  const Landing({
    super.key,
    required this.resolved,
    required this.onExplore,
    required this.onReport,
  });
  final Future<int?> resolved;
  final VoidCallback onExplore;
  final VoidCallback onReport;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const onBar = AldiaColors.onBar;
    const muted = Color(0xFFD9DEE3);
    return ColoredBox(
      color: AldiaColors.barOf(context),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: ListView(
            controller: BottomNavigationReselect.landingScrollController,
            shrinkWrap: true,
            padding: EdgeInsets.symmetric(
              horizontal: MediaQuery.sizeOf(context).width < 600
                  ? AldiaSpace.l
                  : AldiaSpace.xl,
              vertical: AldiaSpace.xl,
            ),
            children: [
              const ExcludeSemantics(
                child: Icon(
                  Icons.location_city_outlined,
                  color: onBar,
                  size: 48,
                ),
              ),
              const SizedBox(height: AldiaSpace.l),
              Semantics(
                header: true,
                child: Text(
                  'Tu ciudad, AlDía',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineMedium?.copyWith(color: onBar),
                ),
              ),
              const SizedBox(height: AldiaSpace.m),
              Text(
                'Reporta problemas de tu calle con una foto verificada.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(color: muted),
              ),
              const SizedBox(height: AldiaSpace.xl),
              // Coral key call to action, as in the Figma design.
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size(AldiaSpace.target, 56),
                  backgroundColor: AldiaColors.accentOf(context),
                  foregroundColor: AldiaColors.onAccent,
                ),
                onPressed: onReport,
                icon: const Icon(Icons.add_a_photo_outlined, size: 24),
                label: const Text('Reportar un problema'),
              ),
              const SizedBox(height: AldiaSpace.s),
              OutlinedButton.icon(
                style:
                    OutlinedButton.styleFrom(
                      minimumSize: const Size(AldiaSpace.target, 56),
                      backgroundColor: Colors.transparent,
                      foregroundColor: onBar,
                      side: const BorderSide(color: onBar),
                    ).copyWith(
                      side: WidgetStateProperty.resolveWith((states) {
                        return BorderSide(
                          color: onBar,
                          width: states.contains(WidgetState.focused) ? 2 : 1,
                        );
                      }),
                    ),
                onPressed: onExplore,
                icon: const Icon(Icons.explore_outlined),
                label: const Text('Explorar mi ciudad'),
              ),
              const SizedBox(height: AldiaSpace.xxl),
              const Divider(color: Color(0xFF6B7278), height: 1),
              const SizedBox(height: AldiaSpace.l),
              FutureBuilder<int?>(
                future: resolved,
                builder: (context, snapshot) => Column(
                  children: [
                    Text(
                      snapshot.data?.humanizedCount() ?? '—',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: onBar,
                        fontWeight: FontWeight.w700,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    Text(
                      snapshot.hasData
                          ? 'reportes resueltos'
                          : 'Reportes resueltos: dato no disponible',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(color: muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Draft reminder on Inicio's blue hero: a translucent card on the bar color
/// with the coral accent, so it reads as part of the page.
class DraftBanner extends StatelessWidget {
  const DraftBanner({super.key, required this.draft, required this.onTap});
  final DraftRecord draft;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const onBar = AldiaColors.onBar;
    final category = draft.categoryId == null
        ? null
        : categoryById(draft.categoryId!).label;
    final width = MediaQuery.sizeOf(context).width;
    return ColoredBox(
      color: AldiaColors.barOf(context),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              width < 600 ? AldiaSpace.l : AldiaSpace.xl,
              AldiaSpace.s,
              width < 600 ? AldiaSpace.l : AldiaSpace.xl,
              0,
            ),
            child: Material(
              // White at 12% on the bar keeps white text above 4.5:1.
              color: onBar.withValues(alpha: 0.12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AldiaRadius.card),
                side: BorderSide(color: onBar.withValues(alpha: 0.28)),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                // Announced as one button: title, help and age.
                onTap: onTap,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 56),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AldiaSpace.l,
                      vertical: AldiaSpace.m,
                    ),
                    child: Row(
                      children: [
                        ExcludeSemantics(
                          child: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: AldiaColors.accentOf(context),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.edit_note,
                              color: AldiaColors.onAccent,
                            ),
                          ),
                        ),
                        const SizedBox(width: AldiaSpace.m),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                S.continueDraft,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  color: onBar,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                S.draftBannerHelp,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: onBar,
                                ),
                              ),
                              Text(
                                [
                                  ?category,
                                  S.age(draft.createdAt, DateTime.now()),
                                ].join(' · '),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: onBar,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: AldiaSpace.s),
                        const Icon(Icons.chevron_right, color: onBar),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
