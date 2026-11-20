import 'package:latlong2/latlong.dart';

/// Local-only report. [id] is also its stable Idempotency-Key.
class DraftRecord {
  const DraftRecord({
    required this.id,
    required this.step,
    required this.position,
    required this.createdAt,
    this.locationConfirmed = false,
    this.placeLabel,
    this.categoryId,
    this.photoPath,
    this.capturedAt,
    this.note = '',
    this.failedAttempts = 0,
    this.queueAttempts = 0,
    this.nextAttemptAt,
  });

  factory DraftRecord.fromJson(Map<String, Object?> json) => DraftRecord(
    id: json['id'] as String,
    step: json['step'] as String? ?? 'photo',
    position: LatLng(
      (json['latitude'] as num).toDouble(),
      (json['longitude'] as num).toDouble(),
    ),
    createdAt: DateTime.parse(json['created_at'] as String),
    locationConfirmed: json['location_confirmed'] as bool? ?? false,
    placeLabel: json['place_label'] as String?,
    categoryId: json['category'] as String?,
    photoPath: json['photo_path'] as String?,
    capturedAt: DateTime.tryParse(json['captured_at'] as String? ?? ''),
    note: json['note'] as String? ?? '',
    failedAttempts: json['failed_attempts'] as int? ?? 0,
    queueAttempts: json['queue_attempts'] as int? ?? 0,
    nextAttemptAt: DateTime.tryParse(json['next_attempt_at'] as String? ?? ''),
  );

  final String id;
  final String step;
  final LatLng position;
  final bool locationConfirmed;
  final String? placeLabel;
  final String? categoryId;
  final String? photoPath;
  final DateTime? capturedAt;
  final String note;
  final int failedAttempts;
  final DateTime createdAt;
  final int queueAttempts;
  final DateTime? nextAttemptAt;

  DraftRecord copyWith({
    String? id,
    String? step,
    LatLng? position,
    bool? locationConfirmed,
    String? placeLabel,
    String? categoryId,
    String? photoPath,
    DateTime? capturedAt,
    String? note,
    int? failedAttempts,
    int? queueAttempts,
    DateTime? nextAttemptAt,
    bool clearPhoto = false,
    bool clearRetry = false,
  }) => DraftRecord(
    id: id ?? this.id,
    step: step ?? this.step,
    position: position ?? this.position,
    locationConfirmed: locationConfirmed ?? this.locationConfirmed,
    placeLabel: placeLabel ?? this.placeLabel,
    categoryId: categoryId ?? this.categoryId,
    photoPath: clearPhoto ? null : photoPath ?? this.photoPath,
    capturedAt: clearPhoto ? null : capturedAt ?? this.capturedAt,
    note: note ?? this.note,
    failedAttempts: failedAttempts ?? this.failedAttempts,
    createdAt: createdAt,
    queueAttempts: clearRetry ? 0 : queueAttempts ?? this.queueAttempts,
    nextAttemptAt: clearRetry ? null : nextAttemptAt ?? this.nextAttemptAt,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'step': step,
    'latitude': position.latitude,
    'longitude': position.longitude,
    'location_confirmed': locationConfirmed,
    'place_label': placeLabel,
    'category': categoryId,
    'photo_path': photoPath,
    'captured_at': capturedAt?.toUtc().toIso8601String(),
    'note': note,
    'failed_attempts': failedAttempts,
    'created_at': createdAt.toUtc().toIso8601String(),
    'queue_attempts': queueAttempts,
    'next_attempt_at': nextAttemptAt?.toUtc().toIso8601String(),
  };
}
