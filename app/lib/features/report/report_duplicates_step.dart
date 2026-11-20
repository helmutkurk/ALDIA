import 'package:flutter/material.dart';

import '../../core/categories.dart';
import '../../core/strings.dart';
import '../../widgets/report_tile.dart';
import '../../widgets/status_chips.dart';
import '../detail/report_detail_screen.dart';
import 'report_flow_widgets.dart';
import 'report_flow_controller.dart';

class DuplicatesStep extends StatelessWidget {
  const DuplicatesStep({super.key, required this.controller});
  final ReportFlowController controller;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text(
        'Revisa si alguien ya reportó el mismo problema cerca de este lugar. Puedes seguirlo para consultarlo después.',
      ),
      if (controller.duplicates.isEmpty)
        const FlowNotice(
          'No hay coincidencias disponibles. Puedes continuar con tu reporte.',
        ),
      for (final report in controller.duplicates) ...[
        ReportTile(
          report: report,
          onTap: () => showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            builder: (_) => SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      categoryById(report.category).label,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    StatusChips(report: report),
                    if (report.note != null) Text(report.note!),
                    TextButton(
                      onPressed: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => ReportDetailScreen(report: report),
                          ),
                        );
                      },
                      child: const Text(S.viewDetail),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        OutlinedButton(
          onPressed: () => controller.follow(report),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.favorite_border),
              SizedBox(width: 8),
              Flexible(child: Text(S.followReport)),
            ],
          ),
        ),
        const Divider(),
      ],
    ],
  );
}
