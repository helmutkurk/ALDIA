import 'package:flutter/material.dart';

import 'report_flow_controller.dart';

class SummaryRow extends StatelessWidget {
  const SummaryRow({super.key, required this.controller});
  final ReportFlowController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final place =
        c.placeLabel ??
        (c.locationConfirmed
            ? '${c.position.latitude.toStringAsFixed(5)}, ${c.position.longitude.toStringAsFixed(5)}'
            : 'Elige el lugar del problema');
    final category = c.categories
        .where((item) => item.id == c.categoryId)
        .firstOrNull;
    return Semantics(
      container: true,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(
              child: Icon(
                Icons.location_on_outlined,
                size: 24,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(place, style: Theme.of(context).textTheme.bodyMedium),
                  if (category != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      category.label,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
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
    child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline,
            size: 20,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: Theme.of(context).colorScheme.onSurface),
            ),
          ),
        ],
      ),
    ),
  );
}
