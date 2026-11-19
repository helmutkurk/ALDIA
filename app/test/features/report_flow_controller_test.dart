import 'package:aldia_app/features/report/report_flow_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import '../support/fakes.dart';

ReportFlowController build({
  MemoryStore? store,
  LatLng? gps = const LatLng(14.61, -90.52),
  String createdStatus = 'verified',
  bool failCreate = false,
}) => ReportFlowController(
  repository: fakeRepository(
    store: store,
    createdStatus: createdStatus,
    failCreate: failCreate,
  ),
  location: FakeLocation(gps),
  photos: FakePhotos(),
);

void main() {
  test('cannot advance until each step is complete', () async {
    final c = build();
    expect(c.canAdvance, isFalse);
    await c.useMyLocation();
    expect(c.canAdvance, isTrue);
    c.next();
    expect(c.step, FlowStep.category);
    expect(c.canAdvance, isFalse);
    c.setCategory('pothole');
    c.next();
    expect(c.step, FlowStep.photo);
    expect(c.canAdvance, isFalse);
    await c.takePhoto();
    expect(c.canAdvance, isTrue);
    c.next();
    expect(c.isLastStep, isTrue);
  });

  test('denied location keeps the step blocked and flags it', () async {
    final c = build(gps: null);
    await c.useMyLocation();
    expect(c.locationDenied, isTrue);
    expect(c.canAdvance, isFalse);
    c.setPosition(const LatLng(14.6, -90.5));
    expect(c.canAdvance, isTrue);
    expect(c.locationDenied, isFalse);
  });

  test('note is capped at the contract limit', () {
    final c = build();
    c.setNote('x' * 400);
    expect(c.note.length, 280);
  });

  test('submit stores the id on the device and exposes the result', () async {
    final store = MemoryStore();
    final c = build(store: store);
    await c.useMyLocation();
    c.setCategory('pothole');
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
      await c.useMyLocation();
      c.setCategory('pothole');
      await c.takePhoto();
      await c.submit();
      expect(c.result!.status, 'rejected');
      c.retakePhoto();
      expect(c.step, FlowStep.photo);
      expect(c.photo, isNull);
      expect(c.categoryId, 'pothole');
      expect(c.submitState, SubmitState.editing);
    },
  );

  test('server error leaves the flow editable with a failed state', () async {
    final c = build(failCreate: true);
    await c.useMyLocation();
    c.setCategory('pothole');
    await c.takePhoto();
    await c.submit();
    expect(c.submitState, SubmitState.failed);
    expect(c.result, isNull);
  });
}
