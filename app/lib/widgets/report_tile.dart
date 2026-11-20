import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/categories.dart';
import '../core/citizen_states.dart';
import '../core/strings.dart';
import '../core/theme.dart';
import 'report_photo.dart';
import 'status_chips.dart';
import '../data/report.dart';
import '../data/report_repository.dart';
import '../services/share_service.dart';

/// Public report card. Actions remain separate semantic targets from the detail.
class ReportTile extends StatelessWidget {
  const ReportTile({super.key, required this.report, required this.onTap});
  final Report report;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final category = categoryById(report.category);
    final state = citizenStateFor(report.citizenState);
    final repository = context.read<ReportRepository>();
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MergeSemantics(
            child: Semantics(
              hint: 'Ver detalle',
              child: InkWell(
                onTap: onTap,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ExcludeSemantics(
                      child: ReportPhoto(
                        url: repository.thumbnailUrl(report),
                        height: 190,
                        fit: BoxFit.cover,
                        semanticLabel: S.photoLabel(
                          category.label,
                          state.label,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(AldiaSpace.l),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  category.label,
                                  style: theme.textTheme.titleLarge,
                                ),
                              ),
                              ExcludeSemantics(
                                child: Icon(
                                  Icons.chevron_right,
                                  size: 24,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: AldiaSpace.s),
                          Wrap(
                            spacing: AldiaSpace.m,
                            runSpacing: AldiaSpace.s,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              StatusLabel(state: report.citizenState),
                              Text(
                                S.age(report.createdAt, DateTime.now()),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: AldiaSpace.s),
                          Text(
                            'Punto: ${report.position.latitude.toStringAsFixed(5)}, ${report.position.longitude.toStringAsFixed(5)}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          if (report.note?.isNotEmpty == true)
                            Padding(
                              padding: const EdgeInsets.only(top: AldiaSpace.s),
                              child: Semantics(
                                label: report.note,
                                excludeSemantics: true,
                                child: Text(
                                  report.note!,
                                  style: theme.textTheme.bodyMedium,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                AnimatedBuilder(
                  animation: repository.local,
                  builder: (context, _) {
                    final followed = repository.local.follows(report.id);
                    return IconButton(
                      tooltip: followed
                          ? 'Dejar de seguir reporte'
                          : S.followReport,
                      isSelected: followed,
                      selectedIcon: const Icon(Icons.favorite),
                      icon: const Icon(Icons.favorite_border),
                      onPressed: () async {
                        try {
                          if (followed) {
                            await repository.local.setFollow(report.id, false);
                          } else {
                            await repository.follow(report);
                          }
                        } catch (_) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text(S.storageError)),
                            );
                          }
                        }
                      },
                    );
                  },
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Compartir reporte',
                  icon: const Icon(Icons.share_outlined),
                  onPressed: () async {
                    try {
                      final shared = await ShareService.shareReport(report.id);
                      if (!shared && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Enlace copiado. Pégalo en WhatsApp o donde quieras compartirlo.',
                            ),
                          ),
                        );
                      }
                    } catch (_) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'No se pudo compartir el reporte. Inténtalo de nuevo.',
                            ),
                          ),
                        );
                      }
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
