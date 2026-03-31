import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/providers.dart';
import '../../state/session_controller.dart';
import '../theme/jojo_theme.dart';
import 'jojo_logo.dart';
import 'jojo_surfaces.dart';
import 'mini_player_bar.dart';
import 'shell_bottom_bar.dart';

class ShellChrome extends ConsumerWidget {
  const ShellChrome({
    required this.child,
    required this.onProfilePressed,
    super.key,
    this.topColor,
    this.popToRootOnNavigate = false,
    this.showProfileShortcut = true,
  });

  final Widget child;
  final VoidCallback onProfilePressed;
  final Color? topColor;
  final bool popToRootOnNavigate;
  final bool showProfileShortcut;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mediaQuery = MediaQuery.of(context);
    final useSideNavigation =
        mediaQuery.size.width >= 980 || mediaQuery.size.shortestSide >= 700;
    final showDesktopPlayerPanel =
        useSideNavigation && mediaQuery.size.width >= 1180;
    final playerPanelWidth = mediaQuery.size.width >= 1580
        ? 400.0
        : mediaQuery.size.width >= 1320
        ? 360.0
        : 320.0;

    return JojoPageScaffold(
      topColor: topColor,
      maxContentWidth: useSideNavigation ? null : 1320,
      bottomNavigationBar: showDesktopPlayerPanel
          ? null
          : useSideNavigation
          ? const _DesktopMiniPlayerDock()
          : ShellBottomBar(popToRootOnNavigate: popToRootOnNavigate),
      child: useSideNavigation
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ShellSideRail(popToRootOnNavigate: popToRootOnNavigate),
                if (showDesktopPlayerPanel)
                  DesktopPlayerPanel(width: playerPanelWidth),
                Expanded(
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(22, 18, 24, 0),
                          child: child,
                        ),
                      ),
                      if (showProfileShortcut)
                        Positioned(
                          top: 16,
                          right: 22,
                          child: _ProfileShortcutButton(
                            onPressed: onProfilePressed,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            )
          : Column(
              children: [
                if (showProfileShortcut)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
                    child: Align(
                      alignment: Alignment.topRight,
                      child: _ProfileShortcutButton(
                        onPressed: onProfilePressed,
                        compact: true,
                      ),
                    ),
                  ),
                if (showProfileShortcut) const SizedBox(height: 8),
                Expanded(child: child),
              ],
            ),
    );
  }
}

class _DesktopMiniPlayerDock extends StatelessWidget {
  const _DesktopMiniPlayerDock();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xF0071112),
        border: Border(top: BorderSide(color: Color(0x1FFFFFFF))),
      ),
      child: const MiniPlayerBar(),
    );
  }
}

class _ProfileShortcutButton extends ConsumerWidget {
  const _ProfileShortcutButton({
    required this.onPressed,
    this.compact = false,
  });

  final VoidCallback onPressed;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionControllerProvider).asData?.value;
    final name = session?.user.name ?? 'Profil';
    final trimmedName = name.trim();
    final initial = trimmedName.isEmpty ? 'J' : trimmedName.substring(0, 1);
    final tooltip = trimmedName.isEmpty ? 'Profil' : trimmedName;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(compact ? 20 : 24),
        child: Ink(
          width: compact ? 40 : 48,
          height: compact ? 40 : 48,
          decoration: BoxDecoration(
            color: const Color(0xD90A1718),
            borderRadius: BorderRadius.circular(compact ? 20 : 24),
            border: Border.all(color: const Color(0x1FFFFFFF)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x18000000),
                blurRadius: 16,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Tooltip(
            message: tooltip,
            child: Center(
              child: Text(
                initial.toUpperCase(),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: JojoColors.text,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ShellSideRail extends ConsumerWidget {
  const _ShellSideRail({required this.popToRootOnNavigate});

  final bool popToRootOnNavigate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedIndex = ref.watch(shellTabIndexProvider).clamp(0, 2);
    return Container(
      width: 108,
      decoration: const BoxDecoration(
        color: Color(0xE6081314),
        border: Border(
          right: BorderSide(color: Color(0x1FFFFFFF)),
        ),
        borderRadius: BorderRadius.only(
          topRight: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
      ),
      child: SafeArea(
        right: false,
        bottom: false,
        child: NavigationRail(
          backgroundColor: Colors.transparent,
          selectedIndex: selectedIndex,
          useIndicator: true,
          minWidth: 86,
          minExtendedWidth: 108,
          groupAlignment: -0.92,
          labelType: NavigationRailLabelType.all,
          indicatorColor: JojoColors.surfaceBright,
          destinations: const [
            NavigationRailDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home_rounded),
              label: Text('Accueil'),
            ),
            NavigationRailDestination(
              icon: Icon(Icons.search_outlined),
              selectedIcon: Icon(Icons.search_rounded),
              label: Text('Recherche'),
            ),
            NavigationRailDestination(
              icon: Icon(Icons.library_music_outlined),
              selectedIcon: Icon(Icons.library_music_rounded),
              label: Text('Biblio'),
            ),
          ],
          onDestinationSelected: (value) {
            ref.read(shellTabIndexProvider.notifier).setIndex(value);
            if (popToRootOnNavigate && Navigator.of(context).canPop()) {
              Navigator.of(context).popUntil((route) => route.isFirst);
            }
          },
          leading: Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const JojoLogo(size: 52, borderRadius: 18),
                const SizedBox(height: 10),
                Text(
                  'JojoMusique',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
