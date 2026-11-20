import 'dart:convert';

import 'package:aldia_app/data/api_client.dart';
import 'package:aldia_app/data/report.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';

import '../support/fakes.dart';

void main() {
  for (final wrapped in [false, true]) {
    test(
      'nearby parsing preserves ${wrapped ? 'wrapped' : 'legacy list'} response',
      () async {
        final items = [reportJson()];
        final client = MockClient(
          (_) async => http.Response(
            jsonEncode(wrapped ? {'items': items} : items),
            200,
          ),
        );
        addTearDown(client.close);
        final reports = await ApiClient(
          client: client,
        ).nearbyReports(position: const LatLng(14, -90), category: 'pothole');
        expect(reports.single.id, items.single['id']);
        expect(reports.single.verification!.checks.single.passed, isTrue);
      },
    );
  }

  test('typed model boundary keeps defaults and optional event dates', () {
    final json = reportJson()..remove('resolution');
    json['events'] = [
      <Object?, Object?>{
        'at': 123,
        'to_state': 'nuevo',
        'staff_note': 'ignored',
      },
    ];
    final report = Report.fromJson(json);
    expect(report.resolution, 'open');
    expect(report.events.single.at, isNull);
    expect(report.events.single.toState, 'nuevo');
    expect(() => report.events.clear(), throwsUnsupportedError);
    expect(
      ReportCluster.fromJson({'lat': 14, 'lon': -90, 'count': 3}).ids,
      isEmpty,
    );
  });

  test('typed model boundary still rejects invalid required field types', () {
    final json = reportJson()..['latitude'] = '14';
    expect(() => Report.fromJson(json), throwsA(isA<TypeError>()));
    expect(
      () => VerificationCheck.fromJson({'name': 'image', 'passed': 1}),
      throwsA(isA<TypeError>()),
    );
  });
}
