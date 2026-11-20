import 'dart:async';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// The installed version and build number, read from the platform.
class VersionIndicator extends StatefulWidget {
  const VersionIndicator({super.key});

  @override
  State<VersionIndicator> createState() => _VersionIndicatorState();
}

class _VersionIndicatorState extends State<VersionIndicator> {
  String? _label;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final PackageInfo info = await PackageInfo.fromPlatform();

      if (!mounted) return;

      setState(() {
        _label = '${info.version} (${info.buildNumber})';
      });
    } catch (_) {
      // Widget tests have no platform plugin; the line stays hidden.
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_label == null) {
      return const SizedBox.shrink();
    }

    return Text(
      _label!,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        fontFeatures: const [FontFeature.tabularFigures()],
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}
