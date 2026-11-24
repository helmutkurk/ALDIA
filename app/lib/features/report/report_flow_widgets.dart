import 'package:flutter/material.dart';

import '../../core/text_x.dart';
import '../../core/theme.dart';
import '../../widgets/aldia_banner.dart';
import '../../widgets/place_text.dart';
import 'report_flow_controller.dart';

class SummaryRow extends StatelessWidget {
  const SummaryRow({super.key, required this.controller});
  final ReportFlowController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final style = Theme.of(context).textTheme.bodyMedium;
    final Widget place = c.placeLabel.isUsable || c.locationConfirmed
        ? PlaceText(position: c.position, label: c.placeLabel, style: style)
        : Text('Elige el lugar del problema', style: style);
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
                  place,
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

/// Notice inside a wizard step; an [AldiaBanner] with vertical spacing.
class FlowNotice extends StatelessWidget {
  const FlowNotice(this.text, {super.key, this.kind = BannerKind.info});
  final String text;
  final BannerKind kind;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AldiaSpace.s),
    child: AldiaBanner(text, kind: kind),
  );
}
