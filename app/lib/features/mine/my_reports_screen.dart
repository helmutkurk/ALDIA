import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/categories.dart';
import '../../core/strings.dart';
import '../../data/report.dart';
import '../../data/report_repository.dart';
import '../../widgets/report_tile.dart';
import '../../widgets/routes.dart';
import '../detail/report_detail_screen.dart';
import '../drafts/draft_record.dart';
import '../drafts/draft_store.dart';
import '../outbox/outbox_service.dart';
import '../report/report_flow_screen.dart';

/// Unsent work first (outbox, then drafts), then the reports already sent.
class MyReportsScreen extends StatefulWidget {
  const MyReportsScreen({super.key});

  @override
  State<MyReportsScreen> createState() => _MyReportsScreenState();
}

class _MyReportsScreenState extends State<MyReportsScreen> {
  late Future<List<Report>> _sent;
  List<DraftRecord> _drafts = const [];

  @override
  void initState() {
    super.initState();
    _sent = context.read<ReportRepository>().mine();
    unawaited(_loadDrafts());
  }

  Future<void> _loadDrafts() async {
    final drafts = await context.read<DraftStore?>()?.loadAll();
    if (mounted) setState(() => _drafts = drafts ?? const []);
  }

  void _reloadSent() {
    setState(() {
      _sent = context.read<ReportRepository>().mine();
    });
  }

  Future<void> _openFlow([DraftRecord? draft]) async {
    await AldiaRoute.open<void>(context, ReportFlowScreen(draft: draft));
    if (!mounted) return;
    _reloadSent();
    unawaited(_loadDrafts());
  }

  Future<bool> _confirmDelete(String question) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          content: Text(question),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text(S.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text(S.delete),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _deleteDraft(DraftRecord draft) async {
    if (!await _confirmDelete(S.deleteDraftQuestion) || !mounted) return;
    await context.read<DraftStore?>()?.delete(draft.id);
    await _loadDrafts();
  }

  Future<void> _deleteQueued(OutboxService outbox, OutboxEntry entry) async {
    if (!await _confirmDelete(S.deleteOutboxQuestion)) return;
    await outbox.remove(entry.draft.id);
  }

  @override
  Widget build(BuildContext context) {
    final outbox = context.read<OutboxService?>();
    return Scaffold(
      appBar: AppBar(title: const Text(S.myReports)),
      body: ListenableBuilder(
        listenable: Listenable.merge([?outbox]),
        builder: (context, _) {
          final queued = outbox?.entries ?? const <OutboxEntry>[];
          return FutureBuilder<List<Report>>(
            future: _sent,
            builder: (context, snapshot) {
              final loading = snapshot.connectionState != ConnectionState.done;
              final sent = snapshot.data ?? const <Report>[];
              final empty = queued.isEmpty && _drafts.isEmpty && sent.isEmpty;
              if (!loading && !snapshot.hasError && empty) {
                return _EmptyState(onStart: _openFlow);
              }
              return ListView(
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  if (queued.isNotEmpty) ...[
                    const _SectionHeader(S.outbox),
                    for (final entry in queued)
                      _LocalCard(
                        categoryId: entry.draft.categoryId,
                        status: S.waitingNetwork,
                        statusIcon: Icons.cloud_off,
                        help: entry.missingPhoto
                            ? S.missingPhoto
                            : S.outboxWillRetry,
                        actions: [
                          if (!entry.missingPhoto)
                            _CardAction(
                              icon: Icons.refresh,
                              label: S.retryNow,
                              onPressed: () => unawaited(outbox!.retry()),
                            ),
                          _CardAction(
                            icon: Icons.delete_outline,
                            label: S.delete,
                            onPressed: () => _deleteQueued(outbox!, entry),
                          ),
                        ],
                      ),
                  ],
                  if (_drafts.isNotEmpty) ...[
                    const _SectionHeader(S.savedDrafts),
                    for (final draft in _drafts)
                      _LocalCard(
                        categoryId: draft.categoryId,
                        status: S.draft,
                        statusIcon: Icons.edit_note,
                        help: S.age(draft.createdAt, DateTime.now()),
                        actions: [
                          _CardAction(
                            icon: Icons.edit,
                            label: S.continueDraft,
                            onPressed: () => _openFlow(draft),
                          ),
                          _CardAction(
                            icon: Icons.delete_outline,
                            label: S.deleteDraft,
                            onPressed: () => _deleteDraft(draft),
                          ),
                        ],
                      ),
                  ],
                  if (queued.isNotEmpty || _drafts.isNotEmpty)
                    const _SectionHeader(S.sentReports),
                  if (loading)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  if (snapshot.hasError)
                    Center(
                      child: Column(
                        children: [
                          const Text(S.loadError),
                          TextButton(
                            onPressed: _reloadSent,
                            child: const Text(S.retry),
                          ),
                        ],
                      ),
                    ),
                  for (final report in sent)
                    ReportTile(
                      report: report,
                      onTap: () => AldiaRoute.open<void>(
                        context,
                        ReportDetailScreen(report: report),
                      ),
                    ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(title, style: Theme.of(context).textTheme.titleMedium),
    ),
  );
}

class _CardAction {
  const _CardAction({
    required this.icon,
    required this.label,
    required this.onPressed,
  });
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
}

/// A draft or a queued report: status as icon plus text, actions as text buttons.
class _LocalCard extends StatelessWidget {
  const _LocalCard({
    required this.categoryId,
    required this.status,
    required this.statusIcon,
    required this.help,
    required this.actions,
  });

  final String? categoryId;
  final String status;
  final IconData statusIcon;
  final String help;
  final List<_CardAction> actions;

  @override
  Widget build(BuildContext context) {
    final category = categoryId == null ? null : categoryById(categoryId!);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Semantics(
          container: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                category?.label ?? S.draft,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(statusIcon, size: 18),
                  const SizedBox(width: 6),
                  Expanded(child: Text(status)),
                ],
              ),
              Text(help),
              Wrap(
                spacing: 8,
                children: [
                  for (final action in actions)
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        minimumSize: const Size(48, 48),
                      ),
                      onPressed: action.onPressed,
                      icon: Icon(action.icon),
                      label: Text(action.label),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onStart});
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.add_a_photo_outlined, size: 48),
          const SizedBox(height: 12),
          const Text(S.emptyMine, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton(onPressed: onStart, child: const Text(S.firstReport)),
        ],
      ),
    ),
  );
}
