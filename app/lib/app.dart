import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:provider/provider.dart';

import 'core/strings.dart';
import 'core/theme.dart';
import 'data/report_repository.dart';
import 'features/home/home_screen.dart';
import 'services/location_service.dart';
import 'services/photo_service.dart';

/// Root widget. Dependencies are injected so tests can replace them.
class AldiaApp extends StatelessWidget {
  const AldiaApp({
    super.key,
    required this.repository,
    required this.location,
    required this.photos,
    this.tileProvider,
  });

  final ReportRepository repository;
  final LocationService location;
  final PhotoService photos;

  /// Map tiles source. Tests inject an offline provider.
  final TileProvider? tileProvider;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<ReportRepository>.value(value: repository),
        Provider<LocationService>.value(value: location),
        Provider<PhotoService>.value(value: photos),
        Provider<TileProvider>.value(
          value: tileProvider ?? NetworkTileProvider(),
        ),
      ],
      child: MaterialApp(
        title: S.appName,
        theme: buildTheme(),
        debugShowCheckedModeBanner: false,
        locale: const Locale('es', 'GT'),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('es', 'GT'), Locale('es')],
        home: const HomeScreen(),
      ),
    );
  }
}
