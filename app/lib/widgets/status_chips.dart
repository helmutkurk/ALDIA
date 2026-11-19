import 'package:flutter/material.dart';

import '../core/citizen_states.dart';
import '../core/strings.dart';
import '../core/theme.dart';
import '../data/report.dart';
import '../features/report/verification_feedback.dart';

String statusLabel(String status) => switch (status) {
  'verified' => S.statusVerified,
  'rejected' => S.statusRejected,
  _ => S.statusPending,
};
String reportStatusLabel(Report report) =>
    '${statusLabel(report.status)}${report.verification?.isStub == true ? ' (prueba)' : ''}';

/// Compact state label for cards and pins: icon plus text on a tonal fill
/// (never color alone). Wraps to two lines instead of overflowing.
class StateChip extends StatelessWidget {
  const StateChip({super.key, required this.state});
  final String? state;

  @override
  Widget build(BuildContext context) {
    final info = citizenStateFor(state);
    final scheme = Theme.of(context).colorScheme;
    final (background, foreground) = switch (state) {
      'resuelto' => (scheme.primaryContainer, scheme.onPrimaryContainer),
      'rechazado_verificador' => (
        scheme.errorContainer,
        scheme.onErrorContainer,
      ),
      'en_proceso' ||
      'programado' ||
      'en_revision' => (scheme.secondaryContainer, scheme.onSecondaryContainer),
      _ => (scheme.surfaceContainerHighest, scheme.onSurfaceVariant),
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AldiaSpace.xl),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AldiaSpace.s,
          vertical: AldiaSpace.xs,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(info.icon, size: 16, color: foreground),
            const SizedBox(width: AldiaSpace.xs),
            Flexible(
              child: Text(
                info.label,
                style: Theme.of(context).textTheme.labelMedium
                    ?.copyWith(color: foreground),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// State as icon plus text (never color alone).
class CitizenStateChip extends StatelessWidget {
  const CitizenStateChip({super.key, required this.state});
  final String? state;

  @override
  Widget build(BuildContext context) {
    final info = citizenStateFor(state);
    return Chip(
      avatar: Icon(info.icon, size: 20),
      label: Text(info.label),
      materialTapTargetSize: MaterialTapTargetSize.padded,
    );
  }
}

class StatusChips extends StatelessWidget {
  const StatusChips({super.key, required this.report});
  final Report report;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 4,
    children: [
      CitizenStateChip(state: report.citizenState),
      Chip(
        avatar: Icon(
          report.status == 'verified'
              ? Icons.verified_outlined
              : report.status == 'rejected'
              ? Icons.info_outline
              : Icons.hourglass_empty,
          size: 20,
        ),
        label: Text(reportStatusLabel(report)),
      ),
    ],
  );
}

class ChecksList extends StatelessWidget {
  const ChecksList({super.key, required this.verification, this.category = ''});
  final Verification verification;
  final String category;
  @override
  Widget build(BuildContext context) {
    final checks = [
      ...orderedFailures(verification),
      ...verification.checks.where((c) => c.passed),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (verification.isStub)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(S.stubNotice),
          ),
        for (final check in checks)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  check.passed
                      ? Icons.check_circle_outline
                      : Icons.info_outline,
                  color: check.passed
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.error,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        feedbackFor(check, category).title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(feedbackFor(check, category).reason),
                      if (!check.passed) Text(feedbackFor(check, category).fix),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
