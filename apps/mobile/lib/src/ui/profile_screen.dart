import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/app_models.dart';
import '../state/home_controller.dart';
import '../state/integrations_controller.dart';
import '../state/library_controller.dart';
import '../state/providers.dart';
import '../state/session_controller.dart';
import 'podcast_screen.dart';
import 'widgets/jojo_surfaces.dart';
import 'widgets/shell_chrome.dart';

Future<void> openProfileScreen(BuildContext context) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => const ProfileScreen()),
  );
}

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionControllerProvider).asData?.value;
    final spotify = ref.watch(spotifyIntegrationProvider);

    return ShellChrome(
      topColor: const Color(0xFF1B1720),
      popToRootOnNavigate: true,
      showProfileShortcut: false,
      onProfilePressed: () {},
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 28, 18, 160),
        children: [
          JojoPageHeader(
            title: 'Profil',
            subtitle:
                'Compte JojoMusique, signaux internes et session active.',
            leading: JojoIconButton(
              icon: Icons.arrow_back_rounded,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          const SizedBox(height: 20),
          JojoHeroPanel(
            label: 'Compte actif',
            title: session?.user.name ?? 'Utilisateur',
            subtitle: session?.user.email ?? '',
            accentColor: const Color(0xFF312D1A),
            metadata: const [
              'Historique local',
              'Recommandations',
              'Playlists',
            ],
          ),
          const SizedBox(height: 18),
          const JojoSurfaceCard(
            child: Text(
              'Le compte JojoMusique reste la source de vérité: écoute, favoris, playlists, téléchargements et recommandations sont pilotés ici.',
            ),
          ),
          const SizedBox(height: 18),
          _SpotifyIntegrationPanel(spotify: spotify),
          const SizedBox(height: 18),
          FilledButton.tonal(
            onPressed: () => ref.read(sessionControllerProvider.notifier).logout(),
            child: const Text('Déconnexion'),
          ),
        ],
      ),
    );
  }
}

class _SpotifyIntegrationPanel extends ConsumerWidget {
  const _SpotifyIntegrationPanel({required this.spotify});

  final AsyncValue<SpotifyIntegration> spotify;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return spotify.when(
      data: (integration) => JojoSurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const JojoSectionHeading(
              title: 'Importer depuis Spotify',
              subtitle:
                  'Profil, titres likés et podcasts sauvegardés importés dans JojoMusique.',
            ),
            const SizedBox(height: 14),
            if (!integration.configured)
              JojoStateMessage(
                icon: Icons.settings_suggest_rounded,
                message:
                    integration.configurationHint ??
                    'Le backend Spotify n’est pas encore configuré. Ajoute le client ID, le client secret et le redirect URI côté API.',
              )
            else if (!integration.connected) ...[
              const JojoStateMessage(
                icon: Icons.account_circle_outlined,
                message:
                    'Clique pour connecter ton compte Spotify. Le backend importera ton profil, tes titres likés et tes shows/épisodes sauvegardés.',
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: () async {
                  try {
                    final uri = await ref
                        .read(apiProvider)
                        .createSpotifyConnectUrl();
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Connexion ouverte dans le navigateur. Termine l’autorisation Spotify, puis reviens ici.',
                          ),
                        ),
                      );
                    }
                  } catch (error) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Impossible d’ouvrir la connexion Spotify: $error',
                          ),
                        ),
                      );
                    }
                  }
                },
                icon: const Icon(Icons.link_rounded),
                label: const Text('Connecter Spotify'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => ref.invalidate(spotifyIntegrationProvider),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Rafraîchir le statut'),
              ),
            ] else ...[
              Row(
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: const Color(0xFF153033),
                    backgroundImage: integration.avatarUrl == null
                        ? null
                        : NetworkImage(integration.avatarUrl!),
                    child: integration.avatarUrl == null
                        ? const Icon(Icons.person_rounded)
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          integration.displayName ?? 'Compte Spotify',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          [
                                integration.email,
                                integration.product,
                                integration.country,
                              ]
                              .whereType<String>()
                              .where((value) => value.isNotEmpty)
                              .join(' • '),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _StatPill(
                    label: '${integration.likedTracksImported} titres likés',
                  ),
                  _StatPill(label: '${integration.savedShowsImported} shows'),
                  _StatPill(
                    label: '${integration.savedEpisodesImported} épisodes',
                  ),
                  _StatPill(
                    label: '${integration.recentTracksImported} récents',
                  ),
                ],
              ),
              if (integration.importedAt != null) ...[
                const SizedBox(height: 10),
                Text(
                  'Dernière importation: ${formatCompactDate(integration.importedAt)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 14),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  FilledButton.icon(
                    onPressed: () async {
                      try {
                        await ref.read(apiProvider).syncSpotifyIntegration();
                        ref.invalidate(spotifyIntegrationProvider);
                        ref.invalidate(homeControllerProvider);
                        ref.invalidate(libraryControllerProvider);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Import Spotify mis à jour.'),
                            ),
                          );
                        }
                      } catch (error) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Synchronisation Spotify impossible: $error',
                              ),
                            ),
                          );
                        }
                      }
                    },
                    icon: const Icon(Icons.sync_rounded),
                    label: const Text('Synchroniser'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () async {
                      await ref
                          .read(apiProvider)
                          .disconnectSpotifyIntegration();
                      ref.invalidate(spotifyIntegrationProvider);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Compte Spotify déconnecté.'),
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.link_off_rounded),
                    label: const Text('Déconnecter'),
                  ),
                ],
              ),
              if (integration.savedShows.isNotEmpty) ...[
                const SizedBox(height: 18),
                const JojoSectionHeading(
                  title: 'Shows importés',
                  subtitle:
                      'Aperçu des podcasts Spotify sauvegardés dans ton profil.',
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 282,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: integration.savedShows.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(width: 14),
                    itemBuilder: (context, index) {
                      final show = integration.savedShows[index];
                      return JojoPosterCard(
                        title: show.title,
                        subtitle: show.publisher,
                        artworkUrl: show.artworkUrl,
                        badge: 'Spotify',
                        width: 188,
                        height: 176,
                        backgroundColor: const Color(0xFF15181F),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => PodcastScreen(podcast: show),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
      error: (error, stackTrace) => JojoStateMessage(
        icon: Icons.error_outline_rounded,
        message: 'Erreur intégration Spotify: $error',
      ),
      loading: () => const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  const _StatPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: const Color(0x660C1718),
        border: Border.all(color: const Color(0x1FFFFFFF)),
      ),
      child: Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w800),
      ),
    );
  }
}
