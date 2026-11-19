import 'dart:async';

import 'package:aldia_app/services/connectivity_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class FakeProbe implements ReachabilityProbe {
  bool result = false;
  bool throws = false;
  bool disposed = false;
  int calls = 0;
  @override
  Future<bool> reachable() async {
    calls++;
    if (throws) throw StateError('network unreachable');
    return result;
  }

  @override
  void dispose() {
    disposed = true;
  }
}

void main() {
  test(
    'Android polling detects return of service without platform permissions',
    () async {
      final probe = FakeProbe();
      final ticks = StreamController<void>.broadcast(sync: true);
      final service = PlusConnectivityService(
        probe: probe,
        useReachabilityPolling: true,
        pollTicks: ticks.stream,
      );
      final values = <bool>[];
      final subscription = service.changes.listen(values.add);
      await service.initialize();
      expect(service.isOnline, isFalse);
      expect(probe.calls, 1);
      probe.result = true;
      ticks.add(null);
      await Future<void>.delayed(Duration.zero);
      expect(service.isOnline, isTrue);
      expect(values, [true]);
      probe.result = false;
      ticks.add(null);
      await Future<void>.delayed(Duration.zero);
      expect(values, [true, false]);
      service.dispose();
      expect(probe.disposed, isTrue);
      final calls = probe.calls;
      ticks.add(null);
      await Future<void>.delayed(Duration.zero);
      expect(probe.calls, calls);
      await subscription.cancel();
      await ticks.close();
    },
  );

  test('probe failures leave drafts and outbox safely offline', () async {
    final probe = FakeProbe()..throws = true;
    final ticks = StreamController<void>.broadcast();
    final service = PlusConnectivityService(
      probe: probe,
      useReachabilityPolling: true,
      pollTicks: ticks.stream,
    );
    await service.initialize();
    expect(service.isOnline, isFalse);
    service.dispose();
    await ticks.close();
  });

  test(
    'HTTP probe uses the injected API health endpoint and handles failures',
    () async {
      late Uri seen;
      var status = 200;
      final probe = HttpReachabilityProbe(
        healthUri: Uri.parse('https://api.test/api/health'),
        client: MockClient((request) async {
          seen = request.url;
          return http.Response('{}', status);
        }),
      );
      expect(await probe.reachable(), isTrue);
      expect(seen.toString(), 'https://api.test/api/health');
      status = 503;
      expect(await probe.reachable(), isFalse);
      probe.dispose();
      final failed = HttpReachabilityProbe(
        client: MockClient((_) async {
          throw http.ClientException('offline');
        }),
      );
      expect(await failed.reachable(), isFalse);
      failed.dispose();
    },
  );
}
