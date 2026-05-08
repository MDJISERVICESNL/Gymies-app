<?php

declare(strict_types=1);

namespace App\Helpers;

use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * GymiesMailTemplates: complete branded and standard email template system.
 *
 * Client-facing templates support trainer branding (Pro+ only).
 * Trainer-facing and auth templates use standard Gymies branding.
 * All templates return [subject, textBody, htmlBody] tuple.
 */
final class GymiesMailTemplates
{
    private const GYMIES_NAVY = '#0B1F3A';
    private const GYMIES_ORANGE = '#FF8A00';
    private const GYMIES_LIGHT_GRAY = '#F2F5F9';
    private const GYMIES_TEXT_SECONDARY = '#5C6773';

    /**
     * Branded HTML wrapper for client-facing emails with trainer branding.
     *
     * @param string $title Email title/subtitle
     * @param string $innerHtml Body content (safe HTML)
     * @param array|null $trainerBrand ['color' => '#hex', 'logo_url' => 'https://...', 'name' => 'TrainerName']
     * @param string|null $appName Brand name (e.g., "Gymies")
     * @return string Complete HTML email document
     */
    public static function brandedHtmlWrapper(
        string $title,
        string $innerHtml,
        ?array $trainerBrand = null,
        ?string $appName = null,
    ): string {
        $appName ??= GymiesNotificationEmail::mailBrandName();
        $titleEsc = htmlspecialchars($title, ENT_QUOTES, 'UTF-8');
        $appEsc = htmlspecialchars($appName, ENT_QUOTES, 'UTF-8');

        // Use trainer brand color if provided, else Gymies orange
        $brandColor = self::GYMIES_ORANGE;
        $headerBg = 'linear-gradient(135deg,' . self::GYMIES_NAVY . ' 0%,#153a5c 100%)';
        $headerLogoLeft = '';

        if ($trainerBrand !== null && !empty($trainerBrand['color'])) {
            $brandColor = htmlspecialchars((string) $trainerBrand['color'], ENT_QUOTES, 'UTF-8');
            // Gradient from trainer color to a darker version
            $headerBg = 'linear-gradient(135deg,' . $brandColor . ' 0%,' . self::darkenColor((string) $trainerBrand['color'], 0.2) . ' 100%)';

            // Add trainer logo on left if provided
            if (!empty($trainerBrand['logo_url'])) {
                $logoUrl = htmlspecialchars((string) $trainerBrand['logo_url'], ENT_QUOTES, 'UTF-8');
                $headerLogoLeft = '<img src="' . $logoUrl . '" alt="' . htmlspecialchars((string) ($trainerBrand['name'] ?? 'Trainer'), ENT_QUOTES, 'UTF-8') . '" style="width:48px;height:48px;border-radius:50%;object-fit:cover;display:inline-block;vertical-align:middle;" />'
                    . '<span style="display:inline-block;margin:0 8px;color:rgba(255,255,255,0.6);font-size:16px;">×</span>';
            }
        }

        $gymiesLogo = '<div style="width:48px;height:48px;border-radius:50%;background:#FF8A00;display:inline-flex;align-items:center;justify-content:center;font-weight:700;font-size:24px;color:white;">G</div>';

        return '<!DOCTYPE html>'
            . '<html lang="nl">'
            . '<head>'
            . '<meta charset="UTF-8">'
            . '<meta name="viewport" content="width=device-width,initial-scale=1">'
            . '<title>' . $titleEsc . '</title>'
            . '</head>'
            . '<body style="margin:0;padding:0;background:' . self::GYMIES_LIGHT_GRAY . ';font-family:Segoe UI,system-ui,-apple-system,sans-serif;">'
            . '<table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background:' . self::GYMIES_LIGHT_GRAY . ';padding:24px 12px;">'
            . '<tr><td align="center">'
            . '<table role="presentation" width="100%" style="max-width:600px;background:#ffffff;border-radius:16px;overflow:hidden;box-shadow:0 4px 24px rgba(11,31,58,0.08);">'
            . '<tr><td style="background:' . $headerBg . ';padding:28px 24px;text-align:center;">'
            . '<div style="text-align:center;margin-bottom:8px;">'
            . $headerLogoLeft
            . $gymiesLogo
            . '</div>'
            . '<div style="color:' . $brandColor . ';font-size:22px;font-weight:700;letter-spacing:-0.5px;margin-bottom:4px;">' . $appEsc . '</div>'
            . '<div style="color:rgba(255,255,255,0.85);font-size:14px;">' . $titleEsc . '</div>'
            . '</td></tr>'
            . '<tr><td style="padding:28px 24px;color:' . self::GYMIES_NAVY . ';font-size:15px;line-height:1.6;">'
            . $innerHtml
            . '</td></tr>'
            . '<tr><td style="padding:0 24px 24px;color:' . self::GYMIES_TEXT_SECONDARY . ';font-size:12px;line-height:1.5;">'
            . 'Je ontvangt deze mail omdat je een actie hebt gestart bij ' . $appEsc . '.'
            . '</td></tr>'
            . '<tr><td style="border-top:1px solid #E2E8F0;padding:16px 24px;text-align:center;color:' . self::GYMIES_TEXT_SECONDARY . ';font-size:11px;">'
            . '© ' . date('Y') . ' ' . $appEsc . ' • <a href="https://www.gymies.nl" style="color:' . self::GYMIES_TEXT_SECONDARY . ';text-decoration:none;">Gymies.nl</a>'
            . '</td></tr>'
            . '</table>'
            . '</td></tr>'
            . '</table>'
            . '</body>'
            . '</html>';
    }

    /**
     * Standard Gymies HTML wrapper (no trainer branding, used for auth + trainer emails).
     * Alias to GymiesNotificationEmail::htmlWrapper for consistency.
     */
    public static function htmlWrapper(string $title, string $innerHtml, ?string $appName = null): string
    {
        return GymiesNotificationEmail::htmlWrapper($title, $innerHtml, $appName);
    }

    // ─────────────────────────────────────────────────────────────
    // CLIENT-FACING TEMPLATES (with optional trainer branding)
    // ─────────────────────────────────────────────────────────────

    /**
     * Boeking bevestigd — trainer has confirmed the booking.
     *
     * @return array{0: string, 1: string, 2: string} [subject, textBody, htmlBody]
     */
    public static function boekingBevestigd(
        string $clientName,
        string $trainerName,
        string $scheduledAt,
        int $duration,
        ?array $trainerBrand = null,
    ): array {
        $appName = GymiesNotificationEmail::mailBrandName();
        $subject = "{$appName} – Je boeking is bevestigd!";

        $textBody = "Hoi {$clientName},\n\n"
            . "Goed nieuws! Je sessie met {$trainerName} is bevestigd.\n\n"
            . "Gepland: {$scheduledAt} ({$duration} minuten)\n\n"
            . "Tot ziens in de app!\n\n"
            . "— Team {$appName}";

        $durationEsc = htmlspecialchars((string) $duration, ENT_QUOTES, 'UTF-8');
        $clientNameEsc = htmlspecialchars($clientName, ENT_QUOTES, 'UTF-8');
        $trainerNameEsc = htmlspecialchars($trainerName, ENT_QUOTES, 'UTF-8');
        $scheduledAtEsc = htmlspecialchars($scheduledAt, ENT_QUOTES, 'UTF-8');
        $ctaUrl = htmlspecialchars(GymiesNotificationEmail::mailPublicBaseUrl() . '/boeking', ENT_QUOTES, 'UTF-8');
        $brandColor = $trainerBrand['color'] ?? self::GYMIES_ORANGE;
        $brandColorEsc = htmlspecialchars($brandColor, ENT_QUOTES, 'UTF-8');

        $innerHtml = '<p style="margin:0 0 16px;">Hoi ' . $clientNameEsc . ',</p>'
            . '<p style="margin:0 0 16px;"><strong>Goed nieuws!</strong> Je sessie met ' . $trainerNameEsc . ' is bevestigd.</p>'
            . '<div style="background:' . self::GYMIES_LIGHT_GRAY . ';border-radius:12px;padding:20px;margin:0 0 20px;border-left:4px solid ' . $brandColorEsc . ';">'
            . '<p style="margin:0 0 8px;color:' . self::GYMIES_TEXT_SECONDARY . ';font-size:12px;text-transform:uppercase;letter-spacing:0.05em;">Sessiedetails</p>'
            . '<p style="margin:0;color:' . self::GYMIES_NAVY . ';font-size:16px;font-weight:600;">' . $scheduledAtEsc . '</p>'
            . '<p style="margin:8px 0 0;color:' . self::GYMIES_TEXT_SECONDARY . ';font-size:14px;">Duur: ' . $durationEsc . ' minuten</p>'
            . '</div>'
            . '<p style="margin:0 0 20px;text-align:center;"><a href="' . $ctaUrl . '" style="display:inline-block;background:' . $brandColorEsc . ';color:#ffffff;text-decoration:none;padding:14px 32px;border-radius:12px;font-weight:600;">Open in de app</a></p>'
            . '<p style="margin:0;color:' . self::GYMIES_TEXT_SECONDARY . ';font-size:13px;">Tot ziens! — Team ' . htmlspecialchars($appName, ENT_QUOTES, 'UTF-8') . '</p>';

        $htmlBody = self::brandedHtmlWrapper('Je boeking is bevestigd!', $innerHtml, $trainerBrand, $appName);

        return [$subject, $textBody, $htmlBody];
    }

