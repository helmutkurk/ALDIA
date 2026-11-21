import 'package:flutter/material.dart';

import '../../core/strings.dart';
import '../../core/theme.dart';
import '../../data/report.dart';
import 'nearby_report_list.dart';
import 'report_map_view.dart';

/// Explorar: a full-screen map with floating controls, or the same reports as
/// a list under the same controls (wireframes A3–A7).
class ExploreReports extends StatefulWidget {
  const ExploreReports({
    super.key,
    required this.mapKey,
    required this.group,
    required this.category,
    required this.onOpen,
    required this.reports,
    required this.filterCount,
    required this.query,
    required this.onRetry,
    required this.onClear,
    required this.onBack,
    required this.onFilters,
  });
  final GlobalKey<MapViewState> mapKey;

  /// Contract `state_group` filter, or null for all.
  final String? group;
  final String? category;
  final void Function(Report) onOpen;
  final Future<List<Report>> reports;
  final int filterCount;
  final String query;
  final VoidCallback onRetry;
  final VoidCallback onClear;
  final VoidCallback onBack;
  final VoidCallback onFilters;

  @override
  State<ExploreReports> createState() => _ExploreReportsState();
}

class _ExploreReportsState extends State<ExploreReports> {
  var _list = false;

  Widget _controls({required bool floating}) => _ExploreControls(
    list: _list,
    floating: floating,
    filterCount: widget.filterCount,
    onBack: widget.onBack,
    onFilters: widget.onFilters,
    onMode: (list) => setState(() => _list = list),
  );

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top + AldiaSpace.m;
    final scheme = Theme.of(context).colorScheme;
    return IndexedStack(
      index: _list ? 1 : 0,
      children: [
        Stack(
          children: [
            Positioned.fill(
              child: MapView(
                key: widget.mapKey,
                state: widget.group,
                category: widget.category,
                onOpen: widget.onOpen,
                overlayTop: top + 52 + AldiaSpace.m,
              ),
            ),
            Positioned(
              top: top,
              left: AldiaSpace.l,
              right: AldiaSpace.l,
              child: _controls(floating: true),
            ),
          ],
        ),
        Column(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.surface,
                border: Border(
                  bottom: BorderSide(color: scheme.outlineVariant),
                ),
              ),
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  AldiaSpace.l,
                  top,
                  AldiaSpace.l,
                  AldiaSpace.m,
                ),
                child: _controls(floating: false),
              ),
            ),
            Expanded(
              child: ReportList(
                future: widget.reports,
                filtered: widget.filterCount > 0,
                query: widget.query,
                onOpen: widget.onOpen,
                onRetry: widget.onRetry,
                onClear: widget.onClear,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Back, the Mapa / Lista switch and the filter button with its count.
class _ExploreControls extends StatelessWidget {
  const _ExploreControls({
    required this.list,
    required this.floating,
    required this.filterCount,
    required this.onBack,
    required this.onFilters,
    required this.onMode,
  });
  final bool list;
  final bool floating;
  final int filterCount;
  final VoidCallback onBack;
  final VoidCallback onFilters;
  final ValueChanged<bool> onMode;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget round(Widget child, {Color? color}) => Material(
      color: color ?? scheme.surface,
      shape: const CircleBorder(),
      elevation: floating ? 3 : 0,
      shadowColor: Colors.black45,
      child: SizedBox.square(dimension: 52, child: Center(child: child)),
    );
    return Row(
      children: [
        round(
          IconButton(
            tooltip: S.backToHome,
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back),
          ),
        ),
        const SizedBox(width: AldiaSpace.s),
        Expanded(
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Material(
                color: scheme.surface,
                shape: StadiumBorder(
                  side: floating
                      ? BorderSide.none
                      : BorderSide(color: scheme.outlineVariant),
                ),
                elevation: floating ? 3 : 0,
                shadowColor: Colors.black45,
                child: Padding(
                  padding: const EdgeInsets.all(AldiaSpace.xs),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _Segment(
                        label: S.exploreMap,
                        selected: !list,
                        onTap: () => onMode(false),
                      ),
                      _Segment(
                        label: S.exploreList,
                        selected: list,
                        onTap: () => onMode(true),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: AldiaSpace.s),
        round(
          color: scheme.primary,
          IconButton(
            tooltip: S.filtersLabel,
            color: scheme.onPrimary,
            onPressed: onFilters,
            icon: Badge(
              isLabelVisible: filterCount > 0,
              backgroundColor: AldiaColors.accent,
              textColor: AldiaColors.onAccent,
              label: Text('$filterCount'),
              child: const Icon(Icons.tune),
            ),
          ),
        ),
      ],
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? scheme.primary : Colors.transparent,
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44, minWidth: 88),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AldiaSpace.l),
              child: Center(
                widthFactor: 1,
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: selected ? scheme.onPrimary : scheme.onSurface,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
