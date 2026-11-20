import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/categories.dart';
import '../../core/config.dart';
import '../../core/strings.dart';
import '../../data/report_repository.dart';
import 'report_flow_controller.dart';
import 'report_flow_widgets.dart';

class NoteStep extends StatelessWidget {
  const NoteStep({super.key, required this.controller});
  final ReportFlowController controller;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (controller.photo != null)
        Image.memory(
          controller.photo!.bytes,
          height: 90,
          semanticLabel: S.photoAlternative,
          errorBuilder: (_, _, _) => const Icon(Icons.photo),
        ),
      TextFormField(
        initialValue: controller.note,
        maxLength: AppConfig.maxNoteLength,
        minLines: 3,
        maxLines: 8,
        onChanged: controller.setNote,
        decoration: const InputDecoration(
          labelText: S.noteLabel,
          hintText: S.noteHint,
          border: OutlineInputBorder(),
        ),
      ),
    ],
  );
}

class ReviewStep extends StatelessWidget {
  const ReviewStep({super.key, required this.controller});
  final ReportFlowController controller;
  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (c.photo != null)
          Image.memory(
            c.photo!.bytes,
            height: 180,
            semanticLabel: S.photoAlternative,
            errorBuilder: (_, _, _) => const Icon(Icons.photo),
          ),
        TextButton(
          onPressed: () => c.edit(FlowStep.photo),
          child: const Text('${S.edit}: ${S.stepPhoto}'),
        ),
        Text(
          c.placeLabel ??
              '${c.position.latitude.toStringAsFixed(5)}, ${c.position.longitude.toStringAsFixed(5)}',
        ),
        TextButton(
          onPressed: () => c.edit(FlowStep.location),
          child: const Text('${S.edit}: ${S.stepLocation}'),
        ),
        Text(categoryById(c.categoryId!).label),
        TextButton(
          onPressed: () => c.edit(FlowStep.category),
          child: const Text('${S.edit}: ${S.stepCategory}'),
        ),
        Text(c.note),
        TextButton(
          onPressed: () => c.edit(FlowStep.note),
          child: const Text('${S.edit}: ${S.stepNote}'),
        ),
        Text(
          S.uploadSize((c.photo?.bytes.length ?? 0) + 1024 + c.note.length * 4),
        ),
        const FlowNotice(S.publicPhotoNotice),
        const SizedBox(height: 16),
        Text(
          context.read<ReportRepository>().auth.isSignedIn
              ? 'Tu número está verificado. Podrás consultar este reporte desde tu cuenta.'
              : 'Para recibir avisos de tu reporte verifica tu número.',
        ),
      ],
    );
  }
}
