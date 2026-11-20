import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../core/config.dart';
import 'identity_services.dart';

class CitizenAuthException implements Exception {
  const CitizenAuthException(this.message);
  final String message;
  @override
  String toString() => message;
}

String normalizeCitizenPhone(String input) {
  final value = input.trim().replaceAll(RegExp(r'[\s-]'), '');
  final digits = value.startsWith('+502') ? value.substring(4) : value;
  if (!RegExp(r'^[0-9]{8}$').hasMatch(digits)) {
    throw const CitizenAuthException(
      'Ingresa los 8 dígitos de tu número de Guatemala.',
    );
  }
  return '+502$digits';
}

abstract interface class CitizenCredentialStore {
  Future<String?> read();
  Future<void> write(String value);
}

class SecureCitizenCredentialStore implements CitizenCredentialStore {
  const SecureCitizenCredentialStore({
    this._storage = const FlutterSecureStorage(),
  });
  final FlutterSecureStorage _storage;
  static const _key = 'aldia_citizen_session';
  @override
  Future<String?> read() => _storage.read(key: _key);
  @override
  Future<void> write(String value) => _storage.write(key: _key, value: value);
}

/// Device-bound opaque sessions. Raw phone/code exist only during the exchange.
class PhoneAuthService extends ChangeNotifier implements AuthService {
  PhoneAuthService({
    required this._client,
    required this._store,
    String? baseUrl,
    DateTime Function()? now,
  }) : _baseUrl = (baseUrl ?? AppConfig.apiBaseUrl).replaceAll(
         RegExp(r'/+$'),
         '',
       ),
       _now = now ?? DateTime.now;

  final http.Client _client;
  final CitizenCredentialStore _store;
  final String _baseUrl;
  final DateTime Function() _now;
  String? _device;
  String? _token;
  String? _masked;
  DateTime? _expires;
  Future<void>? _initializing;

  @override
  bool get isSignedIn =>
      _token != null && _expires != null && _now().isBefore(_expires!);
  @override
  String? get maskedPhone => isSignedIn ? _masked : null;
  @override
  Map<String, String> get authorizationHeaders => isSignedIn
      ? {'Authorization': 'Bearer $_token', 'X-Device-ID': _device!}
      : const {};

  @override
  Future<void> initialize() => _initializing ??= _load();

  Future<void> _load() async {
    try {
      final raw = await _store.read();
      if (raw != null) {
        final saved = jsonDecode(raw) as Map<String, dynamic>;
        _device = saved['device_id'] as String?;
        _token = saved['token'] as String?;
        _expires = DateTime.tryParse(saved['expires_at'] as String? ?? '');
        _masked = saved['masked_phone'] as String?;
      }
      if (_device == null || !Uuid.isValidUUID(fromString: _device!)) {
        // A bearer is valid only with the installation id it was issued for.
        _token = null;
        _expires = null;
        _masked = null;
        _device = const Uuid().v4();
      }
      if (!isSignedIn) {
        _token = null;
        _expires = null;
        _masked = null;
      }
      await _persist();
    } catch (_) {
      _token = null;
      _expires = null;
      _masked = null;
      _initializing = null;
      throw const CitizenAuthException(
        'No se pudo abrir el almacenamiento seguro. Inténtalo de nuevo.',
      );
    }
  }

  Future<void> _persist() => _store.write(
    jsonEncode({
      'device_id': _device,
      if (_token != null) 'token': _token,
      if (_expires != null) 'expires_at': _expires!.toUtc().toIso8601String(),
      if (_masked != null) 'masked_phone': _masked,
    }),
  );

  Future<http.Response> _post(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String> headers = const {},
  }) async {
    try {
      return await _client
          .post(
            Uri.parse('$_baseUrl/citizens/$path'),
            headers: {'Content-Type': 'application/json', ...headers},
            body: body == null ? null : jsonEncode(body),
          )
          .timeout(AppConfig.requestTimeout);
    } catch (_) {
      throw const CitizenAuthException(
        'No hay conexión. Revisa tu internet e inténtalo de nuevo.',
      );
    }
  }

  @override
  Future<void> requestCode(String phone) async {
    await initialize();
    final normalized = normalizeCitizenPhone(phone);
    final response = await _post(
      'otp/request',
      body: {'phone': normalized, 'device_id': _device},
    );
    if (response.statusCode != 202) {
      throw CitizenAuthException(
        response.statusCode == 429
            ? 'Espera un momento antes de pedir otro código.'
            : 'No se pudo solicitar el código. Inténtalo de nuevo.',
      );
    }
  }

  @override
  Future<void> verifyCode({
    required String phone,
    required String code,
    String? alias,
    bool aliasPublic = false,
  }) async {
    await initialize();
    final normalized = normalizeCitizenPhone(phone);
    if (!RegExp(r'^[0-9]{6}$').hasMatch(code)) {
      throw const CitizenAuthException('Ingresa los 6 dígitos del código.');
    }
    final response = await _post(
      'otp/verify',
      body: {
        'phone': normalized,
        'code': code,
        'device_id': _device,
        if (alias?.trim().isNotEmpty ?? false) 'alias': alias!.trim(),
        'alias_public': aliasPublic,
      },
    );
    if (response.statusCode != 200) {
      throw CitizenAuthException(switch (response.statusCode) {
        401 =>
          'El código no es válido o venció. Revísalo o solicita uno nuevo.',
        429 =>
          'Demasiados intentos. Espera unos minutos y vuelve a intentarlo.',
        _ => 'No se pudo verificar el número. Inténtalo de nuevo.',
      });
    }
    try {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final token = data['token'] as String;
      final expires = DateTime.parse(data['expires_at'] as String);
      if (token.isEmpty || !_now().isBefore(expires)) {
        throw const FormatException();
      }
      _token = token;
      _expires = expires;
      _masked = '+502 •••• ••${normalized.substring(normalized.length - 2)}';
      await _persist();
    } catch (_) {
      _token = null;
      _expires = null;
      _masked = null;
      throw const CitizenAuthException(
        'No se pudo guardar la sesión de forma segura. Inténtalo de nuevo.',
      );
    }
    notifyListeners();
  }

  @override
  Future<void> signOut() async {
    final headers = authorizationHeaders;
    _token = null;
    _expires = null;
    _masked = null;
    await _persist();
    notifyListeners();
    if (headers.isEmpty) return;
    try {
      final response = await _post('logout', headers: headers);
      if (response.statusCode != 204 && response.statusCode != 401) {
        throw const CitizenAuthException(
          'No se pudo cerrar la sesión en el servidor.',
        );
      }
    } catch (_) {
      throw const CitizenAuthException(
        'Sesión borrada de este dispositivo. No se pudo revocar en el servidor; vuelve a verificar tu número cuando tengas conexión.',
      );
    }
  }
}
