import 'package:aldia_app/core/strings.dart';
import 'package:aldia_app/data/report.dart';
import 'package:aldia_app/features/detail/report_detail_screen.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';
import '../widgets/harness.dart';

Map<String, dynamic> _detailJson() => stateJson(
  'en_revision',
  extra: {
    'events': [
      {
        'at': '2026-11-19T19:00:00Z',
        'actor_role': 'system',
        'to_state': 'nuevo',
        'public_note': null,
        'internal_note': 'secret-staff-text',
      },
      {
        'at': '2026-11-19T20:00:00Z',
        'actor_role': 'operator',
        'to_state': 'en_revision',
        'public_note': 'Cuadrilla asignada',
        'internal_note': 'secret-staff-text',
      },
    ],
  },
);

Report _stub() => Report.fromJson(stateJson('en_revision'));

void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('shows state chip, timeline with public notes only', (
    tester,
  ) async {
    _tall(tester);
    await tester.pumpWidget(
      harness(
        home: ReportDetailScreen(report: _stub()),
        repository: repositoryWith(byId: {detailId: _detailJson()}),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(S.timeline), findsOneWidget);
    expect(find.text('Cuadrilla asignada'), findsOneWidget);
    expect(find.textContaining('secret-staff-text'), findsNothing);
    expect(find.text('Recibido'), findsWidgets);
    expect(find.text('En revisión'), findsWidgets);
  });

  testWidgets('a duplicate links to the main report', (tester) async {
    _tall(tester);
    final json = stateJson('duplicado', extra: {'duplicate_of': mainId});
    await tester.pumpWidget(
      harness(
        home: ReportDetailScreen(report: Report.fromJson(json)),
        repository: repositoryWith(
          byId: {
            detailId: json,
            mainId: stateJson('nuevo', id: mainId),
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(S.duplicateOfTitle), findsOneWidget);
    await tester.tap(find.text(S.viewMainReport));
    await tester.pumpAndSettle();
    expect(find.text(mainId, findRichText: true), findsNothing);
    expect(find.textContaining(mainId), findsOneWidget);
  });

  testWidgets('nearby similar reports are hinted when not a duplicate', (
    tester,
  ) async {
    _tall(tester);
    await tester.pumpWidget(
      harness(
        home: ReportDetailScreen(report: _stub()),
        repository: repositoryWith(
          byId: {detailId: _detailJson()},
          nearby: [stateJson('nuevo', id: mainId)],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(S.nearbyHint), findsOneWidget);
  });

  testWidgets('a v0.1 response without state still renders', (tester) async {
    _tall(tester);
    final json = reportJson(id: detailId);
    await tester.pumpWidget(
      harness(
        home: ReportDetailScreen(report: Report.fromJson(json)),
        repository: repositoryWith(byId: {detailId: json}),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Recibido'), findsWidgets);
  });
}
