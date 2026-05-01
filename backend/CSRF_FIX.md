# CSRF Token Mismatch oplossen (registreren/inloggen)

De TrainMaat API staat in **web.php**. Laravel past daar standaard **CSRF** op toe. De Flutter-app stuurt geen CSRF-token mee, dus je krijgt "419 CSRF token mismatch" bij POST (login/register).

## Oplossing: API- routes uitsluiten van CSRF

**Op de server**, in je Laravel-project:

1. Open **`app/Http/Middleware/VerifyCsrfToken.php`** (Laravel 10 of ouder)  
   of in **Laravel 11** zoek waar CSRF-middleware geregistreerd staat (bijv. `bootstrap/app.php` of een middleware-klasse).

2. Voeg de TrainMaat API-routes toe aan de **uitzonderingen**:

**Als je een klasse `VerifyCsrfToken` hebt** (vaak in `app/Http/Middleware/VerifyCsrfToken.php`):

```php
protected $except = [
    'api/trainmaat/*',
];
```

**Laravel 11** gebruikt soms geen aparte VerifyCsrfToken-klasse maar een alias. Zoek in `bootstrap/app.php` of `app/Http/Kernel.php` naar `VerifyCsrfToken` of naar de `$except`-array voor CSRF en voeg daar `'api/trainmaat/*'` aan toe.

3. Opslaan en eventueel cache legen:

```bash
cd /var/www/mdjiservices.nl/laravel
php artisan config:clear
php artisan cache:clear
```

Daarna zouden registreren en inloggen vanuit de Flutter-app weer moeten werken.
