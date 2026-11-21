import 'package:flutter/material.dart';

import '../../core/categories.dart';
import '../../core/citizen_states.dart';
import '../../core/number_format.dart';
import '../../core/strings.dart';
import '../../core/text_x.dart';
import '../../core/theme.dart';
import '../../data/report.dart';
import '../../widgets/neutral_map_pin.dart';
import '../../widgets/report_tile.dart';

class ReportMapSummary extends StatelessWidget {
  const ReportMapSummary({
    super.key,
    required this.report,
    required this.onOpen,
  });
  final Report report;
  final VoidCallback onOpen;
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AldiaSpace.l),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ReportTile(report: report, onTap: onOpen),
            if (report.publicNote.isUsable)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(report.publicNote!),
              ),
            const SizedBox(height: 8),
            FilledButton(onPressed: onOpen, child: const Text(S.viewDetail)),
          ],
        ),
      ),
    );
  }
}

/// Pin with the state as icon and short text, so it is not color-only.
class StatePin extends StatelessWidget {
  const StatePin({super.key, required this.report, required this.onTap});
  final Report report;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final state = citizenStateFor(report.citizenState);
    final category = categoryById(report.category).label;
    return Semantics(
      button: true,
      label: '$category. ${state.label}',
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            StatusMapPin(
              state: report.citizenState,
              icon: categoryById(report.category).icon,
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
              child: Text(
                state.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textScaler: TextScaler.noScaling,
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ClusterPin extends StatelessWidget {
  const ClusterPin({super.key, required this.cluster, required this.onTap});
  final ReportCluster cluster;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final single = cluster.count == 1;
    return Semantics(
      button: true,
      label: single
          ? S.pinReport
          : '${S.clusterCount(cluster.count)}. ${S.zoomToCluster}',
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: NeutralMapPin(
          child: single
              ? const Icon(Icons.location_on)
              : Text(
                  cluster.count.humanizedCompact(),
                  textScaler: TextScaler.noScaling,
                ),
        ),
      ),
    );
  }
}
