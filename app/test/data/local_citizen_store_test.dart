import 'dart:convert';

import 'package:aldia_app/data/api_client.dart';
import 'package:aldia_app/data/report_repository.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../support/fakes.dart';

import 'package:aldia_app/data/local_citizen_store.dart';
import 'package:aldia_app/data/report.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../widgets/harness.dart';

void main() {
  test('following subscribes the local inbox; unfollowing keeps authored reports separate', () async {
    var state = 'nuevo';
    final authored = MemoryStore();
    final repository = ReportRepository(
      api: ApiClient(
        client: MockClient(
          (request) async => http.Response(jsonEncode(stateJson(state)), 200),
        ),
        baseUrl: 'http://api.test/api',
      ),
      store: authored,
    );
    final report = Report.fromJson(stateJson(state));
    await repository.follow(report);
    expect(authored.saved, isEmpty);
    state = 'en_proceso';
    expect(await repository.mine(), hasLength(1));
    expect(repository.local.notices.single.state, 'en_proceso');
    await repository.local.setFollow(report.id, false);
    expect(await repository.mine(), isEmpty);
    await authored.add(report.id);
    expect(await repository.mine(), hasLength(1));
  });

  test('state baseline is quiet; one changed state survives restart with local follows', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = LocalCitizenStore(preferences: prefs);
    final open = Report.fromJson(stateJson('nuevo'));
    final fixed = Report.fromJson(stateJson('resuelto'));
    await store.observe([open]);
    expect(store.notices, isEmpty);
    await store.setFollow(open.id, true);
    await store.observe([fixed]);
    await store.observe([fixed]);
    final restored = LocalCitizenStore(preferences: prefs);
    expect(restored.notices.single.state, 'resuelto');
    expect(restored.follows(open.id), isTrue);
    await restored.clear();
    final cleared = LocalCitizenStore(preferences: prefs);
    expect(cleared.notices, isEmpty);
    expect(cleared.follows(open.id), isFalse);
  });
}
