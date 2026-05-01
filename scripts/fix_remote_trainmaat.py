#!/usr/bin/env python3
from pathlib import Path


def fix_bootstrap_app(path: Path) -> None:
    text = path.read_text()

    if "'api/trainmaat/*'" not in text:
        text = text.replace(
            "        $middleware->validateCsrfTokens(except: [\n            'tria/bonnetje/api/*',\n        ]);",
            "        $middleware->validateCsrfTokens(except: [\n            'tria/bonnetje/api/*',\n            'api/trainmaat/*',\n        ]);",
        )

    if "'trainmaat.auth'" not in text:
        text = text.replace(
            "            'mamawok.api.auth' => \\App\\Http\\Middleware\\MamawokApiAuth::class,\n            'terminology' => \\App\\Http\\Middleware\\TerminologyMiddleware::class,",
            "            'mamawok.api.auth' => \\App\\Http\\Middleware\\MamawokApiAuth::class,\n            'trainmaat.auth' => \\App\\Http\\Middleware\\TrainMaatAuthMiddleware::class,\n            'terminology' => \\App\\Http\\Middleware\\TerminologyMiddleware::class,",
        )

    path.write_text(text)


def fix_web_routes(path: Path) -> None:
    text = path.read_text()
    old = """Route::prefix('api/trainmaat')->group(function () {
    Route::post('login', [\\App\\Http\\Controllers\\TrainMaat\\TrainMaatAuthController::class, 'login']);
    Route::post('register', [\\App\\Http\\Controllers\\TrainMaat\\TrainMaatAuthController::class, 'register']);
    Route::middleware('trainmaat.auth')->group(function () {
        Route::get('me', [\\App\\Http\\Controllers\\TrainMaat\\TrainMaatAuthController::class, 'me']);
        Route::get('trainers', [\\App\\Http\\Controllers\\TrainMaat\\TrainMaatTrainerController::class, 'index']);
        Route::get('trainers/{id}', [\\App\\Http\\Controllers\\TrainMaat\\TrainMaatTrainerController::class, 'show']);
        Route::get('bookings', [\\App\\Http\\Controllers\\TrainMaat\\TrainMaatBookingController::class, 'index']);
        Route::post('bookings', [\\App\\Http\\Controllers\\TrainMaat\\TrainMaatBookingController::class, 'store']);
    });
});"""
    new = """Route::prefix('api/trainmaat')->group(function () {
    Route::post('login', [\\App\\Http\\Controllers\\TrainMaat\\TrainMaatAuthController::class, 'login']);
    Route::post('register', [\\App\\Http\\Controllers\\TrainMaat\\TrainMaatAuthController::class, 'register']);
    Route::get('trainers', [\\App\\Http\\Controllers\\TrainMaat\\TrainMaatTrainerController::class, 'index']);
    Route::get('trainers/{id}', [\\App\\Http\\Controllers\\TrainMaat\\TrainMaatTrainerController::class, 'show']);

    Route::middleware('trainmaat.auth')->group(function () {
        Route::get('me', [\\App\\Http\\Controllers\\TrainMaat\\TrainMaatAuthController::class, 'me']);
        Route::get('bookings', [\\App\\Http\\Controllers\\TrainMaat\\TrainMaatBookingController::class, 'index']);
        Route::post('bookings', [\\App\\Http\\Controllers\\TrainMaat\\TrainMaatBookingController::class, 'store']);
    });
});"""
    text = text.replace(old, new)
    path.write_text(text)


def main() -> None:
    root = Path("/var/www/mdjiservices.nl/laravel")
    fix_bootstrap_app(root / "bootstrap/app.php")
    fix_web_routes(root / "routes/web.php")
    print("TrainMaat CSRF/middleware/routes fix applied")


if __name__ == "__main__":
    main()
