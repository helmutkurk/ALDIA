import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/report.dart';
import 'nearby_report_list.dart';
import 'report_map_view.dart';

class ExploreReports extends StatelessWidget {
  const ExploreReports({
    super.key,
    required this.mapKey,
    required this.state,
    required this.category,
    required this.onOpen,
    required this.reports,
    required this.filtered,
    required this.query,
    required this.onRetry,
    required this.onClear,
  });
  final GlobalKey<MapViewState> mapKey;
  final String? state;
  final String? category;
  final void Function(Report) onOpen;
  final Future<List<Report>> reports;
  final bool filtered;
  final String query;
  final VoidCallback onRetry;
  final VoidCallback onClear;
  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    animationDuration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 300),
    child: Column(
      children: [
        Material(
          color: AldiaColors.barOf(context),
          child: const TabBar(
            labelColor: AldiaColors.onBar,
            unselectedLabelColor: Color(0xFFD9DEE3),
            indicatorWeight: 4,
            tabs: [
              Tab(text: 'MAPA'),
              Tab(text: 'LISTA'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            physics: MediaQuery.disableAnimationsOf(context)
                ? const NeverScrollableScrollPhysics()
                : null,
            children: [
              MapView(
                key: mapKey,
                state: state,
                category: category,
                onOpen: onOpen,
              ),
              ReportList(
                future: reports,
                filtered: filtered,
                query: query,
                onOpen: onOpen,
                onRetry: onRetry,
                onClear: onClear,
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
