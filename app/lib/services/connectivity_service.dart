import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../core/config.dart';

/// Connectivity is only a hint: uploads still handle unreachable servers.
abstract interface class ConnectivityService {
  bool get isOnline;
  Stream<bool> get changes;
  Future<void> initialize();
  void dispose();
}

abstract interface class ReachabilityProbe {
  Future<bool> reachable();
  void dispose();
}

class HttpReachabilityProbe implements ReachabilityProbe {
  HttpReachabilityProbe({http.Client? client, Uri? healthUri})
    : _client = client ?? http.Client(),
      _healthUri = healthUri ?? Uri.parse('${AppConfig.apiBaseUrl}/health');

  final http.Client _client;
  final Uri _healthUri;

  @override
  Future<bool> reachable() async {
    try {
      final response = await _client
          .get(_healthUri)
          .timeout(const Duration(seconds: 5));
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  @override
  void dispose() => _client.close();
}

class PlusConnectivityService implements ConnectivityService {
  PlusConnectivityService({
    Connectivity? connectivity,
    ReachabilityProbe? probe,
    bool? useReachabilityPolling,
    this._pollTicks,
  }) : _connectivity = connectivity ?? Connectivity(),
       _probe = probe ?? HttpReachabilityProbe(),
       _useReachabilityPolling =
           useReachabilityPolling ??
           defaultTargetPlatform == TargetPlatform.android;

  final Connectivity _connectivity;
  final ReachabilityProbe _probe;
  final bool _useReachabilityPolling;
  final Stream<void>? _pollTicks;
  final _changes = StreamController<bool>.broadcast(sync: true);
  StreamSubscription<void>? _pollSubscription;
  StreamSubscription<List<ConnectivityResult>>? _platformSubscription;
  bool _online = false;
  bool _initialized = false;
  bool _checking = false;
  bool _disposed = false;

  bool _connected(List<ConnectivityResult> values) =>
      values.any((value) => value != ConnectivityResult.none);

  @override
  bool get isOnline => _online;

  @override
  Stream<bool> get changes => _changes.stream;

  void _setOnline(bool value) {
    if (_disposed || value == _online) return;
    _online = value;
    _changes.add(value);
  }

  @override
  Future<void> initialize() async {
    if (_initialized || _disposed) return;
    _initialized = true;
    if (_useReachabilityPolling) {
      // Android's connectivity API needs ACCESS_NETWORK_STATE. Poll the small
      // public health endpoint instead, using only the existing INTERNET grant.
      await _checkReachability();
      _startPolling();
      return;
    }
    try {
      _setOnline(_connected(await _connectivity.checkConnectivity()));
      if (_disposed) return;
      _platformSubscription = _connectivity.onConnectivityChanged.listen(
        (values) => _setOnline(_connected(values)),
        onError: (Object _) => _startPolling(),
      );
    } catch (_) {
      await _checkReachability();
      _startPolling();
    }
  }

  Future<void> _checkReachability() async {
    if (_checking || _disposed) return;
    _checking = true;
    try {
      _setOnline(await _probe.reachable());
    } catch (_) {
      _setOnline(false);
    } finally {
      _checking = false;
    }
  }

  void _startPolling() {
    if (_pollSubscription != null || _disposed) return;
    final ticks =
        _pollTicks ??
        Stream<void>.periodic(const Duration(seconds: 15), (_) {});
    _pollSubscription = ticks.listen((_) {
      unawaited(_checkReachability());
    });
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    unawaited(_pollSubscription?.cancel());
    unawaited(_platformSubscription?.cancel());
    unawaited(_changes.close());
    _probe.dispose();
  }
}
