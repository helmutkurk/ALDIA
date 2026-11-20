import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:uuid/uuid.dart';

import '../../core/config.dart';
import '../../core/categories.dart';
import '../../data/report.dart';
import '../../data/report_repository.dart';
import '../../services/connectivity_service.dart';
import '../../services/location_service.dart';
import '../../services/photo_service.dart';
import '../drafts/draft_record.dart';
import '../drafts/draft_store.dart';
import '../outbox/outbox_service.dart';

enum FlowStep { location, category, duplicates, photo, note, review }

enum SubmitState {
  editing,
  sending,
  done,
  failed,
  queued,
  manualSaved,
  followed,
}

class ReportFlowController extends ChangeNotifier {
  ReportFlowController({
    required this._repository,
    required this._location,
    required this._photos,
    this._drafts,
    this._outbox,
    this._connectivity,
    String Function()? newId,
  }) : _newId = newId ?? const Uuid().v4 {
    _id = _newId();
  }

  final ReportRepository _repository;
  final LocationService _location;
  final PhotoService _photos;
  final DraftStore? _drafts;
  final OutboxService? _outbox;
  final ConnectivityService? _connectivity;
  final String Function() _newId;
  late String _id;
  DateTime _createdAt = DateTime.now().toUtc();
  String? _photoPath;
  CapturedPhoto? _storedPhoto;
  Future<void> _saving = Future.value();
  bool _disposed = false;
  int _manualPicks = 0;
  int _lookup = 0;

  FlowStep step = FlowStep.location;
  LatLng position = AppConfig.defaultCenter;
  bool locationConfirmed = false;
  bool locationDenied = false;
  LocationIssue? locationIssue;
  double? accuracy;
  LatLng? gpsPosition;
  bool locating = false;
  bool lookingForDuplicates = false;
  String? categoryId;
  String? placeLabel;
  List<ReportCategory> categories = reportCategories;

  Future<void> loadCategories() async {
    try {
      categories = await _repository.categories();
      _changed(save: false);
    } catch (_) {
      // The contract defaults keep an offline draft editable.
    }
  }

  CapturedPhoto? photo;
  String note = '';
  bool missingPhoto = false;
  bool photoError = false;
  bool storageError = false;
  int failedAttempts = 0;
  List<Report> duplicates = const [];
  SubmitState submitState = SubmitState.editing;
  Report? result;

  String get idempotencyKey => _id;
  bool get canAdvance =>
      !lookingForDuplicates &&
      switch (step) {
        FlowStep.photo => photo != null,
        FlowStep.location => locationConfirmed,
        FlowStep.category => categoryId != null,
        FlowStep.duplicates => true,
        FlowStep.note => true,
        FlowStep.review =>
          photo != null && categoryId != null && locationConfirmed,
      };
  bool get isLastStep => step == FlowStep.review;
  bool get canManualReview => failedAttempts >= 3;

  void _changed({bool save = true}) {
    if (_disposed) return;
    notifyListeners();
    if (save) unawaited(saveDraft());
  }

  Future<void> restore(DraftRecord draft) async {
    _id = draft.id;
    _createdAt = draft.createdAt;
    position = draft.position;
    locationConfirmed = draft.locationConfirmed;
    categoryId = draft.categoryId;
    placeLabel = draft.placeLabel;
    note = draft.note;
    failedAttempts = draft.failedAttempts;
    _photoPath = draft.photoPath;
    photo = await _drafts?.readPhoto(draft);
    _storedPhoto = photo;
    step =
        FlowStep.values.where((s) => s.name == draft.step).firstOrNull ??
        FlowStep.location;
    missingPhoto = photo == null && draft.photoPath != null;
    if (photo == null &&
        (draft.photoPath != null || step.index > FlowStep.photo.index)) {
      step = FlowStep.photo;
    }
    if (step == FlowStep.duplicates) {
      // Suggestions are transient; refresh after a restart.
      step = FlowStep.category;
    }
    // Also supports drafts created with the previous photo-first wizard.
    if (!locationConfirmed) {
      step = FlowStep.location;
    } else if (categoryId == null && step.index > FlowStep.category.index) {
      step = FlowStep.category;
    }
    _changed();
  }

  Future<void> checkPhotoIntegrity() async {
    await _saving;
    if (_photoPath == null || _drafts == null) return;
    final stored = await _drafts.readPhoto(_record());
    if (stored == null) {
      photo = null;
      _storedPhoto = null;
      missingPhoto = true;
      step = FlowStep.photo;
      submitState = SubmitState.editing;
      _changed();
    }
  }

  DraftRecord _record() => DraftRecord(
    id: _id,
    step: step.name,
    position: position,
    placeLabel: placeLabel,
    createdAt: _createdAt,
    locationConfirmed: locationConfirmed,
    categoryId: categoryId,
    note: note,
    photoPath: _photoPath,
    capturedAt: photo?.capturedAt,
    failedAttempts: failedAttempts,
  );

  Future<void> saveDraft() {
    final store = _drafts;
    if (store == null ||
        submitState == SubmitState.queued ||
        submitState == SubmitState.followed ||
        (submitState == SubmitState.done && result?.status != 'rejected')) {
      return _saving;
    }
    if (photo == null &&
        !locationConfirmed &&
        categoryId == null &&
        note.isEmpty) {
      return _saving;
    }
    final snapshot = _record();
    final captured = photo;
    _saving = _saving.then((_) async {
      try {
        var path = snapshot.photoPath;
        if (captured != null && !identical(captured, _storedPhoto)) {
          path = await store.storePhoto(snapshot.id, captured);
          _storedPhoto = captured;
          _photoPath = path;
        } else if (captured != null) {
          path = _photoPath;
        }
        await store.save(
          snapshot.copyWith(
            photoPath: path,
            capturedAt: captured?.capturedAt,
            clearPhoto: captured == null && !missingPhoto,
          ),
        );
        storageError = false;
      } catch (_) {
        storageError = true;
      }
      if (!_disposed) notifyListeners();
    });
    return _saving;
  }

