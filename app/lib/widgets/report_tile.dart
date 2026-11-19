import 'package:flutter/material.dart';

import '../core/categories.dart';
import '../data/report.dart';
import 'status_chips.dart';

class ReportTile extends StatelessWidget {
  const ReportTile({super.key, required this.report, required this.onTap});

  final Report report;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final category = categoryById(report.category);
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: statusColor(report.status).withValues(alpha: 0.15),
        child: Icon(category.icon, color: statusColor(report.status)),
      ),
      title: Text(category.label),
      subtitle: Text(
        '${reportStatusLabel(report)} · ${resolutionLabel(report.resolution)}',
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
