#!/usr/bin/env php
<?php
/**
 * Test of Laravel-mail (zelfde pipeline als verificatiecode-mail).
 * Server: cd /var/www/gymies && php gymies_deploy/gymies_send_test_mail.php jouw@email.nl
 *
 * Controleer daarna:
 * - Geen exception = Mail::raw is aangeroepen (SMTP/Brevo moet in .env staan).
 * - Mail ontvangen = transport werkt.
 * - Geen mail maar ook geen error = mail.default niet gezet → code valt terug op log-only (zoals verify-email).
 */
declare(strict_types=1);

$to = $argv[1] ?? '';
if ($to === '' || !filter_var($to, FILTER_VALIDATE_EMAIL)) {
    fwrite(STDERR, "Usage: php gymies_send_test_mail.php <geldig@email-adres>\n");
    fwrite(STDERR, "Run vanuit Laravel-root (waar vendor/ en bootstrap/ staan).\n");
    exit(1);
}

$baseDir = dirname(__DIR__);
if (!is_file($baseDir . '/vendor/autoload.php')) {
    fwrite(STDERR, "vendor/autoload.php niet gevonden. Run vanuit project-root of zet baseDir goed.\n");
    exit(1);
}

require $baseDir . '/vendor/autoload.php';
$app = require_once $baseDir . '/bootstrap/app.php';
$app->make(\Illuminate\Contracts\Console\Kernel::class)->bootstrap();

$appName = config('app.name', 'Gymies');
$mailDefault = config('mail.default');
echo "app.name: {$appName}\n";
echo "mail.default: " . ($mailDefault ?: '(leeg — Mail wordt niet verstuurd, alleen log)') . "\n";
echo "app.url: " . config('app.url') . "\n\n";

try {
    if (!$mailDefault || !class_exists(\Illuminate\Mail\Mailer::class)) {
        fwrite(STDERR, "Geen mail driver geconfigureerd. Zet in .env o.a. MAIL_MAILER=smtp en Brevo/SMTP vars.\n");
        exit(2);
    }
    \Illuminate\Support\Facades\Mail::raw(
        "Dit is een testmail van {$appName}.\n\nAls je dit leest, werkt het versturen.\nTijd: " . date('c'),
        function ($message) use ($to, $appName): void {
            $message->to($to)->subject("Testmail {$appName}");
        }
    );
    echo "OK — Mail::raw afgerond zonder exception. Controleer inbox (en spam) voor: {$to}\n";
} catch (\Throwable $e) {
    fwrite(STDERR, "FOUT: " . $e->getMessage() . "\n");
    exit(1);
}
