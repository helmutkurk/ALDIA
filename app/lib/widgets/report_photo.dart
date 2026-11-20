import 'package:flutter/material.dart';

/// Network photo with a stable neutral fallback and bounded decode memory.
class ReportPhoto extends StatelessWidget {
  const ReportPhoto({
    super.key,
    required this.url,
    required this.semanticLabel,
    required this.fit,
    this.height,
  });

  final String url;
  final String semanticLabel;
  final BoxFit fit;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return SizedBox(
      width: double.infinity,
      height: height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final logicalWidth = constraints.maxWidth;
          final dpr = MediaQuery.devicePixelRatioOf(context);
          final cacheWidth = logicalWidth.isFinite && logicalWidth > 0
              ? (logicalWidth * dpr).ceil().clamp(1, 1600).toInt()
              : null;
          return Semantics(
            image: true,
            label: semanticLabel,
            child: Image.network(
              url,
              width: double.infinity,
              height: constraints.maxHeight.isFinite
                  ? constraints.maxHeight
                  : null,
              fit: fit,
              cacheWidth: cacheWidth,
              excludeFromSemantics: true,
              frameBuilder: (context, child, frame, synchronous) {
                if (synchronous || reduceMotion) return child;
                return AnimatedOpacity(
                  opacity: frame == null ? 0 : 1,
                  duration: const Duration(milliseconds: 150),
                  curve: const Cubic(0.23, 1, 0.32, 1),
                  child: child,
                );
              },
              loadingBuilder: (context, child, progress) => progress == null
                  ? child
                  : ColoredBox(color: colors.surfaceContainerHighest),
              errorBuilder: (context, error, stackTrace) => ColoredBox(
                color: colors.surfaceContainerHighest,
                child: Center(
                  child: Icon(
                    Icons.image_not_supported_outlined,
                    size: 56,
                    color: colors.onSurfaceVariant,
                    semanticLabel: null,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
