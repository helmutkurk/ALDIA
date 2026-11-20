import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../core/config.dart';
import '../core/categories.dart';
import 'report.dart';
import '../services/identity_services.dart';

class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => 'ApiException($statusCode): $message';
}

/// Thin client for the Aldia API. Contract: documentation/api-contract.md.
class ApiClient {
  ApiClient({
    required this._client,
    String? baseUrl,
    this.auth = const NoopAuthService(),
  }) : _baseUrl = (baseUrl ?? AppConfig.apiBaseUrl).replaceAll(
         RegExp(r'/+$'),
         '',
       );

  final AuthService auth;
  final http.Client _client;
  final String _baseUrl;

  /// Absolute URL of a photo path such as `/api/reports/<id>/photo`.
  String photoUrl(String photoPath) {
    if (Uri.parse(photoPath).hasScheme) return photoPath;
    final uri = Uri.parse(_baseUrl);
    return uri.replace(path: photoPath, query: null).toString();
  }

  Future<int?> resolvedCount() async {
    final json = jsonDecode(
      await _send(() => _client.get(Uri.parse('$_baseUrl/stats'))),
    ) as Map<String, dynamic>;
    final value =
        json['resueltos'] ?? (json['by_resolution'] as Map?)?['fixed'];
    return value is num ? value.toInt() : null;
  }

  Future<List<ReportCategory>> categories() async {
    final decoded = jsonDecode(
      await _send(() => _client.get(Uri.parse('$_baseUrl/categories'))),
    ) as List;
    return decoded
        .map(
          (e) => ReportCategory.fromJson(Map<String, dynamic>.from(e as Map)),
        )
        .toList();
  }

  Future<List<Report>> listReports({
    LatLng? southWest,
    LatLng? northEast,
    int limit = 100,
    String? state,
    String? category,
  }) async {
    final query = <String, String>{
      'limit': '$limit',
      'state': ?state,
      'category': ?category,
    };
    if (southWest != null && northEast != null) {
      query['bbox'] =
          '${southWest.longitude},${southWest.latitude},${northEast.longitude},${northEast.latitude}';
    }
    final uri = Uri.parse('$_baseUrl/reports').replace(queryParameters: query);
    final body = await _send(() => _client.get(uri));
    final items =
        (jsonDecode(body) as Map<String, dynamic>)['items'] as List<dynamic>;
    return items
        .map((e) => Report.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<Report>> nearbyReports({
    required LatLng position,
    required String category,
  }) async {
    final uri = Uri.parse('$_baseUrl/reports/nearby').replace(
      queryParameters: {
        'lat': '${position.latitude}',
        'lon': '${position.longitude}',
        'category': category,
        'radius_m': '150',
      },
    );
    final decoded = jsonDecode(await _send(() => _client.get(uri)));
    final items = decoded is List
        ? decoded
        : (decoded as Map<String, dynamic>)['items'] as List;
    return items
        .map((e) => Report.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

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
    final body =
        jsonDecode(await _send(() => _client.get(uri))) as Map<String, dynamic>;
    return (body['clusters'] as List)
        .map((e) => ReportCluster.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<Report> getReport(String id) async {
    final body = await _send(
      () => _client.get(Uri.parse('$_baseUrl/reports/$id')),
    );
    return Report.fromJson(jsonDecode(body) as Map<String, dynamic>);
  }

  Future<List<Report>> citizenReports() async {
    if (!auth.isSignedIn) return const [];
    final reports = <Report>[];
    var offset = 0;
    while (true) {
      final uri = Uri.parse('$_baseUrl/citizens/me/reports')
          .replace(queryParameters: {'limit': '100', 'offset': '$offset'});
      final body = await _send(
        () => _client.get(uri, headers: auth.authorizationHeaders),
      );
      final data = jsonDecode(body) as Map<String, dynamic>;
      final items = (data['items'] as List)
          .map((e) => Report.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      reports.addAll(items);
      offset += items.length;
      if (items.isEmpty || offset >= (data['total'] as int)) break;
    }
    return reports;
  }

  Future<Report> createReport({
    required Uint8List photoBytes,
    required String filename,
    required String category,
    required LatLng position,
    required DateTime capturedAt,
    String? note,
    String? idempotencyKey,
  }) async {
    final request =
        http.MultipartRequest('POST', Uri.parse('$_baseUrl/reports'))
          ..fields['category'] = category
          ..fields['latitude'] = position.latitude.toString()
          ..fields['longitude'] = position.longitude.toString()
          ..fields['captured_at'] = capturedAt.toUtc().toIso8601String()
          ..files.add(
            http.MultipartFile.fromBytes(
              'photo',
              photoBytes,
              filename: filename,
            ),
          );
    request.headers.addAll(auth.authorizationHeaders);
    if (idempotencyKey != null) {
      request.headers['Idempotency-Key'] = idempotencyKey;
    }
    if (note != null && note.trim().isNotEmpty) {
      request.fields['note'] = note.trim();
    }
    final body = await _send(() async {
      final streamed = await _client.send(request);
      return http.Response.fromStream(streamed);
    });
    return Report.fromJson(jsonDecode(body) as Map<String, dynamic>);
  }

  Future<String> _send(Future<http.Response> Function() call) async {
    try {
      final response = await call().timeout(AppConfig.requestTimeout);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return utf8.decode(response.bodyBytes);
      }
      if (response.statusCode == 401 && auth.isSignedIn) {
        // A rotated/revoked device token must offer verification on the next try.
        try {
          await auth.signOut();
        } catch (_) {}
      }
      throw ApiException(
        _errorMessage(response),
        statusCode: response.statusCode,
      );
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Network error: ${e.runtimeType}');
    }
  }

  String _errorMessage(http.Response response) {
    try {
      final data =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final error = data['error'] as Map<String, dynamic>;
      return error['message'] as String;
    } catch (_) {
      return 'HTTP ${response.statusCode}';
    }
  }
}
