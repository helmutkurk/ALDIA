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
          constraints: const BoxConstraints(maxWidth: 680),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(AldiaSpace.xl),
            children: [
              const ExcludeSemantics(
                child: Icon(
                  Icons.location_city_outlined,
                  color: onBar,
                  size: 72,
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
              const SizedBox(height: AldiaSpace.xl),
              FutureBuilder<int?>(
                future: resolved,
                builder: (context, snapshot) => Column(
                  children: [
                    Text(
                      snapshot.data?.toString() ?? '—',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.displayLarge?.copyWith(
                        color: onBar,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      snapshot.hasData
                          ? 'reportes resueltos'
                          : 'Reportes resueltos: dato no disponible',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: muted,
                      ),
                    ),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: AldiaSpace.xl),
                child: Divider(color: Color(0xFF6B7278)),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(64),
                  backgroundColor: AldiaColors.surface,
                  foregroundColor: AldiaColors.text,
                ),
                onPressed: onExplore,
                icon: const Icon(Icons.explore_outlined),
                label: const Text('Explorar mi ciudad'),
              ),
              const SizedBox(height: AldiaSpace.l),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(64),
                ),
                onPressed: onReport,
                icon: const Icon(Icons.add_a_photo_outlined),
                label: const Text('Reportar un problema'),
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
        color: Theme.of(context).colorScheme.secondaryContainer,
        child: ListTile(
          minTileHeight: 56,
          leading: const Icon(Icons.edit_note),
          title: const Text(S.continueDraft),
          subtitle: Text(
            [
              S.draftBannerHelp,
              ?category,
              S.age(draft.createdAt, DateTime.now()),
            ].join(' · '),
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: onTap,
        ),
      ),
    );
  }
}
