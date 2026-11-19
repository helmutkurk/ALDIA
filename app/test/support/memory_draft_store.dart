import 'package:aldia_app/features/drafts/draft_record.dart';
import 'package:aldia_app/features/drafts/draft_store.dart';
import 'package:aldia_app/services/photo_service.dart';

/// In-memory service fake; tests can share photos across draft/outbox stores.
class MemoryDraftStore implements DraftStore {
  MemoryDraftStore({Map<String, CapturedPhoto>? sharedPhotos})
    : photos = sharedPhotos ?? {};

  final Map<String, DraftRecord> records = {};
  final Map<String, CapturedPhoto> photos;
  Object? saveError;

  @override
  Future<List<DraftRecord>> loadAll() async => List.of(records.values);

  @override
  Future<void> save(DraftRecord draft) async {
    if (saveError case final Object error) throw error;
    records[draft.id] = draft;
  }

  @override
  Future<void> delete(String id) async {
    records.remove(id);
  }

  @override
  Future<String> storePhoto(String id, CapturedPhoto photo) async {
    final path = '/private/$id-${photo.capturedAt.microsecondsSinceEpoch}.jpg';
    photos[path] = photo;
    return path;
  }

  @override
  Future<CapturedPhoto?> readPhoto(DraftRecord draft) async =>
      photos[draft.photoPath];
}
