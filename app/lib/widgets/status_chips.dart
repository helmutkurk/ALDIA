import 'package:flutter/material.dart';

import '../core/strings.dart';
import '../core/theme.dart';
import '../data/report.dart';

Color statusColor(String status) => switch (status) {
  'verified' => AldiaColors.success,
  'rejected' => AldiaColors.danger,
  _ => AldiaColors.accent,
};

String statusLabel(String status) => switch (status) {
  'verified' => S.statusVerified,
  'rejected' => S.statusRejected,
  _ => S.statusPending,
};

/// Status text for a report. A result from the stub verifier is never shown as
/// a real verification (contract: documentation/api-contract.md).
String reportStatusLabel(Report report) =>
    report.status == 'verified' && (report.verification?.isStub ?? false)
    ? S.statusVerifiedStub
    : statusLabel(report.status);

String resolutionLabel(String resolution) => switch (resolution) {
  'acknowledged' => S.resolutionAcknowledged,
  'fixed' => S.resolutionFixed,
  _ => S.resolutionOpen,
};

class StatusChips extends StatelessWidget {
  const StatusChips({super.key, required this.report});

  final Report report;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        Chip(
          label: Text(reportStatusLabel(report)),
          backgroundColor: statusColor(report.status).withValues(alpha: 0.15),
          side: BorderSide(color: statusColor(report.status)),
          visualDensity: VisualDensity.compact,
        ),
        Chip(
          label: Text(resolutionLabel(report.resolution)),
          visualDensity: VisualDensity.compact,
        ),
      ],
    );
  }
}

/// Why a photo passed or failed, so the citizen can retake it.
class ChecksList extends StatelessWidget {
  const ChecksList({super.key, required this.verification});

  final Verification verification;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final check in verification.checks)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              check.passed ? Icons.check_circle : Icons.cancel,
              color: check.passed ? AldiaColors.success : AldiaColors.danger,
            ),
            title: Text(check.name),
            subtitle: Text(check.detail),
          ),
        if (verification.isStub)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              S.stubNotice,
              style: TextStyle(color: AldiaColors.textMuted),
            ),
          ),
      ],
    );
  }
}
