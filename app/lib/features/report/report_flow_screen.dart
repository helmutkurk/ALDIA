import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/strings.dart';
import '../../data/report_repository.dart';
import '../../services/connectivity_service.dart';
import '../../services/location_service.dart';
import '../../services/photo_service.dart';
import '../citizen/login_sheet.dart';
import '../drafts/draft_record.dart';
import '../drafts/draft_store.dart';
import '../outbox/outbox_service.dart';
import 'report_category_step.dart';
import 'report_details_steps.dart';
import 'report_duplicates_step.dart';
import 'report_flow_controller.dart';
import 'report_flow_widgets.dart';
import 'report_location_step.dart';
import 'report_photo_step.dart';
import 'report_result_view.dart';

class ReportFlowScreen extends StatelessWidget {
  const ReportFlowScreen({super.key, this.draft});
  final DraftRecord? draft;

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (context) {
      final controller = ReportFlowController(
        repository: context.read<ReportRepository>(),
        location: context.read<LocationService>(),
        photos: context.read<PhotoService>(),
        drafts: context.read<DraftStore?>(),
        outbox: context.read<OutboxService?>(),
        connectivity: context.read<ConnectivityService?>(),
      );
      unawaited(controller.loadCategories());
      if (draft != null) unawaited(controller.restore(draft!));
      return controller;
    },
    child: _FlowView(draft: draft),
  );
}

class _FlowView extends StatefulWidget {
  const _FlowView({this.draft});
  final DraftRecord? draft;
  @override
  State<_FlowView> createState() => _FlowViewState();
}

