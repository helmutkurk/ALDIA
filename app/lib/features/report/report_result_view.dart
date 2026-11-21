import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/categories.dart';
import '../../core/strings.dart';
import '../../data/report.dart';
import '../../data/report_repository.dart';
import '../../widgets/report_tile.dart';
import '../../widgets/status_chips.dart';
import '../detail/report_detail_screen.dart';
import 'report_flow_widgets.dart';
import 'report_flow_controller.dart';

class ResultView extends StatelessWidget {
  const ResultView({super.key, required this.controller});
  final ReportFlowController controller;
  @override
  Widget build(BuildContext context) {
    final c = controller;
    final report = c.result;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (c.submitState == SubmitState.queued)
          const FlowNotice(S.waitingNetworkHelp),
        if (c.submitState == SubmitState.manualSaved)
          const FlowNotice(S.manualSaved),
        if (report != null) ...[
          Text(S.reference(report.id)),
          StatusChips(report: report),
          if (report.status == 'pending') const FlowNotice(S.pendingHelp),
          if (report.status == 'rejected') ...[
            if (c.photo != null)
              Stack(
                children: [
                  Image.memory(
                    c.photo!.bytes,
                    height: 140,
                    semanticLabel: S.photoAlternative,
                    errorBuilder: (_, _, _) => const Icon(Icons.photo),
                  ),
                  const Positioned(
                    top: 0,
                    right: 0,
                    child: Icon(Icons.error, semanticLabel: S.resultRejected),
                  ),
                ],
              ),
            if (report.verification != null)
              ChecksList(
                verification: report.verification!,
                category: categoryById(report.category).label,
              ),
            if (report.verification?.checks.any(
                  (v) => v.name == 'duplicate' && !v.passed,
                ) ==
                true)
              _DuplicateResult(controller: c),
            OutlinedButton(
              onPressed: c.retakePhoto,
              child: const Text(S.retakePhoto),
            ),
            OutlinedButton(
              onPressed: () => c.edit(FlowStep.category),
              child: const Text(S.changeCategory),
            ),
            OutlinedButton(
              onPressed: () => c.edit(FlowStep.location),
              child: const Text(S.adjustLocation),
            ),
            if (c.canManualReview)
              OutlinedButton(
                onPressed: c.saveForManualReview,
                child: const Text(S.manualReview),
              ),
          ],
        ],
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text(S.close),
        ),
      ],
    );
  }
}

class _DuplicateResult extends StatefulWidget {
  const _DuplicateResult({required this.controller});
  final ReportFlowController controller;
  @override
  State<_DuplicateResult> createState() => _DuplicateResultState();
}

class _DuplicateResultState extends State<_DuplicateResult> {
  late final Future<List<Report>> _future;
  @override
  void initState() {
    super.initState();
    final c = widget.controller;
    final repo = context.read<ReportRepository>();
    _future = c.result?.duplicateOf != null
        ? repo.get(c.result!.duplicateOf!).then((r) => [r])
        : repo.duplicates(c.position, c.categoryId!);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<Report>>(
    future: _future,
    builder: (context, snapshot) => Column(
      children: [
        for (final report in snapshot.data ?? [])
          Column(
            children: [
              ReportTile(
                report: report,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => ReportDetailScreen(report: report),
                  ),
                ),
              ),
              OutlinedButton(
                onPressed: () => widget.controller.follow(report),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.favorite_border),
                    SizedBox(width: 8),
                    Flexible(child: Text(S.followReport)),
                  ],
                ),
              ),
            ],
          ),
      ],
    ),
  );
}
