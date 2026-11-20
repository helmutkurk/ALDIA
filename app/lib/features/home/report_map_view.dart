import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:provider/provider.dart';

import '../../core/config.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../data/clusters_api.dart';
import '../../data/report.dart';
import '../../data/report_repository.dart';
import '../../services/location_service.dart';
import '../../widgets/map_layers_button.dart';
import 'report_map_widgets.dart';

/// Clusters for the visible viewport; plain reports when clusters are not
/// available or a filter is active (the clusters endpoint has no filters).
class MapView extends StatefulWidget {
  const MapView({
    super.key,
    required this.state,
    required this.category,
    required this.onOpen,
  });

  final String? state;
  final String? category;
  final void Function(Report) onOpen;

  @override
  State<MapView> createState() => MapViewState();
}

class MapViewState extends State<MapView> {
  final _controller = MapController();
  Timer? _debounce;
  var _token = 0;
  var _ready = false;
  List<ReportCluster> _clusters = const [];
  List<Report> _pins = const [];
  bool _clustersFailed = false;
  bool _showReports = true;

  @override
  void didUpdateWidget(MapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state ||
        oldWidget.category != widget.category) {
      unawaited(_load());
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> locate() async {
    final point = await context.read<LocationService>().currentPosition();
    if (!mounted) return;
    if (point != null) {
      _controller.move(point, 16);
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text(S.locationUnavailable)));
    }
  }

  void _scheduleLoad() {
    if (!_ready) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _load);
  }

  Future<void> _load() async {
    final camera = _controller.camera;
    final bounds = camera.visibleBounds;
    final token = ++_token;
    final api = context.read<ClustersApi?>();
    final repository = context.read<ReportRepository>();
    final filtered = widget.state != null || widget.category != null;
    if (api != null && !filtered) {
      try {
        final clusters = await api.clusters(
          southWest: bounds.southWest,
          northEast: bounds.northEast,
          zoom: camera.zoom,
        );
        if (!mounted || token != _token) return;
        setState(() {
          _clusters = clusters;
          _pins = const [];
          _clustersFailed = false;
        });
        return;
      } catch (_) {
        // Fall through to the plain list below.
      }
    }
    try {
      final reports = await repository.nearby(
        southWest: bounds.southWest,
        northEast: bounds.northEast,
        state: widget.state,
        category: widget.category,
      );
      if (!mounted || token != _token) return;
      setState(() {
        _clusters = const [];
        _pins = reports;
        _clustersFailed = api != null && !filtered;
      });
    } catch (_) {
      if (!mounted || token != _token) return;
      setState(() {
        _clusters = const [];
        _pins = const [];
        _clustersFailed = false;
      });
    }
  }

  Future<void> _showSummary(Report report) {
    return showModalBottomSheet<void>(
      context: context,
      sheetAnimationStyle: MediaQuery.disableAnimationsOf(context)
          ? AnimationStyle.noAnimation
          : null,
      builder: (sheetContext) {
        void openDetail() {
          Navigator.of(sheetContext).pop();
          widget.onOpen(report);
        }

        return ReportMapSummary(report: report, onOpen: openDetail);
      },
    );
  }

  Future<void> _tapCluster(ReportCluster cluster) async {
    if (cluster.count == 1 && cluster.ids.length == 1) {
      try {
        final report = await context.read<ReportRepository>().get(
          cluster.ids.single,
        );
        if (mounted) await _showSummary(report);
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text(S.loadError)));
        }
      }
      return;
    }
    final zoom = math.min(_controller.camera.zoom + 2, 18).toDouble();
    _controller.move(cluster.position, zoom);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Semantics(
          label: S.mapAlternative,
          child: FlutterMap(
            mapController: _controller,
            options: MapOptions(
              initialCenter: AppConfig.defaultCenter,
              initialZoom: AppConfig.defaultZoom,
              onMapReady: () {
                _ready = true;
                unawaited(_load());
              },
              onPositionChanged: (_, _) => _scheduleLoad(),
            ),
            children: [
              TileLayer(
                urlTemplate: AppConfig.tileUrl,
                tileProvider: context.read<TileProvider>(),
                userAgentPackageName: AppConfig.userAgentPackage,
              ),
              if (_showReports)
                MarkerLayer(
                  markers: [
                    for (final report in _pins)
                      Marker(
                        point: report.position,
                        width: 104,
                        height: 72,
                        child: StatePin(
                          report: report,
                          onTap: () => _showSummary(report),
                        ),
                      ),
                    for (final cluster in _clusters)
                      Marker(
                        point: cluster.position,
                        width: 56,
                        height: 56,
                        child: ClusterPin(
                          cluster: cluster,
                          onTap: () => _tapCluster(cluster),
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
        Positioned(
          right: 8,
          bottom: 16,
          child: Card(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                MapLayersButton(
                  overlay: 'Reportes de la comunidad',
                  visible: _showReports,
                  onChanged: (value) => setState(() => _showReports = value),
                ),
                IconButton(
                  tooltip: 'Acercar mapa',
                  onPressed: () => _controller.move(
                    _controller.camera.center,
                    (_controller.camera.zoom + 1).clamp(3, 19),
                  ),
                  icon: const Icon(Icons.add),
                ),
                IconButton(
                  tooltip: 'Alejar mapa',
                  onPressed: () => _controller.move(
                    _controller.camera.center,
                    (_controller.camera.zoom - 1).clamp(3, 19),
                  ),
                  icon: const Icon(Icons.remove),
                ),
                IconButton(
                  tooltip: S.useMyLocation,
                  onPressed: locate,
                  icon: const Icon(Icons.my_location),
                ),
              ],
            ),
          ),
        ),
        const Positioned(
          left: 4,
          bottom: 4,
          child: ColoredBox(
            color: Colors.white,
            child: Text(
              '© OpenStreetMap contributors',
              style: TextStyle(color: AldiaColors.text, fontSize: 11),
            ),
          ),
        ),
        if (_clustersFailed)
          const Positioned(
            left: 8,
            right: 8,
            top: 8,
            child: Card(
              child: Padding(
                padding: EdgeInsets.all(8),
                child: Text(S.mapFallback),
              ),
            ),
          ),
      ],
    );
  }
}
