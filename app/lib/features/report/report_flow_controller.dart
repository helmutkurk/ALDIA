import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../../core/config.dart';
import '../../data/report.dart';
import '../../data/report_repository.dart';
import '../../services/location_service.dart';
import '../../services/photo_service.dart';

enum FlowStep { location, category, photo, note }

enum SubmitState { editing, sending, done, failed }

/// State of the four-step report flow: location, category, live photo, note.
class ReportFlowController extends ChangeNotifier {
  ReportFlowController({
    required this._repository,
    required this._location,
    required this._photos,
  });

  final ReportRepository _repository;
  final LocationService _location;
  final PhotoService _photos;

  FlowStep step = FlowStep.location;
  LatLng position = AppConfig.defaultCenter;
  bool locationConfirmed = false;
  bool locationDenied = false;
  String? categoryId;
  CapturedPhoto? photo;
  String note = '';
  SubmitState submitState = SubmitState.editing;
  Report? result;

  bool get canAdvance => switch (step) {
    FlowStep.location => locationConfirmed,
    FlowStep.category => categoryId != null,
    FlowStep.photo => photo != null,
    FlowStep.note => true,
  };

  bool get isLastStep => step == FlowStep.note;

  /// Incremented on every manual pick so a late GPS answer cannot overwrite it.
  int _manualPicks = 0;

  Future<void> useMyLocation() async {
    final picksBefore = _manualPicks;
    final current = await _location.currentPosition();
    if (picksBefore != _manualPicks) return;
    if (current == null) {
      locationDenied = true;
    } else {
      locationDenied = false;
      position = current;
      locationConfirmed = true;
    }
    notifyListeners();
  }

  void setPosition(LatLng value) {
    _manualPicks++;
    position = value;
    locationConfirmed = true;
    locationDenied = false;
    notifyListeners();
  }

  void setCategory(String id) {
    categoryId = id;
    notifyListeners();
  }

  Future<void> takePhoto() async {
    final captured = await _photos.takePhoto();
    if (captured != null) {
      photo = captured;
      notifyListeners();
    }
  }

  void setNote(String value) {
    note = value.length > AppConfig.maxNoteLength
        ? value.substring(0, AppConfig.maxNoteLength)
        : value;
  }

  void next() {
    if (!canAdvance || isLastStep) return;
    step = FlowStep.values[step.index + 1];
    notifyListeners();
  }

  void back() {
    if (step.index == 0) return;
    step = FlowStep.values[step.index - 1];
    notifyListeners();
  }

  /// After a rejected photo: keep location and category, ask for a new photo.
  void retakePhoto() {
    photo = null;
    result = null;
    submitState = SubmitState.editing;
    step = FlowStep.photo;
    notifyListeners();
  }

  Future<void> submit() async {
    final captured = photo;
    final category = categoryId;
    if (captured == null ||
        category == null ||
        submitState == SubmitState.sending) {
      return;
    }
    submitState = SubmitState.sending;
    notifyListeners();
    try {
      result = await _repository.submit(
        photo: captured,
        category: category,
        position: position,
        note: note,
      );
      submitState = SubmitState.done;
    } catch (_) {
      submitState = SubmitState.failed;
    }
    notifyListeners();
  }
}