    /**
     * Boeking geannuleerd.
     *
     * @return array{0: string, 1: string, 2: string} [subject, textBody, htmlBody]
     */
    public static function boekingGeannuleerd(
        string $clientName,
        string $trainerName,
        string $reason,
        ?array $trainerBrand = null,
    ): array {
        $appName = GymiesNotificationEmail::mailBrandName();
        $subject = "{$appName} – Boeking geannuleerd";

        $textBody = "Hoi {$clientName},\n\n"
            . "Helaas is je sessie met {$trainerName} geannuleerd.\n"
            . "Reden: {$reason}\n\n"
            . "Je kunt een nieuwe sessie boeken in de app.\n\n"
            . "— Team {$appName}";

        $clientNameEsc = htmlspecialchars($clientName, ENT_QUOTES, 'UTF-8');
        $trainerNameEsc = htmlspecialchars($trainerName, ENT_QUOTES, 'UTF-8');
        $reasonEsc = htmlspecialchars($reason, ENT_QUOTES, 'UTF-8');
        $ctaUrl = htmlspecialchars(GymiesNotificationEmail::mailPublicBaseUrl() . '/boeken', ENT_QUOTES, 'UTF-8');
        $brandColor = $trainerBrand['color'] ?? self::GYMIES_ORANGE;
        $brandColorEsc = htmlspecialchars($brandColor, ENT_QUOTES, 'UTF-8');

        $innerHtml = '<p style="margin:0 0 16px;">Hoi ' . $clientNameEsc . ',</p>'
            . '<p style="margin:0 0 16px;">Helaas is je sessie met ' . $trainerNameEsc . ' geannuleerd.</p>'
            . '<p style="margin:0 0 16px;"><strong>Reden:</strong> ' . $reasonEsc . '</p>'
            . '<p style="margin:0 0 20px;">Je kunt direct een nieuwe sessie boeken in de app.</p>'
            . '<p style="margin:0 0 20px;text-align:center;"><a href="' . $ctaUrl . '" style="display:inline-block;background:' . $brandColorEsc . ';color:#ffffff;text-decoration:none;padding:14px 32px;border-radius:12px;font-weight:600;">Sessie boeken</a></p>'
            . '<p style="margin:0;color:' . self::GYMIES_TEXT_SECONDARY . ';font-size:13px;">Tot snel! — Team ' . htmlspecialchars($appName, ENT_QUOTES, 'UTF-8') . '</p>';

        $htmlBody = self::brandedHtmlWrapper('Boeking geannuleerd', $innerHtml, $trainerBrand, $appName);

        return [$subject, $textBody, $htmlBody];
    }

    /**
     * Boeking herinnering — 24 uur before session.
     *
     * @return array{0: string, 1: string, 2: string} [subject, textBody, htmlBody]
     */
    public static function boekingHerinnering(
        string $clientName,
        string $trainerName,
        string $scheduledAt,
        ?array $trainerBrand = null,
    ): array {
        $appName = GymiesNotificationEmail::mailBrandName();
        $subject = "{$appName} – Herinnering: je sessie begint morgen";

        $textBody = "Hoi {$clientName},\n\n"
            . "Herinnering: je sessie met {$trainerName} is morgen!\n\n"
            . "Tijd: {$scheduledAt}\n\n"
            . "Zorg dat je 15 minuten van tevoren in de app bent om in te checken.\n\n"
            . "— Team {$appName}";

        $clientNameEsc = htmlspecialchars($clientName, ENT_QUOTES, 'UTF-8');
        $trainerNameEsc = htmlspecialchars($trainerName, ENT_QUOTES, 'UTF-8');
        $scheduledAtEsc = htmlspecialchars($scheduledAt, ENT_QUOTES, 'UTF-8');
        $ctaUrl = htmlspecialchars(GymiesNotificationEmail::mailPublicBaseUrl() . '/boeking', ENT_QUOTES, 'UTF-8');
        $brandColor = $trainerBrand['color'] ?? self::GYMIES_ORANGE;
        $brandColorEsc = htmlspecialchars($brandColor, ENT_QUOTES, 'UTF-8');

        $innerHtml = '<p style="margin:0 0 16px;">Hoi ' . $clientNameEsc . ',</p>'
            . '<p style="margin:0 0 16px;"><strong>Herinnering:</strong> je sessie met ' . $trainerNameEsc . ' begint <strong>morgen</strong>!</p>'
            . '<div style="background:' . self::GYMIES_LIGHT_GRAY . ';border-radius:12px;padding:20px;margin:0 0 20px;border-left:4px solid ' . $brandColorEsc . ';">'
            . '<p style="margin:0;color:' . self::GYMIES_NAVY . ';font-size:16px;font-weight:600;">' . $scheduledAtEsc . '</p>'
            . '</div>'
            . '<p style="margin:0 0 16px;color:' . self::GYMIES_TEXT_SECONDARY . ';">Zorg dat je <strong>15 minuten van tevoren</strong> in de app bent om in te checken.</p>'
            . '<p style="margin:0 0 20px;text-align:center;"><a href="' . $ctaUrl . '" style="display:inline-block;background:' . $brandColorEsc . ';color:#ffffff;text-decoration:none;padding:14px 32px;border-radius:12px;font-weight:600;">Open in de app</a></p>'
            . '<p style="margin:0;color:' . self::GYMIES_TEXT_SECONDARY . ';font-size:13px;">Tot morgen! — Team ' . htmlspecialchars($appName, ENT_QUOTES, 'UTF-8') . '</p>';

        $htmlBody = self::brandedHtmlWrapper('Je sessie is morgen', $innerHtml, $trainerBrand, $appName);

        return [$subject, $textBody, $htmlBody];
    }

