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
          expect(chip.labelStyle?.color, (chip.avatar as Icon).color);
          expect(chip.side?.color, chip.labelStyle?.color);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
}
