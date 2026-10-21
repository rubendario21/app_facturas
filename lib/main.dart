import 'dart:io';

import 'package:device_preview/device_preview.dart';
import 'package:device_preview/presets.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'services/auth_service.dart';
import 'theme/app_theme.dart';

/// Vista previa de un móvil al depurar en escritorio:
/// `flutter run -d windows --dart-define=PREVIEW=ios` (o `android`).
const _preview = String.fromEnvironment('PREVIEW');

Future<void> main() async {
  if (_preview.isNotEmpty && kDebugMode) {
    DevicePreview.enable(enabled: true);
    await DevicePreview.controller.applyPreset(_preview == 'android'
        ? DevicePresets.galaxyS25
        : DevicePresets.iPhone16);
  }
  WidgetsFlutterBinding.ensureInitialized();
  // En escritorio (Windows/Linux/macOS) SQLite se usa vía FFI; en Android no aplica.
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
  await initializeDateFormatting('es');
  Intl.defaultLocale = 'es';
  await AuthService.instance.load();
  await ThemeController.instance.load();
  runApp(const FacturasApp());
}

class FacturasApp extends StatelessWidget {
  const FacturasApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.instance,
      builder: (context, mode, _) => MaterialApp(
        title: 'Facturas',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: mode,
        locale: const Locale('es'),
        supportedLocales: const [Locale('es')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const _StartGate(),
      ),
    );
  }
}

/// Con una sesión guardada se entra directamente (también sin conexión).
class _StartGate extends StatelessWidget {
  const _StartGate();

  @override
  Widget build(BuildContext context) {
    return AuthService.instance.isLoggedIn
        ? const HomeScreen()
        : const LoginScreen();
  }
}
