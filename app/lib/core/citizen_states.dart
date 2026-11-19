import 'package:flutter/material.dart';

/// What a citizen reads for one contract `state` (documentation/api-contract.md).
class CitizenState {
  const CitizenState(this.label, this.explanation, this.icon);

  /// Short name, used in chips, pins and the timeline.
  final String label;

  /// One sentence: what happened and what comes next. Never blames the citizen.
  final String explanation;

  /// Always shown together with [label]; state is never conveyed by color alone.
  final IconData icon;
}

/// All eleven contract states, in lifecycle order.
const Map<String, CitizenState> citizenStates = {
  'pendiente_verificacion': CitizenState(
    'En verificación',
    'Guardado. Estamos comprobando tu foto.',
    Icons.hourglass_empty,
  ),
  'rechazado_verificador': CitizenState(
    'Falta ajustar la foto',
    'No pudimos comprobar la foto. Puedes tomar otra y enviarla de nuevo.',
    Icons.add_a_photo,
  ),
  'nuevo': CitizenState(
    'Recibido',
    'Tu reporte fue aceptado y espera la revisión del municipio.',
    Icons.mark_email_read_outlined,
  ),
  'en_revision': CitizenState(
    'En revisión',
    'El municipio está revisando el problema.',
    Icons.manage_search,
  ),
  'programado': CitizenState(
    'Programado',
    'La atención del problema ya tiene fecha.',
    Icons.event,
  ),
  'en_proceso': CitizenState(
    'En proceso',
    'Se está trabajando en el problema.',
    Icons.construction,
  ),
  'resuelto': CitizenState(
    'Resuelto',
    'El municipio informa que el problema fue atendido.',
    Icons.check_circle_outline,
  ),
  'no_procede': CitizenState(
    'Cerrado',
    'El municipio cerró el reporte. El motivo aparece en el historial.',
    Icons.info_outline,
  ),
  'fuera_de_competencia': CitizenState(
    'Corresponde a otra entidad',
    'Este problema lo atiende otra institución. El motivo aparece en el historial.',
    Icons.swap_horiz,
  ),
  'duplicado': CitizenState(
    'Ya estaba reportado',
    'Otro reporte cubre el mismo problema; el seguimiento continúa allí.',
    Icons.copy_all,
  ),
  'oculto': CitizenState(
    'No disponible',
    'Este reporte ya no se muestra públicamente.',
    Icons.visibility_off_outlined,
  ),
};

const CitizenState _fallback = CitizenState(
  'Recibido',
  'Tu reporte fue recibido.',
  Icons.mark_email_read_outlined,
);

/// Wording for [state]; unknown or missing values (v0.1 servers) read as received.
CitizenState citizenStateFor(String? state) =>
    citizenStates[state] ?? _fallback;
