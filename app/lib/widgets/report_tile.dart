import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_fade/image_fade.dart';
import 'package:provider/provider.dart';

import '../core/categories.dart';
import '../core/citizen_states.dart';
import '../core/date_format.dart';
import '../core/strings.dart';
import '../core/text_x.dart';
import '../core/theme.dart';
import 'status_chips.dart';
import '../data/report.dart';
import '../data/report_repository.dart';
import '../services/haptics.dart';
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
          Semantics(
            button: true,
            label: '${category.label}. ${state.label}. Ver detalle',
            child: InkWell(
              onTap: onTap,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Semantics(
                      image: true,
                      label: S.photoLabel(category.label, state.label),
                      child: ExcludeSemantics(
                        child: ImageFade(
                          image: NetworkImage(repository.photoUrl(report)),
                          fit: BoxFit.cover,
                          placeholder: ColoredBox(
                            color: theme.colorScheme.surfaceContainerHighest,
                          ),
                          errorBuilder: (context, exception) => ColoredBox(
                            color: theme.colorScheme.surfaceContainerHighest,
                            child: Icon(
                              category.icon,
                              size: 56,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(AldiaSpace.l),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        StatusLabel(state: report.citizenState),
                        const SizedBox(height: AldiaSpace.s),
                        Text(
                          category.label,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: AldiaSpace.xs),
                        Text(
                          'Punto: ${report.position.latitude.toStringAsFixed(5)}, ${report.position.longitude.toStringAsFixed(5)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        if (report.note.isUsable)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(report.note!),
                          ),
                        const SizedBox(height: 8),
                        Text(
                          '${report.createdAt.formattedDate()} · ${S.age(report.createdAt, DateTime.now())}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        Text(
                          S.reference(report.id),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
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
                        unawaited(HapticsHelper.light());
                        try {
                          if (followed) {
                            await repository.local.setFollow(report.id, false);
                          } else {
                            await repository.follow(report);
                          }
                        } catch (_) {
                          if (context.mounted) {
                            unawaited(HapticsHelper.error());
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text(S.storageError)),
                            );
                          }
                        }
                      },
                    );
                  },
                ),
                IconButton(
                  tooltip: 'Compartir reporte',
                  icon: const Icon(Icons.share_outlined),
                  onPressed: () async {
                    final shared = await ShareService.shareReport(report.id);
                    if (!shared && context.mounted) {
                      unawaited(HapticsHelper.success());
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Enlace copiado. Pégalo en WhatsApp o donde quieras compartirlo.',
                          ),
                        ),
                      );
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
