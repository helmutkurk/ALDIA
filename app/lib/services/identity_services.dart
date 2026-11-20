import 'package:flutter/foundation.dart';

/// Citizen identity is separate from municipal staff sessions.
abstract interface class AuthService implements Listenable {
  bool get isSignedIn;
  String? get maskedPhone;
  Map<String, String> get authorizationHeaders;
  Future<void> initialize();
  Future<void> requestCode(String phone);
  Future<void> verifyCode({
    required String phone,
    required String code,
    String? alias,
    bool aliasPublic = false,
  });
  Future<void> signOut();
}

/// Optional default for embedders/tests without identity integration.
class NoopAuthService implements AuthService {
  const NoopAuthService();
  @override
  bool get isSignedIn => false;
  @override
  String? get maskedPhone => null;
  @override
  Map<String, String> get authorizationHeaders => const {};
  @override
  void addListener(VoidCallback listener) {}
  @override
  void removeListener(VoidCallback listener) {}
  @override
  Future<void> initialize() async {}
  @override
  Future<void> requestCode(String phone) async {}
  @override
  Future<void> verifyCode({
    required String phone,
    required String code,
    String? alias,
    bool aliasPublic = false,
  }) async {}
  @override
  Future<void> signOut() async {}
}

/// Follow is local until authenticated subscriptions and push are available.
abstract interface class NotificationsService {
  Future<void> follow(String reportId);
}

class NoopNotificationsService implements NotificationsService {
  const NoopNotificationsService();

  @override
  Future<void> follow(String reportId) async {}
}
