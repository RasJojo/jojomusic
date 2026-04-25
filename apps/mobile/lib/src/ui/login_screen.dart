import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/session_controller.dart';
import 'theme/jojo_theme.dart';
import 'widgets/jojo_logo.dart';
import 'widgets/jojo_surfaces.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _nameController = TextEditingController(text: 'Jojo');
  final _emailController = TextEditingController(text: 'jojo@example.com');
  final _passwordController = TextEditingController(text: 'jojo1234');
  bool _registerMode = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  String _formatErrorMessage(Object? error) {
    final message = error.toString();
    if (message.contains('Invalid credentials')) {
      return 'Email ou mot de passe incorrect. Réessayez.';
    }
    if (message.contains('Connection refused') || message.contains('Failed host lookup')) {
      return 'Impossible de se connecter au serveur. Vérifiez votre connexion internet.';
    }
    if (message.contains('Timeout')) {
      return 'Connexion expirée. Réessayez.';
    }
    if (message.contains('409') || message.contains('Email already in use')) {
      return 'Cet email est déjà utilisé.';
    }
    return 'Erreur: Réessayez.';
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionControllerProvider);

    return JojoPageScaffold(
      topColor: const Color(0xFF142828),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 980),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final desktop = constraints.maxWidth > 760;
                final form = _buildForm(context, session);

                if (!desktop) {
                  return SingleChildScrollView(
                    child: Column(
                      children: [
                        _buildHero(context),
                        const SizedBox(height: 18),
                        form,
                      ],
                    ),
                  );
                }

                return Row(
                  children: [
                    Expanded(flex: 6, child: _buildHero(context)),
                    const SizedBox(width: 20),
                    Expanded(
                      flex: 5,
                      child: SingleChildScrollView(child: form),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHero(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(36),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF153B33), Color(0xFF0B1819)],
        ),
        border: Border.all(color: const Color(0x1FFFFFFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: JojoColors.primary.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Padding(
              padding: EdgeInsets.all(8),
              child: JojoLogo(size: 40, borderRadius: 14),
            ),
          ),
          const SizedBox(height: 24),
          Text('JojoMusique', style: Theme.of(context).textTheme.displaySmall),
          const SizedBox(height: 14),
          Text(
            'Compte perso, historique perso, reco perso. Une interface plus dense, plus lisible, et pensée pour la lecture immédiate.',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: const [
              _HeroPill(label: 'Streaming'),
              _HeroPill(label: 'Playlists'),
              _HeroPill(label: 'Hors-ligne'),
              _HeroPill(label: 'Paroles'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildForm(BuildContext context, AsyncValue<dynamic> session) {
    return JojoSurfaceCard(
      padding: const EdgeInsets.all(22),
      radius: 32,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _registerMode ? 'Créer un compte' : 'Se connecter',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            _registerMode
                ? 'Chaque compte garde son historique, ses playlists et sa recommandation.'
                : 'Reprends tes playlists, tes favoris et ta session locale.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 22),
          if (_registerMode) ...[
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Nom'),
            ),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _emailController,
            decoration: const InputDecoration(labelText: 'Email'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _passwordController,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Mot de passe'),
          ),
          const SizedBox(height: 18),
          FilledButton(
            onPressed: session.isLoading
                ? null
                : () async {
                    if (_registerMode) {
                      await ref
                          .read(sessionControllerProvider.notifier)
                          .register(
                            name: _nameController.text.trim(),
                            email: _emailController.text.trim(),
                            password: _passwordController.text,
                          );
                    } else {
                      await ref
                          .read(sessionControllerProvider.notifier)
                          .login(
                            email: _emailController.text.trim(),
                            password: _passwordController.text,
                          );
                    }
                  },
            child: Text(_registerMode ? 'Créer le compte' : 'Se connecter'),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: () => setState(() => _registerMode = !_registerMode),
            child: Text(
              _registerMode ? 'Déjà un compte ? Connexion' : 'Créer un compte',
            ),
          ),
          if (session.hasError) ...[
            const SizedBox(height: 12),
            Text(
              _formatErrorMessage(session.error),
              style: const TextStyle(color: Colors.redAccent),
            ),
          ],
        ],
      ),
    );
  }
}

class _HeroPill extends StatelessWidget {
  const _HeroPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: const Color(0x660D1717),
        border: Border.all(color: const Color(0x1FFFFFFF)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: JojoColors.mutedStrong,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
