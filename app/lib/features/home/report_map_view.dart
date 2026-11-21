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
import '../../services/haptics.dart';
import '../../services/location_service.dart';
import '../../core/citizen_states.dart';
import '../../widgets/aldia_banner.dart';
import '../../widgets/map_layers_button.dart';
import '../../widgets/status_chips.dart';
import 'report_map_widgets.dart';

/// Clusters for the visible viewport; plain reports when clusters are not
/// available or a filter is active (the clusters endpoint has no filters).
class MapView extends StatefulWidget {
  const MapView({
    super.key,
    required this.state,
    required this.category,
    required this.onOpen,
    this.overlayTop = 0,
  });

  /// Contract `state_group` filter, or null for all.
  final String? state;
  final String? category;
  final void Function(Report) onOpen;

  /// Height covered by the floating Explorar controls; overlays start below.
  final double overlayTop;

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
  bool _loading = true;
  bool _failed = false;

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
      unawaited(HapticsHelper.error());
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
    // Set without a rebuild: this can run while the map is building.
    _loading = true;
    _failed = false;
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
        });
        return;
      } catch (_) {
        // Fall through to the plain list below.
      }
    }
    try {
      final page = await repository.nearby(
        southWest: bounds.southWest,
        northEast: bounds.northEast,
        stateGroup: widget.state,
        category: widget.category,
      );
      if (!mounted || token != _token) return;
      setState(() {
        _clusters = const [];
        _pins = page.items;
        _clustersFailed = api != null && !filtered;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || token != _token) return;
      setState(() {
        _clusters = const [];
        _pins = const [];
        _clustersFailed = false;
        _loading = false;
        _failed = true;
      });
    }
  }

  Future<void> _showSummary(Report report) {
    FocusManager.instance.primaryFocus?.unfocus();
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
          unawaited(HapticsHelper.error());
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
          left: AldiaSpace.l,
          right: AldiaSpace.l,
          top: widget.overlayTop,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_loading && _ready)
                const _Floating(child: AldiaBanner(S.mapLoading))
              else if (_failed)
                _Floating(
                  child: Semantics(
                    button: true,
                    onTap: _load,
                    child: GestureDetector(
                      onTap: _load,
                      child: const AldiaBanner(
                        S.mapError,
                        kind: BannerKind.error,
                      ),
                    ),
                  ),
                )
              else if (_ready && _pins.isEmpty && _clusters.isEmpty)
                const _Floating(
                  child: AldiaBanner(S.mapEmpty, kind: BannerKind.warning),
                ),
              if (_clustersFailed)
                const _Floating(child: AldiaBanner(S.mapFallback)),
            ],
          ),
        ),
        const Positioned(
          left: AldiaSpace.l,
          bottom: AldiaSpace.l,
          child: _Legend(),
        ),
        Positioned(
          right: AldiaSpace.l,
          bottom: AldiaSpace.xxl,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Floating(
                radius: AldiaRadius.tile,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: S.zoomIn,
                      onPressed: () => _controller.move(
                        _controller.camera.center,
                        (_controller.camera.zoom + 1).clamp(3, 19),
                      ),
                      icon: const Icon(Icons.add),
                    ),
                    const SizedBox(width: 32, child: Divider(height: 1)),
                    IconButton(
                      tooltip: S.zoomOut,
                      onPressed: () => _controller.move(
                        _controller.camera.center,
                        (_controller.camera.zoom - 1).clamp(3, 19),
                      ),
                      icon: const Icon(Icons.remove),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AldiaSpace.m),
              _Floating(
                radius: 26,
                child: IconButton(
                  tooltip: S.useMyLocation,
                  onPressed: locate,
                  icon: const Icon(Icons.my_location),
                ),
              ),
              const SizedBox(height: AldiaSpace.m),
              _Floating(
                radius: 26,
                child: MapLayersButton(
                  overlay: 'Reportes de la comunidad',
                  visible: _showReports,
                  onChanged: (value) => setState(() => _showReports = value),
                ),
              ),
            ],
          ),
        ),
        Positioned(
          right: AldiaSpace.s,
          bottom: AldiaSpace.xs,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: Text(
                '© OpenStreetMap contributors',
                style: TextStyle(color: AldiaColors.text, fontSize: 11),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Surface with a soft shadow for controls floating over the map.
class _Floating extends StatelessWidget {
  const _Floating({required this.child, this.radius = AldiaRadius.input});
  final Widget child;
  final double radius;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AldiaSpace.s),
    child: Material(
      color: Theme.of(context).colorScheme.surface,
      elevation: 3,
      shadowColor: Colors.black45,
      borderRadius: BorderRadius.circular(radius),
      clipBehavior: Clip.antiAlias,
      child: child,
    ),
  );
}

/// Map key: one dot and word per public state group.
class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _Floating(
      radius: AldiaRadius.tile,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AldiaSpace.m,
          AldiaSpace.s,
          AldiaSpace.l,
          AldiaSpace.s,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text(S.legendTitle, style: theme.textTheme.labelLarge),
            ),
            for (final group in const ['open', 'in_work', 'resolved', 'closed'])
              Padding(
                padding: const EdgeInsets.only(top: AldiaSpace.xs),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    StatusDot(state: stateGroups[group]!.$2),
                    const SizedBox(width: AldiaSpace.s),
                    Text(
                      stateGroups[group]!.$1,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
