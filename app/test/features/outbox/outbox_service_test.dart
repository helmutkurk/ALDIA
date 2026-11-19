import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:aldia_app/data/report.dart';
import 'package:aldia_app/features/drafts/draft_record.dart';
import 'package:aldia_app/features/drafts/draft_store.dart';
import 'package:aldia_app/features/outbox/outbox_service.dart';
import 'package:aldia_app/services/connectivity_service.dart';
import 'package:aldia_app/services/photo_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import '../../support/fakes.dart';
import '../../support/memory_draft_store.dart';

class FakeConnectivity implements ConnectivityService {
  FakeConnectivity(this.isOnline);
  @override
  bool isOnline;
  final controller = StreamController<bool>.broadcast(sync: true);
  @override
  Stream<bool> get changes => controller.stream;
  @override
  Future<void> initialize() async {}
  @override
  void dispose() {
    unawaited(controller.close());
  }

  void setOnline(bool value) {
    isOnline = value;
    controller.add(value);
  }
}

class FakeClock implements RetryScheduler {
  DateTime now = DateTime.utc(2026, 11, 19);
  DateTime? due;
  void Function()? callback;
  @override
  void cancel() {
    due = null;
    callback = null;
  }

  @override
  void schedule(Duration delay, void Function() action) {
    due = now.add(delay);
    callback = action;
  }

  void elapse(Duration duration) {
    now = now.add(duration);
    if (due != null && !due!.isAfter(now)) {
      final action = callback;
      cancel();
      action?.call();
    }
  }
}

