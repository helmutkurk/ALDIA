import 'dart:convert';

import 'package:aldia_app/services/geocoder_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('Nominatim restricts countries, identifies Aldia, caches and serializes at 1/s', () async {
    final requests = <http.Request>[];
    final times = <DateTime>[];
    final service = NominatimGeocoder(
      client: MockClient((request) async {
        requests.add(request);
        times.add(DateTime.now());
        return http.Response(
          jsonEncode([
            {
              'display_name': 'Zona 1, Guatemala',
              'lat': '14.64',
              'lon': '-90.51',
            },
          ]),
          200,
        );
      }),
    );
    final first = await service.search('Zona 1');
    expect(first.single.position.latitude, 14.64);
    await service.search('Zona 1');
    await service.search('Zona 2');
    expect(requests, hasLength(2));
    expect(requests.first.url.queryParameters['countrycodes'], 'gt,co,mx');
    expect(requests.first.headers['User-Agent'], contains('Aldia'));
    expect(
      times.last.difference(times.first).inMilliseconds,
      greaterThanOrEqualTo(990),
    );
  });
}
