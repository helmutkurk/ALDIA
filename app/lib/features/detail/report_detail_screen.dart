import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/categories.dart';
import '../../core/citizen_states.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../data/report.dart';
import '../../data/report_repository.dart';
import '../../widgets/report_photo.dart';
import '../../widgets/report_tile.dart';
import '../../widgets/routes.dart';
import '../../widgets/status_chips.dart';

final _dateFormat = DateFormat('d/M/y HH:mm');

class ReportDetailScreen extends StatefulWidget {
  const ReportDetailScreen({super.key, required this.report});
  final Report report;

  @override
  State<ReportDetailScreen> createState() => _ReportDetailScreenState();
}

class _ReportDetailScreenState extends State<ReportDetailScreen> {
  late Future<Report> _detail;
  late final Future<List<Report>> _nearby;

  @override
  void initState() {
    super.initState();
    final repository = context.read<ReportRepository>();
    _detail = repository.get(widget.report.id);
    // A linked duplicate is shown through its own hint instead.
    _nearby = widget.report.duplicateOf != null
        ? Future.value(const <Report>[])
        : repository
              .duplicates(widget.report.position, widget.report.category)
              .then(
                (items) =>
                    items.where((r) => r.id != widget.report.id).toList(),
              )
              .catchError((_) => const <Report>[]);
  }

