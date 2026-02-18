import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:pingit/providers/device_provider.dart';
import 'package:pingit/screens/splash_screen.dart';
import 'package:pingit/services/logging_service.dart';
import 'package:pingit/services/notification_service.dart';
import 'package:pingit/ui/app_theme.dart';

void main() async {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    await LoggingService().init();
    await NotificationService().init();
    LoggingService().info('PingIT starting up');
    
    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      LoggingService().error('Flutter Error', data: {
        'exception': details.exception.toString(),
        'stack': details.stack.toString(),
      });
    };

    runApp(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => DeviceProvider()),
        ],
        child: const MyApp(),
      ),
    );
  }, (error, stack) {
    LoggingService().error('Uncaught Error', data: {
      'error': error.toString(),
      'stack': stack.toString(),
    });
  });
}

final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.system);

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (_, mode, __) {
        return MaterialApp(
          title: 'PingIT',
          debugShowCheckedModeBanner: false,
          themeMode: mode,
          theme: AppTheme.build(Brightness.light),
          darkTheme: AppTheme.build(Brightness.dark),
          home: const SplashScreen(),
        );
      },
    );
  }
}
