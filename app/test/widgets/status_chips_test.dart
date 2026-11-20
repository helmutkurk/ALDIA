import 'package:aldia_app/core/citizen_states.dart';
import 'package:aldia_app/core/theme.dart';
import 'package:aldia_app/widgets/status_chips.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final theme in [buildTheme(), buildDarkTheme()]) {
    testWidgets(
      '${theme.brightness.name} statuses retain words and icons on opaque surfaces',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Scaffold(
              body: SingleChildScrollView(
                child: Column(
                  children: [
                    for (final state in citizenStates.keys)
                      Wrap(
                        children: [
                          StateChip(state: state),
                          CitizenStateChip(state: state),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
        for (final entry in citizenStates.entries) {
          expect(find.text(entry.value.label), findsNWidgets(2));
          expect(find.byIcon(entry.value.icon), findsNWidgets(2));
        }
        for (final chip in tester.widgetList<Chip>(find.byType(Chip))) {
          expect(chip.backgroundColor, theme.colorScheme.surface);
          expect(
            (chip.label as Text).style?.color,
            theme.colorScheme.onSurface,
          );
          expect(chip.side?.color, (chip.avatar as Icon).color);
          expect(
            chip.shape,
            isA<RoundedRectangleBorder>().having(
              (shape) => shape.borderRadius,
              'border radius',
              BorderRadius.circular(8),
            ),
          );
          expect(
            chip.padding,
            const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          );
          expect((chip.avatar as Icon).size, 18);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
}
