import 'dart:async';

import 'package:flutter/material.dart';

import '../services/haptics.dart';
import 'spring_bottom_sheet.dart';

/// The street base stays visible; the citizen can toggle the data overlay.
class MapLayersButton extends StatelessWidget {
  const MapLayersButton({
    super.key,
    required this.overlay,
    required this.visible,
    required this.onChanged,
  });
  final String overlay;
  final bool visible;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: 'Capas del mapa',
    icon: const Icon(Icons.layers_outlined),
    onPressed: () {
      FocusManager.instance.primaryFocus?.unfocus();
      showSpringBottomSheet<void>(
        context: context,
        builder: (context) => SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    'Capas del mapa',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                const ListTile(
                  leading: Icon(Icons.map_outlined),
                  title: Text('Calles'),
                  subtitle: Text('© OpenStreetMap contributors'),
                ),
                SwitchListTile(
                  title: Text(overlay),
                  value: visible,
                  onChanged: (value) {
                    unawaited(HapticsHelper.light());
                    onChanged(value);
                    Navigator.pop(context);
                  },
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
