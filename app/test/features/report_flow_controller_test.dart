import 'dart:async';

import 'package:aldia_app/core/strings.dart';
import 'package:aldia_app/data/report.dart';
import 'package:aldia_app/features/drafts/draft_record.dart';
import 'package:aldia_app/features/report/report_flow_controller.dart';
import 'package:aldia_app/features/report/verification_feedback.dart';
import 'package:aldia_app/services/location_service.dart';
import 'package:aldia_app/services/photo_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../support/fakes.dart';
import '../support/memory_draft_store.dart';

class _RestorationStore extends MemoryDraftStore {
  final Completer<CapturedPhoto?> read = Completer<CapturedPhoto?>();
  bool fail = false;
  int saves = 0;

  @override
  Future<CapturedPhoto?> readPhoto(DraftRecord draft) {
    if (fail) throw StateError('synthetic storage failure');
    return read.future;
  }

  @override
  Future<void> save(DraftRecord draft) async {
    saves++;
    await super.save(draft);
  }
}

class _DeleteFailStore extends MemoryDraftStore {
  bool failDelete = true;

  @override
  Future<void> delete(String id) async {
    if (failDelete) throw StateError('synthetic delete failure');
    await super.delete(id);
  }
}

class _StaleIntegrityStore extends MemoryDraftStore {
  final Completer<void> readStarted = Completer<void>();
  final Completer<CapturedPhoto?> read = Completer<CapturedPhoto?>();

  @override
  Future<CapturedPhoto?> readPhoto(DraftRecord draft) {
    if (!readStarted.isCompleted) readStarted.complete();
    return read.future;
  }
}

class _PendingLocation implements LocationService, LocationDiagnostics {
  final Completer<LocationFix> result = Completer<LocationFix>();
  @override
  Future<LatLng?> currentPosition() async => (await result.future).position;
  @override
  Future<LocationFix> locate() => result.future;
  @override
  Future<void> openSettings() async {}
}

class _PendingPhotos implements PhotoService {
  final Completer<CapturedPhoto?> result = Completer<CapturedPhoto?>();
  int calls = 0;
  @override
  Future<CapturedPhoto?> takePhoto() {
    calls++;
    return result.future;
  }
}

ReportFlowController build({
  MemoryStore? store,
  LatLng? gps = const LatLng(14.61, -90.52),
  String createdStatus = 'verified',
  bool failCreate = false,
  List<Map<String, dynamic>> nearby = const [],
  bool failNearby = false,
  List<http.BaseRequest>? requests,
  bool Function()? failCreateWhen,
  MemoryDraftStore? drafts,
  LocationService? location,
}) => ReportFlowController(
  repository: fakeRepository(
    store: store,
    createdStatus: createdStatus,
    failCreate: failCreate,
    nearby: nearby,
    failNearby: failNearby,
    requests: requests,
    failCreateWhen: failCreateWhen,
  ),
  location: location ?? FakeLocation(gps),
  photos: FakePhotos(),
  drafts: drafts,
  newId: () => 'key-${DateTime.now().microsecondsSinceEpoch}',
);

Future<void> toCategory(ReportFlowController c) async {
  await c.useMyLocation();
  await c.next();
  c.setCategory('pothole');
}