    /**
     * Betaling ontvangen.
     *
     * @return array{0: string, 1: string, 2: string} [subject, textBody, htmlBody]
     */
    public static function betalingOntvangen(
        string $clientName,
        string $trainerName,
        string $amount,
        ?array $trainerBrand = null,
    ): array {
        $appName = GymiesNotificationEmail::mailBrandName();
        $subject = "{$appName} – Betaling ontvangen";

        $textBody = "Hoi {$clientName},\n\n"
            . "We hebben je betaling ontvangen: {$amount}\n\n"
            . "Je sessies met {$trainerName} zijn nu geboekt.\n\n"
            . "Bedankt!\n— Team {$appName}";

        $clientNameEsc = htmlspecialchars($clientName, ENT_QUOTES, 'UTF-8');
        $trainerNameEsc = htmlspecialchars($trainerName, ENT_QUOTES, 'UTF-8');
        $amountEsc = htmlspecialchars($amount, ENT_QUOTES, 'UTF-8');
        $ctaUrl = htmlspecialchars(GymiesNotificationEmail::mailPublicBaseUrl() . '/mijn-sessies', ENT_QUOTES, 'UTF-8');
        $brandColor = $trainerBrand['color'] ?? self::GYMIES_ORANGE;
        $brandColorEsc = htmlspecialchars($brandColor, ENT_QUOTES, 'UTF-8');

        $innerHtml = '<p style="margin:0 0 16px;">Hoi ' . $clientNameEsc . ',</p>'
            . '<p style="margin:0 0 16px;"><strong>Betaling ontvangen!</strong> Bedankt.</p>'
            . '<div style="background:' . self::GYMIES_LIGHT_GRAY . ';border-radius:12px;padding:20px;margin:0 0 20px;border-left:4px solid ' . $brandColorEsc . ';">'
            . '<p style="margin:0 0 8px;color:' . self::GYMIES_TEXT_SECONDARY . ';font-size:12px;text-transform:uppercase;letter-spacing:0.05em;">Betaald bedrag</p>'
            . '<p style="margin:0;color:' . self::GYMIES_NAVY . ';font-size:24px;font-weight:700;">' . $amountEsc . '</p>'
            . '</div>'
            . '<p style="margin:0 0 16px;">Je sessies met ' . $trainerNameEsc . ' zijn nu geboekt. Je kunt ze zien in "Mijn sessies".</p>'
            . '<p style="margin:0 0 20px;text-align:center;"><a href="' . $ctaUrl . '" style="display:inline-block;background:' . $brandColorEsc . ';color:#ffffff;text-decoration:none;padding:14px 32px;border-radius:12px;font-weight:600;">Mijn sessies</a></p>'
            . '<p style="margin:0;color:' . self::GYMIES_TEXT_SECONDARY . ';font-size:13px;">Vragen? Neem contact op via de app. — Team ' . htmlspecialchars($appName, ENT_QUOTES, 'UTF-8') . '</p>';

        $htmlBody = self::brandedHtmlWrapper('Betaling ontvangen', $innerHtml, $trainerBrand, $appName);

        return [$subject, $textBody, $htmlBody];
    }

    /**
     * Boeking verlopen (geen reactie van trainer).
     *
     * @return array{0: string, 1: string, 2: string} [subject, textBody, htmlBody]
     */
    public static function boekingVerlopenGeenReactie(
        string $clientName,
        string $trainerName,
        ?array $trainerBrand = null,
    ): array {
        $appName = GymiesNotificationEmail::mailBrandName();
        $subject = "{$appName} – Boeking verlopen";

        $textBody = "Hoi {$clientName},\n\n"
            . "Helaas hebben we geen reactie gehad van {$trainerName} op je boekingsverzoek, dus is dit verzoek verlopen.\n\n"
            . "Je kunt je sessie met een andere trainer boeken.\n\n"
            . "— Team {$appName}";

        $clientNameEsc = htmlspecialchars($clientName, ENT_QUOTES, 'UTF-8');
        $trainerNameEsc = htmlspecialchars($trainerName, ENT_QUOTES, 'UTF-8');
        $ctaUrl = htmlspecialchars(GymiesNotificationEmail::mailPublicBaseUrl() . '/trainers', ENT_QUOTES, 'UTF-8');
        $brandColor = $trainerBrand['color'] ?? self::GYMIES_ORANGE;
        $brandColorEsc = htmlspecialchars($brandColor, ENT_QUOTES, 'UTF-8');

        $innerHtml = '<p style="margin:0 0 16px;">Hoi ' . $clientNameEsc . ',</p>'
            . '<p style="margin:0 0 16px;">Helaas hebben we geen reactie gehad van ' . $trainerNameEsc . ' op je boekingsverzoek. Het verzoek is nu verlopen.</p>'
            . '<p style="margin:0 0 16px;">Geen zorgen! Je kunt direct met een andere trainer een sessie boeken.</p>'
            . '<p style="margin:0 0 20px;text-align:center;"><a href="' . $ctaUrl . '" style="display:inline-block;background:' . $brandColorEsc . ';color:#ffffff;text-decoration:none;padding:14px 32px;border-radius:12px;font-weight:600;">Trainers bekijken</a></p>'
            . '<p style="margin:0;color:' . self::GYMIES_TEXT_SECONDARY . ';font-size:13px;">Vragen? Neem contact op. — Team ' . htmlspecialchars($appName, ENT_QUOTES, 'UTF-8') . '</p>';

        $htmlBody = self::brandedHtmlWrapper('Boeking verlopen', $innerHtml, $trainerBrand, $appName);

        return [$subject, $textBody, $htmlBody];
    }

    // ─────────────────────────────────────────────────────────────
    // TRAINER-FACING TEMPLATES (standard Gymies branding)
    // ─────────────────────────────────────────────────────────────

    /**
     * Nieuwe boeking — sent to trainer when client books.
     * Matches GymiesCronController::processNotificationEmails() signature.
     *
     * @return array{0: string, 1: string, 2: string} [subject, textBody, htmlBody]
     */
    public static function nieuweBoeking(
        string $trainerName,
        string $clientName,
        string $scheduledAt,
        int $duration,
        string $appName,
        string $baseUrl,
    ): array {
        $subject = "{$appName} – Nieuwe boeking van {$clientName}";

        $textBody = "Hoi {$trainerName},\n\n"
            . "Er is een nieuwe boeking binnengekomen van {$clientName}.\n\n"
            . "Gepland: {$scheduledAt} ({$duration} min)\n\n"
            . "Bevestig of wijzig de boeking in de app.\n\n"
            . "— Team {$appName}";

        $link = $baseUrl . '/trainer';
        $linkEsc = htmlspecialchars($link, ENT_QUOTES, 'UTF-8');
        $trainerNameEsc = htmlspecialchars($trainerName, ENT_QUOTES, 'UTF-8');
        $clientNameEsc = htmlspecialchars($clientName, ENT_QUOTES, 'UTF-8');
        $scheduledAtEsc = htmlspecialchars($scheduledAt, ENT_QUOTES, 'UTF-8');
        $durationEsc = htmlspecialchars((string) $duration, ENT_QUOTES, 'UTF-8');

        $innerHtml = '<p style="margin:0 0 16px;">Hoi ' . $trainerNameEsc . ',</p>'
            . '<p style="margin:0 0 16px;">Er is een <strong>nieuwe boeking</strong> binnengekomen van ' . $clientNameEsc . '.</p>'
            . '<div style="background:' . self::GYMIES_LIGHT_GRAY . ';border-radius:12px;padding:20px;margin:0 0 20px;border-left:4px solid ' . self::GYMIES_ORANGE . ';">'
            . '<p style="margin:0 0 8px;color:' . self::GYMIES_TEXT_SECONDARY . ';font-size:12px;text-transform:uppercase;letter-spacing:0.05em;">Sessiedetails</p>'
            . '<p style="margin:0;color:' . self::GYMIES_NAVY . ';font-size:16px;font-weight:600;">' . $scheduledAtEsc . '</p>'
            . '<p style="margin:8px 0 0;color:' . self::GYMIES_TEXT_SECONDARY . ';font-size:14px;">Duur: ' . $durationEsc . ' minuten</p>'
            . '</div>'
            . '<p style="margin:0 0 20px;text-align:center;"><a href="' . $linkEsc . '" style="display:inline-block;background:' . self::GYMIES_ORANGE . ';color:#ffffff;text-decoration:none;padding:14px 32px;border-radius:12px;font-weight:600;">Bevestig in de app</a></p>'
            . '<p style="margin:0;color:' . self::GYMIES_TEXT_SECONDARY . ';font-size:13px;">Met vriendelijke groet,<br>' . htmlspecialchars($appName, ENT_QUOTES, 'UTF-8') . '</p>';

        $htmlBody = self::htmlWrapper($subject, $innerHtml, $appName);

        return [$subject, $textBody, $htmlBody];
    }

