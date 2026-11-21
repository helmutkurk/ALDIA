import 'package:flutter/material.dart';

import '../../core/categories.dart';
import '../../core/citizen_states.dart';
import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../data/report.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/report_tile.dart';
import 'bottom_navigation_reselect.dart';

class ReportList extends StatelessWidget {
  const ReportList({
    super.key,
    required this.future,
    required this.filtered,
    required this.query,
    required this.onOpen,
    required this.onRetry,
    required this.onClear,
  });

  final Future<List<Report>> future;
  final bool filtered;
  final String query;
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
        final all = snapshot.data!;
        final needle = query.toLowerCase();
        final reports = needle.isEmpty
            ? all
            : [
                for (final r in all)
                  if ([
                    categoryById(r.category).label,
                    citizenStateFor(r.citizenState).label,
                    r.note ?? '',
                  ].any((t) => t.toLowerCase().contains(needle)))
                    r,
              ];
        if (reports.isEmpty && needle.isNotEmpty) {
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
