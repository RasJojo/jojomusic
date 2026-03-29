import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'src/state/home_controller.dart';
import 'src/state/library_controller.dart';
import 'src/state/player_controller.dart';
import 'src/state/providers.dart';
import 'src/state/session_controller.dart';
import 'src/ui/login_screen.dart';
import 'src/ui/shell_screen.dart';
import 'src/ui/theme/jojo_theme.dart';

class JojoMusiqueApp extends ConsumerStatefulWidget {
  const JojoMusiqueApp({super.key});

  @override
  ConsumerState<JojoMusiqueApp> createState() => _JojoMusiqueAppState();
}

class _JojoMusiqueAppState extends ConsumerState<JojoMusiqueApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      return;
    }
    ref.invalidate(connectivityStatusProvider);
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionControllerProvider);

    ref.listen(sessionControllerProvider, (previous, next) {
      final previousSession = previous?.asData?.value;
      final nextSession = next.asData?.value;
      final previousToken = previousSession?.accessToken;
      final nextToken = nextSession?.accessToken;
      if (nextToken != null && nextToken != previousToken) {
        ref.invalidate(homeControllerProvider);
        ref.invalidate(libraryControllerProvider);
      }
    });

    ref.listen(currentMediaItemProvider, (_, next) {
      final mediaItem = next.asData?.value;
      if (mediaItem != null) {
        unawaited(
          ref
              .read(playerControllerProvider)
              .preloadLyricsForMediaItem(mediaItem),
        );
      }
    });

    ref.listen(connectivityStatusProvider, (previous, next) {
      final previousStatus = previous?.asData?.value;
      final hasNetwork = next.asData?.value ?? false;
      final sessionValue = ref.read(sessionControllerProvider).asData?.value;
      if (!hasNetwork || sessionValue == null || previousStatus == hasNetwork) {
        return;
      }
      unawaited(ref.read(homeControllerProvider.notifier).refresh());
      unawaited(ref.read(libraryControllerProvider.notifier).refresh());
    });

    return MaterialApp(
      title: 'JojoMusique',
      debugShowCheckedModeBanner: false,
      theme: buildJojoTheme(),
      home: session.when(
        data: (authSession) =>
            authSession == null ? const LoginScreen() : const ShellScreen(),
        error: (error, stackTrace) =>
            Scaffold(body: Center(child: Text('Session error: $error'))),
        loading: () =>
            const Scaffold(body: Center(child: CircularProgressIndicator())),
      ),
    );
  }
}
