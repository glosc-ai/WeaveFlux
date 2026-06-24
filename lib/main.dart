import 'dart:async';

import 'package:flutter/material.dart';

import 'screens/app_shell.dart';
import 'theme/app_theme.dart';

void main() {
  runZonedGuarded(
    () {
      FlutterError.onError = (details) {
        FlutterError.presentError(details);
        debugPrint(
          'Flutter error: ${details.exceptionAsString()} \n'
          'Stack: ${details.stack}',
        );
      };
      runApp(const WeaveFluxApp());
    },
    (error, stack) {
      debugPrint('Uncaught Dart error: $error \n Stack: $stack');
    },
  );
}

class WeaveFluxApp extends StatelessWidget {
  const WeaveFluxApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WeaveFlux',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: const AppShell(),
    );
  }
}
