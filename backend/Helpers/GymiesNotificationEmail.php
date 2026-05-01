<?php

declare(strict_types=1);

namespace App\Helpers;

use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Mail;

/**
 * Verstuur transactionele e-mails voor notificaties (Brevo API of Laravel Mail).
 * Gebruikt dezelfde gegevensbronnen als de verificatiemail: GYMIES_MAIL_BRAND, GYMIES_PUBLIC_URL.
 * Gebruikt door de notification-email cron.
 */
final class GymiesNotificationEmail
{
    private static ?string $brevoApiKey = null;

    /**
     * Merknaam in mails. Zelfde logica als GymiesAuthController::mailBrandName().
     * .env: GYMIES_MAIL_BRAND of config mail.from.name, fallback "Gymies".
     */
    public static function mailBrandName(): string
    {
        $n = trim((string) env('GYMIES_MAIL_BRAND', ''));
        if ($n !== '') {
            return $n;
        }
        $fromName = trim((string) (config('mail.from.name') ?? ''));
        if ($fromName !== '' && !preg_match('/^laravel$/i', $fromName)) {
            return $fromName;
        }
        return 'Gymies';
    }

    /**
     * Basis-URL voor links in mails. Zelfde logica als GymiesAuthController::mailPublicBaseUrl().
     * .env: GYMIES_PUBLIC_URL; voorkomt http://IP/... in de inbox.
     */
    public static function mailPublicBaseUrl(): string
    {
        $forced = rtrim(trim((string) env('GYMIES_PUBLIC_URL', '')), '/');
        if ($forced !== '') {
            return $forced;
        }
        $url = rtrim((string) config('app.url', ''), '/');
        if ($url === '' || str_contains($url, 'localhost')) {
            return 'https://www.gymies.nl';
        }
        if (preg_match('#^https?://(\d{1,3}\.){3}\d{1,3}(:\d+)?#', $url)) {
            return 'https://www.gymies.nl';
        }
        if (preg_match('#^http://(gymies\.nl|www\.gymies\.nl)#i', $url)) {
            return preg_replace('#^http://#i', 'https://', $url);
        }
        return $url;
    }

    public static function send(string $toEmail, string $subject, string $textBody, ?string $htmlBody = null): bool
    {
        if (self::sendViaBrevo($toEmail, $subject, $textBody, $htmlBody)) {
            return true;
        }
        try {
            if (config('mail.default') && class_exists(\Illuminate\Mail\Mailer::class)) {
                if ($htmlBody !== null && $htmlBody !== '') {
                    Mail::send([], [], function ($message) use ($toEmail, $subject, $textBody, $htmlBody): void {
                        $message->to($toEmail)->subject($subject);
                        self::applyMailHtmlAndText($message, $htmlBody, $textBody);
                    });
                } else {
                    Mail::raw($textBody, function ($message) use ($toEmail, $subject): void {
                        $message->to($toEmail)->subject($subject);
                    });
                }
                return true;
            }
        } catch (\Throwable $e) {
            if (function_exists('logger')) {
                logger()->warning('Gymies notification email send failed', ['email' => $toEmail, 'error' => $e->getMessage()]);
            }
        }
        return false;
    }

    private static function applyMailHtmlAndText(object $message, string $htmlBody, string $textBody): void
    {
        if (method_exists($message, 'getSymfonyMessage')) {
            $email = $message->getSymfonyMessage();
            if (method_exists($email, 'html')) {
                $email->html($htmlBody);
            }
            if ($textBody !== '' && method_exists($email, 'text')) {
                $email->text($textBody);
            }
            return;
        }
        if (method_exists($message, 'html')) {
            $message->html($htmlBody);
            if ($textBody !== '' && method_exists($message, 'text')) {
                $message->text($textBody);
            }
            return;
        }
        if (function_exists('logger')) {
            logger()->warning('Gymies notification mail: kon html/text niet zetten');
        }
    }

