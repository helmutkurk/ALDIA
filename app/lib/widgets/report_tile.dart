import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/categories.dart';
import '../core/citizen_states.dart';
import '../core/strings.dart';
import '../data/report.dart';
import '../data/report_repository.dart';
import 'status_chips.dart';

class ReportTile extends StatelessWidget {
  const ReportTile({super.key, required this.report, required this.onTap});
  final Report report;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final category = categoryById(report.category);
    final state = citizenStateFor(report.citizenState);
    final age = S.age(report.createdAt, DateTime.now());
    return Semantics(
      button: true,
      label: '${category.label}. ${state.label}. $age',
      excludeSemantics: true,
      onTap: onTap,
      child: ListTile(
        minVerticalPadding: 12,
        minTileHeight: 56,
        leading: SizedBox(
          width: 48,
          height: 48,
          child: Image.network(
            context.read<ReportRepository>().thumbnailUrl(report),
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => Icon(category.icon),
          ),
        ),
        title: Text(category.label),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(state.icon, size: 16),
                const SizedBox(width: 4),
                Expanded(
                  child: Text('${state.label} · ${reportStatusLabel(report)}'),
                ),
              ],
            ),
            Text(age),
          ],
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
