import 'dart:io';
import 'dart:typed_data';

import 'package:aldia_app/features/drafts/draft_record.dart';
import 'package:aldia_app/features/drafts/draft_store.dart';
import 'package:aldia_app/services/photo_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

void main() {
  late Directory directory;
  late DraftStore store;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('aldia-drafts-');
    store = JsonDraftStore(directory: () async => directory);
  });
  tearDown(() async => directory.delete(recursive: true));

  test('save and restore fields and photo in private documents', () async {
    final capturedAt = DateTime.utc(2026, 11, 19);
    final path = await store.storePhoto(
      'stable-key',
      CapturedPhoto(
        bytes: Uint8List.fromList([1, 2, 3]),
        filename: 'camera.jpg',
        capturedAt: capturedAt,
      ),
    );
    final draft = DraftRecord(
      id: 'stable-key',
      step: 'review',
      position: const LatLng(14.6, -90.5),
      createdAt: capturedAt,
      locationConfirmed: true,
      categoryId: 'pothole',
      photoPath: path,
      capturedAt: capturedAt,
      note: 'Detalle',
      failedAttempts: 2,
    );
    await store.save(draft);
    final restored = (await store.loadAll()).single;
    expect(restored.toJson(), draft.toJson());
    expect(path, startsWith('${directory.path}/aldia/drafts/'));
    expect((await store.readPhoto(restored))!.bytes, [1, 2, 3]);
    expect((await store.readPhoto(restored))!.capturedAt, capturedAt);
  });

  test(
    'missing photo is reported without losing the other draft fields',
    () async {
      final draft = DraftRecord(
        id: 'stable-key',
        step: 'review',
        position: const LatLng(14.6, -90.5),
        createdAt: DateTime.utc(2026),
        locationConfirmed: true,
        categoryId: 'pothole',
        note: 'Conservar este detalle',
        failedAttempts: 2,
        photoPath: '${directory.path}/missing.jpg',
        capturedAt: DateTime.utc(2026),
      );
      await store.save(draft);
      final restored = (await store.loadAll()).single;
      expect(await store.readPhoto(restored), isNull);
      expect(restored.categoryId, 'pothole');
      expect(restored.note, 'Conservar este detalle');
      expect(restored.position, draft.position);
      expect(restored.failedAttempts, 2);
    },
  );

  test(
    'concurrent step saves retain the latest step and delete removes photos',
    () async {
      final draft = DraftRecord(
        id: 'one',
        step: 'photo',
        position: const LatLng(14.6, -90.5),
        createdAt: DateTime.utc(2026),
      );
      await Future.wait([
        store.save(draft),
        store.save(draft.copyWith(step: 'location')),
        store.save(draft.copyWith(step: 'category')),
      ]);
      expect((await store.loadAll()).single.step, 'category');
      final path = await store.storePhoto(
        'one',
        CapturedPhoto(
          bytes: Uint8List.fromList([1]),
          filename: 'camera.jpg',
          capturedAt: DateTime.utc(2026),
        ),
      );
      await store.delete('one');
      expect(await store.loadAll(), isEmpty);
      expect(await File(path).exists(), isFalse);
    },
  );

  test('a malformed draft does not hide intact drafts', () async {
    final draft = DraftRecord(
      id: 'one',
      step: 'photo',
      position: const LatLng(14.6, -90.5),
      createdAt: DateTime.utc(2026),
    );
    await store.save(draft);
    await File('${directory.path}/aldia/drafts/broken.json').writeAsString('{');
    expect((await store.loadAll()).single.id, 'one');
  });
}
