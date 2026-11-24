import 'dart:async';

import 'package:aldia_app/core/strings.dart';
import 'package:aldia_app/core/theme.dart';
import 'package:aldia_app/data/report_repository.dart';
import 'package:aldia_app/features/drafts/draft_record.dart';
import 'package:aldia_app/features/drafts/draft_store.dart';
import 'package:aldia_app/features/report/report_flow_screen.dart';
import 'package:aldia_app/services/geocoder_service.dart';
import 'package:aldia_app/services/location_service.dart';
import 'package:aldia_app/services/photo_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../support/fakes.dart';
import '../support/memory_draft_store.dart';
import '../support/offline_tiles.dart';

class _PendingReadStore extends MemoryDraftStore {
  final Completer<CapturedPhoto?> read = Completer<CapturedPhoto?>();
  int saves = 0;

  @override
  Future<CapturedPhoto?> readPhoto(DraftRecord draft) => read.future;

  @override
  Future<void> save(DraftRecord draft) async {
    saves++;
    await super.save(draft);
  }
}

Widget host(
  ReportRepository repository, {
  double textScale = 1,
  GeocoderService? geocoder,
  DraftStore? drafts,
  DraftRecord? draft,
  ThemeData? theme,
  bool disableAnimations = false,
}) => MultiProvider(
  providers: [
    Provider<ReportRepository>.value(value: repository),
    Provider<LocationService>.value(
      value: FakeLocation(const LatLng(14.61, -90.52)),
    ),
    Provider<PhotoService>.value(value: FakePhotos()),
    Provider<DraftStore?>.value(value: drafts),
    Provider<GeocoderService?>.value(value: geocoder ?? FakeGeocoder()),
    Provider<TileProvider>.value(value: OfflineTileProvider()),
  ],
  child: MaterialApp(
    theme: theme,
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          disableAnimations: disableAnimations,
        ),
        child: ReportFlowScreen(draft: draft),
      ),
    ),
  ),
);