    /**
     * Spoed inval aanbod.
     *
     * @param string $trainerName
     * @param int $count Number of sessions offered
     * @param string $scheduledAt First session time
     * @param string $appName
     * @param string $baseUrl
     * @return array{0: string, 1: string, 2: string} [subject, textBody, htmlBody]
     */
    public static function spoedInvalAanbod(
        string $trainerName,
        int $count,
        string $scheduledAt,
        string $appName,
        string $baseUrl,
    ): array {
        $subject = "{$appName} – Spoed inval: wil je deze sessie(s) overnemen?";

        $textBody = "Hoi {$trainerName},\n\n"
            . "Er is een spoed inval aanbod: {$count} sessie(s) om over te nemen.\n\n"
            . "Start: {$scheduledAt}\n\n"
            . "Reageer snel in de app – ja of nee.\n\n"
            . "— Team {$appName}";

        $link = $baseUrl . '/trainer';
        $linkEsc = htmlspecialchars($link, ENT_QUOTES, 'UTF-8');
        $trainerNameEsc = htmlspecialchars($trainerName, ENT_QUOTES, 'UTF-8');
        $countEsc = htmlspecialchars((string) $count, ENT_QUOTES, 'UTF-8');
        $scheduledAtEsc = htmlspecialchars($scheduledAt, ENT_QUOTES, 'UTF-8');

        $innerHtml = '<p style="margin:0 0 16px;">Hoi ' . $trainerNameEsc . ',</p>'
            . '<p style="margin:0 0 16px;"><strong>Spoed inval</strong> – ' . $countEsc . ' sessie(s) om over te nemen.</p>'
            . '<div style="background:' . self::GYMIES_LIGHT_GRAY . ';border-radius:12px;padding:20px;margin:0 0 20px;border-left:4px solid ' . self::GYMIES_ORANGE . ';">'
            . '<p style="margin:0;color:' . self::GYMIES_NAVY . ';font-size:16px;font-weight:600;">Start: ' . $scheduledAtEsc . '</p>'
            . '</div>'
            . '<p style="margin:0 0 20px;text-align:center;"><a href="' . $linkEsc . '" style="display:inline-block;background:' . self::GYMIES_ORANGE . ';color:#ffffff;text-decoration:none;padding:14px 32px;border-radius:12px;font-weight:600;">Reageer in de app</a></p>'
            . '<p style="margin:0;color:' . self::GYMIES_TEXT_SECONDARY . ';font-size:13px;">Met vriendelijke groet,<br>' . htmlspecialchars($appName, ENT_QUOTES, 'UTF-8') . '</p>';

        $htmlBody = self::htmlWrapper($subject, $innerHtml, $appName);

        return [$subject, $textBody, $htmlBody];
    }

    /**
     * Spoed inval geaccepteerd.
     *
     * @return array{0: string, 1: string, 2: string} [subject, textBody, htmlBody]
     */
    public static function spoedInvalGeaccepteerd(
        string $trainerName,
        string $substituteDisplayName,
        string $appName,
        string $baseUrl,
    ): array {
        $subject = "{$appName} – Spoed inval geaccepteerd";

        $textBody = "Hoi {$trainerName},\n\n"
            . "{$substituteDisplayName} heeft je spoed-invalverzoek geaccepteerd. De sessies zijn overgedragen.\n\n"
            . "— Team {$appName}";

        $link = $baseUrl . '/trainer';
        $linkEsc = htmlspecialchars($link, ENT_QUOTES, 'UTF-8');
        $trainerNameEsc = htmlspecialchars($trainerName, ENT_QUOTES, 'UTF-8');
        $substituteNameEsc = htmlspecialchars($substituteDisplayName, ENT_QUOTES, 'UTF-8');

        $innerHtml = '<p style="margin:0 0 16px;">Hoi ' . $trainerNameEsc . ',</p>'
            . '<p style="margin:0 0 16px;">' . $substituteNameEsc . ' heeft je spoed-invalverzoek <strong>geaccepteerd</strong>. De sessies zijn overgedragen.</p>'
            . '<p style="margin:0 0 20px;text-align:center;"><a href="' . $linkEsc . '" style="display:inline-block;background:' . self::GYMIES_ORANGE . ';color:#ffffff;text-decoration:none;padding:14px 32px;border-radius:12px;font-weight:600;">Bekijk in de app</a></p>'
            . '<p style="margin:0;color:' . self::GYMIES_TEXT_SECONDARY . ';font-size:13px;">Met vriendelijke groet,<br>' . htmlspecialchars($appName, ENT_QUOTES, 'UTF-8') . '</p>';

        $htmlBody = self::htmlWrapper($subject, $innerHtml, $appName);

        return [$subject, $textBody, $htmlBody];
    }

    /**
     * Nieuwe aanmelding groepsles.
     *
     * @return array{0: string, 1: string, 2: string} [subject, textBody, htmlBody]
     */
    public static function nieuweGroepslesAanmelding(
        string $trainerName,
        string $sessionTitle,
        string $appName,
        string $baseUrl,
    ): array {
        $subject = "{$appName} – Nieuwe aanmelding: {$sessionTitle}";

        $textBody = "Hoi {$trainerName},\n\n"
            . "Er is een nieuwe aanmelding voor je groepsles \"{$sessionTitle}\".\n\n"
            . "Bekijk de details in de app.\n\n"
            . "— Team {$appName}";

        $link = $baseUrl . '/trainer';
        $linkEsc = htmlspecialchars($link, ENT_QUOTES, 'UTF-8');
        $trainerNameEsc = htmlspecialchars($trainerName, ENT_QUOTES, 'UTF-8');
        $titleEsc = htmlspecialchars($sessionTitle, ENT_QUOTES, 'UTF-8');

        $innerHtml = '<p style="margin:0 0 16px;">Hoi ' . $trainerNameEsc . ',</p>'
            . '<p style="margin:0 0 16px;">Nieuwe aanmelding voor <strong>' . $titleEsc . '</strong>.</p>'
            . '<p style="margin:0 0 20px;text-align:center;"><a href="' . $linkEsc . '" style="display:inline-block;background:' . self::GYMIES_ORANGE . ';color:#ffffff;text-decoration:none;padding:14px 32px;border-radius:12px;font-weight:600;">Bekijk in de app</a></p>'
            . '<p style="margin:0;color:' . self::GYMIES_TEXT_SECONDARY . ';font-size:13px;">Met vriendelijke groet,<br>' . htmlspecialchars($appName, ENT_QUOTES, 'UTF-8') . '</p>';

        $htmlBody = self::htmlWrapper($subject, $innerHtml, $appName);

        return [$subject, $textBody, $htmlBody];
    }

    /**
     * Invaller gezocht.
     *
     * @return array{0: string, 1: string, 2: string} [subject, textBody, htmlBody]
     */
    public static function invallerGezocht(
        string $trainerName,
        string $sessionTitle,
        string $appName,
        string $baseUrl,
    ): array {
        $subject = "{$appName} – Invaller gezocht: {$sessionTitle}";

        $textBody = "Hoi {$trainerName},\n\n"
            . "Er is een verzoek voor een invaller voor \"{$sessionTitle}\".\n\n"
            . "Bekijk de details in de app.\n\n"
            . "— Team {$appName}";

        $link = $baseUrl . '/trainer';
        $linkEsc = htmlspecialchars($link, ENT_QUOTES, 'UTF-8');
        $trainerNameEsc = htmlspecialchars($trainerName, ENT_QUOTES, 'UTF-8');
        $titleEsc = htmlspecialchars($sessionTitle, ENT_QUOTES, 'UTF-8');

        $innerHtml = '<p style="margin:0 0 16px;">Hoi ' . $trainerNameEsc . ',</p>'
            . '<p style="margin:0 0 16px;">Invaller gezocht voor <strong>' . $titleEsc . '</strong>.</p>'
            . '<p style="margin:0 0 20px;text-align:center;"><a href="' . $linkEsc . '" style="display:inline-block;background:' . self::GYMIES_ORANGE . ';color:#ffffff;text-decoration:none;padding:14px 32px;border-radius:12px;font-weight:600;">Bekijk in de app</a></p>'
            . '<p style="margin:0;color:' . self::GYMIES_TEXT_SECONDARY . ';font-size:13px;">Met vriendelijke groet,<br>' . htmlspecialchars($appName, ENT_QUOTES, 'UTF-8') . '</p>';

        $htmlBody = self::htmlWrapper($subject, $innerHtml, $appName);

        return [$subject, $textBody, $htmlBody];
    }

