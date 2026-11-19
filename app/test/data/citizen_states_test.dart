import 'package:aldia_app/core/citizen_states.dart';
import 'package:aldia_app/data/report.dart';
import 'package:aldia_app/features/report/verification_feedback.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  test(
    'all eleven contract states have citizen wording, explanation, icon',
    () {
      const states = [
        'pendiente_verificacion',
        'rechazado_verificador',
        'nuevo',
        'en_revision',
        'programado',
        'en_proceso',
        'resuelto',
        'no_procede',
        'fuera_de_competencia',
        'duplicado',
        'oculto',
      ];
      expect(citizenStates.keys, unorderedEquals(states));
      for (final state in states) {
        final info = citizenStateFor(state);
        expect(info.label, isNotEmpty, reason: state);
        expect(info.explanation, endsWith('.'), reason: state);
        expect(info, same(citizenStates[state]));
      }
      expect(
        citizenStates.values.map((s) => s.label).toSet(),
        hasLength(states.length),
        reason: 'distinct labels keep chips unambiguous',
      );
    },
  );
  test('a missing or unknown state reads as received', () {
    expect(citizenStateFor(null).label, 'Recibido');
    expect(citizenStateFor('futuro').label, 'Recibido');
  });
  test(
    'old responses derive state; optional v0.2 fields parse public events only',
    () {
      expect(Report.fromJson(reportJson()).citizenState, 'nuevo');
      final report = Report.fromJson({
        ...reportJson(),
        'state': 'en_revision',
        'duplicate_of': 'other',
        'events': [
          {
            'at': '2026-11-19T19:00:00Z',
            'to_state': 'en_revision',
            'public_note': 'Estamos revisando',
            'internal_note': 'never expose',
          },
        ],
      });
      expect(report.citizenState, 'en_revision');
      expect(report.events.single.publicNote, 'Estamos revisando');
      expect(report.duplicateOf, 'other');
    },
  );
  for (final name in ['place', 'freshness', 'duplicate', 'category', 'image']) {
    test('$name failure has a plain reason and a way to fix it', () {
      final feedback = feedbackFor(
        VerificationCheck(name: name, passed: false, detail: 'raw technical'),
        'Bache',
      );
      expect(feedback.reason, isNotEmpty);
      expect(feedback.fix, isNotEmpty);
      expect(feedback.reason, isNot(contains('raw technical')));
    });
  }
  test('multiple failures start with the one-tap fixes, then the pin, then retakes', () {
    final verification = Verification(
      passed: false,
      mode: 'stub',
      checks: [
        for (final name in [
          'image',
          'freshness',
          'place',
          'category',
          'duplicate',
        ])
          VerificationCheck(name: name, passed: false, detail: ''),
      ],
    );
    expect(orderedFailures(verification).map((c) => c.name), [
      'category',
      'place',
      'duplicate',
      'freshness',
      'image',
    ]);
  });
}
