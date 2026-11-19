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

/// Live camera only, including debug and simulator builds.
class CameraPhotoService implements PhotoService {
  CameraPhotoService({ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  @override
  Future<CapturedPhoto?> takePhoto() async {
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
