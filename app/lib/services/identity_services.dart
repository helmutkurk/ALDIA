/// Reserved for the server-supported phone-code login integration.
abstract interface class AuthService {
  bool get isSignedIn;
  Future<void> signOut();
}

class NoopAuthService implements AuthService {
  const NoopAuthService();

  @override
  bool get isSignedIn => false;

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
