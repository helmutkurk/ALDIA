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

/// Status dot: filled in the status color, or hollow while verification is
/// pending. Always placed next to the status word, never alone.
class StatusDot extends StatelessWidget {
  const StatusDot({super.key, required this.state, this.size = 10});
  final String? state;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = AldiaColors.status(state, Theme.of(context).brightness);
    final hollow = AldiaColors.statusIsHollow(state);
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: hollow ? Colors.transparent : color,
          border: Border.all(color: color, width: 2),
        ),
      ),
    );
  }
}

/// Dot plus status word in the normal text color (reference card style).
class StatusLabel extends StatelessWidget {
  const StatusLabel({super.key, required this.state, this.style});
  final String? state;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final info = citizenStateFor(state);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        StatusDot(state: state),
        const SizedBox(width: AldiaSpace.s),
        Flexible(
          child: Text(
            info.label,
            style: style ?? Theme.of(context).textTheme.labelLarge,
          ),
        ),
      ],
    );
  }
}

/// Compact state label: functional icon plus text on an opaque surface
/// (never color alone). Wraps to two lines instead of overflowing.
class StateChip extends StatelessWidget {
  const StateChip({super.key, required this.state});
  final String? state;

  @override
  Widget build(BuildContext context) {
    final info = citizenStateFor(state);
    final scheme = Theme.of(context).colorScheme;
    final foreground = AldiaColors.status(state, scheme.brightness);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border.all(color: foreground),
        borderRadius: BorderRadius.circular(AldiaSpace.s),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AldiaSpace.s,
          vertical: AldiaSpace.xs,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(info.icon, size: 18, color: foreground),
            const SizedBox(width: AldiaSpace.xs),
            Flexible(
              child: Text(
                info.label,
                style: Theme.of(context).textTheme.labelMedium
                    ?.copyWith(color: scheme.onSurface),
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
    final theme = Theme.of(context);
    final foreground = AldiaColors.status(state, theme.brightness);
    return Chip(
      backgroundColor: theme.colorScheme.surface,
      side: BorderSide(color: foreground),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      avatar: Icon(info.icon, size: 18, color: foreground),
      label: Text(
        info.label,
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurface,
        ),
      ),
      labelPadding: const EdgeInsets.only(left: 4),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}

class StatusChips extends StatelessWidget {
  const StatusChips({super.key, required this.report});
  final Report report;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = AldiaColors.status(report.status, theme.brightness);
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        CitizenStateChip(state: report.citizenState),
        Chip(
          backgroundColor: theme.colorScheme.surface,
          side: BorderSide(color: foreground),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          avatar: Icon(
            report.status == 'verified'
                ? Icons.verified_outlined
                : report.status == 'rejected'
                ? Icons.info_outline
                : Icons.hourglass_empty,
            size: 18,
            color: foreground,
          ),
          label: Text(
            reportStatusLabel(report),
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurface,
            ),
          ),
          labelPadding: const EdgeInsets.only(left: 4),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ],
    );
  }
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
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              S.stubNotice,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        for (final check in checks)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AldiaSpace.m),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  check.passed
                      ? Icons.check_circle_outline
                      : Icons.info_outline,
                  color: check.passed
                      ? AldiaColors.status(
                          'verified',
                          Theme.of(context).brightness,
                        )
                      : Theme.of(context).colorScheme.error,
                  size: 24,
                ),
                const SizedBox(width: AldiaSpace.m),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        feedbackFor(check, category).title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: AldiaSpace.xs),
                      Text(
                        feedbackFor(check, category).reason,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (!check.passed) ...[
                        const SizedBox(height: AldiaSpace.xs),
                        Text(
                          feedbackFor(check, category).fix,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ],
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
