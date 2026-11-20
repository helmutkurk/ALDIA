import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/categories.dart';
import '../../core/strings.dart';
import '../../data/report.dart';
import '../../data/report_repository.dart';
import '../../widgets/report_tile.dart';
import '../../widgets/routes.dart';
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
    final rejected =
        c.submitState == SubmitState.done && report?.status == 'rejected';
    final icon = switch (c.submitState) {
      SubmitState.queued => Icons.cloud_upload_outlined,
      SubmitState.manualSaved => Icons.edit_note,
      SubmitState.followed => Icons.favorite_border,
      SubmitState.done when rejected => Icons.info_outline,
      _ => Icons.check_circle_outline,
    };
    final scheme = Theme.of(context).colorScheme;
    final iconBackground = rejected
        ? scheme.errorContainer
        : scheme.primaryContainer;
    final iconForeground = rejected
        ? scheme.onErrorContainer
        : scheme.onPrimaryContainer;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: iconBackground,
              borderRadius: BorderRadius.circular(16),
            ),
            alignment: Alignment.center,
            child: ExcludeSemantics(
              child: Icon(icon, size: 32, color: iconForeground),
            ),
          ),
        ),
        const SizedBox(height: 24),
        if (c.submitState == SubmitState.queued)
          const FlowNotice(S.waitingNetworkHelp),
        if (c.submitState == SubmitState.manualSaved)
          const FlowNotice(S.manualSaved),
        if (c.following || c.followError)
          Semantics(
            liveRegion: true,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: c.following
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
        if (report != null) ...[
          Text(
            S.reference(report.id),
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          StatusChips(report: report),
          if (report.status == 'pending') ...[
            const SizedBox(height: 16),
            const FlowNotice(S.pendingHelp),
          ],
          if (report.status == 'rejected') ...[
            const SizedBox(height: 16),
            if (c.photo != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  height: 140,
                  color: scheme.surfaceContainerLow,
                  alignment: Alignment.center,
                  child: Image.memory(
                    c.photo!.bytes,
                    height: 140,
                    fit: BoxFit.contain,
                    semanticLabel: S.photoAlternative,
                    errorBuilder: (_, _, _) => const Icon(Icons.photo),
                  ),
                ),
              ),
            if (c.photo != null) const SizedBox(height: 16),
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
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => c.edit(FlowStep.category),
              child: const Text(S.changeCategory),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => c.edit(FlowStep.location),
              child: const Text(S.adjustLocation),
            ),
            if (c.canManualReview) ...[
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: c.saveForManualReview,
                child: const Text(S.manualReview),
              ),
            ],
          ],
        ],
        const SizedBox(height: 24),
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
  late Future<List<Report>> _future;
  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Report>> _load() {
    final c = widget.controller;
    final repo = context.read<ReportRepository>();
    final duplicateId = c.result?.duplicateOf;
    return duplicateId != null
        ? repo.get(duplicateId).then((report) => [report])
        : repo.duplicates(c.position, c.categoryId!);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<Report>>(
    future: _future,
    builder: (context, snapshot) => Column(
      children: [
        if (snapshot.connectionState == ConnectionState.waiting)
          const Padding(
            padding: EdgeInsets.all(8),
            child: Center(child: CircularProgressIndicator()),
          ),
        if (snapshot.hasError)
          Column(
            children: [
              const SizedBox(height: 16),
              const Text('No se pudieron cargar los reportes relacionados.'),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => setState(() {
                  _future = _load();
                }),
                child: const Text('Reintentar'),
              ),
            ],
          ),
        if (snapshot.connectionState == ConnectionState.done &&
            !snapshot.hasError &&
            (snapshot.data?.isEmpty ?? true))
          const Padding(
            padding: EdgeInsets.only(top: 16),
            child: Text('No hay reportes relacionados disponibles.'),
          ),
        for (final report in snapshot.data ?? [])
          Column(
            children: [
              const SizedBox(height: 16),
              ReportTile(
                report: report,
                onTap: () {
                  FocusManager.instance.primaryFocus?.unfocus();
                  AldiaRoute.open(context, ReportDetailScreen(report: report));
                },
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: widget.controller.following
                    ? null
                    : () => widget.controller.follow(report),
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