  Future<void> useMyLocation() async {
    final picksBefore = _manualPicks;
    locating = true;
    _changed(save: false);
    final diagnostics = _location;
    LocationFix fix;
    if (diagnostics is LocationDiagnostics) {
      fix = await (diagnostics as LocationDiagnostics).locate();
    } else {
      final point = await _location.currentPosition();
      fix = LocationFix(
        position: point,
        issue: point == null ? LocationIssue.denied : null,
      );
    }
    locating = false;
    if (picksBefore != _manualPicks || _disposed) return;
    locationIssue = fix.issue;
    locationDenied = fix.issue != null;
    accuracy = fix.accuracy;
    gpsPosition = fix.position;
    if (fix.position != null) {
      position = fix.position!;
      placeLabel = null;
      locationConfirmed = true;
    }
    _changed();
  }

  Future<void> openLocationSettings() async {
    if (_location case final LocationDiagnostics diagnostics) {
      await diagnostics.openSettings();
    }
  }

  void setPosition(LatLng value, {String? label}) {
    _manualPicks++;
    _lookup++;
    position = value;
    placeLabel = label;
    locationConfirmed = true;
    locationDenied = false;
    // Keep poor GPS accuracy visible; the pin itself is always manually adjustable.
    _changed();
  }

  void setCategory(String id) {
    categoryId = id;
    _lookup++;
    _changed();
  }

  Future<void> takePhoto() async {
    photoError = false;
    try {
      final captured = await _photos.takePhoto();
      if (captured != null) {
        photo = captured;
        missingPhoto = false;
      }
    } catch (_) {
      photoError = true;
    }
    _changed();
    await _saving;
  }

  void setNote(String value) {
    note = String.fromCharCodes(value.runes.take(AppConfig.maxNoteLength));
    _changed();
  }

  Future<void> next() async {
    if (!canAdvance || isLastStep) return;
    if (step == FlowStep.category) {
      final generation = ++_lookup;
      lookingForDuplicates = true;
      _changed(save: false);
      List<Report> nearby = [];
      if (_connectivity?.isOnline != false) {
        try {
          nearby = await _repository
              .duplicates(position, categoryId!)
              .timeout(const Duration(seconds: 4));
        } catch (_) {
          /* Suggestions are optional; never block a report. */
        }
      }
      lookingForDuplicates = false;
      if (_disposed || generation != _lookup) {
        _changed(save: false);
        return;
      }
      duplicates = List.unmodifiable(nearby);
      step = FlowStep.duplicates;
    } else {
      step = FlowStep.values[step.index + 1];
    }
    _changed();
    if (step == FlowStep.location && !locationConfirmed) {
      unawaited(useMyLocation());
    }
  }

  void back() {
    if (step.index == 0) return;
    _lookup++;
    step = FlowStep.values[step.index - 1];
    _changed();
  }

  void edit(FlowStep target) {
    if (result?.status == 'rejected') _startCorrection();
    step = target;
    submitState = SubmitState.editing;
    _changed();
  }

  void _startCorrection() {
    // A corrected rejected submission is a new server attempt; network retries
    // of that attempt keep this key unchanged.
    _id = _newId();
    _photoPath = null;
    _storedPhoto = null;
    result = null;
  }

  void retakePhoto() {
    if (result?.status == 'rejected') _startCorrection();
    photo = null;
    _photoPath = null;
    _storedPhoto = null;
    result = null;
    submitState = SubmitState.editing;
    step = FlowStep.photo;
    _changed();
  }

  Future<void> follow(Report report) async {
    await _repository.follow(report);
    await _saving;
    await _drafts?.delete(_id);
    result = report;
    photo = null;
    submitState = SubmitState.followed;
    _changed(save: false);
  }

  Future<void> saveForManualReview() async {
    if (!canManualReview) return;
    await saveDraft();
    if (storageError) return;
    submitState = SubmitState.manualSaved;
    _changed(save: false);
  }

  Future<void> submit() async {
    final captured = photo;
    final category = categoryId;
    if (captured == null ||
        category == null ||
        !locationConfirmed ||
        submitState == SubmitState.sending ||
        (_repository.requireCitizenLogin && !_repository.auth.isSignedIn)) {
      return;
    }
    submitState = SubmitState.sending;
    _changed(save: false);
    await saveDraft();
    if (storageError) {
      submitState = SubmitState.failed;
      _changed(save: false);
      return;
    }
    try {
      if (_outbox != null) {
        result = await _outbox.enqueue(_record());
        if (result == null) {
          await _drafts?.delete(_id);
          submitState = SubmitState.queued;
          _changed(save: false);
          return;
        }
      } else {
        result = await _repository.submit(
          photo: captured,
          category: category,
          position: position,
          note: note,
          idempotencyKey: _id,
        );
      }
      submitState = SubmitState.done;
      if (result!.status == 'rejected') {
        failedAttempts++;
        await saveDraft();
      } else {
        await _drafts?.delete(_id);
      }
    } catch (_) {
      submitState = SubmitState.failed;
    }
    _changed(save: false);
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
