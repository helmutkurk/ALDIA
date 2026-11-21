import 'package:flutter/material.dart';

import '../../core/categories.dart';
import '../../core/config.dart';
import '../../core/strings.dart';
import '../../widgets/place_text.dart';
import 'report_flow_controller.dart';
import 'report_flow_widgets.dart';

class NoteStep extends StatelessWidget {
  const NoteStep({super.key, required this.controller});
  final ReportFlowController controller;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (controller.photo != null) ...[
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Container(
            height: 120,
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            alignment: Alignment.center,
            child: Image.memory(
              controller.photo!.bytes,
              height: 120,
              fit: BoxFit.contain,
              semanticLabel: S.photoAlternative,
              errorBuilder: (_, _, _) => const Icon(Icons.photo),
            ),
          ),
        ),
        const SizedBox(height: 16),
      ],
      TextFormField(
        style: Theme.of(context).textTheme.bodyLarge,
        initialValue: controller.note,
        maxLength: AppConfig.maxNoteLength,
        minLines: 3,
        maxLines: 8,
        onChanged: controller.setNote,
        decoration: const InputDecoration(
          labelText: S.noteLabel,
          hintText: S.noteHint,
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
        if (c.photo != null) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Container(
              height: 200,
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              alignment: Alignment.center,
              child: Image.memory(
                c.photo!.bytes,
                height: 200,
                fit: BoxFit.contain,
                semanticLabel: S.photoAlternative,
                errorBuilder: (_, _, _) => const Icon(Icons.photo),
              ),
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => c.edit(FlowStep.photo),
            child: const Text('${S.edit}: ${S.stepPhoto}'),
          ),
        ],
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ReviewGroup(
                label: 'Ubicación',
                value: PlaceText(
                  position: c.position,
                  label: c.placeLabel,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                editLabel: '${S.edit}: ${S.stepLocation}',
                onEdit: () => c.edit(FlowStep.location),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Divider(height: 1),
              ),
              _ReviewGroup(
                label: 'Categoría',
                value: Text(
                  categoryById(c.categoryId!).label,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                editLabel: '${S.edit}: ${S.stepCategory}',
                onEdit: () => c.edit(FlowStep.category),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Divider(height: 1),
              ),
              _ReviewGroup(
                label: 'Descripción (opcional)',
                value: Text(
                  c.note.isEmpty ? 'Sin descripción' : c.note,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                editLabel: '${S.edit}: ${S.stepNote}',
                onEdit: () => c.edit(FlowStep.note),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          S.uploadSize((c.photo?.bytes.length ?? 0) + 1024 + c.note.length * 4),
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        const FlowNotice(S.publicPhotoNotice),
      ],
    );
  }
}

class _ReviewGroup extends StatelessWidget {
  const _ReviewGroup({
    required this.label,
    required this.value,
    required this.editLabel,
    required this.onEdit,
  });

  final String label;
  final Widget value;
  final String editLabel;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(label, style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 4),
      value,
      const SizedBox(height: 4),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton(onPressed: onEdit, child: Text(editLabel)),
      ),
    ],
  );
}
