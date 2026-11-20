import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
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

class MapViewState extends State<MapView> with AutomaticKeepAliveClientMixin {
  final _controller = MapController();
  Timer? _debounce;
  var _token = 0;
  var _ready = false;
  List<ReportCluster> _clusters = const [];
  List<Report> _pins = const [];
  bool _clustersFailed = false;
  bool _loading = false;
  bool _loadFailed = false;
  bool _hasSuccessfulLoad = false;
  bool _showReports = true;
  bool _locating = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void didUpdateWidget(MapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state ||
        oldWidget.category != widget.category) {
      _debounce?.cancel();
      ++_token;
      _clusters = const [];
      _pins = const [];
      _clustersFailed = false;
      _loading = false;
      _loadFailed = false;
      _hasSuccessfulLoad = false;
      setState(() {});
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
    if (!mounted || !_ready || _locating) return;
    _locating = true;
    LatLng? point;
    try {
      point = await context.read<LocationService>().currentPosition();
    } catch (_) {
      point = null;
    } finally {
      _locating = false;
    }
    if (!mounted || !_ready) return;
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
    if (!mounted || !_ready) return;
    _debounce?.cancel();
    final camera = _controller.camera;
    final bounds = camera.visibleBounds;
    final token = ++_token;
    final api = context.read<ClustersApi?>();
    final repository = context.read<ReportRepository>();
    final state = widget.state;
    final category = widget.category;
    final filtered = state != null || category != null;
    setState(() {
      _loading = true;
      _loadFailed = false;
      _clustersFailed = false;
    });
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
          _loading = false;
          _loadFailed = false;
          _hasSuccessfulLoad = true;
        });
        return;
      } catch (_) {
        // Fall through to the viewport reports when this request is current.
      }
    }
    if (!mounted || token != _token) return;
    try {
      final reports = await repository.nearby(
        southWest: bounds.southWest,
        northEast: bounds.northEast,
        state: state,
        category: category,
      );
      if (!mounted || token != _token) return;
      setState(() {
        _clusters = const [];
        _pins = reports;
        _clustersFailed = api != null && !filtered;
        _loading = false;
        _loadFailed = false;
        _hasSuccessfulLoad = true;
      });
    } catch (_) {
      if (!mounted || token != _token) return;
      setState(() {
        _loading = false;
        _loadFailed = true;
      });
    }
  }

  /// Reload reports for the current viewport and filters.
  Future<void> refresh() {
    _debounce?.cancel();
    if (!mounted || !_ready) return Future<void>.value();
    return _load();
  }

  Future<void> _showSummary(Report report) {
    return showModalBottomSheet<void>(
      context: context,
      sheetAnimationStyle: MediaQuery.disableAnimationsOf(context)
          ? AnimationStyle.noAnimation
          : const AnimationStyle(
              duration: Duration(milliseconds: 240),
              reverseDuration: Duration(milliseconds: 180),
            ),
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
    super.build(context);
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
          right: AldiaSpace.l,
          bottom: AldiaSpace.xl,
          child: Card(
            color: Theme.of(context).colorScheme.surface,
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AldiaSpace.xs),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      MapLayersButton(
                        overlay: 'Reportes de la comunidad',
                        visible: _showReports,
                        onChanged: (value) =>
                            setState(() => _showReports = value),
                      ),
                      IconButton(
                        tooltip: 'Acercar mapa',
                        onPressed: _ready
                            ? () => _controller.move(
                                _controller.camera.center,
                                (_controller.camera.zoom + 1).clamp(3, 19),
                              )
                            : null,
                        icon: const Icon(Icons.add),
                      ),
                      IconButton(
                        tooltip: 'Alejar mapa',
                        onPressed: _ready
                            ? () => _controller.move(
                                _controller.camera.center,
                                (_controller.camera.zoom - 1).clamp(3, 19),
                              )
                            : null,
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
              ],
            ),
          ),
        ),
        Positioned(
          left: AldiaSpace.xs,
          bottom: AldiaSpace.xs,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AldiaSpace.xs,
                vertical: AldiaSpace.xs / 2,
              ),
              child: Text(
                '© OpenStreetMap contributors',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: Theme.of(context).colorScheme.onSurface),
              ),
            ),
          ),
        ),
        if (_loading ||
            _loadFailed ||
            _clustersFailed ||
            (_showReports &&
                _hasSuccessfulLoad &&
                _clusters.isEmpty &&
                _pins.isEmpty))
          Positioned(
            left: 8,
            right: 8,
            top: 8,
            child: LayoutBuilder(
              builder: (context, constraints) => ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: constraints.maxHeight * .4,
                ),
                child: Card(
                  color: Theme.of(context).colorScheme.surface,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(AldiaSpace.m),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_loading) const LinearProgressIndicator(),
                        if (_loading && (_loadFailed || _clustersFailed))
                          const SizedBox(height: AldiaSpace.s),
                        if (_loadFailed) ...[
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.error_outline,
                                size: 20,
                                color: Theme.of(context).colorScheme.error,
                              ),
                              const SizedBox(width: AldiaSpace.s),
                              Expanded(
                                child: Semantics(
                                  liveRegion: true,
                                  child: Text(
                                    _hasSuccessfulLoad
                                        ? 'No se pudieron actualizar los reportes. Se muestran los últimos datos disponibles.'
                                        : 'No se pudieron cargar los reportes.',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurface,
                                        ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: AldiaSpace.s),
                          TextButton.icon(
                            style: TextButton.styleFrom(
                              minimumSize: const Size(
                                AldiaSpace.target,
                                AldiaSpace.target,
                              ),
                            ),
                            onPressed: refresh,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Reintentar'),
                          ),
                        ] else ...[
                          if (!_loading && _clustersFailed)
                            Text(
                              S.mapFallback,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface,
                                  ),
                            ),
                          if (!_loading &&
                              _clustersFailed &&
                              _showReports &&
                              _hasSuccessfulLoad &&
                              _clusters.isEmpty &&
                              _pins.isEmpty)
                            const SizedBox(height: AldiaSpace.s),
                          if (!_loading &&
                              _showReports &&
                              _hasSuccessfulLoad &&
                              _clusters.isEmpty &&
                              _pins.isEmpty)
                            Text(
                              'No hay reportes en esta zona.',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface,
                                  ),
                            ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
