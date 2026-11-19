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
import '../../widgets/report_tile.dart';
import '../../widgets/routes.dart';
import '../detail/report_detail_screen.dart';
import '../drafts/draft_record.dart';
import '../drafts/draft_store.dart';
import '../mine/my_reports_screen.dart';
import '../report/report_flow_screen.dart';

enum _View { map, list }

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
  _View _view = _View.map;
  String? _state;
  String? _category;
  DraftRecord? _draft;
  late Future<List<Report>> _list;

  bool get _filtered => _state != null || _category != null;

  @override
  void initState() {
    super.initState();
    _list = _loadList();
    unawaited(_loadDraft());
  }

  Future<List<Report>> _loadList() => context.read<ReportRepository>().nearby(
    state: _state,
    category: _category,
  );

  Future<void> _loadDraft() async {
    final drafts = await context.read<DraftStore?>()?.loadAll();
    if (mounted) setState(() => _draft = drafts?.firstOrNull);
  }

  void _reload() {
    setState(() {
      _list = _loadList();
    });
  }

  void _open(Report report) =>
      AldiaRoute.open<void>(context, ReportDetailScreen(report: report));

  Future<void> _startReport([DraftRecord? draft]) async {
    await AldiaRoute.open<void>(context, ReportFlowScreen(draft: draft));
    if (!mounted) return;
    _reload();
    unawaited(_loadDraft());
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(S.appName),
        actions: [
          IconButton(
            tooltip: S.myReports,
            icon: const Icon(Icons.person_outline),
            onPressed: () =>
                AldiaRoute.open<void>(context, const MyReportsScreen()),
          ),
        ],
      ),
      body: Column(
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.4,
            ),
            child: SingleChildScrollView(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                    child: SegmentedButton<_View>(
                      segments: const [
                        ButtonSegment(
                          value: _View.map,
                          icon: Icon(Icons.map),
                          label: Text(S.navMap),
                        ),
                        ButtonSegment(
                          value: _View.list,
                          icon: Icon(Icons.list),
                          label: Text(S.navList),
                        ),
                      ],
                      selected: {_view},
                      onSelectionChanged: (s) =>
                          setState(() => _view = s.first),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _editFilters,
                      icon: const Icon(Icons.filter_list),
                      label: Text(
                        _filtered
                            ? '${S.filtersLabel} (${(_state != null ? 1 : 0) + (_category != null ? 1 : 0)})'
                            : S.filtersLabel,
                      ),
                    ),
                  ),
                  if (_draft case final draft?)
                    _DraftBanner(
                      draft: draft,
                      onTap: () => _startReport(draft),
                    ),
                ],
              ),
            ),
          ),
          Expanded(
            child: _view == _View.map
                ? _MapView(state: _state, category: _category, onOpen: _open)
                : _ReportList(
                    future: _list,
                    filtered: _filtered,
                    onOpen: _open,
                    onRetry: _reload,
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _startReport,
        icon: const Icon(Icons.add_a_photo),
        label: const Text(S.newReport),
      ),
    );
  }
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
    return Card(
      margin: const EdgeInsets.fromLTRB(8, 8, 8, 0),
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
  });

  final Future<List<Report>> future;
  final bool filtered;
  final void Function(Report) onOpen;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Report>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(S.loadError),
                TextButton(onPressed: onRetry, child: const Text(S.retry)),
              ],
            ),
          );
        }
        final reports = snapshot.data!;
        if (reports.isEmpty) {
          return Center(
            child: Text(filtered ? S.emptyFiltered : S.emptyNearby),
          );
        }
        return RefreshIndicator(
          onRefresh: () async => onRetry(),
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: 88),
            itemCount: reports.length,
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
            padding: const EdgeInsets.all(8),
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
            CircleAvatar(
              radius: 20,
              backgroundColor: AldiaColors.primaryDark,
              child: Icon(state.icon, color: Colors.white, size: 22),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                state.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textScaler: TextScaler.noScaling,
                style: const TextStyle(fontSize: 11),
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
        child: CircleAvatar(
          backgroundColor: AldiaColors.primaryDark,
          child: single
              ? const Icon(Icons.location_on, color: Colors.white)
              : Text(
                  '${cluster.count}',
                  textScaler: TextScaler.noScaling,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
        ),
      ),
    );
  }
}
