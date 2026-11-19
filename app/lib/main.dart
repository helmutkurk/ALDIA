import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'app.dart';
import 'data/api_client.dart';
import 'data/clusters_api.dart';
import 'data/my_reports_store.dart';
import 'data/report_repository.dart';
import 'features/drafts/draft_store.dart';
import 'features/outbox/outbox_service.dart';
import 'services/connectivity_service.dart';
import 'services/location_service.dart';
import 'services/photo_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final client = http.Client();
  final repository = ReportRepository(
    api: ApiClient(client: client),
    store: PrefsMyReportsStore(),
  );
  final connectivity = PlusConnectivityService();
  final drafts = JsonDraftStore();
  final queueStore = JsonDraftStore(folderName: 'outbox');
  // The draft id is the Idempotency-Key, so a retry never duplicates a report.
  final outbox = DurableOutbox(
    store: queueStore,
    connectivity: connectivity,
    send: (draft) async {
      final photo = await queueStore.readPhoto(draft);
      if (photo == null || draft.categoryId == null) {
        throw StateError('Incomplete queued report');
      }
      return repository.submit(
        photo: photo,
        category: draft.categoryId!,
        position: draft.position,
        note: draft.note,
        idempotencyKey: draft.id,
      );
    },
  );
  runApp(
    AldiaApp(
      repository: repository,
      location: const GeolocatorLocationService(),
      photos: CameraPhotoService(),
      drafts: drafts,
      outbox: outbox,
      connectivity: connectivity,
      clusters: HttpClustersApi(client: client),
    ),
  );
}
