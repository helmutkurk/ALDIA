import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class AddressResult {
  const AddressResult({required this.label, required this.position});
  final String label;
  final LatLng position;
}

abstract interface class GeocoderService {
  Future<List<AddressResult>> search(String query);
}

/// Demo-only explicit searches, never autocomplete. Shared by all wizard runs.
/// Public Nominatim allows at most one request/second for the entire demo.
class NominatimGeocoder implements GeocoderService {
  NominatimGeocoder({required this._client, Uri? endpoint})
    : _endpoint =
          endpoint ?? Uri.parse('https://nominatim.openstreetmap.org/search');

  final http.Client _client;
  final Uri _endpoint;
  final _cache = <String, List<AddressResult>>{};
  Future<void> _queue = Future.value();
  DateTime? _lastRequest;

  @override
  Future<List<AddressResult>> search(String query) {
    final key = query.trim();
    if (key.length < 3) return Future.value(const []);
    final result = Completer<List<AddressResult>>();
    _queue = _queue.then((_) async {
      try {
        if (_cache[key] case final cached?) {
          result.complete(cached);
          return;
        }
        final last = _lastRequest;
        if (last != null) {
          final remaining =
              const Duration(seconds: 1) - DateTime.now().difference(last);
          if (remaining > Duration.zero) await Future<void>.delayed(remaining);
        }
        _lastRequest = DateTime.now();
        final response = await _client
            .get(
              _endpoint.replace(
                queryParameters: {
                  'q': key,
                  'format': 'jsonv2',
                  'limit': '5',
                  'countrycodes': 'gt,co,mx',
                  'accept-language': 'es',
                },
              ),
              headers: {'User-Agent': 'Aldia/0.1 (citizen reporting demo)'},
            )
            .timeout(const Duration(seconds: 8));
        if (response.statusCode != 200) {
          throw http.ClientException('Geocoding unavailable');
        }
        final rows =
            jsonDecode(utf8.decode(response.bodyBytes)) as List<Object?>;
        final addresses = rows
            .map((item) {
              final row = item as Map<String, Object?>;
              return AddressResult(
                label: row['display_name'] as String,
                position: LatLng(
                  double.parse(row['lat'] as String),
                  double.parse(row['lon'] as String),
                ),
              );
            })
            .toList(growable: false);
        // Bounded in-memory cache; addresses are not written to disk.
        if (_cache.length >= 50) _cache.remove(_cache.keys.first);
        _cache[key] = addresses;
        result.complete(addresses);
      } catch (error, stack) {
        result.completeError(error, stack);
      }
    });
    return result.future;
  }
}
