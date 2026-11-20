import 'dart:convert';

import 'package:aldia_app/core/strings.dart';
import 'package:aldia_app/data/api_client.dart';
import 'package:aldia_app/data/report.dart';
import 'package:aldia_app/data/report_repository.dart';
import 'package:aldia_app/features/report/report_flow_controller.dart';
import 'package:aldia_app/features/report/report_result_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../support/fakes.dart';

void main() {
  for (final linked in [false, true]) {
    testWidgets(
      'rejected duplicates use ${linked ? 'linked report' : 'nearby suggestions'} and can be followed',
      (tester) async {
        const suggestedId = '22222222-2222-4222-8222-222222222222';
        final requests = <Uri>[];
        final client = MockClient((request) async {
          requests.add(request.url);
          final report = reportJson(id: suggestedId);
          return http.Response(
            jsonEncode(
              linked
                  ? report
                  : {
                      'items': [report],
                    },
            ),
            200,
          );
        });
        addTearDown(client.close);
        final repository = ReportRepository(
          api: ApiClient(client: client, baseUrl: 'http://api.test/api'),
          store: MemoryStore(),
        );
        addTearDown(repository.local.dispose);
        final controller =
            ReportFlowController(
                repository: repository,
                location: FakeLocation(null),
                photos: FakePhotos(),
              )
              ..categoryId = 'pothole'
              ..position = const LatLng(14, -90)
              ..submitState = SubmitState.done
              ..result = Report.fromJson({
                ...reportJson(
                  status: 'rejected',
                  checks: [
                    {
                      'name': 'duplicate',
                      'passed': false,
                      'detail': 'synthetic duplicate',
                    },
                  ],
                ),
                if (linked) 'duplicate_of': suggestedId,
              });
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          Provider<ReportRepository>.value(
            value: repository,
            child: MaterialApp(
              home: Scaffold(
                body: SingleChildScrollView(
                  child: ResultView(controller: controller),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(requests, hasLength(1));
        expect(
          requests.single.path,
          linked ? '/api/reports/$suggestedId' : '/api/reports/nearby',
        );
        final follow = find.text(S.followReport);
        await tester.ensureVisible(follow);
        await tester.tap(follow);
        await tester.pumpAndSettle();
        expect(controller.submitState, SubmitState.followed);
        expect(controller.result!.id, suggestedId);
        expect(repository.local.follows(suggestedId), isTrue);
      },
    );
  }
}
