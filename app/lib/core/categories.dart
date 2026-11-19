import 'package:flutter/material.dart';

/// Report category. Ids are the contract ids (documentation/api-contract.md).
/// The final MVP list depends on what the verifier can recognize in photos.
class ReportCategory {
  const ReportCategory(this.id, this.label, this.icon);

  final String id;
  final String label;
  final IconData icon;
}

const List<ReportCategory> reportCategories = [
  ReportCategory(
    'accessibility',
    'Accesibilidad (rampas, bordillos)',
    Icons.accessible,
  ),
  ReportCategory('sidewalk', 'Acera en mal estado', Icons.directions_walk),
  ReportCategory('pothole', 'Bache', Icons.warning_amber),
  ReportCategory('graffiti', 'Grafiti', Icons.brush),
  ReportCategory('open_drain', 'Alcantarilla abierta', Icons.water_drop),
  ReportCategory('street_light', 'Luminaria dañada', Icons.lightbulb_outline),
];

ReportCategory categoryById(String id) {
  return reportCategories.firstWhere(
    (c) => c.id == id,
    orElse: () => ReportCategory(id, id, Icons.help_outline),
  );
}
