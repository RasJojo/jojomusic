import 'dart:ui';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'src/audio/jojo_audio_handler.dart';
import 'src/config/app_environment.dart';
import 'src/data/app_database.dart';
import 'src/state/providers.dart';
import 'src/ui/theme/jojo_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    return false;
  };
  runApp(const _BootstrapApp());
}

class _BootstrapApp extends StatefulWidget {
  const _BootstrapApp();

  @override
  State<_BootstrapApp> createState() => _BootstrapAppState();
}

class _BootstrapAppState extends State<_BootstrapApp> {
  late final Future<_BootstrapData> _bootstrapFuture;

  @override
  void initState() {
    super.initState();
    _bootstrapFuture = Future<_BootstrapData>.delayed(Duration.zero, () async {
      final sharedPreferences = await SharedPreferences.getInstance();
      final environment = AppEnvironment.fromPlatform();
      final database = AppDatabase();
      final audioHandler = kIsWeb
          ? JojoAudioHandler(environment: environment, database: database)
          : await AudioService.init(
              builder: () =>
                  JojoAudioHandler(environment: environment, database: database),
              config: const AudioServiceConfig(
                androidNotificationChannelId: 'com.jojomusic.playback',
                androidNotificationChannelName: 'JojoMusique Playback',
                androidNotificationOngoing: true,
              ),
            );
      return _BootstrapData(
        sharedPreferences: sharedPreferences,
        environment: environment,
        database: database,
        audioHandler: audioHandler,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_BootstrapData>(
      future: _bootstrapFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: buildJojoTheme(),
            home: _BootstrapErrorScreen(error: snapshot.error),
          );
        }

        final data = snapshot.data;
        if (data == null) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: buildJojoTheme(),
            home: const _BootstrapLoadingScreen(),
          );
        }

        return ProviderScope(
          overrides: [
            environmentProvider.overrideWithValue(data.environment),
            sharedPreferencesProvider.overrideWithValue(data.sharedPreferences),
            appDatabaseProvider.overrideWithValue(data.database),
            audioHandlerProvider.overrideWithValue(data.audioHandler),
          ],
          child: const JojoMusiqueApp(),
        );
      },
    );
  }
}

class _BootstrapData {
  const _BootstrapData({
    required this.sharedPreferences,
    required this.environment,
    required this.database,
    required this.audioHandler,
  });

  final SharedPreferences sharedPreferences;
  final AppEnvironment environment;
  final AppDatabase database;
  final JojoAudioHandler audioHandler;
}

class _BootstrapLoadingScreen extends StatelessWidget {
  const _BootstrapLoadingScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF13312D), Color(0xFF091617), Color(0xFF050B0C)],
          ),
        ),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Initialisation de JojoMusique'),
            ],
          ),
        ),
      ),
    );
  }
}

class _BootstrapErrorScreen extends StatelessWidget {
  const _BootstrapErrorScreen({required this.error});

  final Object? error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF13312D), Color(0xFF091617), Color(0xFF050B0C)],
          ),
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline_rounded, size: 42),
                const SizedBox(height: 16),
                const Text(
                  'Initialisation impossible',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                Text('$error', textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