void main() {
  late Directory directory;
  late DraftStore drafts;
  late DraftStore queue;
  late FakeClock clock;
  late FakeConnectivity connectivity;
  late DraftRecord draft;
  final outboxes = <DurableOutbox>[];

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('aldia-outbox-');
    drafts = JsonDraftStore(directory: () async => directory);
    queue = JsonDraftStore(
      directory: () async => directory,
      folderName: 'outbox',
    );
    clock = FakeClock();
    connectivity = FakeConnectivity(true);
    final path = await drafts.storePhoto(
      'stable-uuid',
      CapturedPhoto(
        bytes: Uint8List.fromList([1, 2, 3]),
        filename: 'live.jpg',
        capturedAt: clock.now,
      ),
    );
    draft = DraftRecord(
      id: 'stable-uuid',
      step: 'review',
      position: const LatLng(14.6, -90.5),
      createdAt: clock.now,
      locationConfirmed: true,
      categoryId: 'pothole',
      capturedAt: clock.now,
      photoPath: path,
      note: 'Nota',
    );
    await drafts.save(draft);
  });
  tearDown(() async {
    for (final outbox in outboxes) {
      outbox.dispose();
    }
    outboxes.clear();
    await connectivity.controller.close();
    await directory.delete(recursive: true);
  });

  DurableOutbox make(Future<Report> Function(DraftRecord) send) {
    final outbox = DurableOutbox(
      store: queue,
      connectivity: connectivity,
      send: send,
      now: () => clock.now,
      scheduler: clock,
    );
    outboxes.add(outbox);
    return outbox;
  }

  test('offline enqueue persists before send and connectivity automatically delivers', () async {
    connectivity.isOnline = false;
    var calls = 0;
    final outbox = make((value) async {
      calls++;
      expect((await queue.loadAll()).single.id, value.id);
      expect(value.capturedAt, draft.capturedAt);
      return Report.fromJson(reportJson());
    });
    await outbox.initialize();
    expect(await outbox.enqueue(draft), isNull);
    expect(calls, 0);
    expect(outbox.entries.single.draft.id, draft.id);
    // Removing the editable draft cannot delete the independent queued photo.
    await drafts.delete(draft.id);
    expect(await queue.readPhoto(outbox.entries.single.draft), isNotNull);
    connectivity.setOnline(true);
    await outbox.retry();
    expect(calls, 1);
    expect(outbox.entries, isEmpty);
    expect(await queue.loadAll(), isEmpty);
  });

  test(
    'failed uploads use exponential backoff and reuse the idempotency key',
    () async {
      final keys = <String>[];
      final outbox = make((value) async {
        keys.add(value.id);
        if (keys.length <= 3) throw StateError('unreachable');
        return Report.fromJson(reportJson());
      });
      await outbox.initialize();
      expect(await outbox.enqueue(draft), isNull);
      expect(keys, ['stable-uuid']);
      expect(clock.due, clock.now.add(const Duration(seconds: 2)));
      await outbox.retry();
      expect(keys, hasLength(1));
      clock.elapse(const Duration(seconds: 2));
      await outbox.retry();
      expect(keys, hasLength(2));
      expect(clock.due, clock.now.add(const Duration(seconds: 4)));
      clock.elapse(const Duration(seconds: 4));
      await outbox.retry();
      expect(keys, hasLength(3));
      expect(clock.due, clock.now.add(const Duration(seconds: 8)));
      clock.elapse(const Duration(seconds: 8));
      await outbox.retry();
      expect(keys, List.filled(4, draft.id));
      expect(outbox.entries, isEmpty);
    },
  );

  test(
    'restart restores retry time and key without sending before the deadline',
    () async {
      final keys = <String>[];
      final first = make((value) async {
        keys.add(value.id);
        throw StateError('timeout after server might have accepted');
      });
      await first.initialize();
      await first.enqueue(draft);
      final deadline = first.entries.single.nextAttemptAt;
      first.dispose();
      outboxes.remove(first);
      final restored = make((value) async {
        keys.add(value.id);
        return Report.fromJson(reportJson());
      });
      await restored.initialize();
      expect(keys, hasLength(1));
      expect(restored.entries.single.attempts, 1);
      expect(restored.entries.single.nextAttemptAt, deadline);
      clock.elapse(const Duration(seconds: 2));
      await restored.retry();
      expect(keys, ['stable-uuid', 'stable-uuid']);
      expect(restored.entries, isEmpty);
    },
  );

  test(
    'a missing queued photo is retained for repair without an endless retry',
    () async {
      connectivity.isOnline = false;
      var calls = 0;
      final first = make((_) async {
        calls++;
        return Report.fromJson(reportJson());
      });
      await first.initialize();
      await first.enqueue(draft);
      final queued = first.entries.single.draft;
      await File(queued.photoPath!).delete();
      first.dispose();
      outboxes.remove(first);
      connectivity.isOnline = true;
      final restored = make((_) async {
        calls++;
        return Report.fromJson(reportJson());
      });
      await restored.initialize();
      expect(restored.entries.single.missingPhoto, isTrue);
      expect(restored.entries.single.draft.note, 'Nota');
      expect(calls, 0);
      expect(clock.due, isNull);
    },
  );

  test('simultaneous enqueue and retries send each key only once', () async {
    var calls = 0;
    final outbox = make((value) async {
      calls++;
      return Report.fromJson(reportJson());
    });
    await outbox.initialize();
    connectivity.isOnline = false;
    await Future.wait([outbox.enqueue(draft), outbox.enqueue(draft)]);
    expect(outbox.entries, hasLength(1));
    connectivity.setOnline(true);
    await Future.wait([outbox.retry(), outbox.retry()]);
    expect(calls, 1);
  });

  test(
    'background storage failure is exposed and the persisted queue survives',
    () async {
      final memory = MemoryDraftStore();
      final photo = (await drafts.readPhoto(draft))!;
      final path = await memory.storePhoto(draft.id, photo);
      queue = memory;
      connectivity.isOnline = false;
      final outbox = make((_) async {
        throw StateError('network failure');
      });
      await outbox.initialize();
      await outbox.enqueue(draft.copyWith(photoPath: path));
      final diskError = FileSystemException('disk full');
      memory.saveError = diskError;
      connectivity.setOnline(true);
      await Future<void>.delayed(Duration.zero);
      expect(outbox.persistenceError, same(diskError));
      expect(outbox.entries.single.draft.id, draft.id);
      expect((await memory.loadAll()).single.id, draft.id);
    },
  );
}
