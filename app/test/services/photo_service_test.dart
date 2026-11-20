import 'dart:ui' as ui;

import 'package:aldia_app/services/photo_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

class RecordingPicker extends ImagePicker {
  ImageSource? source;

  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) async {
    this.source = source;
    return null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const fakeCamera = bool.fromEnvironment('DEV_FAKE_CAMERA');

  tearDown(() => debugDefaultTargetPlatformOverride = null);

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    test('$platform always requests the live camera', () async {
      debugDefaultTargetPlatformOverride = platform;
      final picker = RecordingPicker();
      expect(await CameraPhotoService(picker: picker).takePhoto(), isNull);
      expect(picker.source, ImageSource.camera);
    });
  }

  test('desktop requires the explicit debug demo flag', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    final picker = RecordingPicker();
    final before = DateTime.now().toUtc();
    final photo = await CameraPhotoService(picker: picker).takePhoto();
    if (!fakeCamera) {
      expect(photo, isNull);
      expect(picker.source, ImageSource.camera);
      return;
    }

    expect(picker.source, isNull);
    expect(photo!.filename, 'sample.png');
    expect(photo.bytes.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
    expect(photo.capturedAt.isUtc, isTrue);
    expect(photo.capturedAt.isBefore(before), isFalse);
    final codec = await ui.instantiateImageCodec(photo.bytes);
    final frame = await codec.getNextFrame();
    expect(frame.image.width, greaterThanOrEqualTo(640));
    expect(frame.image.height, greaterThanOrEqualTo(480));
    frame.image.dispose();
    codec.dispose();
  });
}