    // ─────────────────────────────────────────────────────────────
    // AUTH TEMPLATES (standard Gymies branding)
    // ─────────────────────────────────────────────────────────────

    /**
     * Email verificatie code.
     *
     * @return array{0: string, 1: string, 2: string} [subject, textBody, htmlBody]
     */
    public static function verificatie(
        string $recipientName,
        string $code,
        string $appName,
        string $baseUrl,
    ): array {
        $subject = "{$appName}: bevestig je e-mail";

        $textBody = "Hoi {$recipientName},\n\n"
            . "Welkom bij {$appName}! Hier is je code om je e-mail te bevestigen:\n\n"
            . "  {$code}\n\n"
            . "De code is 15 minuten geldig.\n\n"
            . "Of ga naar {$baseUrl}/verifieer-email en vul je e-mail + code handmatig in.\n\n"
            . "Tot zo in de app — team {$appName}\n";

        $verifyUrl = $baseUrl . '/verifieer-email';
        $verifyUrlEsc = htmlspecialchars($verifyUrl, ENT_QUOTES, 'UTF-8');
        $codeEsc = htmlspecialchars($code, ENT_QUOTES, 'UTF-8');
        $recipientNameEsc = htmlspecialchars($recipientName, ENT_QUOTES, 'UTF-8');

        $codeBlock = '<div style="background:linear-gradient(180deg,#F8FAFC 0%,#F2F5F9 100%);border-radius:14px;padding:24px 20px;text-align:center;margin:0 0 22px;border:1px solid #E2E8F0;">'
            . '<div style="color:' . self::GYMIES_TEXT_SECONDARY . ';font-size:11px;text-transform:uppercase;letter-spacing:0.12em;margin-bottom:10px;">Jouw code · 15 minuten geldig</div>'
            . '<div style="font-size:32px;font-weight:800;letter-spacing:0.4em;color:' . self::GYMIES_NAVY . ';font-family:Consolas,monospace;">' . $codeEsc . '</div>'
            . '</div>';

        $innerHtml = '<p style="margin:0 0 12px;font-size:16px;">Hoi ' . $recipientNameEsc . ',</p>'
            . '<p style="margin:0 0 18px;">Welkom bij <strong style="color:' . self::GYMIES_NAVY . ';">' . htmlspecialchars($appName, ENT_QUOTES, 'UTF-8') . '</strong>. Vul de code hieronder in de app in om je account te activeren.</p>'
            . $codeBlock
            . '<p style="margin:0 0 18px;text-align:center;"><a href="' . $verifyUrlEsc . '" style="display:inline-block;background:' . self::GYMIES_ORANGE . ';color:#ffffff;text-decoration:none;padding:16px 32px;border-radius:14px;font-weight:700;box-shadow:0 4px 14px rgba(255,138,0,0.35);">Naar verificatie</a></p>'
            . '<p style="margin:0 0 8px;color:' . self::GYMIES_TEXT_SECONDARY . ';font-size:13px;">Werkt de knop niet? Kopieer deze link:</p>'
            . '<p style="margin:0 0 20px;word-break:break-all;font-size:12px;"><a href="' . $verifyUrlEsc . '" style="color:' . self::GYMIES_NAVY . ';">' . $verifyUrlEsc . '</a></p>'
            . '<p style="margin:0;color:' . self::GYMIES_TEXT_SECONDARY . ';font-size:13px;">Nieuwe code nodig? In de app: <strong>Code opnieuw sturen</strong>.</p>';

        $htmlBody = self::htmlWrapper('Bevestig je e-mail', $innerHtml, $appName);

        return [$subject, $textBody, $htmlBody];
    }

    /**
     * Wachtwoord reset.
     *
     * @return array{0: string, 1: string, 2: string} [subject, textBody, htmlBody]
     */
    public static function wachtwoordReset(
        string $recipientName,
        string $resetUrl,
        string $appName,
        string $baseUrl,
    ): array {
        $subject = "Wachtwoord resetten – {$appName}";

        $textBody = "Hallo {$recipientName},\n\n"
            . "Je hebt een link aangevraagd om je wachtwoord te resetten voor {$appName}.\n\n"
            . "Open deze link:\n{$resetUrl}\n\n"
            . "Deze link is 1 uur geldig.\n\n"
            . "Met vriendelijke groet,\n{$appName}";

        $resetUrlEsc = htmlspecialchars($resetUrl, ENT_QUOTES, 'UTF-8');
        $recipientNameEsc = htmlspecialchars($recipientName, ENT_QUOTES, 'UTF-8');

        $innerHtml = '<p style="margin:0 0 16px;">Hoi ' . $recipientNameEsc . ',</p>'
            . '<p style="margin:0 0 16px;">Je hebt een wachtwoordreset aangevraagd. Klik op de knop om een nieuw wachtwoord in te stellen.</p>'
            . '<p style="margin:0 0 20px;"><a href="' . $resetUrlEsc . '" style="display:inline-block;background:' . self::GYMIES_ORANGE . ';color:#ffffff;text-decoration:none;padding:14px 28px;border-radius:12px;font-weight:600;">Nieuw wachtwoord instellen</a></p>'
            . '<p style="margin:0 0 8px;color:' . self::GYMIES_TEXT_SECONDARY . ';font-size:13px;">Werkt de knop niet? Kopieer deze link in je browser:</p>'
            . '<p style="margin:0;word-break:break-all;font-size:13px;"><a href="' . $resetUrlEsc . '" style="color:' . self::GYMIES_NAVY . ';">' . $resetUrlEsc . '</a></p>'
            . '<p style="margin:20px 0 0;color:' . self::GYMIES_TEXT_SECONDARY . ';font-size:13px;">Deze link is <strong>1 uur</strong> geldig.</p>';

        $htmlBody = self::htmlWrapper($subject, $innerHtml, $appName);

        return [$subject, $textBody, $htmlBody];
    }

    // ─────────────────────────────────────────────────────────────
    // ADMIN + GYM TEMPLATES (standard Gymies branding)
    // ─────────────────────────────────────────────────────────────

    /**
     * Admin: ticket antwoord notification.
     *
     * @return array{0: string, 1: string, 2: string} [subject, textBody, htmlBody]
     */
    public static function ticketAntwoord(
        string $recipientName,
        string $ticketId,
        string $appName,
        string $baseUrl,
    ): array {
        $subject = "{$appName} – Antwoord op je supportticket #{$ticketId}";

        $textBody = "Hoi {$recipientName},\n\n"
            . "Er is een nieuw antwoord op je supportticket #{$ticketId}.\n\n"
            . "Bekijk het antwoord in de app.\n\n"
            . "— Team {$appName}";

        $link = $baseUrl . '/support';
        $linkEsc = htmlspecialchars($link, ENT_QUOTES, 'UTF-8');
        $recipientNameEsc = htmlspecialchars($recipientName, ENT_QUOTES, 'UTF-8');
        $ticketIdEsc = htmlspecialchars($ticketId, ENT_QUOTES, 'UTF-8');

        $innerHtml = '<p style="margin:0 0 16px;">Hoi ' . $recipientNameEsc . ',</p>'
            . '<p style="margin:0 0 16px;">Er is een nieuw antwoord op je supportticket <strong>#' . $ticketIdEsc . '</strong>.</p>'
            . '<p style="margin:0 0 20px;text-align:center;"><a href="' . $linkEsc . '" style="display:inline-block;background:' . self::GYMIES_ORANGE . ';color:#ffffff;text-decoration:none;padding:14px 32px;border-radius:12px;font-weight:600;">Bekijk het antwoord</a></p>'
            . '<p style="margin:0;color:' . self::GYMIES_TEXT_SECONDARY . ';font-size:13px;">— Team ' . htmlspecialchars($appName, ENT_QUOTES, 'UTF-8') . '</p>';

        $htmlBody = self::htmlWrapper($subject, $innerHtml, $appName);

        return [$subject, $textBody, $htmlBody];
    }

