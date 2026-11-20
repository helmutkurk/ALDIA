import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/categories.dart';
import '../../core/strings.dart';
import '../../data/report.dart';
import '../../data/report_repository.dart';
import '../../core/theme.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/report_tile.dart';
import '../../widgets/routes.dart';
import '../detail/report_detail_screen.dart';
import '../drafts/draft_record.dart';
import '../drafts/draft_store.dart';
import '../outbox/outbox_service.dart';
import '../report/report_flow_screen.dart';

/// Unsent work first (outbox, then drafts), then the reports already sent.
class MyReportsScreen extends StatefulWidget {
  const MyReportsScreen({
    super.key,
    this.embedded = false,
    this.reloadToken = 0,
  });

  /// True inside the home shell: no app bar of its own.
  final bool embedded;

  /// Changing this value reloads the sent reports and the drafts.
  final int reloadToken;

  @override
  State<MyReportsScreen> createState() => _MyReportsScreenState();
}

class _MyReportsScreenState extends State<MyReportsScreen> {
  late Future<List<Report>> _sent;
  List<DraftRecord> _drafts = const [];
  bool _draftsLoading = true;
  bool _draftsFailed = false;
  int _draftLoadGeneration = 0;
  final Set<String> _pendingOperations = {};
  bool _queueRetrying = false;

  @override
  void initState() {
    super.initState();
    _sent = context.read<ReportRepository>().mine();
    unawaited(_loadDrafts());
  }

  @override
  void didUpdateWidget(MyReportsScreen old) {
    super.didUpdateWidget(old);
    if (old.reloadToken != widget.reloadToken) {
      _reloadSent();
      unawaited(_loadDrafts());
    }
  }

