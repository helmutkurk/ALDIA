import 'package:aldia_app/app.dart';
import 'package:aldia_app/features/citizen/login_sheet.dart';
import 'package:aldia_app/features/citizen/citizen_screens.dart';
import 'package:aldia_app/services/test_account.dart';
import 'package:aldia_app/core/strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import '../../support/fake_auth.dart';
import '../../support/fakes.dart';
import '../../support/offline_tiles.dart';
import '../../widgets/harness.dart';
import '../report_flow_screen_test.dart' show advanceToReview, tapText, host;

Future<void> fillPhone(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const Key('citizen-phone')),
    List.filled(8, '2').join(),
  );
  await tester.tap(find.text('Solicitar código'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('phone validation, expired code, resend cooldown and success', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final auth = FakeCitizenAuth();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showCitizenLogin(context, auth),
              child: const Text('Abrir'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Solicitar código'));
    await tester.pumpAndSettle();
    expect(find.textContaining('8 dígitos de tu número'), findsOneWidget);
    expect(auth.requests, 0);
    await fillPhone(tester);
    expect(auth.requests, 1);
    expect(find.textContaining('Reenviar en'), findsOneWidget);
    final resend = find.widgetWithText(TextButton, 'Reenviar en 60 s');
    expect(tester.widget<TextButton>(resend).onPressed, isNull);
    await tester.enterText(
      find.byKey(const Key('citizen-code')),
      List.filled(6, '1').join(),
    );
    auth.verifyError =
        'El código no es válido o venció. Revísalo o solicita uno nuevo.';
    await tester.tap(find.text('Verificar número'));
    await tester.pumpAndSettle();
    expect(find.textContaining('venció'), findsOneWidget);
    expect(auth.isSignedIn, isFalse);
    await tester.pump(const Duration(seconds: 60));
    await tester.tap(find.text('Reenviar código'));
    await tester.pumpAndSettle();
    expect(auth.requests, 2);
    auth.verifyError = null;
    await tester.enterText(
      find.byKey(const Key('citizen-code')),
      List.filled(6, '1').join(),
    );
    await tester.tap(find.text('Verificar número'));
    await tester.pumpAndSettle();
    expect(auth.isSignedIn, isTrue);
    expect(find.byType(CitizenLoginSheet), findsNothing);
  });

  testWidgets('offline request keeps phone entry available with clear error', (
    tester,
  ) async {
    final auth = FakeCitizenAuth()
      ..requestError =
          'No hay conexión. Revisa tu internet e inténtalo de nuevo.';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: CitizenLoginSheet(auth: auth)),
      ),
    );
    await fillPhone(tester);
    expect(find.textContaining('No hay conexión'), findsOneWidget);
    expect(find.byKey(const Key('citizen-code')), findsNothing);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
  });

  testWidgets(
    'required login shows the login screen first and opens home once verified',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final auth = FakeCitizenAuth();
      await tester.pumpWidget(
        AldiaApp(
          repository: repositoryWith(auth: auth, requireCitizenLogin: true),
          location: FakeLocation(const LatLng(14.6, -90.5)),
          photos: FakePhotos(),
          tileProvider: OfflineTileProvider(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(CitizenLoginScreen), findsOneWidget);
      expect(find.text('Entra a Aldia'), findsOneWidget);
      expect(find.text('Cerrar'), findsNothing);
      expect(find.text(S.newReport), findsNothing);

      await fillPhone(tester);
      await tester.enterText(
        find.byKey(const Key('citizen-code')),
        List.filled(6, '1').join(),
      );
      await tester.tap(find.text('Verificar número'));
      await tester.pumpAndSettle();
      expect(auth.isSignedIn, isTrue);
      expect(find.byType(CitizenLoginScreen), findsNothing);
      expect(find.text(S.newReport), findsOneWidget);
    },
  );

  testWidgets('the MVP test account enters, sends and logs out', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final saved = <bool>[];
    final testAccount = TestAccountSession(
      onChanged: (active) async => saved.add(active),
    );
    final posts = <dynamic>[];
    final repository = repositoryWith(
      requireCitizenLogin: true,
      testAccount: testAccount,
      onPost: () => posts.add(true),
    );
    await tester.pumpWidget(
      AldiaApp(
        repository: repository,
        location: FakeLocation(const LatLng(14.6, -90.5)),
        photos: FakePhotos(),
        tileProvider: OfflineTileProvider(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Entrar con cuenta de prueba'));
    await tester.pumpAndSettle();
    expect(find.byType(CitizenLoginScreen), findsNothing);
    expect(repository.hasAccount, isTrue);
    expect(saved, [true]);

    await repository.submit(
      photo: (await FakePhotos().takePhoto())!,
      category: 'pothole',
      position: const LatLng(14.6, -90.5),
    );
    expect(posts, hasLength(1));

    await testAccount.end();
    await tester.pumpAndSettle();
    expect(find.byType(CitizenLoginScreen), findsOneWidget);
    expect(saved, [true, false]);
  });

  testWidgets('a signed-in citizen sends without any phone prompt', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final posts = <dynamic>[];
    await tester.pumpWidget(
      host(
        repositoryWith(
          auth: FakeCitizenAuth(signedIn: true),
          requireCitizenLogin: true,
          onPost: () => posts.add(true),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await advanceToReview(tester);
    await tapText(tester, S.send);
    expect(posts, hasLength(1));
    expect(find.byType(CitizenLoginSheet), findsNothing);
  });

  testWidgets('profile masks verified number and logout clears it', (
    tester,
  ) async {
    final auth = FakeCitizenAuth(signedIn: true);
    await tester.pumpWidget(
      harness(
        home: Scaffold(body: ProfileScreen(onCleared: () {})),
        repository: repositoryWith(auth: auth),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(auth.maskedPhone!), findsOneWidget);
    await tester.tap(find.text('Cerrar sesión'));
    await tester.pumpAndSettle();
    expect(auth.isSignedIn, isFalse);
    expect(find.text('Verificar mi número'), findsOneWidget);
  });
  testWidgets('login sheet scrolls at phone width and double text scale', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final auth = FakeCitizenAuth();
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(body: CitizenLoginSheet(auth: auth)),
      ),
    );
    await tester.enterText(
      find.byKey(const Key('citizen-phone')),
      List.filled(8, '2').join(),
    );
    await tester.ensureVisible(find.text('Solicitar código'));
    await tester.tap(find.text('Solicitar código'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('citizen-code')));
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Verificar número'));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