    /**
     * Gym: welkomsmail na registratie.
     *
     * @return array{0: string, 1: string, 2: string} [subject, textBody, htmlBody]
     */
    public static function gymWelkom(
        string $gymName,
        string $appName,
        string $baseUrl,
    ): array {
        $subject = "Welkom bij {$appName}, {$gymName}!";

        $textBody = "Hallo {$gymName},\n\n"
            . "Welkom bij {$appName}! Je account is klaar.\n\n"
            . "Log in op {$baseUrl} om je trainingsstudio in te richten.\n\n"
            . "— Team {$appName}";

        $link = htmlspecialchars($baseUrl, ENT_QUOTES, 'UTF-8');
        $gymNameEsc = htmlspecialchars($gymName, ENT_QUOTES, 'UTF-8');

        $innerHtml = '<p style="margin:0 0 16px;">Hallo ' . $gymNameEsc . ',</p>'
            . '<p style="margin:0 0 16px;">Welkom bij <strong>' . htmlspecialchars($appName, ENT_QUOTES, 'UTF-8') . '</strong>! Je account is klaar.</p>'
            . '<p style="margin:0 0 20px;">Log in om je trainingsstudio in te richten en je eerste trainers uit te nodigen.</p>'
            . '<p style="margin:0 0 20px;text-align:center;"><a href="' . $link . '" style="display:inline-block;background:' . self::GYMIES_ORANGE . ';color:#ffffff;text-decoration:none;padding:14px 32px;border-radius:12px;font-weight:600;">Inloggen</a></p>'
            . '<p style="margin:0;color:' . self::GYMIES_TEXT_SECONDARY . ';font-size:13px;">Vragen? Neem contact op. — Team ' . htmlspecialchars($appName, ENT_QUOTES, 'UTF-8') . '</p>';

        $htmlBody = self::htmlWrapper($subject, $innerHtml, $appName);

        return [$subject, $textBody, $htmlBody];
    }

    /**
     * Gym: demo bevestiging.
     *
     * @return array{0: string, 1: string, 2: string} [subject, textBody, htmlBody]
     */
    public static function gymDemoBevestiging(
        string $gymName,
        string $demoDateTime,
        string $appName,
        string $baseUrl,
    ): array {
        $subject = "{$appName} – Demo gepland: {$demoDateTime}";

        $textBody = "Hallo {$gymName},\n\n"
            . "Je demo is bevestigd voor {$demoDateTime}.\n\n"
            . "We kijken uit naar het gesprek!\n\n"
            . "— Team {$appName}";

        $link = htmlspecialchars($baseUrl, ENT_QUOTES, 'UTF-8');
        $gymNameEsc = htmlspecialchars($gymName, ENT_QUOTES, 'UTF-8');
        $demoDateTimeEsc = htmlspecialchars($demoDateTime, ENT_QUOTES, 'UTF-8');

        $innerHtml = '<p style="margin:0 0 16px;">Hallo ' . $gymNameEsc . ',</p>'
            . '<p style="margin:0 0 16px;">Je demo is <strong>bevestigd</strong> voor <strong>' . $demoDateTimeEsc . '</strong>.</p>'
            . '<p style="margin:0 0 20px;">We kijken uit naar het gesprek en willen je graag alles over ' . htmlspecialchars($appName, ENT_QUOTES, 'UTF-8') . ' laten zien!</p>'
            . '<p style="margin:0 0 20px;text-align:center;"><a href="' . $link . '" style="display:inline-block;background:' . self::GYMIES_ORANGE . ';color:#ffffff;text-decoration:none;padding:14px 32px;border-radius:12px;font-weight:600;">Meer info</a></p>'
            . '<p style="margin:0;color:' . self::GYMIES_TEXT_SECONDARY . ';font-size:13px;">Tot ziens! — Team ' . htmlspecialchars($appName, ENT_QUOTES, 'UTF-8') . '</p>';

        $htmlBody = self::htmlWrapper($subject, $innerHtml, $appName);

        return [$subject, $textBody, $htmlBody];
    }

    /**
     * Admin: nieuwe demo aanvraag notification.
     *
     * @return array{0: string, 1: string, 2: string} [subject, textBody, htmlBody]
     */
    public static function adminNieuweDemoAanvraag(
        string $gymName,
        string $contactEmail,
        string $appName,
        string $adminUrl,
    ): array {
        $subject = "{$appName} – Nieuwe demo aanvraag van {$gymName}";

        $textBody = "Hallo,\n\n"
            . "Er is een nieuwe demo aanvraag binnengekomen van {$gymName} ({$contactEmail}).\n\n"
            . "Bekijk de details en plan een moment in.\n\n"
            . "— Admin Alert";

        $link = htmlspecialchars($adminUrl, ENT_QUOTES, 'UTF-8');
        $gymNameEsc = htmlspecialchars($gymName, ENT_QUOTES, 'UTF-8');
        $contactEmailEsc = htmlspecialchars($contactEmail, ENT_QUOTES, 'UTF-8');

        $innerHtml = '<p style="margin:0 0 16px;">Hallo,</p>'
            . '<p style="margin:0 0 16px;">Er is een <strong>nieuwe demo aanvraag</strong> binnengekomen van <strong>' . $gymNameEsc . '</strong>.</p>'
            . '<p style="margin:0 0 16px;">Contactperson: ' . $contactEmailEsc . '</p>'
            . '<p style="margin:0 0 20px;text-align:center;"><a href="' . $link . '" style="display:inline-block;background:' . self::GYMIES_ORANGE . ';color:#ffffff;text-decoration:none;padding:14px 32px;border-radius:12px;font-weight:600;">Bekijk in admin</a></p>'
            . '<p style="margin:0;color:' . self::GYMIES_TEXT_SECONDARY . ';font-size:13px;">— ' . htmlspecialchars($appName, ENT_QUOTES, 'UTF-8') . ' Admin</p>';

        $htmlBody = self::htmlWrapper($subject, $innerHtml, $appName);

        return [$subject, $textBody, $htmlBody];
    }

    /**
     * Gym: trainer uitnodiging.
     *
     * @return array{0: string, 1: string, 2: string} [subject, textBody, htmlBody]
     */
    public static function gymTrainerInvite(
        string $trainerName,
        string $gymName,
        string $inviteUrl,
        string $appName,
    ): array {
        $subject = "{$appName} – {$gymName} nodigt je uit als trainer";

        $textBody = "Hallo {$trainerName},\n\n"
            . "{$gymName} nodigt je uit om trainer te worden op het {$appName} platform!\n\n"
            . "Accepteer de uitnodiging via deze link:\n{$inviteUrl}\n\n"
            . "Tot ziens op het platform!\n\n"
            . "— Team {$appName}";

        $inviteUrlEsc = htmlspecialchars($inviteUrl, ENT_QUOTES, 'UTF-8');
        $trainerNameEsc = htmlspecialchars($trainerName, ENT_QUOTES, 'UTF-8');
        $gymNameEsc = htmlspecialchars($gymName, ENT_QUOTES, 'UTF-8');

        $innerHtml = '<p style="margin:0 0 16px;">Hallo ' . $trainerNameEsc . ',</p>'
            . '<p style="margin:0 0 16px;"><strong>' . $gymNameEsc . '</strong> nodigt je uit om trainer te worden op het ' . htmlspecialchars($appName, ENT_QUOTES, 'UTF-8') . ' platform!</p>'
            . '<p style="margin:0 0 20px;text-align:center;"><a href="' . $inviteUrlEsc . '" style="display:inline-block;background:' . self::GYMIES_ORANGE . ';color:#ffffff;text-decoration:none;padding:14px 32px;border-radius:12px;font-weight:600;">Accepteer uitnodiging</a></p>'
            . '<p style="margin:0 0 8px;color:' . self::GYMIES_TEXT_SECONDARY . ';font-size:13px;">Werkt de knop niet? Kopieer deze link:</p>'
            . '<p style="margin:0;word-break:break-all;font-size:12px;"><a href="' . $inviteUrlEsc . '" style="color:' . self::GYMIES_NAVY . ';">' . $inviteUrlEsc . '</a></p>';

        $htmlBody = self::htmlWrapper($subject, $innerHtml, $appName);

        return [$subject, $textBody, $htmlBody];
    }

