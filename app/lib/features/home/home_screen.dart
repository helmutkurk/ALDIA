import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../data/report.dart';
import '../../data/report_repository.dart';
import '../../services/haptics.dart';
import '../../widgets/adaptive_sheet_route.dart';
import '../../widgets/routes.dart';
import '../changelog/changelog.dart';
import '../citizen/citizen_screens.dart';
import '../detail/report_detail_screen.dart';
import '../drafts/draft_record.dart';
import '../drafts/draft_store.dart';
import '../mine/my_reports_screen.dart';
import '../report/report_flow_screen.dart';
import 'bottom_navigation_reselect.dart';
import 'explore_reports.dart';
import 'home_landing.dart';
import 'home_navigation.dart';
import 'report_filters_sheet.dart';
import 'report_map_view.dart';

/// Nearby reports as a map or a list, with filters and the report button.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.changelog});

  /// Pending "Novedades" to show once. Null in tests.
  final ChangelogController? changelog;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  HomeTab _tab = HomeTab.home;
  bool _exploring = false;
  String _query = '';
  final _mapKey = GlobalKey<MapViewState>();
  late Future<int?> _resolved;
  // Tabs are built on first visit and then kept (map camera, scroll position).
  final _visited = <HomeTab>{HomeTab.home};
  int _mineToken = 0;

  /// Contract `state_group` filter.
  String? _group;
  String? _category;
  DraftRecord? _draft;
  late Future<List<Report>> _list;

  int get _filterCount =>
      (_group != null ? 1 : 0) +
      (_category != null ? 1 : 0) +
      (_query.isNotEmpty ? 1 : 0);

  @override
  void initState() {
    super.initState();
    _list = _loadList();
    _resolved = _loadResolved();
    unawaited(_loadDraft());
    unawaited(_observeMine());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(showChangelogIfNeeded(context, widget.changelog));
    });
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
      stateGroup: _group,
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
      _group = null;
      _category = null;
      _query = '';
      _list = _loadList();
    });
  }

  Future<void> _editFilters() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final result = await Navigator.of(context).push<ReportFilters>(
      FiltersSheet(initial: (group: _group, category: _category, query: _query))
          .asAdaptiveSheetRoute<ReportFilters>(
            reduceMotion: MediaQuery.disableAnimationsOf(context),
          ),
    );
    if (result == null) return;
    setState(() {
      _group = result.group;
      _category = result.category;
      _query = result.query;
      _list = _loadList();
    });
  }

  Widget _body(HomeTab tab) {
    if (!_visited.contains(tab)) return const SizedBox.shrink();
    return switch (tab) {
      HomeTab.home =>
        _exploring
            ? ExploreReports(
                mapKey: _mapKey,
                group: _group,
                category: _category,
                onOpen: _open,
                reports: _list,
                filterCount: _filterCount,
                query: _query,
                onRetry: _reload,
                onClear: _clearFilters,
                onBack: () => setState(() => _exploring = false),
                onFilters: _editFilters,
              )
            : Landing(
                resolved: _resolved,
                onExplore: () => setState(() => _exploring = true),
                onReport: _startReport,
              ),
      HomeTab.notices => NoticesScreen(onOpen: _open),
      HomeTab.mine => MyReportsScreen(embedded: true, reloadToken: _mineToken),
      HomeTab.profile => ProfileScreen(
        onCleared: () {
          setState(() => _mineToken++);
          _reload();
          unawaited(_loadDraft());
        },
      ),
      HomeTab.report => const SizedBox.shrink(),
    };
  }

  @override
  Widget build(BuildContext context) {
    final exploring = _tab == HomeTab.home && _exploring;
    return Scaffold(
      // Explorar draws its own floating controls over a full-screen map.
      appBar: exploring
          ? null
          : AppBar(
              backgroundColor: AldiaColors.barOf(context),
              foregroundColor: AldiaColors.onBar,
              iconTheme: const IconThemeData(color: AldiaColors.onBar),
              shape: null,
              title: Text(switch (_tab) {
                HomeTab.notices => 'Avisos',
                HomeTab.mine => S.myReports,
                HomeTab.profile => 'Perfil',
                _ => S.appName,
              }, style: const TextStyle(color: AldiaColors.onBar)),
            ),
      body: Column(
        children: [
          if (_draft case final draft? when _tab == HomeTab.home && !exploring)
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.3,
              ),
              child: SingleChildScrollView(
                child: DraftBanner(
                  draft: draft,
                  onTap: () => _startReport(draft),
                ),
              ),
            ),
          Expanded(
            child: IndexedStack(
              index: _tab.index,
              children: [for (final tab in HomeTab.values) _body(tab)],
            ),
          ),
        ],
      ),
      bottomNavigationBar: HomeNavigationBar(
        selected: _tab,
        onSelected: (tab) {
          unawaited(HapticsHelper.light());
          if (tab == HomeTab.report) {
            unawaited(_startReport());
            return;
          }
          if (tab == _tab) {
            BottomNavigationReselect.scrollToTop(switch (tab) {
              HomeTab.home =>
                _exploring
                    ? BottomNavigationReselect.exploreListScrollController
                    : BottomNavigationReselect.landingScrollController,
              HomeTab.notices =>
                BottomNavigationReselect.noticesScrollController,
              HomeTab.mine => BottomNavigationReselect.mineScrollController,
              _ => BottomNavigationReselect.profileScrollController,
            }, reduceMotion: MediaQuery.disableAnimationsOf(context));
            return;
          }
          setState(() {
            _tab = tab;
            _visited.add(tab);
          });
          if (tab == HomeTab.notices || tab == HomeTab.mine) {
            unawaited(_observeMine());
          }
        },
      ),
    );
  }
}
