import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../core/config.dart';
import 'report.dart';

class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => 'ApiException($statusCode): $message';
}

/// Thin client for the Aldia API. Contract: documentation/api-contract.md.
class ApiClient {
  ApiClient({required this._client, String? baseUrl})
    : _baseUrl = (baseUrl ?? AppConfig.apiBaseUrl).replaceAll(
        RegExp(r'/+$'),
        '',
      );

  final http.Client _client;
  final String _baseUrl;

  /// Absolute URL of a photo path such as `/api/reports/<id>/photo`.
  String photoUrl(String photoPath) {
    final uri = Uri.parse(_baseUrl);
    return uri.replace(path: photoPath, query: null).toString();
  }

  Future<List<Report>> listReports({
    LatLng? southWest,
    LatLng? northEast,
    int limit = 100,
  }) async {
    final query = <String, String>{'limit': '$limit'};
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

  Future<Report> getReport(String id) async {
    final body = await _send(
      () => _client.get(Uri.parse('$_baseUrl/reports/$id')),
    );
    return Report.fromJson(jsonDecode(body) as Map<String, dynamic>);
  }

  Future<Report> createReport({
    required Uint8List photoBytes,
    required String filename,
    required String category,
    required LatLng position,
    required DateTime capturedAt,
    String? note,
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