    /**
     * Gym: aanvraag goedgekeurd — met registratielink (deep link naar app).
     *
     * @param string $contactName  Naam van de contactpersoon
     * @param string $gymName      Naam van de gym/studio
     * @param string $token        64-hex invite token
     * @param string $expiresInDays Aantal dagen geldig (bijv. "14")
     * @param string $appName      App brand name
     * @param string $baseUrl      Public base URL
     * @return array{0: string, 1: string, 2: string} [subject, textBody, htmlBody]
     */
    public static function gymAanvraagGoedgekeurd(
        string $contactName,
        string $gymName,
        string $token,
        string $expiresInDays,
        string $appName,
        string $baseUrl,
    ): array {
        $subject = "{$appName} – Je aanvraag voor {$gymName} is goedgekeurd!";

        // Deep link die de app opent op het gym-registratiescherm
        $deepLink = "gymies://gym/register?token=" . urlencode($token);
        // Fallback web URL voor als de app niet geïnstalleerd is
        $webLink  = rtrim($baseUrl, '/') . "/gym/register?token=" . urlencode($token);

        $textBody = "Hallo {$contactName},\n\n"
            . "Goed nieuws! Je aanvraag voor {$gymName} is goedgekeurd.\n\n"
            . "Klik op de onderstaande link om je registratie af te ronden:\n"
            . "{$webLink}\n\n"
            . "Of open de Gymies app en gebruik deze link:\n"
            . "{$deepLink}\n\n"
            . "Deze link is {$expiresInDays} dagen geldig.\n\n"
            . "— Team {$appName}";

        $contactNameEsc = htmlspecialchars($contactName, ENT_QUOTES, 'UTF-8');
        $gymNameEsc     = htmlspecialchars($gymName, ENT_QUOTES, 'UTF-8');
        $deepLinkEsc    = htmlspecialchars($deepLink, ENT_QUOTES, 'UTF-8');
        $webLinkEsc     = htmlspecialchars($webLink, ENT_QUOTES, 'UTF-8');

        $innerHtml = '<p style="margin:0 0 16px;">Hallo ' . $contactNameEsc . ',</p>'
            . '<p style="margin:0 0 16px;"><strong>Goed nieuws!</strong> Je aanvraag voor <strong>' . $gymNameEsc . '</strong> is goedgekeurd. Rond nu je registratie af om je gym op het platform te krijgen.</p>'
            . '<p style="margin:0 0 8px;text-align:center;">'
            .   '<a href="' . $deepLinkEsc . '" style="display:inline-block;background:' . self::GYMIES_ORANGE . ';color:#ffffff;text-decoration:none;padding:14px 32px;border-radius:12px;font-weight:600;">Registratie afronden in de app</a>'
            . '</p>'
            . '<p style="margin:0 0 20px;text-align:center;font-size:13px;color:' . self::GYMIES_TEXT_SECONDARY . ';">'
            .   'Werkt de knop niet? <a href="' . $webLinkEsc . '" style="color:' . self::GYMIES_ORANGE . ';">Open via de browser</a>'
            . '</p>'
            . '<p style="margin:0 0 8px;color:' . self::GYMIES_TEXT_SECONDARY . ';font-size:13px;">Deze link is <strong>' . htmlspecialchars($expiresInDays, ENT_QUOTES, 'UTF-8') . ' dagen</strong> geldig.</p>'
            . '<p style="margin:0;color:' . self::GYMIES_TEXT_SECONDARY . ';font-size:13px;">Welkom bij het platform! — Team ' . htmlspecialchars($appName, ENT_QUOTES, 'UTF-8') . '</p>';

        $htmlBody = self::htmlWrapper($subject, $innerHtml, $appName);

        return [$subject, $textBody, $htmlBody];
    }

    /**
     * Gym: aanvraag afgewezen.
     *
     * @return array{0: string, 1: string, 2: string} [subject, textBody, htmlBody]
     */
    public static function gymAanvraagAfgewezen(
        string $contactName,
        string $gymName,
        string $reason,
        string $appName,
        string $baseUrl,
    ): array {
        $subject = "{$appName} – Aanvraag niet goedgekeurd";

        $textBody = "Hallo {$contactName},\n\n"
            . "Helaas kunnen we je aanvraag voor {$gymName} niet goedkeuren.\n"
            . "Reden: {$reason}\n\n"
            . "Neem contact op als je meer wilt weten: {$baseUrl}\n\n"
            . "— Team {$appName}";

        $contactNameEsc = htmlspecialchars($contactName, ENT_QUOTES, 'UTF-8');
        $gymNameEsc     = htmlspecialchars($gymName, ENT_QUOTES, 'UTF-8');
        $reasonEsc      = htmlspecialchars($reason, ENT_QUOTES, 'UTF-8');

        $innerHtml = '<p style="margin:0 0 16px;">Hallo ' . $contactNameEsc . ',</p>'
            . '<p style="margin:0 0 16px;">Helaas kunnen we je aanvraag voor <strong>' . $gymNameEsc . '</strong> niet goedkeuren.</p>'
            . '<p style="margin:0 0 16px;"><strong>Reden:</strong> ' . $reasonEsc . '</p>'
            . '<p style="margin:0;color:' . self::GYMIES_TEXT_SECONDARY . ';font-size:13px;">Neem contact op als je meer wilt weten. — Team ' . htmlspecialchars($appName, ENT_QUOTES, 'UTF-8') . '</p>';

        $htmlBody = self::htmlWrapper($subject, $innerHtml, $appName);

        return [$subject, $textBody, $htmlBody];
    }

    // ─────────────────────────────────────────────────────────────
    // ONBOARDING: trainer notification emails
    // ─────────────────────────────────────────────────────────────

    /** Onboarding: welkom na registratie. */
    public static function welcomeOnboarding(string $trainerName): array
    {
        $subject = 'GYMIES — Welkom bij het platform!';
        $text = "Hey {$trainerName},\n\nWelkom bij Gymies! We zijn blij dat je erbij bent.\n\nRond je aanmelding af in de app om je gratis proefperiode te starten. "
            . "Upload je documenten, kies je plan en dien je aanvraag in — ons team beoordeelt het binnen 24 uur.\n\nSucces!\nTeam Gymies";
        $inner = '<p style="font-size:16px;">Hey ' . e($trainerName) . ',</p>'
            . '<p>Welkom bij Gymies! We zijn blij dat je erbij bent.</p>'
            . '<p>Rond je aanmelding af in de app om je <strong>gratis proefperiode</strong> te starten:</p>'
            . '<ol><li>Upload je documenten (KvK, VOG, diploma\'s)</li><li>Kies je plan en factureringscyclus</li><li>Dien je aanvraag in</li></ol>'
            . '<p>Ons team beoordeelt je aanvraag binnen 24 uur.</p>'
            . '<p style="margin-top:24px;"><a href="https://gymies.nl/app" style="background:#FF8A00;color:#fff;padding:12px 24px;border-radius:8px;text-decoration:none;font-weight:600;">Open de app</a></p>';
        $html = self::htmlWrapper('Welkom bij Gymies! 🎉', $inner);
        return [$subject, $text, $html];
    }

