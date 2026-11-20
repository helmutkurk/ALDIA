import 'package:flutter/material.dart';

import '../../core/categories.dart';
import '../../core/strings.dart';
import '../../widgets/report_tile.dart';
import '../../widgets/routes.dart';
import '../../widgets/status_chips.dart';
import '../detail/report_detail_screen.dart';
import 'report_flow_controller.dart';
import 'report_flow_widgets.dart';

class DuplicatesStep extends StatelessWidget {
  const DuplicatesStep({super.key, required this.controller});
  final ReportFlowController controller;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        'Revisa si alguien ya reportó el mismo problema cerca de este lugar. Puedes seguirlo para consultarlo después.',
        style: Theme.of(context).textTheme.bodyLarge,
      ),
      const SizedBox(height: 16),
      if (controller.following || controller.followError)
        Semantics(
          liveRegion: true,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: controller.following
                ? const Row(
                    children: [
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 8),
                      Flexible(child: Text('Guardando seguimiento…')),
                    ],
                  )
                : const Text(
                    'No se pudo guardar el seguimiento. Inténtalo de nuevo.',
                  ),
          ),
        ),
      if (controller.duplicates.isEmpty)
        const FlowNotice(
          'No hay coincidencias disponibles. Puedes continuar con tu reporte.',
        ),
      for (final report in controller.duplicates) ...[
        ReportTile(
          report: report,
          onTap: () {
            FocusManager.instance.primaryFocus?.unfocus();
            showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              sheetAnimationStyle: MediaQuery.disableAnimationsOf(context)
                  ? AnimationStyle.noAnimation
                  : const AnimationStyle(
                      duration: Duration(milliseconds: 240),
                      reverseDuration: Duration(milliseconds: 180),
                    ),
              builder: (_) => SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        categoryById(report.category).label,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 12),
                      StatusChips(report: report),
                      if (report.note != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          report.note!,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                      const SizedBox(height: 16),
                      TextButton(
                        onPressed: () {
                          Navigator.pop(context);
                          AldiaRoute.open(
                            context,
                            ReportDetailScreen(report: report),
                          );
                        },
                        child: const Text(S.viewDetail),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: controller.following
              ? null
              : () => controller.follow(report),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.favorite_border),
              SizedBox(width: 8),
              Flexible(child: Text(S.followReport)),
            ],
          ),
        ),
        const SizedBox(height: 24),
      ],
    ],
  );
}