class _FlowViewState extends State<_FlowView> with WidgetsBindingObserver {
  final _heading = FocusNode();
  ReportFlowController? _controller;
  String? _lastHeading;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller ??= context.read<ReportFlowController>()
      ..addListener(_focusHeading);
  }

  void _focusHeading() {
    final c = _controller!;
    if (c.restoring || c.restoreFailed) return;
    final key = '${c.step.name}:${c.submitState.name}';
    if (_lastHeading == key) return;
    _lastHeading = key;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _heading.requestFocus();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_controller?.checkPhotoIntegrity());
    } else {
      unawaited(_controller?.saveDraft());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.removeListener(_focusHeading);
    unawaited(_controller?.saveDraft());
    _heading.dispose();
    super.dispose();
  }

  Future<void> _submit(ReportFlowController controller) async {
    final repository = context.read<ReportRepository>();
    final auth = repository.auth;
    if (!auth.isSignedIn) {
      final verified = await showCitizenLogin(context, auth);
      if (!mounted || !verified) return;
    }
    await controller.submit();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ReportFlowController>();
    _focusHeading();
    final outcome = c.submitState;
    final result =
        outcome == SubmitState.done ||
        outcome == SubmitState.queued ||
        outcome == SubmitState.manualSaved ||
        outcome == SubmitState.followed;
    final restoring = c.restoring || c.restoreFailed;
    return Scaffold(
      appBar: AppBar(
        title: const Text(S.newReport),
        actions: [
          IconButton(
            tooltip: 'Ayuda para reportar',
            icon: const Icon(Icons.help_outline),
            onPressed: () {
              FocusManager.instance.primaryFocus?.unfocus();
              showDialog<void>(
                context: context,
                animationStyle: MediaQuery.disableAnimationsOf(context)
                    ? AnimationStyle.noAnimation
                    : const AnimationStyle(
                        duration: Duration(milliseconds: 180),
                        reverseDuration: Duration(milliseconds: 120),
                      ),
                builder: (context) => AlertDialog(
                  title: const Text('Tu reporte, paso a paso'),
                  content: const Text(
                    'Confirma el lugar, elige una categoría y revisa los reportes cercanos. Luego toma una foto en el momento y revisa los datos antes de enviar.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text(S.close),
                    ),
                  ],
                ),
              );
            },
          ),
          if (Navigator.of(context).canPop())
            IconButton(
              tooltip: S.close,
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.close),
            ),
        ],
      ),
      bottomNavigationBar: result || outcome == SubmitState.sending || restoring
          ? null
          : Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                border: Border(
                  top: BorderSide(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
              ),
              child: SafeArea(
                top: false,
                child: Align(
                  alignment: Alignment.topCenter,
                  heightFactor: 1,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 680),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        MediaQuery.sizeOf(context).width < 600 ? 16 : 24,
                        12,
                        MediaQuery.sizeOf(context).width < 600 ? 16 : 24,
                        12,
                      ),
                      child: Builder(
                        builder: (context) {
                          final width = MediaQuery.sizeOf(context).width;
                          final gutter = width < 600 ? 16.0 : 24.0;
                          final contentWidth =
                              (width < 600 ? width : 680.0) - gutter * 2;
                          final stackActions =
                              contentWidth < 400 ||
                              MediaQuery.textScalerOf(context).scale(14) > 20;
                          final forward = FilledButton(
                            onPressed: c.canAdvance
                                ? (c.isLastStep ? () => _submit(c) : c.next)
                                : null,
                            child: Text(switch (c.step) {
                              FlowStep.location => S.confirmLocation,
                              FlowStep.photo => S.usePhoto,
                              FlowStep.duplicates => S.differentProblem,
                              FlowStep.review => S.send,
                              FlowStep.category || FlowStep.note => S.next,
                            }),
                          );
                          final back = c.step.index > 0
                              ? TextButton(
                                  onPressed: c.following || c.takingPhoto
                                      ? null
                                      : c.back,
                                  child: const Text(S.back),
                                )
                              : null;
                          final skipNotices =
                              c.isLastStep &&
                              !context
                                  .read<ReportRepository>()
                                  .requireCitizenLogin &&
                              !context.read<ReportRepository>().auth.isSignedIn;
                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (c.lookingForDuplicates) ...[
                                const LinearProgressIndicator(),
                                const SizedBox(height: 8),
                              ],
                              if (stackActions) ...[
                                forward,
                                if (back != null) ...[
                                  const SizedBox(height: 8),
                                  back,
                                ],
                              ] else if (back != null)
                                Row(
                                  children: [
                                    back,
                                    const SizedBox(width: 12),
                                    Expanded(child: forward),
                                  ],
                                )
                              else
                                forward,
                              if (skipNotices) ...[
                                const SizedBox(height: 8),
                                TextButton(
                                  onPressed: c.canAdvance ? c.submit : null,
                                  child: const Text('Continuar sin avisos'),
                                ),
                              ],
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.fromLTRB(
                MediaQuery.sizeOf(context).width < 600 ? 16 : 24,
                16,
                MediaQuery.sizeOf(context).width < 600 ? 16 : 24,
                24,
              ),
              children: [
                if (c.restoring) ...[
                  const LinearProgressIndicator(),
                  const SizedBox(height: 16),
                  const Text('Recuperando borrador…'),
                ] else if (c.restoreFailed) ...[
                  const Text('No se pudo recuperar el borrador.'),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: widget.draft == null
                        ? null
                        : () => c.restore(widget.draft!),
                    child: const Text('Reintentar'),
                  ),
                ] else ...[
                  if (!result) ...[
                    Text(
                      S.stepProgress(c.step.index + 1, FlowStep.values.length),
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        minHeight: 4,
                        value: (c.step.index + 1) / FlowStep.values.length,
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  Focus(
                    focusNode: _heading,
                    child: Semantics(
                      header: true,
                      child: Text(
                        result ? _resultTitle(c) : _title(c.step),
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (!result) ...[
                    SummaryRow(controller: c),
                    const SizedBox(height: 24),
                  ],
                  if (c.storageError) const FlowNotice(S.storageError),
                  if (outcome == SubmitState.sending) ...[
                    const LinearProgressIndicator(),
                    const SizedBox(height: 16),
                    const Text(S.sending),
                  ] else if (result)
                    ResultView(controller: c)
                  else ...[
                    switch (c.step) {
                      FlowStep.photo => PhotoStep(controller: c),
                      FlowStep.location => LocationStep(controller: c),
                      FlowStep.category => CategoryStep(controller: c),
                      FlowStep.duplicates => DuplicatesStep(controller: c),
                      FlowStep.note => NoteStep(controller: c),
                      FlowStep.review => ReviewStep(controller: c),
                    },
                    if (c.submitState == SubmitState.failed)
                      const FlowNotice(S.sendError),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _title(FlowStep step) => switch (step) {
  FlowStep.photo => S.stepPhoto,
  FlowStep.location => S.stepLocation,
  FlowStep.category => S.stepCategory,
  FlowStep.duplicates => S.stepDuplicates,
  FlowStep.note => S.stepNote,
  FlowStep.review => S.stepReview,
};

String _resultTitle(ReportFlowController c) => switch (c.submitState) {
  SubmitState.queued => S.waitingNetwork,
  SubmitState.manualSaved => S.draft,
  SubmitState.followed => S.following,
  _ => switch (c.result?.status) {
    'verified' =>
      '${S.resultVerified}${c.result?.verification?.isStub == true ? ' (prueba)' : ''}',
    'rejected' =>
      '${S.resultRejected}${c.result?.verification?.isStub == true ? ' (prueba)' : ''}',
    _ => S.resultPending,
  },
};