/// The wizard is a lazy list and the map would swallow drags, so scroll the
/// page through its controller until the text is built, then bring it on screen.
Future<void> reveal(WidgetTester tester, String text) async {
  final finder = find.text(text);
  final position = tester
      .state<ScrollableState>(find.byType(Scrollable).first)
      .position;
  position.jumpTo(0);
  await tester.pump();
  for (var i = 0; i < 40 && finder.evaluate().isEmpty; i++) {
    position.jumpTo(position.pixels + 200);
    await tester.pump();
  }
  expect(finder, findsOneWidget);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

Future<void> tapText(WidgetTester tester, String text) async {
  await reveal(tester, text);
  await tester.tap(find.text(text));
  await tester.pumpAndSettle();
}

Future<void> advanceToPhoto(WidgetTester tester) async {
  await tapText(tester, S.useMyLocation);
  await tapText(tester, S.confirmLocation);
  await tapText(tester, 'Bache');
  await tapText(tester, S.next);
}

Future<void> advanceToReview(WidgetTester tester) async {
  await advanceToPhoto(tester);
  await tapText(tester, S.takePhoto);
  await tapText(tester, S.usePhoto);
  await tapText(tester, S.next);
}

void main() {
  testWidgets(
    'address search is explicit, debounced and selecting a fake result updates the summary',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final geocoder = FakeGeocoder()
        ..results = const [
          AddressResult(
            label: 'Zona 1, Ciudad de Guatemala',
            position: LatLng(14.64, -90.51),
          ),
        ];
      await tester.pumpWidget(host(fakeRepository(), geocoder: geocoder));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Zona 1');
      await tester.pump(const Duration(seconds: 1));
      expect(geocoder.queries, isEmpty);
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump(const Duration(milliseconds: 449));
      expect(geocoder.queries, isEmpty);
      await tester.pump(const Duration(milliseconds: 2));
      await tester.pumpAndSettle();
      expect(geocoder.queries, ['Zona 1']);
      await tapText(tester, 'Zona 1, Ciudad de Guatemala');
      await tapText(tester, S.confirmLocation);
      expect(find.text('Zona 1, Ciudad de Guatemala'), findsOneWidget);
      expect(find.text(S.chooseCategory), findsOneWidget);
    },
  );

  testWidgets('wizard works at text scale 2.0 in light and dark themes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    for (final theme in [buildTheme(), buildDarkTheme()]) {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        host(fakeRepository(), textScale: 2, theme: theme),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .getSize(find.widgetWithText(FilledButton, S.confirmLocation).first)
            .height,
        greaterThanOrEqualTo(48),
      );

      await tapText(tester, S.useMyLocation);
      await tapText(tester, S.confirmLocation);
      final nextForward = find.widgetWithText(FilledButton, S.next);
      final nextBack = find.widgetWithText(TextButton, S.back);
      expect(nextForward, findsOneWidget);
      expect(nextBack, findsOneWidget);
      expect(tester.getSize(nextForward).height, greaterThanOrEqualTo(48));
      expect(tester.getSize(nextBack).height, greaterThanOrEqualTo(48));
      expect(
        tester.getTopLeft(nextForward).dy,
        lessThan(tester.getTopLeft(nextBack).dy),
      );
      await tapText(tester, 'Bache');
      await tapText(tester, S.next);
      final photoForward = find.widgetWithText(FilledButton, S.usePhoto);
      final photoBack = find.widgetWithText(TextButton, S.back);
      expect(photoForward, findsOneWidget);
      expect(photoBack, findsOneWidget);
      expect(tester.getSize(photoForward).height, greaterThanOrEqualTo(48));
      expect(tester.getSize(photoBack).height, greaterThanOrEqualTo(48));
      expect(
        tester.getTopLeft(photoForward).dy,
        lessThan(tester.getTopLeft(photoBack).dy),
      );
      expect(
        tester.getSize(find.widgetWithText(FilledButton, S.takePhoto)).height,
        greaterThanOrEqualTo(48),
      );
      await tapText(tester, S.takePhoto);
      await tapText(tester, S.usePhoto);
      expect(find.widgetWithText(FilledButton, S.next), findsOneWidget);
      expect(find.widgetWithText(TextButton, S.back), findsOneWidget);
      await tapText(tester, S.next);
      expect(find.widgetWithText(FilledButton, S.send), findsOneWidget);
      expect(find.widgetWithText(TextButton, S.back), findsOneWidget);
      await tester.scrollUntilVisible(
        find.textContaining('KB'),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.textContaining('KB'), findsOneWidget);
      for (final label in [
        '${S.edit}: ${S.stepLocation}',
        '${S.edit}: ${S.stepCategory}',
        '${S.edit}: ${S.stepNote}',
      ]) {
        final edit = find.text(label);
        await tester.ensureVisible(edit);
        final button = find.ancestor(
          of: edit,
          matching: find.byType(TextButton),
        );
        expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
      }
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('tap targets are at least 48 dp tall on the photo step', (
    tester,
  ) async {
    await tester.pumpWidget(host(fakeRepository()));
    await tester.pumpAndSettle();
    await advanceToPhoto(tester);
    final size = tester.getSize(find.widgetWithText(FilledButton, S.takePhoto));
    expect(size.height, greaterThanOrEqualTo(48));
    expect(
      tester.getSize(find.widgetWithText(FilledButton, S.usePhoto)).height,
      greaterThanOrEqualTo(48),
    );
  });

  testWidgets('the step heading is a header for screen readers', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(host(fakeRepository()));
    await tester.pumpAndSettle();
    expect(
      tester.getSemantics(find.text(S.stepLocation).last),
      isSemantics(label: S.stepLocation, isHeader: true, isFocused: true),
    );
    handle.dispose();
  });

  testWidgets(
    'draft restoration blocks editing until the photo read finishes',
    (tester) async {
      final store = _PendingReadStore();
      final draft = DraftRecord(
        id: 'draft-id',
        step: 'location',
        position: const LatLng(12, 13),
        placeLabel: 'Lugar recuperado',
        locationConfirmed: true,
        createdAt: DateTime.utc(2026),
      );
      await tester.pumpWidget(
        host(fakeRepository(), drafts: store, draft: draft),
      );
      await tester.pump();
      expect(find.text('Recuperando borrador…'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Lugar recuperado'), findsNothing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(store.saves, 0);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      store.read.complete(null);
      await tester.pumpAndSettle();
      expect(find.text('Lugar recuperado'), findsOneWidget);
    },
  );

  testWidgets(
    'a rejected result explains each failed check and offers the fixes',
    (tester) async {
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        host(
          fakeRepository(
            createdStatus: 'rejected',
            createdChecks: [
              {'name': 'freshness', 'passed': false, 'detail': 'old'},
              {'name': 'category', 'passed': false, 'detail': 'no'},
              {'name': 'place', 'passed': true, 'detail': 'ok'},
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      await advanceToReview(tester);
      await tapText(tester, S.send);

      expect(find.textContaining('(prueba)'), findsWidgets);
      expect(find.text(S.freshnessReason), findsOneWidget);
      expect(find.text(S.freshnessFix), findsOneWidget);
      expect(find.text(S.categoryReason('Bache')), findsOneWidget);
      expect(find.text(S.categoryFix), findsOneWidget);
      expect(find.text(S.placeReason), findsNothing);
      expect(find.text(S.retakePhoto), findsOneWidget);
      expect(find.text(S.changeCategory), findsOneWidget);
      // Easiest fix first: category before freshness.
      expect(
        tester.getTopLeft(find.text(S.categoryReason('Bache'))).dy,
        lessThan(tester.getTopLeft(find.text(S.freshnessReason)).dy),
      );
      // Fewer than three attempts: no manual review yet.
      expect(find.text(S.manualReview), findsNothing);

      await tapText(tester, S.retakePhoto);
      expect(find.text(S.takePhoto), findsOneWidget);
    },
  );

  testWidgets(
    'a pending result is explained as saved and awaiting verification',
    (tester) async {
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(host(fakeRepository(createdStatus: 'pending')));
      await tester.pumpAndSettle();
      await advanceToReview(tester);
      await tapText(tester, S.send);
      expect(find.text(S.pendingHelp), findsOneWidget);
    },
  );

  testWidgets('the location step shows the address, never coordinates', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(fakeRepository()));
    await tester.pumpAndSettle();
    await tapText(tester, S.useMyLocation);
    expect(find.text('6a. Avenida, Zona 1, Guatemala'), findsWidgets);
    expect(find.byType(TextField), findsOneWidget); // address search only
    expect(find.textContaining(RegExp(r'-?\d+\.\d{3,}')), findsNothing);
  });
}
