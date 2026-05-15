import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/player_controller.dart';
import '../state/settings_controller.dart';
import 'theme/jojo_theme.dart';
import 'widgets/jojo_surfaces.dart';
import 'widgets/shell_chrome.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);

    return ShellChrome(
      topColor: const Color(0xFF1A1A2E),
      popToRootOnNavigate: true,
      showProfileShortcut: false,
      onProfilePressed: () {},
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 148),
        children: [
          JojoPageHeader(
            title: 'Réglages',
            subtitle: "Personnalise ton expérience d'écoute.",
            leading: JojoIconButton(
              icon: Icons.arrow_back_rounded,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          const SizedBox(height: 18),

          // Playback speed
          JojoSurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const JojoSectionHeading(
                  title: 'Vitesse de lecture',
                  subtitle: 'Ralentis ou accélère la lecture.',
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final speed in [0.5, 0.75, 1.0, 1.25, 1.5, 2.0])
                      _SpeedChip(
                        speed: speed,
                        selected: settings.playbackSpeed == speed,
                        onTap: () {
                          ref
                              .read(settingsProvider.notifier)
                              .setPlaybackSpeed(speed);
                          ref.read(playerControllerProvider).setSpeed(speed);
                        },
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Crossfade
          JojoSurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const JojoSectionHeading(
                  title: 'Fondu enchaîné',
                  subtitle: 'Fondu en fin de piste pour une transition douce.',
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: settings.crossfadeEnabled,
                  onChanged: (val) {
                    ref.read(settingsProvider.notifier).setCrossfade(val);
                    ref
                        .read(playerControllerProvider)
                        .setCrossfadeEnabled(val);
                  },
                  title: const Text('Activer le fondu'),
                ),
                if (settings.crossfadeEnabled) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Durée : ${settings.crossfadeDurationSeconds} secondes',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  Slider(
                    value: settings.crossfadeDurationSeconds.toDouble(),
                    min: 1,
                    max: 10,
                    divisions: 9,
                    label: '${settings.crossfadeDurationSeconds}s',
                    onChanged: (val) {
                      final secs = val.round();
                      ref
                          .read(settingsProvider.notifier)
                          .setCrossfadeDuration(secs);
                      ref
                          .read(playerControllerProvider)
                          .setCrossfadeDuration(secs);
                    },
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),

          // SponsorBlock
          JojoSurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const JojoSectionHeading(
                  title: 'SponsorBlock',
                  subtitle:
                      'Saute automatiquement les sponsors et intros/outros.',
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: settings.sponsorBlockEnabled,
                  onChanged: (val) {
                    ref.read(settingsProvider.notifier).setSponsorBlock(val);
                    ref
                        .read(playerControllerProvider)
                        .setSponsorBlockEnabled(val);
                  },
                  title: const Text('Activer SponsorBlock'),
                  subtitle: const Text(
                    'Source communautaire — sponsor.ajay.app',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SpeedChip extends StatelessWidget {
  const _SpeedChip({
    required this.speed,
    required this.selected,
    required this.onTap,
  });

  final double speed;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = speed == 1.0 ? 'Normal' : '${speed}x';
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? JojoColors.primary.withAlpha(40)
              : JojoColors.surfaceBright,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? JojoColors.primary : Colors.white12,
          ),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: selected ? JojoColors.primary : null,
            fontWeight: selected ? FontWeight.w700 : null,
          ),
        ),
      ),
    );
  }
}
