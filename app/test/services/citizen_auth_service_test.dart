import 'dart:convert';

import 'package:aldia_app/services/citizen_auth_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class MemoryCitizenCredentials implements CitizenCredentialStore {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String value) async => this.value = value;
}

String testPhone() => '+502${List.filled(8, '2').join()}';
String testCode() => List.filled(6, '1').join();

void main() {
  test(
    'validates Guatemala digits and defaults country without echoing input',
    () {
      expect(normalizeCitizenPhone(List.filled(8, '2').join()), testPhone());
      expect(normalizeCitizenPhone(testPhone()), testPhone());
      expect(
        () => normalizeCitizenPhone('abc'),
        throwsA(isA<CitizenAuthException>()),
      );
      expect(
        () => normalizeCitizenPhone('123'),
        throwsA(isA<CitizenAuthException>()),
      );
    },
  );

  test('persists only masked digits, device and expiring session; restores and logs out', () async {
    final store = MemoryCitizenCredentials();
    final paths = <String>[];
    final deviceIds = <String>[];
    final client = MockClient((request) async {
      paths.add(request.url.path);
      if (request.url.path.endsWith('/logout')) {
        expect(request.headers['authorization'], isNotNull);
        expect(request.headers['x-device-id'], isNotNull);
        return http.Response('', 204);
      }
      final payload = jsonDecode(request.body) as Map;
      deviceIds.add(payload['device_id'] as String);
      return request.url.path.endsWith('/verify')
          ? http.Response(
              jsonEncode({
                'token': 'synthetic-session',
                'expires_at': DateTime.now()
                    .add(const Duration(days: 90))
                    .toUtc()
                    .toIso8601String(),
              }),
              200,
            )
          : http.Response('{"accepted":true}', 202);
    });
    final auth = PhoneAuthService(
      client: client,
      store: store,
      baseUrl: 'https://api.test/api',
    );
    await auth.initialize();
    await auth.requestCode(testPhone());
    await auth.verifyCode(phone: testPhone(), code: testCode());
    expect(auth.isSignedIn, isTrue);
    expect(auth.maskedPhone, endsWith('22'));
    expect(store.value!.contains(testPhone()), isFalse);
    expect(store.value!.contains(testCode()), isFalse);
    expect(deviceIds.toSet(), hasLength(1));
    final restored = PhoneAuthService(
      client: client,
      store: store,
      baseUrl: 'https://api.test/api',
    );
    await restored.initialize();
    expect(restored.isSignedIn, isTrue);
    expect(restored.authorizationHeaders, auth.authorizationHeaders);
    await restored.signOut();
    expect(restored.isSignedIn, isFalse);
    expect(restored.authorizationHeaders, isEmpty);
    expect(paths.last, endsWith('/logout'));
    expect(store.value!.contains('synthetic-session'), isFalse);
  });

  test('expired stored session is removed and never used', () async {
    var now = DateTime.utc(2026, 11, 20);
    final store = MemoryCitizenCredentials();
    final auth = PhoneAuthService(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'token': 'synthetic-session',
            'expires_at': now.add(const Duration(seconds: 1)).toIso8601String(),
          }),
          200,
        ),
      ),
      store: store,
      now: () => now,
    );
    await auth.initialize();
    await auth.verifyCode(phone: testPhone(), code: testCode());
    now = now.add(const Duration(seconds: 2));
    expect(auth.isSignedIn, isFalse);
    expect(auth.authorizationHeaders, isEmpty);
    final restored = PhoneAuthService(
      client: MockClient((_) async => http.Response('', 500)),
      store: store,
      now: () => now,
    );
    await restored.initialize();
    expect(restored.isSignedIn, isFalse);
    expect(store.value!.contains('synthetic-session'), isFalse);
  });

  test(
    'expired-code and offline errors are clear and contain no submitted values',
    () async {
      final auth = PhoneAuthService(
        client: MockClient(
          (_) async => http.Response(
            '{"error":{"code":"citizen_code_invalid","message":"not valid"}}',
            401,
          ),
        ),
        store: MemoryCitizenCredentials(),
      );
      await auth.initialize();
      await expectLater(
        auth.verifyCode(phone: testPhone(), code: testCode()),
        throwsA(
          isA<CitizenAuthException>().having(
            (e) => e.message,
            'message',
            contains('venció'),
          ),
        ),
      );
      final offline = PhoneAuthService(
        client: MockClient((_) async => throw http.ClientException('offline')),
        store: MemoryCitizenCredentials(),
      );
      await offline.initialize();
      await expectLater(
        offline.requestCode(testPhone()),
        throwsA(
          isA<CitizenAuthException>().having(
            (e) => e.message,
            'message',
            contains('conexión'),
          ),
        ),
      );
      expect(offline.isSignedIn, isFalse);
    },
  );

  test(
    'offline logout clears local token and reports pending server revocation',
    () async {
      var fail = false;
      final store = MemoryCitizenCredentials();
      final auth = PhoneAuthService(
        client: MockClient((_) async {
          if (fail) throw http.ClientException('offline');
          return http.Response(
            jsonEncode({
              'token': 'synthetic-session',
              'expires_at': DateTime.now()
                  .add(const Duration(days: 90))
                  .toUtc()
                  .toIso8601String(),
            }),
            200,
          );
        }),
        store: store,
      );
      await auth.initialize();
      await auth.verifyCode(phone: testPhone(), code: testCode());
      fail = true;
      await expectLater(auth.signOut(), throwsA(isA<CitizenAuthException>()));
      expect(auth.isSignedIn, isFalse);
      expect(auth.authorizationHeaders, isEmpty);
    },
  );
  for (final invalidDevice in <String?>[null, 'invalid-device']) {
    test(
      'missing or invalid stored installation id discards its session: ${invalidDevice == null ? 'missing' : 'invalid'}',
      () async {
        final store = MemoryCitizenCredentials()
          ..value = jsonEncode({
            'device_id': ?invalidDevice,
            'token': 'synthetic-session',
            'expires_at': DateTime.now()
                .add(const Duration(days: 90))
                .toUtc()
                .toIso8601String(),
            'masked_phone': '+502 •••• ••22',
          });
        final auth = PhoneAuthService(
          client: MockClient((_) async => http.Response('', 500)),
          store: store,
        );
        await auth.initialize();
        expect(auth.isSignedIn, isFalse);
        expect(auth.authorizationHeaders, isEmpty);
        expect(store.value!.contains('synthetic-session'), isFalse);
      },
    );
  }
}
