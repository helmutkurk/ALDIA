import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/categories.dart';
import '../core/citizen_states.dart';
import '../core/strings.dart';
import '../core/theme.dart';
import '../data/report.dart';
import '../data/report_repository.dart';
import 'status_chips.dart';

/// Compact report card: thumbnail, category, state chip and age.
class ReportTile extends StatelessWidget {
  const ReportTile({super.key, required this.report, required this.onTap});
  final Report report;
  final VoidCallback onTap;

  static const double _thumb = 72;

  @override
  Widget build(BuildContext context) {
    final category = categoryById(report.category);
    final state = citizenStateFor(report.citizenState);
    final age = S.age(report.createdAt, DateTime.now());
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      label: '${category.label}. ${state.label}. $age',
      excludeSemantics: true,
      onTap: onTap,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AldiaSpace.s),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: _thumb,
                    height: _thumb,
                    child: Image.network(
                      context.read<ReportRepository>().thumbnailUrl(report),
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => ColoredBox(
                        color: theme.colorScheme.surfaceContainerHighest,
                        child: Icon(
                          category.icon,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AldiaSpace.m),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(category.label, style: theme.textTheme.titleMedium),
                      const SizedBox(height: AldiaSpace.xs),
                      Wrap(
                        spacing: AldiaSpace.s,
                        runSpacing: AldiaSpace.xs,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          StateChip(state: report.citizenState),
                          Text(age, style: theme.textTheme.bodySmall),
                        ],
                      ),
                    ],
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
