import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../core/config.dart';
import '../../core/strings.dart';
import '../../services/location_service.dart';
import '../../widgets/map_layers_button.dart';
import '../../widgets/neutral_map_pin.dart';
import 'address_search.dart';
import 'report_flow_widgets.dart';
import 'report_flow_controller.dart';

class LocationStep extends StatefulWidget {
  const LocationStep({super.key, required this.controller});
  final ReportFlowController controller;
  @override
  State<LocationStep> createState() => _LocationStepState();
}

class _LocationStepState extends State<LocationStep> {
  final _map = MapController();
  late final TextEditingController _lat;
  late final TextEditingController _lon;
  bool _invalid = false;
  bool _showAccuracy = true;

  @override
  void initState() {
    super.initState();
    _lat = TextEditingController(
      text: '${widget.controller.position.latitude}',
    );
    _lon = TextEditingController(
      text: '${widget.controller.position.longitude}',
    );
  }

  @override
  void didUpdateWidget(covariant LocationStep oldWidget) {
    super.didUpdateWidget(oldWidget);
    _map.move(widget.controller.position, _map.camera.zoom);
    _lat.text = '${widget.controller.position.latitude}';
    _lon.text = '${widget.controller.position.longitude}';
  }

  @override
  void dispose() {
    _map.dispose();
    _lat.dispose();
    _lon.dispose();
    super.dispose();
  }

  void _apply() {
    final lat = double.tryParse(_lat.text);
    final lon = double.tryParse(_lon.text);
    setState(
      () => _invalid =
          lat == null ||
          lon == null ||
          !lat.isFinite ||
          !lon.isFinite ||
          lat.abs() > 90 ||
          lon.abs() > 180,
    );
    if (!_invalid) widget.controller.setPosition(LatLng(lat!, lon!));
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final issue = switch (c.locationIssue) {
      LocationIssue.denied => S.locationDenied,
      LocationIssue.deniedForever => S.locationDeniedForever,
      LocationIssue.serviceOff => S.locationServiceOff,
      LocationIssue.unavailable => S.locationUnavailable,
      null => null,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AddressSearch(
          onSelected: (address) =>
              c.setPosition(address.position, label: address.label),
        ),
        const Text(S.locationHint),
        const SizedBox(height: 8),
        SizedBox(
          height: 260,
          child: Semantics(
            label: S.pinAlternative,
            child: FlutterMap(
              mapController: _map,
              options: MapOptions(
                initialCenter: c.position,
                initialZoom: 16,
                onTap: (_, point) => c.setPosition(point),
              ),
              children: [
                TileLayer(
                  urlTemplate: AppConfig.tileUrl,
                  tileProvider: context.read<TileProvider>(),
                  userAgentPackageName: AppConfig.userAgentPackage,
                ),
                if (_showAccuracy &&
                    c.accuracy != null &&
                    c.gpsPosition != null)
                  CircleLayer(
                    circles: [
                      CircleMarker(
                        point: c.gpsPosition!,
                        radius: c.accuracy!,
                        useRadiusInMeter: true,
                        color: Theme.of(context).colorScheme.primary
                            .withValues(alpha: .15),
                        borderColor: Theme.of(context).colorScheme.primary,
                        borderStrokeWidth: 2,
                      ),
                    ],
                  ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: c.position,
                      width: 48,
                      height: 48,
                      child: const NeutralMapPin(
                        size: 48,
                        child: Icon(Icons.location_on_outlined),
                      ),
                    ),
                  ],
                ),
                Align(
                  alignment: Alignment.topRight,
                  child: Card(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        MapLayersButton(
                          overlay: 'Precisión del GPS',
                          visible: _showAccuracy,
                          onChanged: (value) =>
                              setState(() => _showAccuracy = value),
                        ),
                        IconButton(
                          tooltip: 'Acercar mapa',
                          onPressed: () => _map.move(
                            _map.camera.center,
                            (_map.camera.zoom + 1).clamp(3, 19),
                          ),
                          icon: const Icon(Icons.add),
                        ),
                        IconButton(
                          tooltip: 'Alejar mapa',
                          onPressed: () => _map.move(
                            _map.camera.center,
                            (_map.camera.zoom - 1).clamp(3, 19),
                          ),
                          icon: const Icon(Icons.remove),
                        ),
                        IconButton(
                          tooltip: S.useMyLocation,
                          onPressed: c.locating ? null : c.useMyLocation,
                          icon: const Icon(Icons.my_location),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const Text(
          '© OpenStreetMap contributors · búsqueda y mapa',
          style: TextStyle(fontSize: 12),
        ),
        if (c.locating) const FlowNotice(S.locating),
        if (issue != null) FlowNotice(issue),
        if (c.locationIssue == LocationIssue.deniedForever)
          OutlinedButton(
            onPressed: c.openLocationSettings,
            child: const Text(S.openSettings),
          ),
        if (c.accuracy != null) Text(S.accuracy(c.accuracy!)),
        if ((c.accuracy ?? 0) > 50) const FlowNotice(S.poorAccuracy),
        TextButton.icon(
          onPressed: c.locating ? null : c.useMyLocation,
          icon: const Icon(Icons.my_location),
          label: const Text(S.useMyLocation),
        ),
        const Text(S.confirmPinHint),
        TextField(
          controller: _lat,
          decoration: const InputDecoration(labelText: S.latitude),
          keyboardType: const TextInputType.numberWithOptions(
            signed: true,
            decimal: true,
          ),
        ),
        TextField(
          controller: _lon,
          decoration: const InputDecoration(labelText: S.longitude),
          keyboardType: const TextInputType.numberWithOptions(
            signed: true,
            decimal: true,
          ),
        ),
        if (_invalid) const FlowNotice(S.coordinatesInvalid),
        TextButton(onPressed: _apply, child: const Text(S.applyCoordinates)),
      ],
    );
  }
}
