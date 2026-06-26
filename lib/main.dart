import 'dart:async';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'screens/app_shell.dart';
import 'theme/app_theme.dart';

void main() {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      FlutterError.onError = (details) {
        FlutterError.presentError(details);
        debugPrint(
          'Flutter error: ${details.exceptionAsString()} \n'
          'Stack: ${details.stack}',
        );
      };
      final analytics = await _initializeAnalytics();
      runApp(WeaveFluxApp(analytics: analytics));
    },
    (error, stack) {
      debugPrint('Uncaught Dart error: $error \n Stack: $stack');
    },
  );
}

Future<FirebaseAnalytics?> _initializeAnalytics() async {
  try {
    await Firebase.initializeApp();
    final analytics = FirebaseAnalytics.instance;
    await analytics.setAnalyticsCollectionEnabled(true);
    await analytics.logAppOpen();
    return analytics;
  } catch (error, stack) {
    debugPrint('Firebase Analytics init failed: $error\nStack: $stack');
    return null;
  }
}

class WeaveFluxApp extends StatelessWidget {
  const WeaveFluxApp({super.key, this.analytics});

  final FirebaseAnalytics? analytics;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WeaveFlux',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      navigatorObservers: [
        if (analytics != null) FirebaseAnalyticsObserver(analytics: analytics!),
      ],
      home: const AppShell(),
    );
  }
}
