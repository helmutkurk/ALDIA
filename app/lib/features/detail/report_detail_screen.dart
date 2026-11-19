import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/categories.dart';
import '../../core/citizen_states.dart';
import '../../core/strings.dart';
import '../../data/report.dart';
import '../../data/report_repository.dart';
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
          return _DetailBody(
            report: report,
            nearby: _nearby,
            loadFailed: snapshot.hasError,
            onRetry: _reload,
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
    required this.onRetry,
  });

  final Report report;
  final Future<List<Report>> nearby;
  final bool loadFailed;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final category = categoryById(report.category);
    final state = citizenStateFor(report.citizenState);
    final events = report.events.where((e) => e.toState != null).toList();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Semantics(
          header: true,
          child: Text(category.label, style: theme.textTheme.headlineSmall),
        ),
        const SizedBox(height: 12),
        AspectRatio(
          aspectRatio: 4 / 3,
          child: Image.network(
            context.read<ReportRepository>().photoUrl(report),
            fit: BoxFit.contain,
            semanticLabel: S.photoLabel(category.label, state.label),
            errorBuilder: (_, _, _) => const Icon(
              Icons.broken_image,
              semanticLabel: S.photoAlternative,
            ),
          ),
        ),
        const SizedBox(height: 8),
        StatusChips(report: report),
        const SizedBox(height: 8),
        Text(state.explanation),
        const SizedBox(height: 8),
        Text(S.reference(report.id)),
        Text(_dateFormat.format(report.createdAt.toLocal())),
        if (report.note?.isNotEmpty == true) Text(report.note!),
        if (report.publicNote?.isNotEmpty == true) ...[
          const SizedBox(height: 12),
          Semantics(
            header: true,
            child: Text(S.officialMessage, style: theme.textTheme.titleMedium),
          ),
          Text(report.publicNote!),
        ],
        if (report.duplicateOf != null) ...[
          const SizedBox(height: 16),
          _DuplicateHint(duplicateOf: report.duplicateOf!),
        ],
        const SizedBox(height: 20),
        Semantics(
          header: true,
          child: Text(S.timeline, style: theme.textTheme.titleLarge),
        ),
        if (loadFailed)
          TextButton(onPressed: onRetry, child: const Text(S.retry)),
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
                const SizedBox(height: 16),
                Semantics(
                  header: true,
                  child: Text(S.nearbyHint, style: theme.textTheme.titleMedium),
                ),
                for (final item in items)
                  ReportTile(
                    report: item,
                    onTap: () => AldiaRoute.open<void>(
                      context,
                      ReportDetailScreen(report: item),
                    ),
                  ),
              ],
            );
          },
        ),
        if (report.verification != null) ...[
          const SizedBox(height: 16),
          Semantics(
            header: true,
            child: Text(S.checks, style: theme.textTheme.titleLarge),
          ),
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Semantics(
        container: true,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(state.icon),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    state.label,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  if (event.at != null)
                    Text(_dateFormat.format(event.at!.toLocal())),
                  if (event.publicNote?.isNotEmpty == true)
                    Text(event.publicNote!),
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
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.copy_all),
                const SizedBox(width: 8),
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
            const Text(S.duplicateHint),
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
