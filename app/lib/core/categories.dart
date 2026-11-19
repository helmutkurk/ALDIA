import 'package:flutter/material.dart';

/// Report category. Ids are the contract ids (documentation/api-contract.md).
/// The final MVP list depends on what the verifier can recognize in photos.
class ReportCategory {
  const ReportCategory(
    this.id,
    this.label,
    this.icon, {
    this.group = 'espacio_publico',
  });

  factory ReportCategory.fromJson(Map<String, dynamic> json) => ReportCategory(
    json['id'] as String,
    json['label'] as String,
    categoryById(json['id'] as String).icon,
    group: json['group'] as String? ?? 'espacio_publico',
  );

  final String group;

  final String id;
  final String label;
  final IconData icon;
}

const List<ReportCategory> reportCategories = [
  ReportCategory(
    'accessibility',
    'Accesibilidad (rampas, bordillos)',
    Icons.accessible,
    group: 'movilidad',
  ),
  ReportCategory(
    'sidewalk',
    'Acera en mal estado',
    Icons.directions_walk,
    group: 'movilidad',
  ),
  ReportCategory('pothole', 'Bache', Icons.warning_amber, group: 'movilidad'),
  ReportCategory('graffiti', 'Grafiti', Icons.brush),
  ReportCategory(
    'open_drain',
    'Alcantarilla abierta',
    Icons.water_drop,
    group: 'servicios',
  ),
  ReportCategory(
    'street_light',
    'Luminaria dañada',
    Icons.lightbulb_outline,
    group: 'servicios',
  ),
];

ReportCategory categoryById(String id) {
  return reportCategories.firstWhere(
    (c) => c.id == id,
    orElse: () => ReportCategory(id, id, Icons.help_outline),
  );
}

String categoryGroupLabel(String group) => switch (group) {
  'movilidad' => 'Movilidad',
  'espacio_publico' => 'Espacio público',
  'servicios' => 'Servicios',
  _ => group,
};
