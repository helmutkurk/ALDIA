import 'package:flutter/material.dart';

import '../../core/categories.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../drafts/draft_record.dart';

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
                  'Tu ciudad, al día',
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
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size(AldiaSpace.target, 56),
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
                      snapshot.data?.toString() ?? '—',
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

class DraftBanner extends StatelessWidget {
  const DraftBanner({super.key, required this.draft, required this.onTap});
  final DraftRecord draft;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final category = draft.categoryId == null
        ? null
        : categoryById(draft.categoryId!).label;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AldiaSpace.l,
        AldiaSpace.s,
        AldiaSpace.l,
        0,
      ),
      child: Card(
        color: scheme.primaryContainer,
        child: ListTile(
          minTileHeight: 56,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AldiaSpace.l,
            vertical: AldiaSpace.s,
          ),
          leading: Icon(Icons.edit_note, color: scheme.onPrimaryContainer),
          title: Text(
            S.continueDraft,
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(color: scheme.onPrimaryContainer),
          ),
          subtitle: Text(
            [
              S.draftBannerHelp,
              ?category,
              S.age(draft.createdAt, DateTime.now()),
            ].join(' · '),
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: scheme.onPrimaryContainer),
          ),
          trailing: Icon(Icons.chevron_right, color: scheme.onPrimaryContainer),
          onTap: onTap,
        ),
      ),
    );
  }
}
