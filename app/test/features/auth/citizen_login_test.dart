import 'package:aldia_app/features/citizen/login_sheet.dart';
import 'package:aldia_app/features/citizen/citizen_screens.dart';
import 'package:aldia_app/core/strings.dart';
import 'package:aldia_app/core/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_auth.dart';
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
    'required wizard blocks upload until verified and then sends once',
    (tester) async {
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final auth = FakeCitizenAuth();
      final posts = <dynamic>[];
      final repository = repositoryWith(
        auth: auth,
        requireCitizenLogin: true,
        onPost: () => posts.add(true),
      );
      await tester.pumpWidget(host(repository));
      await tester.pumpAndSettle();
      await advanceToReview(tester);
      expect(find.text('Continuar sin avisos'), findsNothing);
      await tapText(tester, S.send);
      expect(posts, isEmpty);
      expect(find.byType(CitizenLoginSheet), findsOneWidget);
      await fillPhone(tester);
      await tester.enterText(
        find.byKey(const Key('citizen-code')),
        List.filled(6, '1').join(),
      );
      await tester.tap(find.text('Verificar número'));
      await tester.pumpAndSettle();
      expect(posts, hasLength(1));
      expect(auth.isSignedIn, isTrue);
    },
  );

  testWidgets('optional wizard explicitly offers anonymous submission', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final posts = <dynamic>[];
    await tester.pumpWidget(
      host(repositoryWith(onPost: () => posts.add(true))),
    );
    await tester.pumpAndSettle();
    await advanceToReview(tester);
    await tapText(tester, 'Continuar sin avisos');
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
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    for (final theme in [buildTheme(), buildDarkTheme()]) {
      final auth = FakeCitizenAuth();
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
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
      // The keyboard appears only after opening the sheet and focusing input.
      tester.view.viewInsets = const FakeViewPadding(bottom: 260);
      await tester.pumpAndSettle();
      final sheetContext = tester.element(find.byType(CitizenLoginSheet));
      final route = ModalRoute.of(sheetContext)!;
      expect(route.transitionDuration, Duration.zero);
      expect(route.reverseTransitionDuration, Duration.zero);
      await tester.enterText(
        find.byKey(const Key('citizen-phone')),
        List.filled(8, '2').join(),
      );
      final primaryButton = find.ancestor(
        of: find.text('Solicitar código'),
        matching: find.byType(FilledButton),
      );
      await tester.ensureVisible(primaryButton);
      expect(tester.getSize(primaryButton).height, greaterThanOrEqualTo(48));
      await tester.tap(find.text('Solicitar código'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('citizen-code')));
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Verificar número'));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    }
  });
}
