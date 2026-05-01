<?php

declare(strict_types=1);

namespace App\Http\Controllers\Gymies;

use App\Http\Controllers\Controller;
use Illuminate\Http\Response;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * SEO: dynamische sitemap met trainer-profielen.
 * Nginx moet /sitemap.xml naar Laravel routeren (zie deploy/nginx-gymies.conf).
 */
final class GymiesSeoController extends Controller
{
    private const BASE_URL = 'https://www.gymies.nl';

    /** Statische pagina's (zelfde als SeoConfig.sitemapPaths). */
    private const STATIC_PATHS = [
        ['path' => '', 'priority' => '1.0', 'changefreq' => 'weekly'],
        ['path' => '/zoeken', 'priority' => '0.95', 'changefreq' => 'daily'],
        ['path' => '/personal-trainer-amsterdam', 'priority' => '0.9', 'changefreq' => 'weekly'],
        ['path' => '/voor-trainers', 'priority' => '0.9', 'changefreq' => 'weekly'],
        ['path' => '/zoekengroepslessen', 'priority' => '0.85', 'changefreq' => 'weekly'],
        ['path' => '/over-ons', 'priority' => '0.8', 'changefreq' => 'monthly'],
        ['path' => '/hoe-het-werkt', 'priority' => '0.8', 'changefreq' => 'monthly'],
        ['path' => '/faq', 'priority' => '0.75', 'changefreq' => 'monthly'],
        ['path' => '/contact', 'priority' => '0.75', 'changefreq' => 'monthly'],
        ['path' => '/algemene-voorwaarden', 'priority' => '0.4', 'changefreq' => 'yearly'],
        ['path' => '/cookiebeleid', 'priority' => '0.35', 'changefreq' => 'yearly'],
        ['path' => '/privacy', 'priority' => '0.4', 'changefreq' => 'yearly'],
    ];

    public function sitemap(): Response
    {
        $lastmod = now()->format('Y-m-d');
        $xml = '<?xml version="1.0" encoding="UTF-8"?>' . "\n";
        $xml .= '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">' . "\n";

        foreach (self::STATIC_PATHS as $p) {
            $loc = self::BASE_URL . ($p['path'] === '' ? '/' : $p['path']);
            $xml .= "  <url>\n";
            $xml .= "    <loc>" . htmlspecialchars($loc, ENT_XML1) . "</loc>\n";
            $xml .= "    <lastmod>{$lastmod}</lastmod>\n";
            $xml .= "    <changefreq>{$p['changefreq']}</changefreq>\n";
            $xml .= "    <priority>{$p['priority']}</priority>\n";
            $xml .= "  </url>\n";
        }

        if (Schema::hasTable('gymies_users') && Schema::hasTable('gymies_trainer_profiles')) {
            $trainers = DB::table('gymies_users as u')
                ->join('gymies_trainer_profiles as p', 'u.id', '=', 'p.user_id')
                ->where('u.role', 'trainer')
                ->where(function ($q) {
                    $q->whereNull('p.moderation_status')->orWhere('p.moderation_status', 'approved');
                })
                ->select('u.id')
                ->limit(5000)
                ->get();
            foreach ($trainers as $t) {
                $loc = self::BASE_URL . '/trainer-profiel/' . (int) $t->id;
                $xml .= "  <url>\n";
                $xml .= "    <loc>" . htmlspecialchars($loc, ENT_XML1) . "</loc>\n";
                $xml .= "    <lastmod>{$lastmod}</lastmod>\n";
                $xml .= "    <changefreq>weekly</changefreq>\n";
                $xml .= "    <priority>0.8</priority>\n";
                $xml .= "  </url>\n";
            }
        }

        $xml .= '</urlset>';

        return response($xml, 200, [
            'Content-Type' => 'application/xml; charset=UTF-8',
            'Cache-Control' => 'public, max-age=3600',
        ]);
    }
}
