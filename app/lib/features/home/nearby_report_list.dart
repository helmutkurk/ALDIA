import 'package:flutter/material.dart';

import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../data/report.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/report_tile.dart';
import 'bottom_navigation_reselect.dart';
import 'explore_query.dart';

/// Lista: the same reports as the map, for the same area and filters.
class ReportList extends StatelessWidget {
  const ReportList({super.key, required this.query, required this.onOpen});

  final ExploreQuery query;
  final void Function(Report) onOpen;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: query,
      builder: (context, _) {
        final state = query.state;
        if (state.loading) {
          return const Center(child: CircularProgressIndicator());
        }
        if (state.failed) {
          return EmptyState(
            icon: Icons.cloud_off,
            title: S.loadError,
            actionLabel: S.retry,
            onAction: query.retry,
          );
        }
        final reports = state.reports;
        final searching = query.filters.query.isNotEmpty;
        final filtered = query.filterCount > 0;
        if (reports.isEmpty && searching) {
          return const EmptyState(
            icon: Icons.search_off,
            title: 'Sin resultados para tu búsqueda',
            help: 'Prueba con otra palabra o quita la búsqueda.',
          );
        }
        if (reports.isEmpty) {
          return filtered
              ? EmptyState(
                  icon: Icons.filter_list_off,
                  title: S.emptyFiltered,
                  actionLabel: S.clearFilters,
                  onAction: () => query.setFilters(noFilters),
                )
              : const EmptyState(
                  icon: Icons.map_outlined,
                  title: S.emptyNearby,
                  help: S.emptyNearbyHelp,
                );
        }
        return RefreshIndicator(
          onRefresh: query.retry,
          child: ListView.separated(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            controller: BottomNavigationReselect.exploreListScrollController,
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
