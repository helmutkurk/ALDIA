import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:provider/provider.dart';

import '../../core/categories.dart';
import '../../core/citizen_states.dart';
import '../../core/config.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../data/clusters_api.dart';
import '../../data/report.dart';
import '../../data/report_repository.dart';
import '../../services/location_service.dart';
import '../citizen/citizen_screens.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/report_tile.dart';
import '../../widgets/map_layers_button.dart';
import '../../widgets/neutral_map_pin.dart';
import '../../widgets/routes.dart';
import '../detail/report_detail_screen.dart';
import '../drafts/draft_record.dart';
import '../drafts/draft_store.dart';
import '../mine/my_reports_screen.dart';
import '../report/report_flow_screen.dart';

enum _Tab { home, notices, report, mine, profile }

/// States a citizen can filter by (`oculto` is never public).
final List<String> _filterStates = [
  for (final state in citizenStates.keys)
    if (state != 'oculto') state,
];

/// Nearby reports as a map or a list, with filters and the report button.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  _Tab _tab = _Tab.home;
  bool _exploring = false;
  late Future<int?> _resolved;
  // Tabs are built on first visit and then kept (map camera, scroll position).
  final _visited = <_Tab>{_Tab.home};
  int _mineToken = 0;
  String? _state;
  String? _category;
  DraftRecord? _draft;
  late Future<List<Report>> _list;

  bool get _filtered => _state != null || _category != null;

  @override
  void initState() {
    super.initState();
    _list = _loadList();
    _resolved = _loadResolved();
    unawaited(_loadDraft());
    unawaited(_observeMine());
  }

  Future<int?> _loadResolved() async {
    try {
      return await context.read<ReportRepository>().resolvedCount();
    } catch (_) {
      return null;
    }
  }

  Future<void> _observeMine() async {
    try {
      await context.read<ReportRepository>().mine();
    } catch (_) {
      /* The inbox remains available offline. */
    }
  }

  Future<List<Report>> _loadList() {
    final future = context.read<ReportRepository>().nearby(
      state: _state,
      category: _category,
    );
    // Explore is lazy. Observe failures now; FutureBuilder still receives the
    // original error when the citizen opens Lista and offers Retry.
    future.ignore();
    return future;
  }

  Future<void> _loadDraft() async {
    final drafts = await context.read<DraftStore?>()?.loadAll();
    if (mounted) setState(() => _draft = drafts?.firstOrNull);
  }

  void _reload() {
    setState(() {
      _list = _loadList();
      _resolved = _loadResolved();
    });
    unawaited(_observeMine());
  }

  void _open(Report report) =>
      AldiaRoute.open<void>(context, ReportDetailScreen(report: report));

  Future<void> _startReport([DraftRecord? draft]) async {
    await AldiaRoute.open<void>(context, ReportFlowScreen(draft: draft));
    if (!mounted) return;
    setState(() => _mineToken++);
    _reload();
    unawaited(_loadDraft());
  }

  void _clearFilters() {
    setState(() {
      _state = null;
      _category = null;
      _list = _loadList();
    });
  }

  Future<void> _editFilters() async {
    final result = await showModalBottomSheet<(String?, String?)>(
      context: context,
      isScrollControlled: true,
      sheetAnimationStyle: _sheetStyle(context),
      builder: (_) => _FiltersSheet(state: _state, category: _category),
    );
    if (result == null) return;
    setState(() {
      _state = result.$1;
      _category = result.$2;
      _list = _loadList();
    });
  }

  Widget _body(_Tab tab) {
    if (!_visited.contains(tab)) return const SizedBox.shrink();
    return switch (tab) {
      _Tab.home =>
        _exploring
            ? DefaultTabController(
                length: 2,
                animationDuration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 300),
                child: Column(
                  children: [
                    TabBar(
                      indicatorColor: Theme.of(context).colorScheme.primary,
                      indicatorWeight: 3,
                      tabs: const [
                        Tab(text: 'MAPA'),
                        Tab(text: 'LISTA'),
                      ],
                    ),
                    Expanded(
                      child: TabBarView(
                        physics: MediaQuery.disableAnimationsOf(context)
                            ? const NeverScrollableScrollPhysics()
                            : null,
                        children: [
                          _MapView(
                            state: _state,
                            category: _category,
                            onOpen: _open,
                          ),
                          _ReportList(
                            future: _list,
                            filtered: _filtered,
                            onOpen: _open,
                            onRetry: _reload,
                            onClear: _clearFilters,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              )
            : _Landing(
                resolved: _resolved,
                onExplore: () => setState(() => _exploring = true),
                onReport: _startReport,
              ),
      _Tab.notices => NoticesScreen(onOpen: _open),
      _Tab.mine => MyReportsScreen(embedded: true, reloadToken: _mineToken),
      _Tab.profile => ProfileScreen(
        onCleared: () {
          setState(() => _mineToken++);
          _reload();
          unawaited(_loadDraft());
        },
      ),
      _Tab.report => const SizedBox.shrink(),
    };
  }

  @override
  Widget build(BuildContext context) {
    final filterCount = (_state != null ? 1 : 0) + (_category != null ? 1 : 0);
    final exploring = _tab == _Tab.home && _exploring;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AldiaColors.primary,
        foregroundColor: Colors.white,
        leading: exploring
            ? IconButton(
                tooltip: 'Volver a Inicio',
                onPressed: () => setState(() => _exploring = false),
                icon: const Icon(Icons.arrow_back),
              )
            : null,
        title: Text(
          exploring
              ? 'Explorar mi ciudad'
              : switch (_tab) {
                  _Tab.notices => 'Avisos',
                  _Tab.mine => S.myReports,
                  _Tab.profile => 'Perfil',
                  _ => S.appName,
                },
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          if (exploring)
            IconButton(
              tooltip: S.filtersLabel,
              onPressed: _editFilters,
              icon: Badge(
                isLabelVisible: _filtered,
                label: Text('$filterCount'),
                child: const Icon(Icons.filter_list),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          if (_draft case final draft? when _tab == _Tab.home)
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.3,
              ),
              child: SingleChildScrollView(
                child: _DraftBanner(
                  draft: draft,
                  onTap: () => _startReport(draft),
                ),
              ),
            ),
          Expanded(
            child: IndexedStack(
              index: _tab.index,
              children: [for (final tab in _Tab.values) _body(tab)],
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab.index,
        height: MediaQuery.textScalerOf(context).scale(14) > 20 ? 104 : 80,
        animationDuration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 300),
        onDestinationSelected: (i) {
          final tab = _Tab.values[i];
          if (tab == _Tab.report) {
            unawaited(_startReport());
            return;
          }
          setState(() {
            _tab = tab;
            _visited.add(tab);
          });
          if (tab == _Tab.notices || tab == _Tab.mine) {
            unawaited(_observeMine());
          }
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Inicio',
          ),
          NavigationDestination(
            icon: Icon(Icons.notifications_outlined),
            selectedIcon: Icon(Icons.notifications),
            label: 'Avisos',
          ),
          NavigationDestination(
            icon: Icon(Icons.add_circle_outline, size: 36),
            label: S.newReport,
          ),
          NavigationDestination(
            icon: Icon(Icons.assignment_outlined),
            selectedIcon: Icon(Icons.assignment),
            label: S.myReports,
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Perfil',
          ),
        ],
      ),
    );
  }
}

class _Landing extends StatelessWidget {
  const _Landing({
    required this.resolved,
    required this.onExplore,
    required this.onReport,
  });
  final Future<int?> resolved;
  final VoidCallback onExplore;
  final VoidCallback onReport;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Theme.of(context).scaffoldBackgroundColor,
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(AldiaSpace.xl),
          children: [
            Icon(
              Icons.location_city_outlined,
              color: Theme.of(context).colorScheme.primary,
              size: 88,
            ),
            const SizedBox(height: 16),
            Text(
              'Tu ciudad, al día',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineMedium
                  ?.copyWith(color: Theme.of(context).colorScheme.onSurface),
            ),
            const SizedBox(height: 24),
            FutureBuilder<int?>(
              future: resolved,
              builder: (context, snapshot) => Column(
                children: [
                  Text(
                    snapshot.data?.toString() ?? '—',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.displayLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    snapshot.hasData
                        ? 'reportes resueltos'
                        : 'Reportes resueltos: dato no disponible',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Divider(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
            FilledButton.tonalIcon(
              onPressed: onExplore,
              icon: const Icon(Icons.explore_outlined),
              label: const Text('Explorar mi ciudad'),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onReport,
              icon: const Icon(Icons.add_a_photo_outlined),
              label: const Text('Reportar un problema'),
            ),
          ],
        ),
      ),
    ),
  );
}

AnimationStyle? _sheetStyle(BuildContext context) =>
    MediaQuery.disableAnimationsOf(context) ? AnimationStyle.noAnimation : null;

class _DraftBanner extends StatelessWidget {
  const _DraftBanner({required this.draft, required this.onTap});
  final DraftRecord draft;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final category = draft.categoryId == null
        ? null
        : categoryById(draft.categoryId!).label;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AldiaSpace.l,
        AldiaSpace.s,
        AldiaSpace.l,
        0,
      ),
      child: Card(
        color: Theme.of(context).colorScheme.secondaryContainer,
        child: ListTile(
          minTileHeight: 56,
          leading: const Icon(Icons.edit_note),
          title: const Text(S.continueDraft),
          subtitle: Text(
            [
              S.draftBannerHelp,
              ?category,
              S.age(draft.createdAt, DateTime.now()),
            ].join(' · '),
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: onTap,
        ),
      ),
    );
  }
}

class _FiltersSheet extends StatefulWidget {
  const _FiltersSheet({this.state, this.category});
  final String? state;
  final String? category;

  @override
  State<_FiltersSheet> createState() => _FiltersSheetState();
}

class _FiltersSheetState extends State<_FiltersSheet> {
  late String? _state = widget.state;
  late String? _category = widget.category;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(
                S.filtersLabel,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              initialValue: _state,
              isExpanded: true,
              decoration: const InputDecoration(labelText: S.filterState),
              items: [
                const DropdownMenuItem(child: Text(S.allStates)),
                for (final state in _filterStates)
                  DropdownMenuItem(
                    value: state,
                    child: Text(citizenStates[state]!.label),
                  ),
              ],
              onChanged: (value) => setState(() => _state = value),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              initialValue: _category,
              isExpanded: true,
              decoration: const InputDecoration(labelText: S.filterCategory),
              items: [
                const DropdownMenuItem(child: Text(S.allCategories)),
                for (final category in reportCategories)
                  DropdownMenuItem(
                    value: category.id,
                    child: Text(category.label),
                  ),
              ],
              onChanged: (value) => setState(() => _category = value),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.of(context).pop((_state, _category)),
              child: const Text(S.apply),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop((null, null)),
              child: const Text(S.clearFilters),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReportList extends StatelessWidget {
  const _ReportList({
    required this.future,
    required this.filtered,
    required this.onOpen,
    required this.onRetry,
    required this.onClear,
  });

  final Future<List<Report>> future;
  final bool filtered;
  final void Function(Report) onOpen;
  final VoidCallback onRetry;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Report>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return EmptyState(
            icon: Icons.cloud_off,
            title: S.loadError,
            actionLabel: S.retry,
            onAction: onRetry,
          );
        }
        final reports = snapshot.data!;
        if (reports.isEmpty) {
          return filtered
              ? EmptyState(
                  icon: Icons.filter_list_off,
                  title: S.emptyFiltered,
                  actionLabel: S.clearFilters,
                  onAction: onClear,
                )
              : const EmptyState(
                  icon: Icons.map_outlined,
                  title: S.emptyNearby,
                  help: S.emptyNearbyHelp,
                );
        }
        return RefreshIndicator(
          onRefresh: () async => onRetry(),
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(
              AldiaSpace.l,
              AldiaSpace.s,
              AldiaSpace.l,
              AldiaSpace.fabClearance,
            ),
            itemCount: reports.length,
            separatorBuilder: (_, _) => const SizedBox(height: AldiaSpace.s),
            itemBuilder: (context, i) =>
                ReportTile(report: reports[i], onTap: () => onOpen(reports[i])),
          ),
        );
      },
    );
  }
}

