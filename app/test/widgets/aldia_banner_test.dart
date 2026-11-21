import 'package:aldia_app/core/theme.dart';
import 'package:aldia_app/widgets/aldia_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('each banner kind shows its icon next to the words', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: const Scaffold(
          body: Column(
            children: [
              AldiaBanner('Información'),
              AldiaBanner('Cuidado', kind: BannerKind.warning),
              AldiaBanner('Algo falló', kind: BannerKind.error),
            ],
          ),
        ),
      ),
    );
    expect(find.text('Información'), findsOneWidget);
    expect(find.byIcon(Icons.info_outline), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
    final error = tester.getSemantics(find.text('Algo falló'));
    expect(error.label, contains('Algo falló'));
  });
}
