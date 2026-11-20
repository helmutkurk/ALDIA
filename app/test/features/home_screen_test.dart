import 'package:aldia_app/core/strings.dart';
import 'package:aldia_app/core/theme.dart';
import 'package:aldia_app/data/report.dart';
import 'package:aldia_app/features/drafts/draft_record.dart';
import 'package:aldia_app/features/home/home_screen.dart';
import 'package:aldia_app/features/home/report_map_view.dart';
import 'package:aldia_app/widgets/neutral_map_pin.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import '../support/memory_draft_store.dart';
import '../widgets/harness.dart';

const _cluster = ReportCluster(position: LatLng(14.63, -90.5), count: 7);

void main() {
  testWidgets('extracted map keeps its state across shell destinations', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(
        home: const HomeScreen(),
        repository: repositoryWith(),
        clusters: FakeClusters([_cluster]),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Explorar mi ciudad'));
    await tester.pumpAndSettle();
    final map = tester.state(find.byType(MapView));
    await tester.tap(find.text('Perfil'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Inicio'));
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(MapView)), same(map));
    expect(find.text('MAPA'), findsOneWidget);
  });

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

    await tester.tap(find.text('Explorar mi ciudad'));
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
          repository: repositoryWith(
            list: [
              stateJson('en_revision'),
              stateJson('resuelto', id: mainId, extra: {'longitude': -90.45}),
            ],
          ),
          clusters: FakeClusters(const [], fail: true),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Explorar mi ciudad'));
      await tester.pumpAndSettle();
      expect(find.text(S.mapFallback), findsOneWidget);
      expect(find.text('En revisión'), findsOneWidget);
      expect(find.byType(StatusMapPin), findsNWidgets(2));
      // Pin fill follows the state (orange open, blue resolved), white outline.
      final fills = <Color?>[];
      for (final pin in tester.widgetList<StatusMapPin>(
        find.byType(StatusMapPin),
      )) {
        final outer = tester.widget<Container>(
          find
              .descendant(
                of: find.byWidget(pin),
                matching: find.byType(Container),
              )
              .first,
        );
        final decoration = outer.decoration! as BoxDecoration;
        fills.add(decoration.color);
        expect(decoration.border, Border.all(color: Colors.white, width: 3));
      }
      expect(fills, [AldiaColors.open, AldiaColors.resolved]);

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
    await tester.tap(find.text('Explorar mi ciudad'));
    await tester.pumpAndSettle();
    final before = clusters.calls;

    await tester.tap(find.byTooltip(S.filtersLabel));
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
    await tester.tap(find.text('Explorar mi ciudad'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('LISTA'));
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
