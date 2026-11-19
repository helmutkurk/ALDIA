import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/strings.dart';
import '../../data/report.dart';
import '../../data/report_repository.dart';
import '../../widgets/report_tile.dart';
import '../detail/report_detail_screen.dart';

class MyReportsScreen extends StatefulWidget {
  const MyReportsScreen({super.key});

  @override
  State<MyReportsScreen> createState() => _MyReportsScreenState();
}

class _MyReportsScreenState extends State<MyReportsScreen> {
  late Future<List<Report>> _future;

  @override
  void initState() {
    super.initState();
    _future = context.read<ReportRepository>().mine();
  }

  void _reload() {
    setState(() => _future = context.read<ReportRepository>().mine());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(S.myReports)),
      body: FutureBuilder<List<Report>>(
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
                  TextButton(onPressed: _reload, child: const Text(S.retry)),
                ],
              ),
            );
          }
          final reports = snapshot.data!;
          if (reports.isEmpty) return const Center(child: Text(S.emptyMine));
          return ListView.builder(
            itemCount: reports.length,
            itemBuilder: (context, i) => ReportTile(
              report: reports[i],
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ReportDetailScreen(report: reports[i]),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
