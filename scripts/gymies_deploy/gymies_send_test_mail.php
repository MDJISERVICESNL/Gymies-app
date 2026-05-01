#!/usr/bin/env php
<?php
/**
 * Testmail — Brevo API (BREVO_API_KEY) eerst, anders Laravel Mail (SMTP).
 * Server: cd /var/www/gymies && php gymies_deploy/gymies_send_test_mail.php jouw@email.nl
 */
declare(strict_types=1);

$to = $argv[1] ?? '';
if ($to === '' || !filter_var($to, FILTER_VALIDATE_EMAIL)) {
    fwrite(STDERR, "Usage: php gymies_send_test_mail.php <email>\n");
    exit(1);
}

$baseDir = dirname(__DIR__);
if (!is_file($baseDir . '/vendor/autoload.php')) {
    $baseDir = getcwd();
}
if (!is_file($baseDir . '/vendor/autoload.php')) {
    fwrite(STDERR, "Kan vendor/autoload niet vinden. cd naar Laravel-root.\n");
    exit(1);
}

require $baseDir . '/vendor/autoload.php';
$app = require_once $baseDir . '/bootstrap/app.php';
$app->make(\Illuminate\Contracts\Console\Kernel::class)->bootstrap();

$apiKey = trim((string) env('BREVO_API_KEY', ''));
$fromEmail = (string) (config('mail.from.address') ?: env('MAIL_FROM_ADDRESS', ''));
$fromName = (string) (config('mail.from.name') ?: config('app.name', 'Gymies'));

echo "BREVO_API_KEY: " . ($apiKey !== '' ? '(gezet)' : '(leeg)') . "\n";
echo "mail.default: " . (config('mail.default') ?: '(leeg)') . "\n";
echo "MAIL_FROM_ADDRESS: " . ($fromEmail !== '' ? $fromEmail : '(leeg — vereist voor Brevo API)') . "\n\n";

if ($apiKey !== '' && $fromEmail !== '' && str_contains($fromEmail, '@')) {
    try {
        $r = \Illuminate\Support\Facades\Http::withHeaders([
            'api-key' => $apiKey,
            'accept' => 'application/json',
            'content-type' => 'application/json',
        ])->timeout(15)->post('https://api.brevo.com/v3/smtp/email', [
            'sender' => ['name' => $fromName, 'email' => $fromEmail],
            'to' => [['email' => $to]],
            'subject' => 'Gymies testmail (Brevo API)',
            'textContent' => "Test via Brevo API " . date('c'),
        ]);
        if ($r->successful()) {
            echo "OK — Brevo API 2xx. Check inbox/spam: {$to}\n";
            exit(0);
        }
        fwrite(STDERR, "Brevo API HTTP " . $r->status() . " " . $r->body() . "\n");
    } catch (\Throwable $e) {
        fwrite(STDERR, "Brevo API: " . $e->getMessage() . "\n");
    }
}

if (!config('mail.default')) {
    fwrite(STDERR, "Geen BREVO_API_KEY+FROM of MAIL_MAILER — geen mail verstuurd.\n");
    exit(2);
}

try {
    \Illuminate\Support\Facades\Mail::raw(
        "Testmail Gymies " . date('c'),
        function ($m) use ($to): void {
            $m->to($to)->subject('Gymies testmail (SMTP)');
        }
    );
    echo "OK — SMTP Mail::raw. Check inbox/spam: {$to}\n";
} catch (\Throwable $e) {
    fwrite(STDERR, $e->getMessage() . "\n");
    exit(1);
}