  Future<void> _loadDrafts() async {
    final generation = ++_draftLoadGeneration;
    final store = context.read<DraftStore?>();
    setState(() {
      _draftsLoading = true;
      _draftsFailed = false;
    });
    try {
      final drafts = await store?.loadAll() ?? const <DraftRecord>[];
      if (!mounted || generation != _draftLoadGeneration) return;
      setState(() {
        _drafts = drafts;
        _draftsLoading = false;
      });
    } catch (_) {
      if (!mounted || generation != _draftLoadGeneration) return;
      setState(() {
        _draftsFailed = true;
        _draftsLoading = false;
      });
    }
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

  Future<bool> _confirmDelete(String question) async {
    FocusManager.instance.primaryFocus?.unfocus();
    final scheme = Theme.of(context).colorScheme;
    return await showDialog<bool>(
          context: context,
          animationStyle: MediaQuery.disableAnimationsOf(context)
              ? AnimationStyle.noAnimation
              : const AnimationStyle(
                  duration: Duration(milliseconds: 180),
                  reverseDuration: Duration(milliseconds: 120),
                ),
          builder: (context) => AlertDialog(
            content: Text(question),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text(S.cancel),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: scheme.error,
                  foregroundColor: scheme.onError,
                ),
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text(S.delete),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _deleteDraft(DraftRecord draft) async {
    if (_pendingOperations.contains(draft.id)) return;
    final store = context.read<DraftStore?>();
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _pendingOperations.add(draft.id));
    try {
      final confirmed = await _confirmDelete(S.deleteDraftQuestion);
      if (!mounted || !confirmed) return;
      await store?.delete(draft.id);
      if (!mounted) return;
      setState(
        () => _drafts = _drafts.where((item) => item.id != draft.id).toList(),
      );
      await _loadDrafts();
    } catch (_) {
      if (mounted) {
        messenger.showSnackBar(const SnackBar(content: Text(S.storageError)));
      }
    } finally {
      if (mounted) setState(() => _pendingOperations.remove(draft.id));
    }
  }

  Future<void> _deleteQueued(OutboxService outbox, OutboxEntry entry) async {
    final id = entry.draft.id;
    if (_pendingOperations.contains(id)) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _pendingOperations.add(id));
    try {
      final confirmed = await _confirmDelete(S.deleteOutboxQuestion);
      if (!mounted || !confirmed) return;
      await outbox.remove(id);
    } catch (_) {
      if (mounted) {
        messenger.showSnackBar(const SnackBar(content: Text(S.storageError)));
      }
    } finally {
      if (mounted) setState(() => _pendingOperations.remove(id));
    }
  }

  Future<void> _retryQueue(OutboxService outbox) async {
    if (_queueRetrying) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _queueRetrying = true);
    try {
      await outbox.retry();
    } catch (_) {
      if (mounted) {
        messenger.showSnackBar(const SnackBar(content: Text(S.storageError)));
      }
    } finally {
      if (mounted) setState(() => _queueRetrying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final outbox = context.read<OutboxService?>();
    return Scaffold(
      appBar: widget.embedded ? null : AppBar(title: const Text(S.myReports)),
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
              if (!loading &&
                  !snapshot.hasError &&
                  !_draftsLoading &&
                  !_draftsFailed &&
                  outbox?.persistenceError == null &&
                  empty) {
                return _EmptyState(onStart: _openFlow);
              }
              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 680),
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(
                      MediaQuery.sizeOf(context).width < 600
                          ? AldiaSpace.l
                          : AldiaSpace.xl,
                      AldiaSpace.l,
                      MediaQuery.sizeOf(context).width < 600
                          ? AldiaSpace.l
                          : AldiaSpace.xl,
                      AldiaSpace.xl,
                    ),
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
                                  onPressed: _queueRetrying
                                      ? null
                                      : () => _retryQueue(outbox!),
                                ),
                              _CardAction(
                                icon: Icons.delete_outline,
                                label: S.delete,
                                onPressed:
                                    _pendingOperations.contains(entry.draft.id)
                                    ? null
                                    : () => _deleteQueued(outbox!, entry),
                              ),
                            ],
                          ),
                      ],
                      if (outbox?.persistenceError != null)
                        Semantics(
                          liveRegion: true,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(S.storageError),
                              TextButton(
                                onPressed: _queueRetrying
                                    ? null
                                    : () => _retryQueue(outbox!),
                                child: const Text(S.retry),
                              ),
                            ],
                          ),
                        ),
                      if (_draftsLoading || _draftsFailed) ...[
                        const _SectionHeader(S.savedDrafts),
                        if (_draftsLoading)
                          const Padding(
                            padding: EdgeInsets.all(16),
                            child: Center(child: CircularProgressIndicator()),
                          ),
                        if (_draftsFailed)
                          Semantics(
                            liveRegion: true,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'No se pudieron cargar los borradores.',
                                ),
                                TextButton(
                                  onPressed: () => unawaited(_loadDrafts()),
                                  child: const Text(S.retry),
                                ),
                              ],
                            ),
                          ),
                      ],
                      if (_drafts.isNotEmpty) ...[
                        if (!_draftsLoading && !_draftsFailed)
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
                                onPressed: _pendingOperations.contains(draft.id)
                                    ? null
                                    : () => _deleteDraft(draft),
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
                        Padding(
                          padding: const EdgeInsets.only(bottom: AldiaSpace.m),
                          child: ReportTile(
                            report: report,
                            onTap: () => AldiaRoute.open<void>(
                              context,
                              ReportDetailScreen(report: report),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
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
      padding: const EdgeInsets.fromLTRB(0, AldiaSpace.xl, 0, AldiaSpace.m),
      child: Text(title, style: Theme.of(context).textTheme.titleLarge),
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
  final VoidCallback? onPressed;
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
      margin: const EdgeInsets.only(bottom: AldiaSpace.m),
      child: Padding(
        padding: const EdgeInsets.all(AldiaSpace.l),
        child: Semantics(
          container: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                category?.label ?? S.draft,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: AldiaSpace.s),
              Row(
                children: [
                  Icon(statusIcon, size: 24),
                  const SizedBox(width: AldiaSpace.s),
                  Expanded(
                    child: Text(
                      status,
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AldiaSpace.s),
              Text(
                help,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AldiaSpace.m),
              Wrap(
                spacing: 8,
                runSpacing: AldiaSpace.s,
                children: [
                  for (final action in actions)
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        minimumSize: const Size(48, 48),
                        foregroundColor: action.icon == Icons.delete_outline
                            ? Theme.of(context).colorScheme.error
                            : Theme.of(context).colorScheme.primary,
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
  Widget build(BuildContext context) => EmptyState(
    icon: Icons.add_a_photo_outlined,
    title: S.emptyMine,
    help: 'Toma una foto del problema y sigue aquí sus cambios de estado.',
    actionLabel: S.firstReport,
    onAction: onStart,
  );
}
