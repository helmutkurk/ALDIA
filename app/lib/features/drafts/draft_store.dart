import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../services/photo_service.dart';
import 'draft_record.dart';

abstract interface class DraftStore {
  Future<List<DraftRecord>> loadAll();
  Future<void> save(DraftRecord draft);
  Future<void> delete(String id);
  Future<String> storePhoto(String id, CapturedPhoto photo);
  Future<CapturedPhoto?> readPhoto(DraftRecord draft);
}

/// One atomic JSON file per report, with photos in app-private documents.
/// Operations are serialized so a lifecycle save cannot overtake a step save.
class JsonDraftStore implements DraftStore {
  JsonDraftStore({
    Future<Directory> Function()? directory,
    this.folderName = 'drafts',
  }) : _directory = directory ?? getApplicationDocumentsDirectory;

  final Future<Directory> Function() _directory;
  final String folderName;
  Future<void> _pending = Future<void>.value();

  Future<T> _serial<T>(Future<T> Function() operation) {
    final result = _pending.then((_) => operation());
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<Directory> _folder() async {
    final root = await _directory();
    return Directory('${root.path}/aldia/$folderName').create(recursive: true);
  }

  String _safe(String id) {
    if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(id)) {
      throw ArgumentError.value(id, 'id');
    }
    return id;
  }

  @override
  Future<List<DraftRecord>> loadAll() => _serial(() async {
    final folder = await _folder();
    final records = <DraftRecord>[];
    await for (final entity in folder.list()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      try {
        records.add(
          DraftRecord.fromJson(
            jsonDecode(await entity.readAsString()) as Map<String, dynamic>,
          ),
        );
      } on FormatException {
        // Keep damaged files untouched; other valid drafts remain available.
      } on TypeError {
        // A partial or incompatible record must not hide the other reports.
      }
    }
    records.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return List.unmodifiable(records);
  });

  @override
  Future<void> save(DraftRecord draft) => _serial(() async {
    final folder = await _folder();
    final path = '${folder.path}/${_safe(draft.id)}.json';
    final temporary = File('$path.tmp');
    await temporary.writeAsString(jsonEncode(draft.toJson()), flush: true);
    await temporary.rename(path);
  });

  @override
  Future<void> delete(String id) => _serial(() async {
    final folder = await _folder();
    final safeId = _safe(id);
    final record = File('${folder.path}/$safeId.json');
    if (await record.exists()) await record.delete();
    // Photos are namespaced by report id, including superseded captures.
    await for (final entity in folder.list()) {
      if (entity is File &&
          entity.uri.pathSegments.last.startsWith('${safeId}_')) {
        await entity.delete();
      }
    }
  });

  @override
  Future<String> storePhoto(
    String id,
    CapturedPhoto photo,
  ) => _serial(() async {
    final folder = await _folder();
    final path =
        '${folder.path}/${_safe(id)}_${photo.capturedAt.microsecondsSinceEpoch}.jpg';
    final temporary = File('$path.tmp');
    await temporary.writeAsBytes(photo.bytes, flush: true);
    await temporary.rename(path);
    return path;
  });

  @override
  Future<CapturedPhoto?> readPhoto(DraftRecord draft) async {
    final path = draft.photoPath;
    final capturedAt = draft.capturedAt;
    if (path == null || capturedAt == null) return null;
    try {
      final file = File(path);
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) return null;
      return CapturedPhoto(
        bytes: bytes,
        filename: file.uri.pathSegments.last,
        capturedAt: capturedAt,
      );
    } on FileSystemException {
      return null;
    }
  }
}
