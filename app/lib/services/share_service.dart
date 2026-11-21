import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class ShareService {
  static const _channel = MethodChannel('org.aldia/share');
  static const _portalUrl = String.fromEnvironment(
    'PUBLIC_PORTAL_URL',
    defaultValue: 'http://localhost:5173',
  );

  /// Opens sharing when available, otherwise copies the public report link.
  static Future<bool> shareReport(String id) async {
    final url = Uri.parse(_portalUrl)
        .replace(fragment: '/reports/$id')
        .toString();
    final text = 'Mira este reporte en AlDía: $url';
    try {
      if (!kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.android ||
              defaultTargetPlatform == TargetPlatform.iOS)) {
        if (await _channel.invokeMethod<bool>('share', {'text': text}) ==
            true) {
          return true;
        }
      } else if (!kIsWeb && defaultTargetPlatform == TargetPlatform.linux) {
        final result = await Process.run('xdg-open', [
          Uri.https('wa.me', '/', {'text': text}).toString(),
        ]);
        if (result.exitCode == 0) return true;
      }
    } on PlatformException {
      // A native share target is unavailable; keep the public link useful.
    } on MissingPluginException {
      // Other desktop targets can still copy the public link.
    } on ProcessException {
      // A desktop without xdg-open can still copy the public link.
    }
    await Clipboard.setData(ClipboardData(text: url));
    return false;
  }
}