/// Clusters for the visible viewport; plain reports when clusters are not
/// available or a filter is active (the clusters endpoint has no filters).
class _MapView extends StatefulWidget {
  const _MapView({
    required this.state,
    required this.category,
    required this.onOpen,
  });

  final String? state;
  final String? category;
  final void Function(Report) onOpen;

  @override
  State<_MapView> createState() => _MapViewState();
}

class _MapViewState extends State<_MapView> {
  final _controller = MapController();
  Timer? _debounce;
  var _token = 0;
  var _ready = false;
  List<ReportCluster> _clusters = const [];
  List<Report> _pins = const [];
  bool _clustersFailed = false;
  bool _showReports = true;

  @override
  void didUpdateWidget(_MapView old) {
    super.didUpdateWidget(old);
    if (old.state != widget.state || old.category != widget.category) {
      unawaited(_load());
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
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
      sheetAnimationStyle: _sheetStyle(context),
      builder: (sheetContext) {
        void openDetail() {
          Navigator.of(sheetContext).pop();
          widget.onOpen(report);
        }

        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AldiaSpace.l),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ReportTile(report: report, onTap: openDetail),
                if (report.publicNote?.isNotEmpty == true)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(report.publicNote!),
                  ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: openDetail,
                  child: const Text(S.viewDetail),
                ),
              ],
            ),
          ),
        );
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
                        child: _StatePin(
                          report: report,
                          onTap: () => _showSummary(report),
                        ),
                      ),
                    for (final cluster in _clusters)
                      Marker(
                        point: cluster.position,
                        width: 56,
                        height: 56,
                        child: _ClusterPin(
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
                  onPressed: () async {
                    final point = await context
                        .read<LocationService>()
                        .currentPosition();
                    if (!mounted || !context.mounted) return;
                    if (point != null) {
                      _controller.move(point, 16);
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text(S.locationUnavailable)),
                      );
                    }
                  },
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

/// Pin with the state as icon and short text, so it is not color-only.
class _StatePin extends StatelessWidget {
  const _StatePin({required this.report, required this.onTap});
  final Report report;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final state = citizenStateFor(report.citizenState);
    final category = categoryById(report.category).label;
    return Semantics(
      button: true,
      label: '$category. ${state.label}',
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            NeutralMapPin(child: Icon(state.icon)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
              child: Text(
                state.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textScaler: TextScaler.noScaling,
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ClusterPin extends StatelessWidget {
  const _ClusterPin({required this.cluster, required this.onTap});
  final ReportCluster cluster;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final single = cluster.count == 1;
    return Semantics(
      button: true,
      label: single
          ? S.pinReport
          : '${S.clusterCount(cluster.count)}. ${S.zoomToCluster}',
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: NeutralMapPin(
          child: single
              ? const Icon(Icons.location_on)
              : Text('${cluster.count}', textScaler: TextScaler.noScaling),
        ),
      ),
    );
  }
}
