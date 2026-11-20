import 'dart:async';
import 'dart:convert';

import 'package:aldia_app/data/api_client.dart';
import 'package:aldia_app/core/strings.dart';
import 'package:aldia_app/core/theme.dart';
import 'package:aldia_app/data/report.dart';
import 'package:aldia_app/data/report_repository.dart';
import 'package:aldia_app/features/drafts/draft_record.dart';
import 'package:aldia_app/features/home/home_screen.dart';
import 'package:aldia_app/features/home/report_map_view.dart';
import 'package:aldia_app/widgets/neutral_map_pin.dart';
import 'package:aldia_app/widgets/report_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';

import '../support/memory_draft_store.dart';
import '../support/fakes.dart';
import '../widgets/harness.dart';

const _cluster = ReportCluster(position: LatLng(14.63, -90.5), count: 7);

ReportRepository _controlledRepository(
  Future<http.Response> Function(http.BaseRequest) handler,
) => ReportRepository(
  api: ApiClient(client: MockClient(handler), baseUrl: 'http://api.test/api'),
  store: MemoryStore(),
);

http.Response _ok(Object body) => http.Response(jsonEncode(body), 200);

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
    expect(find.text(S.navMap), findsOneWidget);
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
    'falls back to pins with icon and state text, keyboard opens summary',
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

      final semanticPin = find.bySemanticsLabel('Bache. En revisión');
      expect(semanticPin, findsOneWidget);
      final pinButton = find.descendant(
        of: semanticPin,
        matching: find.byType(TextButton),
      );
      expect(pinButton, findsOneWidget);
      expect(tester.getRect(pinButton).width, greaterThanOrEqualTo(48));
      expect(tester.getRect(pinButton).height, greaterThanOrEqualTo(48));
      expect(tester.widget<TextButton>(pinButton).onPressed, isNotNull);
      expect(
        tester
            .getSemantics(semanticPin)
            .getSemanticsData()
            .hasAction(SemanticsAction.tap),
        isTrue,
      );
      final pinContent = find.descendant(
        of: pinButton,
        matching: find.byType(Column),
      );
      Focus.of(tester.element(pinContent), scopeOk: true).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
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
    await tester.tap(find.text(S.navList));
    await tester.pumpAndSettle();
    expect(find.textContaining('Programado'), findsOneWidget);
  });

  testWidgets('map failures can retry and keep previously loaded pins', (
    tester,
  ) async {
    var mapCalls = 0;
    final repository = _controlledRepository((request) async {
      if (request.url.path.endsWith('/stats')) {
        return _ok({'by_resolution': {}});
      }
      if (request.url.path.endsWith('/reports') &&
          request.url.queryParameters.containsKey('bbox')) {
        mapCalls++;
        return switch (mapCalls) {
          1 => http.Response('{}', 503),
          2 => _ok({'items': []}),
          3 => _ok({
            'items': [stateJson('nuevo')],
          }),
          _ => http.Response('{}', 503),
        };
      }
      if (request.url.path.endsWith('/reports')) {
        return _ok({'items': [], 'total': 0});
      }
      return _ok([]);
    });
    await tester.pumpWidget(
      harness(
        home: const HomeScreen(),
        repository: repository,
        clusters: FakeClusters(const [], fail: true),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Explorar mi ciudad'));
    await tester.pumpAndSettle();

    expect(find.text('No se pudieron cargar los reportes.'), findsOneWidget);
    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();
    expect(find.text('No hay reportes en esta zona.'), findsOneWidget);

    Future<void> update() async {
      await tester.tap(find.byTooltip('Más opciones'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Actualizar'));
      await tester.pumpAndSettle();
    }

    await update();
    expect(find.byType(StatusMapPin), findsOneWidget);
    await update();
    expect(find.byType(StatusMapPin), findsOneWidget);
    expect(
      find.text(
        'No se pudieron actualizar los reportes. Se muestran los últimos datos disponibles.',
      ),
      findsOneWidget,
    );
    expect(find.text('No hay reportes en esta zona.'), findsNothing);
  });

  testWidgets('Actualizar waits for the list and refreshes the map', (
    tester,
  ) async {
    final listRefresh = Completer<http.Response>();
    var listCalls = 0;
    var mapCalls = 0;
    final repository = _controlledRepository((request) async {
      final path = request.url.path;
      if (path.endsWith('/stats')) return _ok({'by_resolution': {}});
      if (path.endsWith('/reports') &&
          request.url.queryParameters.containsKey('bbox')) {
        mapCalls++;
        return _ok({'items': []});
      }
      if (path.endsWith('/reports')) {
        listCalls++;
        if (listCalls == 2) return listRefresh.future;
        return _ok({
          'items': [stateJson('en_revision')],
          'total': 1,
        });
      }
      return _ok([]);
    });
    await tester.pumpWidget(
      harness(
        home: const HomeScreen(),
        repository: repository,
        clusters: FakeClusters(const [], fail: true),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Explorar mi ciudad'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(S.navList));
    await tester.pumpAndSettle();
    expect(find.byType(ReportTile), findsOneWidget);

    await tester.tap(find.byTooltip('Más opciones'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Actualizar'));
    await tester.pump();

    expect(listCalls, 2);
    expect(mapCalls, 2);
    expect(find.byType(ReportTile), findsOneWidget);
    expect(find.byKey(const ValueKey('list-refresh-progress')), findsOneWidget);

    listRefresh.complete(
      _ok({
        'items': [stateJson('en_revision')],
        'total': 1,
      }),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('list-refresh-progress')), findsNothing);
  });

  testWidgets('search selects the list and leaving the list clears it', (
    tester,
  ) async {
    final repository = _controlledRepository((request) async {
      if (request.url.path.endsWith('/stats')) {
        return _ok({'by_resolution': {}});
      }
      if (request.url.path.endsWith('/reports/nearby')) {
        return _ok({'items': []});
      }
      if (request.url.path.endsWith('/reports')) {
        return _ok({
          'items': [stateJson('resuelto'), stateJson('nuevo', id: mainId)],
          'total': 2,
        });
      }
      return _ok([]);
    });
    await tester.pumpWidget(
      harness(
        home: const HomeScreen(),
        repository: repository,
        clusters: FakeClusters([_cluster]),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Explorar mi ciudad'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Buscar en la lista'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'resuelto');
    await tester.pumpAndSettle();
    expect(find.byType(ReportTile), findsOneWidget);

    await tester.tap(find.text(S.navMap));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Buscar en la lista'), findsOneWidget);
    await tester.tap(find.text(S.navList));
    await tester.pumpAndSettle();
    expect(find.byType(ReportTile), findsNWidgets(2));
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
