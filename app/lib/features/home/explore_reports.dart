import 'package:flutter/material.dart';

import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../data/report.dart';
import 'nearby_report_list.dart';
import 'report_map_view.dart';

class ExploreReports extends StatefulWidget {
  const ExploreReports({
    super.key,
    required this.mapKey,
    required this.state,
    required this.category,
    required this.onOpen,
    required this.reports,
    required this.filtered,
    required this.query,
    required this.isSearching,
    required this.onRetry,
    required this.onClear,
    required this.onMapSelected,
  });

  final GlobalKey<MapViewState> mapKey;
  final String? state;
  final String? category;
  final void Function(Report) onOpen;
  final Future<List<Report>> reports;
  final bool filtered;
  final String query;
  final bool isSearching;
  final Future<void> Function() onRetry;
  final VoidCallback onClear;
  final VoidCallback onMapSelected;

  @override
  State<ExploreReports> createState() => _ExploreReportsState();
}

class _ExploreReportsState extends State<ExploreReports>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  var _hasTabs = false;
  var _reportedMapSelection = false;
  var _disableAnimations = false;

  @override
  void didUpdateWidget(ExploreReports oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((!oldWidget.isSearching && widget.isSearching) ||
        (oldWidget.query != widget.query && widget.query.isNotEmpty)) {
      _selectList();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    if (!_hasTabs || disableAnimations != _disableAnimations) {
      final index = _hasTabs ? _tabs.index : 0;
      if (_hasTabs) {
        _tabs
          ..removeListener(_selectionChanged)
          ..dispose();
      }
      _disableAnimations = disableAnimations;
      _tabs = TabController(
        length: 2,
        initialIndex: index,
        vsync: this,
        animationDuration: _disableAnimations
            ? Duration.zero
            : const Duration(milliseconds: 220),
      )..addListener(_selectionChanged);
      _hasTabs = true;
    }
  }

  void _selectList() => _tabs.animateTo(
    1,
    duration: _disableAnimations
        ? Duration.zero
        : const Duration(milliseconds: 220),
    curve: const Cubic(0.23, 1, 0.32, 1),
  );

  void _selectionChanged() {
    if (_tabs.index != 0) {
      _reportedMapSelection = false;
      return;
    }
    if (!widget.isSearching || _reportedMapSelection) return;
    _reportedMapSelection = true;
    widget.onMapSelected();
  }

  @override
  void dispose() {
    if (_hasTabs) {
      _tabs
        ..removeListener(_selectionChanged)
        ..dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Material(
        color: AldiaColors.barOf(context),
        child: TabBar(
          controller: _tabs,
          labelColor: AldiaColors.onBar,
          unselectedLabelColor: const Color(0xFFD9DEE3),
          indicatorWeight: 3,
          indicatorSize: TabBarIndicatorSize.tab,
          tabs: const [
            Tab(text: S.navMap),
            Tab(text: S.navList),
          ],
        ),
      ),
      Expanded(
        child: TabBarView(
          controller: _tabs,
          physics: MediaQuery.disableAnimationsOf(context)
              ? const NeverScrollableScrollPhysics()
              : null,
          children: [
            MapView(
              key: widget.mapKey,
              state: widget.state,
              category: widget.category,
              onOpen: widget.onOpen,
            ),
            ReportList(
              future: widget.reports,
              filtered: widget.filtered,
              query: widget.query,
              onOpen: widget.onOpen,
              onRetry: widget.onRetry,
              onClear: widget.onClear,
            ),
          ],
        ),
      ),
    ],
  );
}
