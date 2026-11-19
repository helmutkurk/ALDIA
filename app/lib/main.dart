import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'app.dart';
import 'data/api_client.dart';
import 'data/my_reports_store.dart';
import 'data/report_repository.dart';
import 'services/location_service.dart';
import 'services/photo_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final repository = ReportRepository(
    api: ApiClient(client: http.Client()),
    store: PrefsMyReportsStore(),
  );
  runApp(
    AldiaApp(
      repository: repository,
      location: const GeolocatorLocationService(),
      photos: CameraPhotoService(),
    ),
  );
}
