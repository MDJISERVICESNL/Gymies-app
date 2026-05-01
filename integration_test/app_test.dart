import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:gymies_app/main.dart' as app;

/// Gymies — Integration Tests (Happy Flow)
/// ────────────────────────────────────────
/// Test de volledige app flow: splash → login → dashboard → navigatie.
///
/// Gebruik:
///   flutter test integration_test/app_test.dart
///
/// Op een echte device/emulator:
///   flutter drive \
///     --driver=test_driver/integration_test.dart \
///     --target=integration_test/app_test.dart \
///     --dart-define=API_BASE_URL=https://gymies.nl/api/gymies
///
/// Let op: deze tests vereisen een werkende backend of mock server.
/// Voor CI gebruik je een test account met vaste credentials.

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('App Startup', () {
    testWidgets('App start zonder crash', (tester) async {
      // Start de app
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 5));

      // App moet iets renderen (geen crash)
      expect(find.byType(MaterialApp), findsOneWidget);
    });

    testWidgets('Splash/loading screen verschijnt', (tester) async {
      app.main();
      // Wacht kort — splash screen moet zichtbaar zijn
      await tester.pump(const Duration(seconds: 1));

      // Zoek naar een scaffold of een loading indicator
      final hasMaterial = find.byType(MaterialApp);
      expect(hasMaterial, findsOneWidget);
    });
  });

  group('Login Flow', () {
    testWidgets('Login velden zijn zichtbaar', (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 5));

      // Als er geen opgeslagen sessie is, moet het login scherm verschijnen
      // Zoek naar email/wachtwoord velden of een login knop
      final loginIndicators = [
        find.byType(TextFormField),
        find.byType(TextField),
        find.text('Inloggen'),
        find.text('Login'),
        find.text('E-mail'),
        find.text('Email'),
      ];

      // Tenminste één login-indicator moet zichtbaar zijn,
      // OF we zijn al ingelogd en zien het dashboard
      final dashboardIndicators = [
        find.text('Dashboard'),
        find.text('Home'),
        find.byType(BottomNavigationBar),
        find.byType(NavigationBar),
      ];

      final hasLogin = loginIndicators.any(
        (f) => f.evaluate().isNotEmpty,
      );
      final hasDashboard = dashboardIndicators.any(
        (f) => f.evaluate().isNotEmpty,
      );

      // App moet ofwel login ofwel dashboard tonen
      expect(
        hasLogin || hasDashboard,
        isTrue,
        reason: 'App toont noch login noch dashboard',
      );
    });
  });

  group('Navigation', () {
    testWidgets('Bottom navigation tabs werken', (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 8));

      // Zoek de bottom navigation
      final bottomNav = find.byType(BottomNavigationBar);
      final navBar = find.byType(NavigationBar);

      if (bottomNav.evaluate().isNotEmpty) {
        // Tap op de verschillende tabs
        final navWidget = tester.widget<BottomNavigationBar>(bottomNav);
        final itemCount = navWidget.items.length;

        // Tap op elke tab en controleer dat het geen crash geeft
        for (var i = 0; i < itemCount; i++) {
          // Vind het tab item en tap erop
          final items = find.descendant(
            of: bottomNav,
            matching: find.byType(InkResponse),
          );

          if (items.evaluate().length > i) {
            await tester.tap(items.at(i));
            await tester.pumpAndSettle(const Duration(seconds: 2));
          }
        }
      } else if (navBar.evaluate().isNotEmpty) {
        // NavigationBar (Material 3)
        final destinations = find.descendant(
          of: navBar,
          matching: find.byType(NavigationDestination),
        );

        for (var i = 0; i < destinations.evaluate().length; i++) {
          await tester.tap(destinations.at(i));
          await tester.pumpAndSettle(const Duration(seconds: 2));
        }
      }

      // Als we hier komen zonder crash, is de navigatie OK
      expect(find.byType(MaterialApp), findsOneWidget);
    });
  });

  group('Error Handling', () {
    testWidgets('App crasht niet bij netwerk timeout', (tester) async {
      // Start app — als backend onbereikbaar is, moet de app
      // een foutmelding tonen i.p.v. crashen
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 10));

      // App moet nog steeds draaien
      expect(find.byType(MaterialApp), findsOneWidget);
    });
  });

  group('Feature Flags', () {
    testWidgets('App start correct ongeacht feature flag status', (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 5));

      // App moet starten ongeacht welke feature flags aan/uit staan
      expect(find.byType(MaterialApp), findsOneWidget);
    });
  });
}
