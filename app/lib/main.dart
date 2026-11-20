import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/config.dart';
import 'core/date_format.dart';
import 'data/api_client.dart';
import 'data/local_citizen_store.dart';
import 'data/clusters_api.dart';
import 'data/my_reports_store.dart';
import 'data/report_repository.dart';
import 'features/changelog/changelog.dart';
import 'features/drafts/draft_store.dart';
import 'features/outbox/outbox_service.dart';
import 'services/connectivity_service.dart';
import 'services/location_service.dart';
import 'services/geocoder_service.dart';
import 'services/photo_service.dart';
import 'services/citizen_auth_service.dart';
import 'services/test_account.dart';
import 'widgets/friendly_error_view.dart';

const _onboardingKey = 'onboarding_seen';
const _testAccountKey = 'test_account_active';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  ErrorWidget.builder = (details) => FriendlyErrorView(details: details);
  await initializeDateFormatting(appLanguageCode);
  final prefs = await SharedPreferences.getInstance();
  final changelog = ChangelogController(preferences: prefs);
  try {
    await changelog.initialize();
  } catch (_) {
    // An unreadable version never blocks the app; the dialog just stays away.
  }
  final client = http.Client();
  final auth = PhoneAuthService(
    client: client,
    store: const SecureCitizenCredentialStore(),
  );
  // A storage failure leaves reporting available in optional mode. Login shows
  // the actionable storage error and can retry initialization later.
  try {
    await auth.initialize();
  } catch (_) {}
  final testAccount = TestAccountSession(
    active: prefs.getBool(_testAccountKey) ?? false,
    onChanged: (active) => prefs.setBool(_testAccountKey, active),
  );
  final repository = ReportRepository(
    api: ApiClient(client: client, auth: auth),
    store: PrefsMyReportsStore(),
    local: LocalCitizenStore(preferences: prefs),
    requireCitizenLogin: AppConfig.requireCitizenLogin,
    testAccount: AppConfig.allowTestAccount ? testAccount : null,
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
      geocoder: NominatimGeocoder(client: client),
      drafts: drafts,
      outbox: outbox,
      connectivity: connectivity,
      clusters: HttpClustersApi(client: client),
      showOnboarding: !(prefs.getBool(_onboardingKey) ?? false),
      onOnboardingDone: () => unawaited(prefs.setBool(_onboardingKey, true)),
      changelog: changelog,
    ),
  );
}