    /** Onboarding: aanvraag goedgekeurd. */
    public static function onboardingApproved(string $trainerName): array
    {
        $subject = 'GYMIES — Je aanvraag is goedgekeurd!';
        $text = "Hey {$trainerName},\n\nGeweldig nieuws! Je aanvraag is goedgekeurd door ons team.\n\n"
            . "Open de app om je betaling af te ronden (€0,01 mandaat) en je proefperiode te starten.\n\nTeam Gymies";
        $inner = '<p style="font-size:16px;">Hey ' . e($trainerName) . ',</p>'
            . '<p><strong>Geweldig nieuws!</strong> Je aanvraag is goedgekeurd door ons team. 🎉</p>'
            . '<p>Nog één stap: rond je betaling af in de app om je proefperiode te starten.</p>'
            . '<p style="margin-top:24px;"><a href="https://gymies.nl/app" style="background:#FF8A00;color:#fff;padding:12px 24px;border-radius:8px;text-decoration:none;font-weight:600;">Betaling afronden</a></p>';
        $html = self::htmlWrapper('Aanvraag goedgekeurd!', $inner);
        return [$subject, $text, $html];
    }

    /** Onboarding: aanvraag afgewezen. */
    public static function onboardingRejected(string $trainerName, string $reason): array
    {
        $subject = 'GYMIES — Je aanvraag is niet goedgekeurd';
        $text = "Hey {$trainerName},\n\nHelaas is je aanvraag niet goedgekeurd.\n\nReden: {$reason}\n\n"
            . "Je kunt je gegevens aanpassen en opnieuw indienen via de app.\n\nTeam Gymies";
        $inner = '<p style="font-size:16px;">Hey ' . e($trainerName) . ',</p>'
            . '<p>Helaas is je aanvraag niet goedgekeurd.</p>'
            . '<p><strong>Reden:</strong> ' . e($reason) . '</p>'
            . '<p>Je kunt je gegevens aanpassen en opnieuw indienen via de app.</p>'
            . '<p style="margin-top:24px;"><a href="https://gymies.nl/app" style="background:#0B1F3A;color:#fff;padding:12px 24px;border-radius:8px;text-decoration:none;font-weight:600;">Aanvraag aanpassen</a></p>';
        $html = self::htmlWrapper('Aanvraag niet goedgekeurd', $inner);
        return [$subject, $text, $html];
    }

    /** Trial: bijna afgelopen (3 dagen). */
    public static function trialExpiringSoon(string $trainerName, int $daysLeft): array
    {
        $subject = "GYMIES — Nog {$daysLeft} dagen in je proefperiode";
        $text = "Hey {$trainerName},\n\nJe proefperiode loopt over {$daysLeft} dagen af.\n\n"
            . "Zorg dat je etalage klaar is en je eerste sessies gepland hebt!\n\nTeam Gymies";
        $inner = '<p style="font-size:16px;">Hey ' . e($trainerName) . ',</p>'
            . '<p>Je proefperiode loopt over <strong>' . $daysLeft . ' dagen</strong> af.</p>'
            . '<p>Tips om het meeste eruit te halen:</p>'
            . '<ul><li>Vul je etalage volledig in</li><li>Stel je beschikbaarheid in</li><li>Deel je profiel met potentiële klanten</li></ul>';
        $html = self::htmlWrapper('Proefperiode loopt bijna af ⏰', $inner);
        return [$subject, $text, $html];
    }

    /** Betaalherinnering: mandaat niet afgerond. */
    public static function paymentReminder(string $trainerName, int $attempt): array
    {
        $urgency = $attempt >= 3 ? 'Laatste herinnering: ' : '';
        $subject = "GYMIES — {$urgency}Betaling afronden";
        $text = "Hey {$trainerName},\n\nJe betaling is nog niet afgerond. Rond het af in de app om actief te blijven.\n\nTeam Gymies";
        $inner = '<p style="font-size:16px;">Hey ' . e($trainerName) . ',</p>'
            . '<p>Je betaling is nog niet afgerond. Rond het af om je account actief te houden.</p>'
            . '<p style="margin-top:24px;"><a href="https://gymies.nl/app" style="background:#FF8A00;color:#fff;padding:12px 24px;border-radius:8px;text-decoration:none;font-weight:600;">Betaling afronden</a></p>';
        $html = self::htmlWrapper('Betaling afronden', $inner);
        return [$subject, $text, $html];
    }

    /** Onboarding herinnering: 24u na registratie, onboarding incompleet. */
    public static function onboardingReminder24h(string $trainerName): array
    {
        $subject = 'GYMIES — Maak je aanmelding af';
        $text = "Hey {$trainerName},\n\nJe bent gisteren begonnen met je aanmelding maar hebt deze nog niet afgerond.\n\n"
            . "Het duurt maar 5 minuten — open de app en ga verder.\n\nTeam Gymies";
        $inner = '<p style="font-size:16px;">Hey ' . e($trainerName) . ',</p>'
            . '<p>Je bent gisteren begonnen met je aanmelding maar hebt deze nog niet afgerond.</p>'
            . '<p>Het duurt maar <strong>5 minuten</strong> — upload je documenten en kies je plan.</p>'
            . '<p style="margin-top:24px;"><a href="https://gymies.nl/app" style="background:#FF8A00;color:#fff;padding:12px 24px;border-radius:8px;text-decoration:none;font-weight:600;">Aanmelding afronden</a></p>';
        $html = self::htmlWrapper('Je aanmelding wacht op je!', $inner);
        return [$subject, $text, $html];
    }

    /** Onboarding nudge: 72u na registratie, nog steeds incompleet. */
    public static function onboardingNudge72h(string $trainerName): array
    {
        $subject = 'GYMIES — Start je gratis proefperiode';
        $text = "Hey {$trainerName},\n\nJe aanmelding bij Gymies is nog niet compleet.\n\n"
            . "Wist je dat je gratis kunt starten? Rond je aanmelding af en ontdek het platform.\n\nTeam Gymies";
        $inner = '<p style="font-size:16px;">Hey ' . e($trainerName) . ',</p>'
            . '<p>Je aanmelding bij Gymies is nog niet compleet.</p>'
            . '<p>Wist je dat je <strong>gratis</strong> kunt starten? Rond je aanmelding af en ontdek:</p>'
            . '<ul><li>Je eigen professionele etalagepagina</li><li>Online boekingen en betalingen</li><li>Chat met klanten</li></ul>'
            . '<p style="margin-top:24px;"><a href="https://gymies.nl/app" style="background:#FF8A00;color:#fff;padding:12px 24px;border-radius:8px;text-decoration:none;font-weight:600;">Nu starten</a></p>';
        $html = self::htmlWrapper('Start je gratis proefperiode 💪', $inner);
        return [$subject, $text, $html];
    }

    // ─────────────────────────────────────────────────────────────
    // UTILITY: darken hex color for gradient
    // ─────────────────────────────────────────────────────────────

    /**
     * Darken a hex color by a percentage factor.
     * @param string $hex Hex color like #FF8A00
     * @param float $factor 0.2 = 20% darker
     * @return string Darkened hex color
     */
    private static function darkenColor(string $hex, float $factor): string
    {
        $hex = ltrim($hex, '#');
        if (strlen($hex) !== 6) {
            return $hex;
        }
        $r = (int) hexdec(substr($hex, 0, 2));
        $g = (int) hexdec(substr($hex, 2, 2));
        $b = (int) hexdec(substr($hex, 4, 2));

        $r = (int) ($r * (1 - $factor));
        $g = (int) ($g * (1 - $factor));
        $b = (int) ($b * (1 - $factor));

        return '#' . strtoupper(
            str_pad(dechex($r), 2, '0', STR_PAD_LEFT)
            . str_pad(dechex($g), 2, '0', STR_PAD_LEFT)
            . str_pad(dechex($b), 2, '0', STR_PAD_LEFT)
        );
    }
}
