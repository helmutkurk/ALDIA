import 'dart:convert';
import 'dart:typed_data';

import 'package:aldia_app/data/api_client.dart';
import 'package:aldia_app/data/my_reports_store.dart';
import 'package:aldia_app/data/report_repository.dart';
import 'package:aldia_app/services/location_service.dart';
import 'package:aldia_app/services/photo_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';

Map<String, dynamic> reportJson({
  String id = '11111111-1111-4111-8111-111111111111',
  String status = 'verified',
  bool withVerification = true,
}) => {
  'id': id,
  'category': 'pothole',
  'latitude': 14.6349,
  'longitude': -90.5069,
  'captured_at': '2026-11-19T18:30:00Z',
  'created_at': '2026-11-19T18:30:05Z',
  'status': status,
  'resolution': 'open',
  'note': null,
  'photo_url': '/api/reports/$id/photo',
  'verification': withVerification
      ? {
          'passed': status == 'verified',
          'mode': 'stub',
          'checks': [
            {'name': 'freshness', 'passed': true, 'detail': 'age 5 s'},
          ],
        }
      : null,
};

class MemoryStore implements MyReportsStore {
  final List<String> saved = [];

  @override
  Future<void> add(String id) async => saved.insert(0, id);

  @override
  Future<List<String>> ids() async => List.of(saved);
}

class FakeLocation implements LocationService {
  FakeLocation(this.value);

  final LatLng? value;

  @override
  Future<LatLng?> currentPosition() async => value;
}

class FakePhotos implements PhotoService {
  @override
  Future<CapturedPhoto?> takePhoto() async => CapturedPhoto(
    bytes: Uint8List.fromList([1, 2, 3]),
    filename: 'photo.jpg',
    capturedAt: DateTime.utc(2026, 11, 19, 18, 30),
  );
}

/// Repository backed by a MockClient that answers like the real API.
ReportRepository fakeRepository({
  MemoryStore? store,
  String createdStatus = 'verified',
  bool failCreate = false,
}) {
  final client = MockClient((http.Request request) async {
    final path = request.url.path;
    if (request.method == 'POST' && path.endsWith('/reports')) {
      if (failCreate) {
        return http.Response(
          jsonEncode({
            'error': {'code': 'server_error', 'message': 'boom'},
          }),
          500,
        );
      }
      return http.Response(jsonEncode(reportJson(status: createdStatus)), 201);
    }
    if (request.method == 'GET' && path.endsWith('/reports')) {
      return http.Response(
        jsonEncode({
          'items': [reportJson()],
          'total': 1,
        }),
        200,
      );
    }
    return http.Response(jsonEncode(reportJson()), 200);
  });
  return ReportRepository(
    api: ApiClient(client: client, baseUrl: 'http://api.test/api'),
    store: store ?? MemoryStore(),
  );
}
