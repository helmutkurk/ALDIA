import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../data/report.dart';
import '../../data/report_repository.dart';
import '../../widgets/routes.dart';
import '../citizen/citizen_screens.dart';
import '../detail/report_detail_screen.dart';
import '../drafts/draft_record.dart';
import '../drafts/draft_store.dart';
import '../mine/my_reports_screen.dart';
import '../report/report_flow_screen.dart';
import 'explore_reports.dart';
import 'home_landing.dart';
import 'home_navigation.dart';
import 'report_filters_sheet.dart';
import 'report_map_view.dart';

/// Nearby reports as a map or a list, with filters and the report button.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  HomeTab _tab = HomeTab.home;
  bool _exploring = false;
  bool _searching = false;
  String _query = '';
  final _mapKey = GlobalKey<MapViewState>();
  late Future<int?> _resolved;
  // Tabs are built on first visit and then kept (map camera, scroll position).
  final _visited = <HomeTab>{HomeTab.home};
  int _mineToken = 0;
  int _draftLoadToken = 0;
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
    final token = ++_draftLoadToken;
    try {
      final drafts = await context.read<DraftStore?>()?.loadAll();
      if (mounted && token == _draftLoadToken) {
        setState(() => _draft = drafts?.firstOrNull);
      }
    } catch (_) {
      if (mounted && token == _draftLoadToken) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text(S.storageError)));
      }
    }
  }

  Future<void> _reload() async {
    late final Future<List<Report>> list;
    try {
      list = _loadList();
    } catch (error, stackTrace) {
      list = Future<List<Report>>.error(error, stackTrace)..ignore();
    }
    setState(() {
      _list = list;
      _resolved = _loadResolved();
    });
    unawaited(_observeMine());
    late final Future<void> mapRefresh;
    try {
      mapRefresh = _mapKey.currentState?.refresh() ?? Future<void>.value();
    } catch (_) {
      mapRefresh = Future<void>.value();
    }
    final listCompletion = list.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    final mapCompletion = mapRefresh.catchError((Object _) {});
    await Future.wait<void>([listCompletion, mapCompletion]);
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
    FocusManager.instance.primaryFocus?.unfocus();
    final result = await showModalBottomSheet<(String?, String?)>(
      context: context,
      isScrollControlled: true,
      sheetAnimationStyle: MediaQuery.disableAnimationsOf(context)
          ? AnimationStyle.noAnimation
          : const AnimationStyle(
              duration: Duration(milliseconds: 240),
              reverseDuration: Duration(milliseconds: 180),
            ),
      builder: (_) => FiltersSheet(state: _state, category: _category),
    );
    if (!mounted || result == null) return;
    setState(() {
      _state = result.$1;
      _category = result.$2;
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
                state: _state,
                category: _category,
                onOpen: _open,
                reports: _list,
                filtered: _filtered,
                query: _query,
                isSearching: _searching,
                onRetry: _reload,
                onClear: _clearFilters,
                onMapSelected: () {
                  FocusManager.instance.primaryFocus?.unfocus();
                  setState(() {
                    _searching = false;
                    _query = '';
                  });
                },
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
    final filterCount = (_state != null ? 1 : 0) + (_category != null ? 1 : 0);
    final exploring = _tab == HomeTab.home && _exploring;
    final barIconStyle =
        IconButton.styleFrom(
          minimumSize: const Size(AldiaSpace.target, AldiaSpace.target),
        ).copyWith(
          side: WidgetStateProperty.resolveWith((states) {
            return states.contains(WidgetState.focused)
                ? const BorderSide(color: AldiaColors.onBar, width: 2)
                : BorderSide.none;
          }),
        );
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AldiaColors.barOf(context),
        foregroundColor: AldiaColors.onBar,
        iconTheme: const IconThemeData(color: AldiaColors.onBar),
        actionsIconTheme: const IconThemeData(color: AldiaColors.onBar),
        shape: null,
        leading: exploring
            ? IconButton(
                style: barIconStyle,
                tooltip: 'Volver a Inicio',
                onPressed: () {
                  FocusManager.instance.primaryFocus?.unfocus();
                  setState(() {
                    _exploring = false;
                    _searching = false;
                    _query = '';
                  });
                },
                icon: const Icon(Icons.arrow_back),
              )
            : null,
        title: exploring && _searching
            ? TextField(
                autofocus: true,
                style: Theme.of(context).textTheme.bodyLarge
                    ?.copyWith(color: AldiaColors.onBar),
                cursorColor: AldiaColors.onBar,
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(
                  hintText: 'Buscar en la lista',
                  labelText: 'Buscar en la lista',
                  hintStyle: TextStyle(color: Color(0xFFD9DEE3)),
                  labelStyle: TextStyle(color: AldiaColors.onBar),
                  floatingLabelStyle: TextStyle(color: AldiaColors.onBar),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                ),
                onTapOutside: (_) =>
                    FocusManager.instance.primaryFocus?.unfocus(),
                onChanged: (value) => setState(() => _query = value.trim()),
              )
            : Text(
                exploring
                    ? 'Explorar mi ciudad'
                    : switch (_tab) {
                        HomeTab.notices => 'Avisos',
                        HomeTab.mine => S.myReports,
                        HomeTab.profile => 'Perfil',
                        _ => S.appName,
                      },
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(color: AldiaColors.onBar),
              ),
        actions: [
          if (exploring) ...[
            IconButton(
              style: barIconStyle,
              tooltip: _searching ? 'Cerrar búsqueda' : 'Buscar en la lista',
              onPressed: () {
                if (_searching) {
                  FocusManager.instance.primaryFocus?.unfocus();
                }
                setState(() {
                  _searching = !_searching;
                  if (!_searching) _query = '';
                });
              },
              icon: Icon(_searching ? Icons.close : Icons.search),
            ),
            IconButton(
              style: barIconStyle,
              tooltip: S.filtersLabel,
              onPressed: _editFilters,
              icon: Badge(
                isLabelVisible: _filtered,
                label: Text('$filterCount'),
                child: const Icon(Icons.filter_list),
              ),
            ),
            PopupMenuButton<String>(
              style: barIconStyle,
              tooltip: 'Más opciones',
              iconColor: AldiaColors.onBar,
              onSelected: (value) =>
                  value == 'clear' ? _clearFilters() : _reload(),
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'reload', child: Text('Actualizar')),
                if (_filtered)
                  const PopupMenuItem(
                    value: 'clear',
                    child: Text(S.clearFilters),
                  ),
              ],
            ),
          ],
        ],
      ),
      body: Column(
        children: [
          if (_draft case final draft? when _tab == HomeTab.home)
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
          if (tab == HomeTab.report) {
            unawaited(_startReport());
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
