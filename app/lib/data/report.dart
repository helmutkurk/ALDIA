import 'package:latlong2/latlong.dart';

class VerificationCheck {
  const VerificationCheck({
    required this.name,
    required this.passed,
    required this.detail,
  });

  factory VerificationCheck.fromJson(Map<String, dynamic> json) =>
      VerificationCheck(
        name: json['name'] as String,
        passed: json['passed'] as bool,
        detail: (json['detail'] as String?) ?? '',
      );

  final String name;
  final bool passed;
  final String detail;
}

class Verification {
  const Verification({
    required this.passed,
    required this.mode,
    required this.checks,
  });

  factory Verification.fromJson(Map<String, dynamic> json) => Verification(
    passed: json['passed'] as bool,
    mode: json['mode'] as String,
    checks: (json['checks'] as List<dynamic>)
        .map((c) => VerificationCheck.fromJson(c as Map<String, dynamic>))
        .toList(),
  );

  final bool passed;
  final String mode;
  final List<VerificationCheck> checks;

  bool get isStub => mode == 'stub';
}

/// Report as returned by the API (documentation/api-contract.md).
class Report {
  const Report({
    required this.id,
    required this.category,
    required this.position,
    required this.capturedAt,
    required this.createdAt,
    required this.status,
    required this.resolution,
    required this.photoUrl,
    this.note,
    this.verification,
  });

  factory Report.fromJson(Map<String, dynamic> json) => Report(
    id: json['id'] as String,
    category: json['category'] as String,
    position: LatLng(
      (json['latitude'] as num).toDouble(),
      (json['longitude'] as num).toDouble(),
    ),
    capturedAt: DateTime.parse(json['captured_at'] as String),
    createdAt: DateTime.parse(json['created_at'] as String),
    status: json['status'] as String,
    resolution: (json['resolution'] as String?) ?? 'open',
    note: json['note'] as String?,
    photoUrl: json['photo_url'] as String,
    verification: json['verification'] == null
        ? null
        : Verification.fromJson(json['verification'] as Map<String, dynamic>),
  );

  final String id;
  final String category;
  final LatLng position;
  final DateTime capturedAt;
  final DateTime createdAt;

  /// `pending`, `verified` or `rejected`.
  final String status;

  /// `open`, `acknowledged` or `fixed`.
  final String resolution;
  final String? note;
  final String photoUrl;
  final Verification? verification;
}
