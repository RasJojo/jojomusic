import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:mobile/main.dart' as app;
import 'package:mobile/src/ui/widgets/jojo_surfaces.dart';

const _testEmail = 'ci_test_jojomusique@mailinator.com';
const _testPassword = 'TestCI2026!';
const _screenshotDir = '/tmp/jojo_smoke';

Future<void> _pump(WidgetTester t, int times, [int ms = 100]) async {
  for (int i = 0; i < times; i++) {
    await t.pump(Duration(milliseconds: ms));
  }
}

Future<void> _shot(
  IntegrationTestWidgetsFlutterBinding binding,
  String name,
) async {
  final bytes = await binding.takeScreenshot(name);
  final dir = Directory(_screenshotDir);
  if (!dir.existsSync()) dir.createSync(recursive: true);
  File('$_screenshotDir/$name.png').writeAsBytesSync(bytes);
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Flow complet : login → accueil → lecture → recherche',
      (tester) async {
    app.main();

    // Wait for bootstrap + login screen
    await _pump(tester, 80); // 8s
    await _shot(binding, '01_demarrage');

    // ── Login ──────────────────────────────────────────────────────────────
    final textFields = find.byType(TextField);
    if (textFields.evaluate().isNotEmpty) {
      await tester.tap(textFields.at(0));
      await _pump(tester, 5);
      await tester.enterText(textFields.at(0), _testEmail);
      await _pump(tester, 5);

      if (textFields.evaluate().length >= 2) {
        await tester.tap(textFields.at(1));
        await _pump(tester, 5);
        await tester.enterText(textFields.at(1), _testPassword);
        await _pump(tester, 5);
      }

      await _shot(binding, '02_login_rempli');

      final loginBtn = find.byType(FilledButton);
      if (loginBtn.evaluate().isNotEmpty) {
        await tester.tap(loginBtn.first);
        await _pump(tester, 150); // 15s for network + navigation
        await _shot(binding, '03_apres_login');
      }
    } else {
      await _shot(binding, '03_deja_connecte');
    }

    // ── Lecture depuis l'accueil ────────────────────────────────────────────
    // Scroll down on home until "Lancer" button appears
    final homeList = find.byType(ListView);
    if (homeList.evaluate().isNotEmpty) {
      // Scroll down incrementally until "Lancer" text is visible
      for (int i = 0; i < 8; i++) {
        await tester.drag(homeList.first, const Offset(0, -300));
        await _pump(tester, 5);
        if (find.text('Lancer').evaluate().isNotEmpty) break;
      }
      // Scroll a bit more to bring "Lancer" away from the bottom nav bar
      await tester.drag(homeList.first, const Offset(0, -280));
      await _pump(tester, 10);
      await _shot(binding, '04_scroll_accueil');

      final lancerBtn = find.text('Lancer');
      if (lancerBtn.evaluate().isNotEmpty) {
        await tester.tap(lancerBtn.first, warnIfMissed: false);
        await _pump(tester, 200); // 20s for stream resolve + playback
        await _shot(binding, '05_lecture_lancee');
      } else {
        // Fallback: tap first visible JojoPosterCard
        final cards = find.byType(JojoPosterCard);
        if (cards.evaluate().isNotEmpty) {
          await tester.tap(cards.first, warnIfMissed: false);
          await _pump(tester, 80);
          await _shot(binding, '05_collection_ouverte');
        }
      }
    }

    // ── Recherche ──────────────────────────────────────────────────────────
    final rechercheTab = find.text('Recherche');
    if (rechercheTab.evaluate().isNotEmpty) {
      await tester.tap(rechercheTab.first);
      await _pump(tester, 20);
      await _shot(binding, '06_onglet_recherche');

      final searchField = find.byType(TextField);
      if (searchField.evaluate().isNotEmpty) {
        await tester.tap(searchField.first);
        await _pump(tester, 5);
        await tester.enterText(searchField.first, 'Daft Punk');
        await _pump(tester, 80); // 8s for search results
        await _shot(binding, '07_resultats_recherche');
      }
    }

    await _shot(binding, '08_final');
  });
}
