import 'package:flutter/material.dart';

import '../../core/strings.dart';
import 'report_flow_widgets.dart';
import '../../widgets/aldia_banner.dart';
import 'report_flow_controller.dart';

class PhotoStep extends StatelessWidget {
  const PhotoStep({super.key, required this.controller});
  final ReportFlowController controller;
  Future<void> _takePhoto(BuildContext context) {
    FocusManager.instance.primaryFocus?.unfocus();
    return controller.takePhoto();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(S.photoRequired, style: Theme.of(context).textTheme.bodyLarge),
      if (controller.missingPhoto)
        const FlowNotice(S.missingPhoto, kind: BannerKind.warning),
      if (controller.photoError)
        const FlowNotice(S.photoError, kind: BannerKind.error),
      if (controller.takingPhoto) ...[
        const LinearProgressIndicator(),
        const SizedBox(height: 12),
        const Text('Abriendo cámara…'),
      ],
      if (controller.photo == null) ...[
        const SizedBox(height: 16),
        Container(
          height: 96,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.center,
          child: ExcludeSemantics(
            child: Icon(
              Icons.camera_alt_outlined,
              size: 32,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: controller.takingPhoto ? null : () => _takePhoto(context),
          icon: const Icon(Icons.camera_alt_outlined),
          label: Text(
            controller.takingPhoto ? 'Abriendo cámara…' : S.takePhoto,
          ),
        ),
      ] else ...[
        const SizedBox(height: 16),
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Container(
            height: 220,
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            alignment: Alignment.center,
            child: Image.memory(
              controller.photo!.bytes,
              height: 220,
              fit: BoxFit.contain,
              semanticLabel: S.photoAlternative,
              errorBuilder: (_, _, _) =>
                  const Icon(Icons.broken_image, semanticLabel: S.imageReason),
            ),
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: controller.takingPhoto ? null : () => _takePhoto(context),
          icon: const Icon(Icons.camera_alt),
          label: Text(
            controller.takingPhoto ? 'Abriendo cámara…' : S.retakePhoto,
          ),
        ),
      ],
    ],
  );
}
