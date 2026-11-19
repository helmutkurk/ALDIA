import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:provider/provider.dart';

import '../../core/config.dart';
import '../../core/strings.dart';
import '../../data/report.dart';
import '../../data/report_repository.dart';
import '../../widgets/report_tile.dart';
import '../../widgets/status_chips.dart';
import '../detail/report_detail_screen.dart';
import '../mine/my_reports_screen.dart';
import '../report/report_flow_screen.dart';

enum _View { map, list }

/// Nearby reports as a map or a list (SeeClickFix feed) with a report button.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  _View _view = _View.map;
  late Future<List<Report>> _future;

  @override
  void initState() {
    super.initState();
    _future = context.read<ReportRepository>().nearby();
  }

  void _reload() {
    setState(() => _future = context.read<ReportRepository>().nearby());
  }

  void _open(Report report) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReportDetailScreen(report: report),
      ),
    );
  }

  Future<void> _startReport() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const ReportFlowScreen()));
    if (mounted) _reload();
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
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const MyReportsScreen()),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
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
              onSelectionChanged: (s) => setState(() => _view = s.first),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Report>>(
              future: _future,
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
                        TextButton(
                          onPressed: _reload,
                          child: const Text(S.retry),
                        ),
                      ],
                    ),
                  );
                }
                final reports = snapshot.data!;
                return _view == _View.map
                    ? _MapView(reports: reports, onOpen: _open)
                    : _ListView(reports: reports, onOpen: _open);
              },
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

class _MapView extends StatelessWidget {
  const _MapView({required this.reports, required this.onOpen});

  final List<Report> reports;
  final void Function(Report) onOpen;

  @override
  Widget build(BuildContext context) {
    return FlutterMap(
      options: const MapOptions(
        initialCenter: AppConfig.defaultCenter,
        initialZoom: AppConfig.defaultZoom,
      ),
      children: [
        TileLayer(
          urlTemplate: AppConfig.tileUrl,
          tileProvider: context.read<TileProvider>(),
          userAgentPackageName: AppConfig.userAgentPackage,
        ),
        MarkerLayer(
          markers: [
            for (final report in reports)
              Marker(
                point: report.position,
                width: 40,
                height: 40,
                child: GestureDetector(
                  onTap: () => onOpen(report),
                  child: Icon(
                    Icons.location_pin,
                    size: 40,
                    color: statusColor(report.status),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _ListView extends StatelessWidget {
  const _ListView({required this.reports, required this.onOpen});

  final List<Report> reports;
  final void Function(Report) onOpen;

  @override
  Widget build(BuildContext context) {
    if (reports.isEmpty) return const Center(child: Text(S.emptyNearby));
    return ListView.builder(
      itemCount: reports.length,
      itemBuilder: (context, i) =>
          ReportTile(report: reports[i], onTap: () => onOpen(reports[i])),
    );
  }
}
