import 'package:flutter/material.dart';

import '../../core/strings.dart';
import 'report_flow_widgets.dart';
import '../../widgets/aldia_banner.dart';
import 'report_flow_controller.dart';

class PhotoStep extends StatelessWidget {
  const PhotoStep({super.key, required this.controller});
  final ReportFlowController controller;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text(S.photoRequired),
      if (controller.missingPhoto)
        const FlowNotice(S.missingPhoto, kind: BannerKind.warning),
      if (controller.photoError)
        const FlowNotice(S.photoError, kind: BannerKind.error),
      if (controller.photo != null) ...[
        const SizedBox(height: 12),
        Image.memory(
          controller.photo!.bytes,
          height: 220,
          fit: BoxFit.contain,
          semanticLabel: S.photoAlternative,
          errorBuilder: (_, _, _) =>
              const Icon(Icons.broken_image, semanticLabel: S.imageReason),
        ),
      ],
      const SizedBox(height: 12),
      if (controller.photo == null)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Center(
            child: Semantics(
              button: true,
              label: 'Abrir cámara para tomar la foto',
              child: Tooltip(
                message: 'Abrir cámara',
                child: Material(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  shape: CircleBorder(
                    side: BorderSide(
                      color: Theme.of(context).colorScheme.primary,
                      width: 3,
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: controller.takePhoto,
                    child: SizedBox(
                      width: 176,
                      height: 176,
                      child: Icon(
                        Icons.camera_alt_outlined,
                        size: 72,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      OutlinedButton.icon(
        onPressed: controller.takePhoto,
        icon: const Icon(Icons.camera_alt),
        label: Text(controller.photo == null ? S.takePhoto : S.retakePhoto),
      ),
    ],
  );
}
