import 'package:aldia_app/core/strings.dart';
import 'package:aldia_app/data/report.dart';
import 'package:aldia_app/features/drafts/draft_record.dart';
import 'package:aldia_app/features/home/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import '../support/memory_draft_store.dart';
import '../widgets/harness.dart';

const _cluster = ReportCluster(position: LatLng(14.63, -90.5), count: 7);

void main() {
  testWidgets('map shows clusters from the clusters endpoint', (tester) async {
    final clusters = FakeClusters([_cluster]);
    await tester.pumpWidget(
      harness(
        home: const HomeScreen(),
        repository: repositoryWith(),
        clusters: clusters,
      ),
    );
    await tester.pumpAndSettle();

    expect(clusters.calls, greaterThan(0));
    expect(find.text('7'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('7 reportes')), findsOneWidget);
  });

  testWidgets(
    'falls back to pins with icon and state text, tap opens summary',
    (tester) async {
      await tester.pumpWidget(
        harness(
          home: const HomeScreen(),
          repository: repositoryWith(list: [stateJson('en_revision')]),
          clusters: FakeClusters(const [], fail: true),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(S.mapFallback), findsOneWidget);
      expect(find.text('En revisión'), findsOneWidget);
      expect(find.byIcon(Icons.manage_search), findsOneWidget);

      await tester.tap(find.text('En revisión'));
      await tester.pumpAndSettle();
      expect(find.text(S.viewDetail), findsOneWidget);
      expect(find.text('Bache'), findsOneWidget);
    },
  );

  testWidgets('a filter skips clusters and sends state and category', (
    tester,
  ) async {
    final requests = <Uri>[];
    final clusters = FakeClusters([_cluster]);
    await tester.pumpWidget(
      harness(
        home: const HomeScreen(),
        repository: repositoryWith(
          list: [stateJson('resuelto')],
          requests: requests,
        ),
        clusters: clusters,
      ),
    );
    await tester.pumpAndSettle();
    final before = clusters.calls;

    await tester.tap(find.text(S.filtersLabel));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String?>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Resuelto').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text(S.apply));
    await tester.pumpAndSettle();

    expect(clusters.calls, before);
    expect(
      requests.where((u) => u.queryParameters['state'] == 'resuelto'),
      isNotEmpty,
    );
    expect(find.text('Resuelto'), findsWidgets);
  });

  testWidgets('list alternative shows reports and the empty state', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(
        home: const HomeScreen(),
        repository: repositoryWith(list: [stateJson('programado')]),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(S.navList));
    await tester.pumpAndSettle();
    expect(find.textContaining('Programado'), findsOneWidget);
  });

  testWidgets('shows a continue-draft banner that opens the flow', (
    tester,
  ) async {
    final drafts = MemoryDraftStore();
    await drafts.save(
      DraftRecord(
        id: 'd1',
        step: 'category',
        position: const LatLng(14.6, -90.5),
        createdAt: DateTime.now().toUtc(),
        categoryId: 'pothole',
      ),
    );
    await tester.pumpWidget(
      harness(
        home: const HomeScreen(),
        repository: repositoryWith(),
        drafts: drafts,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(S.continueDraft), findsOneWidget);
    expect(find.textContaining('Bache'), findsOneWidget);
  });
}
