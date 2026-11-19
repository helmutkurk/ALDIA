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

/// Live camera only. The gallery is allowed in debug builds so the iOS simulator
/// (which has no camera) can be tested; release builds never accept old photos.
class CameraPhotoService implements PhotoService {
  CameraPhotoService({ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  @override
  Future<CapturedPhoto?> takePhoto() async {
    final source = kDebugMode && defaultTargetPlatform == TargetPlatform.iOS
        ? ImageSource.gallery
        : ImageSource.camera;
    final file = await _picker.pickImage(
      source: source,
      maxWidth: 1920,
      imageQuality: 85,
    );
    if (file == null) return null;
    return CapturedPhoto(
      bytes: await file.readAsBytes(),
      filename: file.name.isEmpty ? 'photo.jpg' : file.name,
      capturedAt: DateTime.now().toUtc(),
    );
  }
}