    private static function sendViaBrevo(string $toEmail, string $subject, string $textBody, ?string $htmlBody = null): bool
    {
        $apiKey = self::brevoApiKey();
        if ($apiKey === null) {
            return false;
        }
        $fromEmail = (string) (config('mail.from.address') ?: env('MAIL_FROM_ADDRESS', ''));
        $fromName = self::mailBrandName();
        if ($fromEmail === '' || !str_contains($fromEmail, '@')) {
            return false;
        }
        $payload = [
            'sender' => ['name' => $fromName, 'email' => $fromEmail],
            'to' => [['email' => $toEmail]],
            'subject' => $subject,
            'textContent' => $textBody,
        ];
        if ($htmlBody !== null && $htmlBody !== '') {
            $payload['htmlContent'] = $htmlBody;
        }
        try {
            $response = Http::withHeaders([
                'api-key' => $apiKey,
                'accept' => 'application/json',
                'content-type' => 'application/json',
            ])->timeout(15)->post('https://api.brevo.com/v3/smtp/email', $payload);
            if ($response->successful()) {
                return true;
            }
            if (function_exists('logger')) {
                logger()->warning('Brevo API notification email failed', [
                    'email' => $toEmail,
                    'status' => $response->status(),
                    'body' => $response->body(),
                ]);
            }
        } catch (\Throwable $e) {
            if (function_exists('logger')) {
                logger()->warning('Brevo API exception', ['email' => $toEmail, 'error' => $e->getMessage()]);
            }
        }
        return false;
    }

    private static function brevoApiKey(): ?string
    {
        if (self::$brevoApiKey === null) {
            $key = trim((string) (config('services.brevo.api_key') ?? env('BREVO_API_KEY', '')));
            self::$brevoApiKey = $key !== '' ? $key : '';
        }
        return self::$brevoApiKey !== '' ? self::$brevoApiKey : null;
    }

    /**
     * Gymies thema: navy #0B1F3A, oranje #FF8A00.
     * Zelfde footer-stijl als verificatiemail.
     */
    public static function htmlWrapper(string $title, string $innerHtml, ?string $appName = null): string
    {
        $titleEsc = htmlspecialchars($title, ENT_QUOTES, 'UTF-8');
        $appEsc = htmlspecialchars($appName ?? self::mailBrandName(), ENT_QUOTES, 'UTF-8');
        return '<!DOCTYPE html><html lang="nl"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1">'
            . '<title>' . $titleEsc . '</title></head>'
            . '<body style="margin:0;padding:0;background:#F2F5F9;font-family:Segoe UI,system-ui,-apple-system,sans-serif;">'
            . '<table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background:#F2F5F9;padding:24px 12px;">'
            . '<tr><td align="center">'
            . '<table role="presentation" width="100%" style="max-width:560px;background:#ffffff;border-radius:16px;overflow:hidden;box-shadow:0 4px 24px rgba(11,31,58,0.08);">'
            . '<tr><td style="background:linear-gradient(135deg,#0B1F3A 0%,#153a5c 100%);padding:28px 24px;text-align:center;">'
            . '<div style="color:#FF8A00;font-size:22px;font-weight:700;letter-spacing:-0.5px;">' . $appEsc . '</div>'
            . '<div style="color:rgba(255,255,255,0.85);font-size:14px;margin-top:6px;">' . $titleEsc . '</div></td></tr>'
            . '<tr><td style="padding:28px 24px;color:#0B1F3A;font-size:15px;line-height:1.55;">' . $innerHtml . '</td></tr>'
            . '<tr><td style="padding:0 24px 24px;color:#5C6773;font-size:12px;line-height:1.5;">'
            . 'Je ontvangt deze mail omdat je een actie hebt gestart bij ' . $appEsc . '.'
            . '</td></tr></table>'
            . '<p style="color:#5C6773;font-size:11px;margin-top:16px;">© ' . date('Y') . ' ' . $appEsc . '</p>'
            . '</td></tr></table></body></html>';
    }
}
