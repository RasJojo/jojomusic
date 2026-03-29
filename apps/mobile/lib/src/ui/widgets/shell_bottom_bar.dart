import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/providers.dart';
import 'mini_player_bar.dart';

class ShellBottomBar extends ConsumerWidget {
  const ShellBottomBar({super.key, this.popToRootOnNavigate = false});

  final bool popToRootOnNavigate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedIndex = ref.watch(shellTabIndexProvider);
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xF0071112),
        border: Border(top: BorderSide(color: Color(0x1FFFFFFF))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const MiniPlayerBar(),
          NavigationBar(
            selectedIndex: selectedIndex,
            onDestinationSelected: (value) {
              ref.read(shellTabIndexProvider.notifier).setIndex(value);
              if (popToRootOnNavigate && Navigator.of(context).canPop()) {
                Navigator.of(context).popUntil((route) => route.isFirst);
              }
            },
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home_rounded),
                label: 'Accueil',
              ),
              NavigationDestination(
                icon: Icon(Icons.search_outlined),
                selectedIcon: Icon(Icons.search_rounded),
                label: 'Recherche',
              ),
              NavigationDestination(
                icon: Icon(Icons.library_music_outlined),
                selectedIcon: Icon(Icons.library_music_rounded),
                label: 'Bibliothèque',
              ),
              NavigationDestination(
                icon: Icon(Icons.person_outline_rounded),
                selectedIcon: Icon(Icons.person_rounded),
                label: 'Profil',
              ),
            ],
          ),
        ],
      ),
    );
  }
}
