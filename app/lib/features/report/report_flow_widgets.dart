import 'package:flutter/material.dart';

import '../../core/text_x.dart';
import '../../core/theme.dart';
import 'report_flow_controller.dart';

class SummaryRow extends StatelessWidget {
  const SummaryRow({super.key, required this.controller});
  final ReportFlowController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final place = c.placeLabel.isUsable
        ? c.placeLabel!
        : (c.locationConfirmed
              ? '${c.position.latitude.toStringAsFixed(5)}, ${c.position.longitude.toStringAsFixed(5)}'
              : 'Elige el lugar del problema');
    final category = c.categories
        .where((item) => item.id == c.categoryId)
        .firstOrNull;
    return Semantics(
      container: true,
      child: Container(
        padding: const EdgeInsets.all(AldiaSpace.m),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              child: Icon(
                c.photo == null
                    ? Icons.add_a_photo_outlined
                    : Icons.photo_camera,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    c.step == FlowStep.location
                        ? '¿Es este el lugar correcto?'
                        : 'Tu reporte',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(place),
                  if (category != null) Text(category.label),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class FlowNotice extends StatelessWidget {
  const FlowNotice(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.info_outline),
        const SizedBox(width: 8),
        Expanded(child: Text(text)),
      ],
    ),
  );
}