void main() {
  test('the wizard order is place, category, photo, details, review', () {
    expect(FlowStep.values, [
      FlowStep.location,
      FlowStep.category,
      FlowStep.photo,
      FlowStep.note,
      FlowStep.review,
    ]);
  });

  test('cannot advance until each step is complete', () async {
    final c = build();
    expect(c.step, FlowStep.location);
    expect(c.canAdvance, isFalse);
    await c.useMyLocation();
    expect(c.canAdvance, isTrue);
    await c.next();
    expect(c.step, FlowStep.category);
    expect(c.canAdvance, isFalse);
    c.setCategory('pothole');
    await c.next();
    expect(c.step, FlowStep.photo);
    expect(c.photo, isNull);
    expect(c.canAdvance, isFalse);
    await c.takePhoto();
    await c.next();
    expect(c.step, FlowStep.note);
    await c.next();
    expect(c.isLastStep, isTrue);
  });

  test(
    'denied location keeps the step blocked and a manual pin unblocks it',
    () async {
      final c = build(gps: null);
      await c.useMyLocation();
      expect(c.locationDenied, isTrue);
      expect(c.canAdvance, isFalse);
      c.setPosition(const LatLng(14.6, -90.5));
      expect(c.canAdvance, isTrue);
      expect(c.locationDenied, isFalse);
    },
  );

  test(
    'denied forever, GPS off and poor accuracy are distinct states',
    () async {
      final location = FakeDiagnosticLocation(
        const LocationFix(issue: LocationIssue.deniedForever),
      );
      final c = build(location: location);
      await c.useMyLocation();
      expect(c.locationIssue, LocationIssue.deniedForever);
      await c.openLocationSettings();
      expect(location.settingsOpened, 1);
      location.fix = const LocationFix(issue: LocationIssue.serviceOff);
      await c.useMyLocation();
      expect(c.locationIssue, LocationIssue.serviceOff);
      location.fix = const LocationFix(
        position: LatLng(14.6, -90.5),
        accuracy: 80,
      );
      await c.useMyLocation();
      expect(c.locationIssue, isNull);
      expect(c.accuracy, 80);
      expect(c.locationConfirmed, isTrue);
    },
  );

  test('note is capped at the contract limit', () {
    final c = build();
    c.setNote('x' * 400);
    expect(c.note.length, 280);
  });

  test('category goes straight to the photo without a nearby lookup', () async {
    final requests = <http.BaseRequest>[];
    final c = build(requests: requests);
    await toCategory(c);
    await c.next();
    expect(c.step, FlowStep.photo);
    expect(requests.where((r) => r.url.path.endsWith('/nearby')), isEmpty);
    c.back();
    expect(c.step, FlowStep.category);
  });

  test('following a report ends the wizard without sending', () async {
    final store = MemoryStore();
    final requests = <http.BaseRequest>[];
    final c = build(store: store, requests: requests);
    await toCategory(c);
    await c.follow(
      Report.fromJson(reportJson(id: 'aaaa1111-1111-4111-8111-111111111111')),
    );
    expect(c.submitState, SubmitState.followed);
    // A follow remains separate from the ids of authored reports.
    expect(store.saved, isEmpty);
    expect(requests.where((r) => r.method == 'POST'), isEmpty);
  });

  test('submit stores the id on the device and exposes the result', () async {
    final store = MemoryStore();
    final c = build(store: store);
    await toCategory(c);
    await c.takePhoto();
    await c.submit();
    expect(c.submitState, SubmitState.done);
    expect(c.result!.status, 'verified');
    expect(store.saved, [c.result!.id]);
  });

  test(
    'a rejected report can be retaken without losing location and category',
    () async {
      final c = build(createdStatus: 'rejected');
      await toCategory(c);
      await c.takePhoto();
      c.setNote('Hueco grande');
      await c.submit();
      expect(c.result!.status, 'rejected');
      expect(c.failedAttempts, 1);
      c.retakePhoto();
      expect(c.step, FlowStep.photo);
      expect(c.photo, isNull);
      expect(c.categoryId, 'pothole');
      expect(c.locationConfirmed, isTrue);
      expect(c.note, 'Hueco grande');
      expect(c.submitState, SubmitState.editing);
    },
  );

  test('manual review is offered only after three failed attempts', () async {
    final c = build(createdStatus: 'rejected', drafts: MemoryDraftStore());
    await toCategory(c);
    await c.takePhoto();
    for (var i = 0; i < 3; i++) {
      expect(c.canManualReview, isFalse);
      await c.submit();
      c.retakePhoto();
      await c.takePhoto();
    }
    expect(c.canManualReview, isTrue);
  });

  test('server error leaves the flow editable with a failed state', () async {
    final c = build(failCreate: true);
    await toCategory(c);
    await c.takePhoto();
    await c.submit();
    expect(c.submitState, SubmitState.failed);
    expect(c.result, isNull);
  });

  test('a retry after a failure reuses the same Idempotency-Key', () async {
    final requests = <http.BaseRequest>[];
    var fail = true;
    final c = build(requests: requests, failCreateWhen: () => fail);
    await toCategory(c);
    await c.takePhoto();
    await c.submit();
    expect(c.submitState, SubmitState.failed);
    fail = false;
    await c.submit();
    expect(c.submitState, SubmitState.done);
    final keys = requests
        .where((r) => r.method == 'POST')
        .map((r) => r.headers['Idempotency-Key'])
        .toList();
    expect(keys, hasLength(2));
    expect(keys.first, isNotNull);
    expect(keys.last, keys.first);
    expect(keys.first, c.idempotencyKey);
  });

  group('drafts', () {
    test(
      'restoration is atomic, skips lifecycle saves, and can retry errors',
      () async {
        final drafts = _RestorationStore();
        final record = DraftRecord(
          id: 'restored-id',
          step: 'note',
          position: const LatLng(5, 6),
          createdAt: DateTime.utc(2026),
          locationConfirmed: true,
          categoryId: 'pothole',
          note: 'persisted note',
          photoPath: '/photo.jpg',
        );
        final c = build(drafts: drafts);
        final restore = c.restore(record);
        expect(c.restoring, isTrue);
        expect(c.note, '');
        await c.saveDraft();
        expect(drafts.saves, 0);
        drafts.read.complete(null);
        await restore;
        expect(c.note, 'persisted note');
        expect(c.step, FlowStep.photo);
        expect(drafts.saves, 1);

        final retryStore = _RestorationStore()..fail = true;
        final retry = build(drafts: retryStore);
        await retry.restore(record);
        expect(retry.restoreFailed, isTrue);
        await retry.saveDraft();
        expect(retryStore.saves, 0);
        retryStore.fail = false;
        final retryRestore = retry.restore(record);
        retryStore.read.complete(null);
        await retryRestore;
        expect(retry.restoreFailed, isFalse);
        expect(retry.note, 'persisted note');
      },
    );

    test('every step change and edit autosaves the draft', () async {
      final drafts = MemoryDraftStore();
      final c = build(drafts: drafts);
      await c.useMyLocation();
      await c.next();
      await c.saveDraft();
      expect(drafts.records.values.single.step, 'category');
      final restored = build(drafts: drafts);
      await restored.restore(drafts.records.values.single);
      expect(restored.step, FlowStep.category);
      expect(restored.photo, isNull);
      expect(restored.missingPhoto, isFalse);
      c.setNote('hola');
      await c.saveDraft();
      expect(drafts.records.values.single.note, 'hola');
    });

    test(
      'a draft saved on the removed duplicates step resumes at the photo',
      () async {
        final drafts = MemoryDraftStore();
        final first = build(drafts: drafts);
        await toCategory(first);
        await first.saveDraft();
        final record = drafts.records.values.single.copyWith(
          step: 'duplicates',
        );

        final resumed = build(drafts: drafts);
        await resumed.restore(record);
        expect(resumed.step, FlowStep.photo);
        expect(resumed.categoryId, 'pothole');
      },
    );

    test('resume restores fields and photo at the saved step', () async {
      final drafts = MemoryDraftStore();
      final first = build(drafts: drafts);
      await toCategory(first);
      await first.next();
      await first.next();
      await first.takePhoto();
      await first.next();
      first.setNote('Hueco');
      await first.saveDraft();
      final record = drafts.records.values.single;

      final resumed = build(drafts: drafts);
      await resumed.restore(record);
      expect(resumed.step, FlowStep.note);
      expect(resumed.photo, isNotNull);
      expect(resumed.categoryId, 'pothole');
      expect(resumed.note, 'Hueco');
      expect(resumed.missingPhoto, isFalse);
      expect(resumed.idempotencyKey, record.id);
    });

    test(
      'a missing photo sends the citizen to retake only that photo',
      () async {
        final drafts = MemoryDraftStore();
        final first = build(drafts: drafts);
        await toCategory(first);
        await first.takePhoto();
        first.setNote('Hueco');
        await first.saveDraft();
        final record = drafts.records.values.single;
        drafts.photos.clear();

        final resumed = build(drafts: drafts);
        await resumed.restore(record);
        expect(resumed.missingPhoto, isTrue);
        expect(resumed.step, FlowStep.photo);
        expect(resumed.photo, isNull);
        expect(resumed.categoryId, 'pothole');
        expect(resumed.note, 'Hueco');
        expect(resumed.locationConfirmed, isTrue);
        await resumed.takePhoto();
        expect(resumed.missingPhoto, isFalse);
        expect(resumed.canAdvance, isTrue);
      },
    );

    test(
      'the integrity check on resume to foreground catches a purged photo',
      () async {
        final drafts = MemoryDraftStore();
        final c = build(drafts: drafts);
        await toCategory(c);
        await c.takePhoto();
        await c.saveDraft();
        drafts.photos.clear();
        await c.checkPhotoIntegrity();
        expect(c.missingPhoto, isTrue);
        expect(c.step, FlowStep.photo);
      },
    );

    test('a sent report removes its draft', () async {
      final drafts = MemoryDraftStore();
      final c = build(drafts: drafts);
      await toCategory(c);
      await c.takePhoto();
      await c.submit();
      expect(drafts.records, isEmpty);
    });

    test('DraftRecord is the id used as the idempotency key', () {
      final record = DraftRecord(
        id: 'k',
        step: 'photo',
        position: const LatLng(0, 0),
        createdAt: DateTime.utc(2026),
      );
      expect(DraftRecord.fromJson(record.toJson()).id, 'k');
    });
  });

  test('manual location wins while GPS remains pending', () async {
    final location = _PendingLocation();
    final c = build(location: location);
    final pending = c.useMyLocation();
    expect(c.locating, isTrue);
    await c.useMyLocation();
    c.setPosition(const LatLng(1, 2), label: 'Lugar manual');
    c.locationIssue = LocationIssue.serviceOff;
    location.result.complete(const LocationFix(position: LatLng(14, -90)));
    await pending;
    expect(c.locating, isFalse);
    expect(c.position, const LatLng(1, 2));
    expect(c.placeLabel, 'Lugar manual');
    expect(c.locationIssue, LocationIssue.serviceOff);
  });

  test(
    'camera is single flight and late capture after dispose is discarded',
    () async {
      final photos = _PendingPhotos();
      final drafts = MemoryDraftStore();
      final c = ReportFlowController(
        repository: fakeRepository(),
        location: FakeLocation(null),
        photos: photos,
        drafts: drafts,
      );
      final first = c.takePhoto();
      await c.takePhoto();
      expect(photos.calls, 1);
      expect(c.takingPhoto, isTrue);
      c.dispose();
      photos.result.complete(await FakePhotos().takePhoto());
      await first;
      expect(c.photo, isNull);
      expect(drafts.records, isEmpty);
      expect(drafts.photos, isEmpty);
    },
  );

  test(
    'follow persistence failure stays recoverable and can be retried',
    () async {
      final drafts = _DeleteFailStore();
      final c = build(drafts: drafts);
      final report = Report.fromJson(reportJson());
      await c.follow(report);
      expect(c.followError, isTrue);
      expect(c.following, isFalse);
      expect(c.submitState, SubmitState.editing);
      drafts.failDelete = false;
      await c.follow(report);
      expect(c.followError, isFalse);
      expect(c.submitState, SubmitState.followed);
      expect(c.result?.id, report.id);
    },
  );

  test('stale integrity read cannot reset a submitted outcome', () async {
    final drafts = _StaleIntegrityStore();
    final c = build(drafts: drafts);
    await c.takePhoto();
    final photo = c.photo;
    final integrity = c.checkPhotoIntegrity();
    await drafts.readStarted.future;
    c
      ..submitState = SubmitState.done
      ..result = Report.fromJson(reportJson());
    drafts.read.complete(null);
    await integrity;
    expect(c.submitState, SubmitState.done);
    expect(identical(c.photo, photo), isTrue);
  });

  test('stale integrity read cannot clear a newer captured photo', () async {
    final drafts = _StaleIntegrityStore();
    final c = build(drafts: drafts);
    await c.takePhoto();
    final firstPhoto = c.photo;
    final integrity = c.checkPhotoIntegrity();
    await drafts.readStarted.future;
    c.retakePhoto();
    await c.takePhoto();
    final currentPhoto = c.photo;
    expect(identical(currentPhoto, firstPhoto), isFalse);
    drafts.read.complete(null);
    await integrity;
    expect(identical(c.photo, currentPhoto), isTrue);
    expect(c.missingPhoto, isFalse);
  });

  group('verifier feedback', () {
    const checks = ['place', 'freshness', 'duplicate', 'category', 'image'];
    const reasons = {
      'place': S.placeReason,
      'freshness': S.freshnessReason,
      'duplicate': S.duplicateReason,
      'image': S.imageReason,
    };
    const fixes = {
      'place': S.placeFix,
      'freshness': S.freshnessFix,
      'duplicate': S.duplicateFix,
      'category': S.categoryFix,
      'image': S.imageFix,
    };

    for (final name in checks) {
      test('$name maps to a plain reason and a way to fix it', () {
        final feedback = feedbackFor(
          VerificationCheck(name: name, passed: false, detail: 'x'),
          'Bache',
        );
        expect(feedback.title, S.checkTitles[name]);
        expect(feedback.reason, reasons[name] ?? S.categoryReason('Bache'));
        expect(feedback.fix, fixes[name]);
      });
    }

    test('an unknown check never blames the citizen and says what to do', () {
      final feedback = feedbackFor(
        const VerificationCheck(name: 'new_check', passed: false, detail: ''),
        'Bache',
      );
      expect(feedback.reason, S.checkUnknown);
      expect(feedback.fix, S.checkUnknownFix);
    });

    test(
      'several failures come ordered by ease of fix; passed ones are omitted',
      () {
        const verification = Verification(
          passed: false,
          mode: 'stub',
          checks: [
            VerificationCheck(name: 'image', passed: false, detail: ''),
            VerificationCheck(name: 'freshness', passed: false, detail: ''),
            VerificationCheck(name: 'place', passed: true, detail: ''),
            VerificationCheck(name: 'category', passed: false, detail: ''),
          ],
        );
        expect(orderedFailures(verification).map((c) => c.name), [
          'category',
          'freshness',
          'image',
        ]);
        expect(verification.isStub, isTrue);
      },
    );
  });
}
