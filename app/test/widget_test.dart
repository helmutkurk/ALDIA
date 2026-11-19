import 'package:aldia_app/app.dart';
import 'package:aldia_app/core/strings.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'support/fakes.dart';
import 'support/offline_tiles.dart';

void main() {
  testWidgets('home shows the app name, the report button and the list view', (
    tester,
  ) async {
    await tester.pumpWidget(
      AldiaApp(
        repository: fakeRepository(),
        location: FakeLocation(const LatLng(14.6, -90.5)),
        photos: FakePhotos(),
        tileProvider: OfflineTileProvider(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(S.appName), findsOneWidget);
    expect(find.text(S.newReport), findsOneWidget);

    await tester.tap(find.text(S.navList));
    await tester.pumpAndSettle();
    expect(find.text('Bache'), findsOneWidget);
  });

  testWidgets('the report button opens the four-step flow', (tester) async {
    // The Stepper builds steps lazily; use a tall screen so all titles exist.
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      AldiaApp(
        repository: fakeRepository(),
        location: FakeLocation(const LatLng(14.6, -90.5)),
        photos: FakePhotos(),
        tileProvider: OfflineTileProvider(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(S.newReport));
    await tester.pumpAndSettle();

    expect(find.text(S.stepLocation), findsOneWidget);
    expect(find.text(S.stepCategory), findsOneWidget);
    expect(find.text(S.stepPhoto), findsOneWidget);
    expect(find.text(S.stepNote), findsOneWidget);
  });
}
