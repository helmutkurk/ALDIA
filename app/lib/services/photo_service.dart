import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

class CapturedPhoto {
  const CapturedPhoto({
    required this.bytes,
    required this.filename,
    required this.capturedAt,
  });

  final Uint8List bytes;
  final String filename;

  /// Moment the photo was taken (UTC). The verifier checks freshness against it.
  final DateTime capturedAt;
}

abstract class PhotoService {
  Future<CapturedPhoto?> takePhoto();
}

/// Live camera, with an opt-in synthetic image for desktop/web debug demos.
class CameraPhotoService implements PhotoService {
  CameraPhotoService({ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  @override
  Future<CapturedPhoto?> takePhoto() async {
    if (kDebugMode &&
        const bool.fromEnvironment('DEV_FAKE_CAMERA') &&
        defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS) {
      return _syntheticPhoto();
    }
    final file = await _picker.pickImage(
      source: ImageSource.camera,
      maxWidth: 1280,
      imageQuality: 70,
    );
    if (file == null) return null;
    return CapturedPhoto(
      bytes: await file.readAsBytes(),
      filename: file.name.isEmpty ? 'photo.jpg' : file.name,
      capturedAt: DateTime.now().toUtc(),
    );
  }
}

/// Drawn locally: no bundled photo, gallery access or personal data.
Future<CapturedPhoto> _syntheticPhoto() async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final paint = ui.Paint();
  void rectangle(double x, double y, double w, double h, int color) {
    canvas.drawRect(
      ui.Rect.fromLTWH(x, y, w, h),
      paint..color = ui.Color(color),
    );
  }

  rectangle(0, 0, 640, 480, 0xffb9def1);
  rectangle(0, 100, 180, 150, 0xffd6d3d1);
  rectangle(470, 70, 170, 180, 0xffc5d3b3);
  for (final x in [30.0, 100.0, 500.0, 570.0]) {
    rectangle(x, 125, 35, 45, 0xff4b5563);
  }
  rectangle(0, 250, 640, 230, 0xff606974);
  rectangle(0, 240, 640, 25, 0xffd0c8b9);
  for (var y = 280.0; y < 480; y += 80) {
    rectangle(310, y, 20, 40, 0xffe5e7eb);
  }
  canvas.drawOval(
    const ui.Rect.fromLTWH(380, 330, 160, 85),
    paint..color = const ui.Color(0xff9a8066),
  );
  canvas.drawOval(
    const ui.Rect.fromLTWH(394, 338, 133, 60),
    paint..color = const ui.Color(0xff303842),
  );
  rectangle(0, 0, 640, 52, 0xff1f2937);
  final label =
      (ui.ParagraphBuilder(ui.ParagraphStyle(fontSize: 23))
            ..pushStyle(ui.TextStyle(color: const ui.Color(0xffffffff)))
            ..addText('DEMOSTRACIÓN · IMAGEN SINTÉTICA'))
          .build()
        ..layout(const ui.ParagraphConstraints(width: 610));
  canvas.drawParagraph(label, const ui.Offset(15, 12));
  label.dispose();
  final picture = recorder.endRecording();
  final image = await picture.toImage(640, 480);
  picture.dispose();
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return CapturedPhoto(
      bytes: data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      filename: 'sample.png',
      capturedAt: DateTime.now().toUtc(),
    );
  } finally {
    image.dispose();
  }
}
