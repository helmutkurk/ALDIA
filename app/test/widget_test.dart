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

  testWidgets('the report button opens the six-step wizard on the photo step', (
    tester,
  ) async {
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

    // The step list is shown in order; the current step is also the heading.
    for (final title in [
      S.stepPhoto,
      S.stepLocation,
      S.stepCategory,
      S.stepDuplicates,
      S.stepNote,
      S.stepReview,
    ]) {
      expect(find.text(title), findsWidgets);
    }
    expect(find.text(S.stepProgress(1, 6)), findsOneWidget);
    expect(find.text(S.takePhoto), findsOneWidget);
  });
}
