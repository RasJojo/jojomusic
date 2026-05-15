import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';

class AppSettings {
  const AppSettings({
    this.sponsorBlockEnabled = false,
    this.crossfadeEnabled = false,
    this.crossfadeDurationSeconds = 5,
    this.playbackSpeed = 1.0,
  });

  final bool sponsorBlockEnabled;
  final bool crossfadeEnabled;
  final int crossfadeDurationSeconds;
  final double playbackSpeed;

  AppSettings copyWith({
    bool? sponsorBlockEnabled,
    bool? crossfadeEnabled,
    int? crossfadeDurationSeconds,
    double? playbackSpeed,
  }) => AppSettings(
    sponsorBlockEnabled: sponsorBlockEnabled ?? this.sponsorBlockEnabled,
    crossfadeEnabled: crossfadeEnabled ?? this.crossfadeEnabled,
    crossfadeDurationSeconds:
        crossfadeDurationSeconds ?? this.crossfadeDurationSeconds,
    playbackSpeed: playbackSpeed ?? this.playbackSpeed,
  );
}

const _kSponsorBlock = 'settings.sponsorblock';
const _kCrossfade = 'settings.crossfade';
const _kCrossfadeDuration = 'settings.crossfade_duration';
const _kPlaybackSpeed = 'settings.playback_speed';

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(
  SettingsNotifier.new,
);

class SettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    return AppSettings(
      sponsorBlockEnabled: prefs.getBool(_kSponsorBlock) ?? false,
      crossfadeEnabled: prefs.getBool(_kCrossfade) ?? false,
      crossfadeDurationSeconds: prefs.getInt(_kCrossfadeDuration) ?? 5,
      playbackSpeed: prefs.getDouble(_kPlaybackSpeed) ?? 1.0,
    );
  }

  Future<void> setSponsorBlock(bool enabled) async {
    await ref.read(sharedPreferencesProvider).setBool(_kSponsorBlock, enabled);
    state = state.copyWith(sponsorBlockEnabled: enabled);
  }

  Future<void> setCrossfade(bool enabled) async {
    await ref.read(sharedPreferencesProvider).setBool(_kCrossfade, enabled);
    state = state.copyWith(crossfadeEnabled: enabled);
  }

  Future<void> setCrossfadeDuration(int seconds) async {
    await ref
        .read(sharedPreferencesProvider)
        .setInt(_kCrossfadeDuration, seconds);
    state = state.copyWith(crossfadeDurationSeconds: seconds);
  }

  Future<void> setPlaybackSpeed(double speed) async {
    await ref
        .read(sharedPreferencesProvider)
        .setDouble(_kPlaybackSpeed, speed);
    state = state.copyWith(playbackSpeed: speed);
  }
}
