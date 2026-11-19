import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/categories.dart';
import '../../core/strings.dart';
import '../../data/report.dart';
import '../../data/report_repository.dart';
import '../../widgets/status_chips.dart';

class ReportDetailScreen extends StatelessWidget {
  const ReportDetailScreen({super.key, required this.report});

  final Report report;

  @override
  Widget build(BuildContext context) {
    final repository = context.read<ReportRepository>();
    final category = categoryById(report.category);
    final date = DateFormat('d/M/y HH:mm').format(report.capturedAt.toLocal());
    return Scaffold(
      appBar: AppBar(title: const Text(S.reportDetail)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AspectRatio(
            aspectRatio: 4 / 3,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                repository.photoUrl(report),
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const ColoredBox(
                  color: Colors.black12,
                  child: Icon(Icons.broken_image),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(category.icon),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  category.label,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          StatusChips(report: report),
          const SizedBox(height: 8),
          Text(date),
          if (report.note != null && report.note!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(report.note!),
          ],
          if (report.verification != null) ...[
            const SizedBox(height: 16),
            Text(S.checks, style: Theme.of(context).textTheme.titleMedium),
            ChecksList(verification: report.verification!),
          ],
        ],
      ),
    );
  }
}
