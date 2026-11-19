import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:provider/provider.dart';

import '../../core/categories.dart';
import '../../core/config.dart';
import '../../core/strings.dart';
import '../../data/report_repository.dart';
import '../../services/location_service.dart';
import '../../services/photo_service.dart';
import '../../widgets/status_chips.dart';
import 'report_flow_controller.dart';

/// Four steps (SeeClickFix flow): location, category, live photo, note.
class ReportFlowScreen extends StatelessWidget {
  const ReportFlowScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => ReportFlowController(
        repository: context.read<ReportRepository>(),
        location: context.read<LocationService>(),
        photos: context.read<PhotoService>(),
      )..useMyLocation(),
      child: const _FlowView(),
    );
  }
}

class _FlowView extends StatelessWidget {
  const _FlowView();

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ReportFlowController>();
    return Scaffold(
      appBar: AppBar(title: const Text(S.newReport)),
      body: switch (c.submitState) {
        SubmitState.done => _ResultView(controller: c),
        SubmitState.sending => const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text(S.sending),
            ],
          ),
        ),
        _ => _Steps(controller: c),
      },
    );
  }
}

class _Steps extends StatelessWidget {
  const _Steps({required this.controller});

  final ReportFlowController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Stepper(
      currentStep: c.step.index,
      physics: const ClampingScrollPhysics(),
      controlsBuilder: (context, details) => Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Column(
          children: [
            if (c.submitState == SubmitState.failed)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text(S.sendError, style: TextStyle(color: Colors.red)),
              ),
            Row(
              children: [
                if (c.step.index > 0)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: c.back,
                      child: const Text(S.back),
                    ),
                  ),
                if (c.step.index > 0) const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: c.canAdvance
                        ? (c.isLastStep ? c.submit : c.next)
                        : null,
                    child: Text(c.isLastStep ? S.send : S.next),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      steps: [
        Step(
          title: const Text(S.stepLocation),
          isActive: c.step == FlowStep.location,
          state: c.locationConfirmed ? StepState.complete : StepState.indexed,
          content: _LocationStep(controller: c),
        ),
        Step(
          title: const Text(S.stepCategory),
          isActive: c.step == FlowStep.category,
          state: c.categoryId != null ? StepState.complete : StepState.indexed,
          content: _CategoryStep(controller: c),
        ),
        Step(
          title: const Text(S.stepPhoto),
          isActive: c.step == FlowStep.photo,
          state: c.photo != null ? StepState.complete : StepState.indexed,
          content: _PhotoStep(controller: c),
        ),
        Step(
          title: const Text(S.stepNote),
          isActive: c.step == FlowStep.note,
          content: _NoteStep(controller: c),
        ),
      ],
    );
  }
}

class _LocationStep extends StatefulWidget {
  const _LocationStep({required this.controller});

  final ReportFlowController controller;

  @override
  State<_LocationStep> createState() => _LocationStepState();
}

class _LocationStepState extends State<_LocationStep> {
  final MapController _mapController = MapController();

  @override
  void didUpdateWidget(covariant _LocationStep oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Keep the map centered on the point after "use my location".
    if (widget.controller.locationConfirmed) {
      _mapController.move(widget.controller.position, 16);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(S.locationHint),
        const SizedBox(height: 8),
        SizedBox(
          height: 260,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: c.position,
                initialZoom: AppConfig.defaultZoom + 2,
                onTap: (_, point) => c.setPosition(point),
              ),
              children: [
                TileLayer(
                  urlTemplate: AppConfig.tileUrl,
                  tileProvider: context.read<TileProvider>(),
                  userAgentPackageName: AppConfig.userAgentPackage,
                ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: c.position,
                      width: 40,
                      height: 40,
                      child: const Icon(
                        Icons.location_pin,
                        size: 40,
                        color: Colors.red,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: c.useMyLocation,
          icon: const Icon(Icons.my_location),
          label: const Text(S.useMyLocation),
        ),
        if (c.locationDenied) const Text(S.locationDenied),
      ],
    );
  }
}

class _CategoryStep extends StatelessWidget {
  const _CategoryStep({required this.controller});

  final ReportFlowController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(S.chooseCategory),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final category in reportCategories)
              ChoiceChip(
                avatar: Icon(category.icon, size: 18),
                label: Text(category.label),
                selected: controller.categoryId == category.id,
                onSelected: (_) => controller.setCategory(category.id),
              ),
          ],
        ),
      ],
    );
  }
}

class _PhotoStep extends StatelessWidget {
  const _PhotoStep({required this.controller});

  final ReportFlowController controller;

  @override
  Widget build(BuildContext context) {
    final photo = controller.photo;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(S.photoRequired),
        const SizedBox(height: 8),
        if (photo != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.memory(photo.bytes, height: 220, fit: BoxFit.cover),
          ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: controller.takePhoto,
          icon: const Icon(Icons.photo_camera),
          label: Text(photo == null ? S.takePhoto : S.retakePhoto),
        ),
      ],
    );
  }
}

class _NoteStep extends StatelessWidget {
  const _NoteStep({required this.controller});

  final ReportFlowController controller;

  @override
  Widget build(BuildContext context) {
    return TextField(
      maxLength: AppConfig.maxNoteLength,
      maxLines: 3,
      decoration: const InputDecoration(
        labelText: S.noteLabel,
        hintText: S.noteHint,
        border: OutlineInputBorder(),
      ),
      onChanged: controller.setNote,
    );
  }
}

class _ResultView extends StatelessWidget {
  const _ResultView({required this.controller});

  final ReportFlowController controller;

  @override
  Widget build(BuildContext context) {
    final report = controller.result!;
    final rejected = report.status == 'rejected';
    final title = switch (report.status) {
      'verified' => S.resultVerified,
      'rejected' => S.resultRejected,
      _ => S.resultPending,
    };
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Icon(
          rejected ? Icons.error_outline : Icons.check_circle_outline,
          size: 64,
          color: statusColor(report.status),
        ),
        const SizedBox(height: 8),
        Text(
          title,
          style: Theme.of(context).textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        if (rejected) ...[
          const SizedBox(height: 8),
          const Text(S.resultRejectedHelp, textAlign: TextAlign.center),
        ],
        if (report.verification != null) ...[
          const SizedBox(height: 16),
          ChecksList(verification: report.verification!),
        ],
        const SizedBox(height: 24),
        if (rejected)
          FilledButton(
            onPressed: controller.retakePhoto,
            child: const Text(S.retakePhoto),
          ),
        if (rejected) const SizedBox(height: 8),
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(S.close),
        ),
      ],
    );
  }
}
