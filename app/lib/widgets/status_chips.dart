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
                      ? AldiaColors.primaryDark
                      : AldiaColors.danger,
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
