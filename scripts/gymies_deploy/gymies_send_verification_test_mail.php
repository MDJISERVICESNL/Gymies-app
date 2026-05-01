#!/usr/bin/env php
<?php
/**
 * Stuurt één testmail met dezelfde HTML als de echte verificatiecode-mail
 * (huisthema: navy #0B1F3A, oranje #FF8A00, lichtgrijs #F2F5F9).
 *
 * Server:
 *   cd /var/www/gymies && php gymies_deploy/gymies_send_verification_test_mail.php mdjiservices@gmail.com
 *
 * Pad 1: BREVO_API_KEY (xkeysib-...) + MAIL_FROM_ADDRESS → Brevo REST API.
 * Pad 2: alleen SMTP (MAIL_MAILER=smtp + MAIL_PASSWORD=xsmtpsib-...) → zelfde HTML via Laravel Mail (zoals controller-fallback).
 */
declare(strict_types=1);

$to = $argv[1] ?? 'mdjiservices@gmail.com';
if (!filter_var($to, FILTER_VALIDATE_EMAIL)) {
    fwrite(STDERR, "Usage: php gymies_send_verification_test_mail.php [email]\n");
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
$baseUrl = rtrim((string) (config('app.url') ?: 'https://gymies.nl'), '/');

// Zelfde als GymiesAuthController::mailHtmlWrapper + sendVerificationCodeEmail inner (testcode).
$appName = $fromName;
$appNameEsc = htmlspecialchars($appName, ENT_QUOTES, 'UTF-8');
$code = '123456'; // alleen voor testmail — geen echte verificatie
$codeEsc = htmlspecialchars($code, ENT_QUOTES, 'UTF-8');
$verifyUrl = $baseUrl . '/verifieer-email?email=' . rawurlencode($to);
$verifyUrlEsc = htmlspecialchars($verifyUrl, ENT_QUOTES, 'UTF-8');
$title = 'Bevestig je e-mail';
$titleEsc = htmlspecialchars($title, ENT_QUOTES, 'UTF-8');

$textBody = "Hoi,\n\n"
    . "Dit is een TESTmail met de Gymies huistijl. Code (niet geldig): {$code}\n\n"
    . "Link: {$verifyUrl}\n\n"
    . "— Gymies testscript " . date('c') . "\n";

$inner = '<p style="margin:0 0 12px;font-size:16px;">Hoi,</p>'
    . '<p style="margin:0 0 18px;">Dit is een <strong style="color:#0B1F3A;">testmail</strong> met dezelfde opmaak als de verificatiecode na registratie.</p>'
    . '<div style="background:linear-gradient(180deg,#F8FAFC 0%,#F2F5F9 100%);border-radius:14px;padding:24px 20px;text-align:center;margin:0 0 22px;border:1px solid #E2E8F0;">'
    . '<div style="color:#5C6773;font-size:11px;text-transform:uppercase;letter-spacing:0.12em;margin-bottom:10px;">Testcode · alleen voor layout</div>'
    . '<div style="font-size:32px;font-weight:800;letter-spacing:0.4em;color:#0B1F3A;font-family:Consolas,monospace;">' . $codeEsc . '</div></div>'
    . '<p style="margin:0 0 18px;text-align:center;"><a href="' . $verifyUrlEsc . '" style="display:inline-block;background:#FF8A00;color:#ffffff;text-decoration:none;padding:16px 32px;border-radius:14px;font-weight:700;box-shadow:0 4px 14px rgba(255,138,0,0.35);">Naar verificatie (testlink)</a></p>'
    . '<p style="margin:0 0 8px;color:#5C6773;font-size:13px;">Werkt de knop niet? Kopieer deze link:</p>'
    . '<p style="margin:0 0 20px;word-break:break-all;font-size:12px;"><a href="' . $verifyUrlEsc . '" style="color:#0B1F3A;">' . $verifyUrlEsc . '</a></p>';

$htmlBody = '<!DOCTYPE html><html lang="nl"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1">'
    . '<title>' . $titleEsc . '</title></head>'
    . '<body style="margin:0;padding:0;background:#F2F5F9;font-family:Segoe UI,system-ui,-apple-system,sans-serif;">'
    . '<table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background:#F2F5F9;padding:24px 12px;">'
    . '<tr><td align="center">'
    . '<table role="presentation" width="100%" style="max-width:560px;background:#ffffff;border-radius:16px;overflow:hidden;box-shadow:0 4px 24px rgba(11,31,58,0.08);">'
    . '<tr><td style="background:linear-gradient(135deg,#0B1F3A 0%,#153a5c 100%);padding:28px 24px;text-align:center;">'
    . '<div style="color:#FF8A00;font-size:22px;font-weight:700;letter-spacing:-0.5px;">' . $appNameEsc . '</div>'
    . '<div style="color:rgba(255,255,255,0.85);font-size:14px;margin-top:6px;">' . $titleEsc . ' (test)</div></td></tr>'
    . '<tr><td style="padding:28px 24px;color:#0B1F3A;font-size:15px;line-height:1.55;">' . $inner . '</td></tr>'
    . '<tr><td style="padding:0 24px 24px;color:#5C6773;font-size:12px;line-height:1.5;">'
    . 'Je ontvangt deze mail omdat je een actie hebt gestart bij ' . $appNameEsc . '.'
    . '</td></tr></table>'
    . '<p style="color:#5C6773;font-size:11px;margin-top:16px;">© ' . date('Y') . ' ' . $appNameEsc . '</p>'
    . '</td></tr></table></body></html>';

$subject = "{$appName}: test — bevestig je e-mail (layout)";

echo "Naar: {$to}\n";
echo "BREVO_API_KEY: " . ($apiKey !== '' ? '(gezet)' : '(leeg — alleen SMTP? zie fallback)') . "\n";
echo "MAIL_FROM_ADDRESS: " . ($fromEmail !== '' ? $fromEmail : '(leeg)') . "\n";
echo "mail.default: " . (config('mail.default') ?: '(leeg)') . "\n\n";

if ($fromEmail === '' || !str_contains($fromEmail, '@')) {
    fwrite(STDERR, "MAIL_FROM_ADDRESS ontbreekt of ongeldig. Zet in .env en php artisan config:clear.\n");
    exit(2);
}

// Pad 1: Brevo API (xkeysib-...)
if ($apiKey !== '') {
try {
    $r = \Illuminate\Support\Facades\Http::withHeaders([
        'api-key' => $apiKey,
        'accept' => 'application/json',
        'content-type' => 'application/json',
    ])->timeout(15)->post('https://api.brevo.com/v3/smtp/email', [
        'sender' => ['name' => $fromName, 'email' => $fromEmail],
        'to' => [['email' => $to]],
        'subject' => $subject,
        'textContent' => $textBody,
        'htmlContent' => $htmlBody,
    ]);
    if ($r->successful()) {
        echo "OK — Brevo API 2xx. Check inbox/spam: {$to}\n";
        exit(0);
    }
    fwrite(STDERR, "Brevo API HTTP " . $r->status() . " " . $r->body() . "\n");
    exit(1);
} catch (\Throwable $e) {
    fwrite(STDERR, $e->getMessage() . "\n");
    exit(1);
}
}

// Pad 2: Laravel Mail / SMTP (xsmtpsib in MAIL_PASSWORD) — zelfde flow als GymiesAuthController::sendTransactionalMail
if (config('mail.default') && class_exists(\Illuminate\Mail\Mailer::class)) {
    try {
        \Illuminate\Support\Facades\Mail::send([], [], function ($message) use ($to, $subject, $textBody, $htmlBody): void {
            $message->to($to)->subject($subject . ' (SMTP)');
            // Symfony Mail: geen setBody(string) — html/text op underlying Email
            if (method_exists($message, 'getSymfonyMessage')) {
                $email = $message->getSymfonyMessage();
                if (method_exists($email, 'html')) {
                    $email->html($htmlBody);
                }
                if ($textBody !== '' && method_exists($email, 'text')) {
                    $email->text($textBody);
                }
            } elseif (method_exists($message, 'html')) {
                $message->html($htmlBody);
                if ($textBody !== '' && method_exists($message, 'text')) {
                    $message->text($textBody);
                }
            } else {
                throw new \RuntimeException('Mail message ondersteunt geen html-body (Symfony/Laravel mismatch).');
            }
        });
        echo "OK — Laravel Mail (SMTP). Check inbox/spam: {$to}\n";
        exit(0);
    } catch (\Throwable $e) {
        fwrite(STDERR, "SMTP/Mail faalde: " . $e->getMessage() . "\n");
    }
}

fwrite(STDERR, "Geen BREVO_API_KEY én geen werkende MAIL_MAILER/SMTP. Zet BREVO_API_KEY=xkeysib-... óf volledige SMTP in .env; daarna config:clear.\n");
exit(2);
