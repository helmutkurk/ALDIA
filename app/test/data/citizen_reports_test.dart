import 'dart:convert';
import 'dart:typed_data';

import 'package:aldia_app/data/api_client.dart';
import 'package:aldia_app/data/report_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';

import '../support/fakes.dart';
import '../support/fake_auth.dart';

void main() {
  test(
    'authenticated creation preserves idempotency and device binding headers',
    () async {
      final auth = FakeCitizenAuth(signedIn: true);
      var called = false;
      final api = ApiClient(
        auth: auth,
        client: MockClient((request) async {
          called = true;
          expect(request.headers['authorization'], isNotNull);
          expect(request.headers['x-device-id'], isNotNull);
          expect(
            request.headers['idempotency-key'],
            '00000000-0000-4000-8000-000000000002',
          );
          return http.Response(jsonEncode(reportJson()), 201);
        }),
      );
      await api.createReport(
        photoBytes: Uint8List(1),
        filename: 'synthetic.jpg',
        category: 'pothole',
        position: const LatLng(14.6, -90.5),
        capturedAt: DateTime.now(),
        idempotencyKey: '00000000-0000-4000-8000-000000000002',
      );
      expect(called, isTrue);
    },
  );

  test(
    'mine paginates account reports and merges local ids without duplicates',
    () async {
      final auth = FakeCitizenAuth(signedIn: true);
      const localId = '00000000-0000-4000-8000-000000000001';
      const remoteId = '00000000-0000-4000-8000-000000000002';
      final offsets = <String>[];
      final api = ApiClient(
        auth: auth,
        client: MockClient((request) async {
          if (request.url.path.endsWith('/citizens/me/reports')) {
            expect(request.headers['authorization'], isNotNull);
            expect(request.headers['x-device-id'], isNotNull);
            final offset = request.url.queryParameters['offset']!;
            offsets.add(offset);
            return http.Response(
              jsonEncode({
                'items': [reportJson(id: offset == '0' ? localId : remoteId)],
                'total': 2,
              }),
              200,
            );
          }
          return http.Response(jsonEncode(reportJson(id: localId)), 200);
        }),
      );
      final repository = ReportRepository(
        api: api,
        store: MemoryStore()..saved.add(localId),
      );
      final reports = await repository.mine();
      expect(reports.map((r) => r.id).toSet(), {localId, remoteId});
      expect(reports, hasLength(2));
      expect(offsets, ['0', '1']);
    },
  );

  test('account report outage preserves locally tracked items', () async {
    final api = ApiClient(
      auth: FakeCitizenAuth(signedIn: true),
      client: MockClient((request) async {
        if (request.url.path.endsWith('/citizens/me/reports')) {
          throw http.ClientException('offline');
        }
        return http.Response(jsonEncode(reportJson()), 200);
      }),
    );
    final store = MemoryStore()..saved.add(reportJson()['id'] as String);
    expect(await ReportRepository(api: api, store: store).mine(), hasLength(1));
  });
  test(
    'account-only listing failure is surfaced instead of an empty history',
    () async {
      final api = ApiClient(
        auth: FakeCitizenAuth(signedIn: true),
        client: MockClient((_) async => throw http.ClientException('offline')),
      );
      await expectLater(
        ReportRepository(api: api, store: MemoryStore()).mine(),
        throwsA(isA<ApiException>()),
      );
    },
  );

  test(
    'server rejection clears revoked credentials before another submission',
    () async {
      final auth = FakeCitizenAuth(signedIn: true);
      final api = ApiClient(
        auth: auth,
        client: MockClient(
          (_) async =>
              http.Response('{"error":{"message":"Sesión vencida"}}', 401),
        ),
      );
      await expectLater(api.citizenReports(), throwsA(isA<ApiException>()));
      expect(auth.isSignedIn, isFalse);
    },
  );
}
