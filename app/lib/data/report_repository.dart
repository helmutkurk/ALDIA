import 'package:latlong2/latlong.dart';

import '../services/photo_service.dart';
import 'api_client.dart';
import 'my_reports_store.dart';
import 'report.dart';

class ReportRepository {
  ReportRepository({required this._api, required this._store});

  final ApiClient _api;
  final MyReportsStore _store;

  String photoUrl(Report report) => _api.photoUrl(report.photoUrl);

  Future<List<Report>> nearby() => _api.listReports();

  /// Reports sent from this device, newest first. Missing ids are skipped.
  Future<List<Report>> mine() async {
    final ids = await _store.ids();
    final results = await Future.wait(
      ids.map((id) async {
        try {
          return await _api.getReport(id);
        } on ApiException {
          return null;
        }
      }),
    );
    return results.whereType<Report>().toList();
  }

  Future<Report> submit({
    required CapturedPhoto photo,
    required String category,
    required LatLng position,
    String? note,
  }) async {
    final report = await _api.createReport(
      photoBytes: photo.bytes,
      filename: photo.filename,
      category: category,
      position: position,
      capturedAt: photo.capturedAt,
      note: note,
    );
    await _store.add(report.id);
    return report;
  }
}
