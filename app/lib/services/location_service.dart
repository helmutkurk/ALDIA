import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

abstract class LocationService {
  Future<LatLng?> currentPosition();
}

enum LocationIssue { denied, deniedForever, serviceOff, unavailable }

class LocationFix {
  const LocationFix({this.position, this.accuracy, this.at, this.issue});
  final LatLng? position;
  final double? accuracy;
  final DateTime? at;
  final LocationIssue? issue;
}

/// Optional richer platform capability; simple v0.1 fakes remain supported.
abstract interface class LocationDiagnostics {
  Future<LocationFix> locate();
  Future<void> openSettings();
}

class GeolocatorLocationService
    implements LocationService, LocationDiagnostics {
  const GeolocatorLocationService();

  @override
  Future<LatLng?> currentPosition() async => (await locate()).position;

  @override
  Future<void> openSettings() async {
    await Geolocator.openAppSettings();
  }

  @override
  Future<LocationFix> locate() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return const LocationFix(issue: LocationIssue.serviceOff);
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        return const LocationFix(issue: LocationIssue.deniedForever);
      }
      if (permission == LocationPermission.denied) {
        return const LocationFix(issue: LocationIssue.denied);
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      return LocationFix(
        position: LatLng(position.latitude, position.longitude),
        accuracy: position.accuracy,
        at: position.timestamp,
      );
    } catch (_) {
      return const LocationFix(issue: LocationIssue.unavailable);
    }
  }
}
