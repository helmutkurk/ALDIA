import 'package:aldia_app/services/identity_services.dart';
import 'package:aldia_app/services/citizen_auth_service.dart';
import 'package:flutter/foundation.dart';

class FakeCitizenAuth extends ChangeNotifier implements AuthService {
  FakeCitizenAuth({this.signedIn = false});
  bool signedIn;
  int requests = 0;
  int verifications = 0;
  String? requestError;
  String? verifyError;
  @override
  bool get isSignedIn => signedIn;
  @override
  String? get maskedPhone => signedIn ? '+502 •••• ••22' : null;
  @override
  Map<String, String> get authorizationHeaders => signedIn
      ? const {
          'Authorization': 'Bearer synthetic-session',
          'X-Device-ID': '00000000-0000-4000-8000-000000000001',
        }
      : const {};
  @override
  Future<void> initialize() async {}
  @override
  Future<void> requestCode(String phone) async {
    requests++;
    if (requestError != null) throw CitizenAuthException(requestError!);
  }

  @override
  Future<void> verifyCode({
    required String phone,
    required String code,
    String? alias,
    bool aliasPublic = false,
  }) async {
    verifications++;
    if (verifyError != null) throw CitizenAuthException(verifyError!);
    signedIn = true;
    notifyListeners();
  }

  @override
  Future<void> signOut() async {
    signedIn = false;
    notifyListeners();
  }
}