  void _reload() {
    setState(() {
      _detail = context.read<ReportRepository>().get(widget.report.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(S.reportDetail)),
      body: FutureBuilder<Report>(
        future: _detail,
        builder: (context, snapshot) {
          final report = snapshot.data ?? widget.report;
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: _DetailBody(
                report: report,
                nearby: _nearby,
                loadFailed: snapshot.hasError,
                loading: snapshot.connectionState != ConnectionState.done,
                onRetry: _reload,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _DetailBody extends StatelessWidget {
  const _DetailBody({
    required this.report,
    required this.nearby,
    required this.loadFailed,
    required this.loading,
    required this.onRetry,
  });

  final Report report;
  final Future<List<Report>> nearby;
  final bool loadFailed;
  final bool loading;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final category = categoryById(report.category);
    final state = citizenStateFor(report.citizenState);
    final events = report.events.where((e) => e.toState != null).toList();
    return ListView(
      padding: EdgeInsets.fromLTRB(
        MediaQuery.sizeOf(context).width < 600 ? AldiaSpace.l : AldiaSpace.xl,
        AldiaSpace.l,
        MediaQuery.sizeOf(context).width < 600 ? AldiaSpace.l : AldiaSpace.xl,
        AldiaSpace.xl + MediaQuery.viewPaddingOf(context).bottom,
      ),
      children: [
        if (loading) ...[
          Semantics(
            label: 'Actualizando reporte',
            child: const LinearProgressIndicator(),
          ),
          const SizedBox(height: 8),
        ],
        if (loadFailed) ...[
          Semantics(
            liveRegion: true,
            child: const Text(
              'No se pudo actualizar el reporte. Se muestran los últimos datos disponibles.',
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text(S.retry)),
        ],
        Semantics(
          header: true,
          child: Text(category.label, style: theme.textTheme.headlineSmall),
        ),
        const SizedBox(height: AldiaSpace.l),
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: ColoredBox(
            color: theme.colorScheme.surfaceContainerLow,
            child: AspectRatio(
              aspectRatio: 4 / 3,
              child: ReportPhoto(
                url: context.read<ReportRepository>().photoUrl(report),
                fit: BoxFit.contain,
                semanticLabel: S.photoLabel(category.label, state.label),
              ),
            ),
          ),
        ),
        const SizedBox(height: AldiaSpace.l),
        StatusChips(report: report),
        const SizedBox(height: AldiaSpace.m),
        Text(state.explanation, style: theme.textTheme.bodyLarge),
        const SizedBox(height: AldiaSpace.l),
        Text(
          _dateFormat.format(report.createdAt.toLocal()),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AldiaSpace.xs),
        Text(
          S.reference(report.id),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (report.note?.isNotEmpty == true) ...[
          const SizedBox(height: AldiaSpace.xl),
          Semantics(
            header: true,
            child: Text('Descripción', style: theme.textTheme.titleMedium),
          ),
          const SizedBox(height: AldiaSpace.s),
          Text(report.note!, style: theme.textTheme.bodyLarge),
        ],
        if (report.publicNote?.isNotEmpty == true) ...[
          const SizedBox(height: AldiaSpace.xl),
          Card(
            color: theme.colorScheme.surfaceContainerLow,
            child: Padding(
              padding: const EdgeInsets.all(AldiaSpace.l),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      S.officialMessage,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  const SizedBox(height: AldiaSpace.s),
                  Text(report.publicNote!, style: theme.textTheme.bodyLarge),
                ],
              ),
            ),
          ),
        ],
        if (report.duplicateOf != null) ...[
          const SizedBox(height: AldiaSpace.xl),
          _DuplicateHint(duplicateOf: report.duplicateOf!),
        ],
        const SizedBox(height: AldiaSpace.xxl),
        Semantics(
          header: true,
          child: Text(S.timeline, style: theme.textTheme.titleLarge),
        ),
        const SizedBox(height: AldiaSpace.m),
        for (final event in events) _TimelineEntry(event: event),
        if (events.isEmpty) Text(state.explanation),
        FutureBuilder<List<Report>>(
          future: nearby,
          builder: (context, snapshot) {
            final items = snapshot.data ?? const <Report>[];
            if (items.isEmpty) return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: AldiaSpace.xxl),
                Semantics(
                  header: true,
                  child: Text(S.nearbyHint, style: theme.textTheme.titleMedium),
                ),
                const SizedBox(height: AldiaSpace.m),
                for (final item in items) ...[
                  ReportTile(
                    report: item,
                    onTap: () => AldiaRoute.open<void>(
                      context,
                      ReportDetailScreen(report: item),
                    ),
                  ),
                  const SizedBox(height: AldiaSpace.l),
                ],
              ],
            );
          },
        ),
        if (report.verification != null) ...[
          const SizedBox(height: AldiaSpace.xxl),
          Semantics(
            header: true,
            child: Text(S.checks, style: theme.textTheme.titleLarge),
          ),
          const SizedBox(height: AldiaSpace.m),
          ChecksList(
            verification: report.verification!,
            category: category.label,
          ),
        ],
      ],
    );
  }
}

/// One status change with its public note, if any.
class _TimelineEntry extends StatelessWidget {
  const _TimelineEntry({required this.event});
  final ReportEvent event;

  @override
  Widget build(BuildContext context) {
    final state = citizenStateFor(event.toState);
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AldiaSpace.m),
      child: Semantics(
        container: true,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Icon(state.icon, size: 24),
              ),
            ),
            const SizedBox(width: AldiaSpace.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    state.label,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  if (event.at != null)
                    Padding(
                      padding: const EdgeInsets.only(top: AldiaSpace.xs),
                      child: Text(
                        _dateFormat.format(event.at!.toLocal()),
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ),
                  if (event.publicNote?.isNotEmpty == true)
                    Padding(
                      padding: const EdgeInsets.only(top: AldiaSpace.s),
                      child: Text(
                        event.publicNote!,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DuplicateHint extends StatelessWidget {
  const _DuplicateHint({required this.duplicateOf});
  final String duplicateOf;

  Future<void> _open(BuildContext context) async {
    final repository = context.read<ReportRepository>();
    try {
      final main = await repository.get(duplicateOf);
      if (context.mounted) {
        await AldiaRoute.open<void>(context, ReportDetailScreen(report: main));
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text(S.loadError)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AldiaSpace.l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.copy_all, size: 24),
                const SizedBox(width: AldiaSpace.s),
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      S.duplicateOfTitle,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AldiaSpace.s),
            Text(
              S.duplicateHint,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AldiaSpace.m),
            TextButton(
              onPressed: () => _open(context),
              child: const Text(S.viewMainReport),
            ),
          ],
        ),
      ),
    );
  }
}
