import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../core/config.dart';
import 'report.dart';

/// Map pins for the visible viewport (`GET /api/reports/clusters`).
abstract interface class ClustersApi {
  /// Throws when the server is unreachable or does not offer clusters; the map
  /// then falls back to the plain report list.
  Future<List<ReportCluster>> clusters({
    required LatLng southWest,
    required LatLng northEast,
    required double zoom,
  });
}

class HttpClustersApi implements ClustersApi {
  HttpClustersApi({required this._client, String? baseUrl})
    : _baseUrl = (baseUrl ?? AppConfig.apiBaseUrl).replaceAll(
        RegExp(r'/+$'),
        '',
      );

  final http.Client _client;
  final String _baseUrl;

  @override
  Future<List<ReportCluster>> clusters({
    required LatLng southWest,
    required LatLng northEast,
    required double zoom,
  }) async {
    final uri = Uri.parse('$_baseUrl/reports/clusters').replace(
      queryParameters: {
        'bbox':
            '${southWest.longitude},${southWest.latitude},${northEast.longitude},${northEast.latitude}',
        'zoom': '${zoom.round().clamp(0, 20)}',
      },
    );
    final response = await _client.get(uri).timeout(AppConfig.requestTimeout);
    if (response.statusCode != 200) {
      throw http.ClientException('HTTP ${response.statusCode}', uri);
    }
    final body = jsonDecode(utf8.decode(response.bodyBytes)) as Map;
    return [
      for (final item in body['clusters'] as List)
        ReportCluster.fromJson(Map<String, dynamic>.from(item as Map)),
    ];
  }
}
