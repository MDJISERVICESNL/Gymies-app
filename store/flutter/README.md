# Flutter-snippets uit hoofdproject

## Imports aanpassen

`api_client.dart` importeert `../core/api_config.dart`. In een nieuw project:

- Zet `api_config.dart` en `app_build.dart` in `lib/core/` en pas import aan, **of**
- Vervang in `ApiClient` constructor: `ApiClient(baseUrl: 'https://www.gymies.nl/api/gymies')`.

## Minimale dependency

- `http` package (zoals in pubspec van hoofdproject).

## trainer_plan.dart

Importeert `../models/user.dart` – in nieuw project either:

- Kopieer `AppUser` / `subscriptionPlan` veld uit `lib/models/user.dart`, **of**
- Vervang door `String? subscriptionPlan` op je eigen user-model.

## Volledige API-wrapper

Het hoofdproject heeft `lib/services/gymies_api.dart` met alle methods – te groot om hier te dupliceren. Gebruik `routes_gymies_full.php` + `ApiClient` om endpoints incrementeel toe te voegen.
