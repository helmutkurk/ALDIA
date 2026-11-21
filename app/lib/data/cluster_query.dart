import 'package:latlong2/latlong.dart';

/// API bbox order is west,south,east,north; zoom is an integer in [0, 20].
Map<String, String> clusterQueryParameters({
  required LatLng southWest,
  required LatLng northEast,
  required double zoom,
}) => {
  'bbox':
      '${southWest.longitude},${southWest.latitude},${northEast.longitude},${northEast.latitude}',
  'zoom': '${zoom.round().clamp(0, 20)}',
};
