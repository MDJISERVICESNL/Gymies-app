<?php

declare(strict_types=1);

namespace App\Http\Controllers\Gymies;

use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Eénmalige schema-”self-heal” zodat endpoints geen 503 geven als migraties nog niet zijn gedraaid.
 * Roept idempotente CREATE/ALTER alleen uit als kolom/tabel ontbreekt.
 */
final class GymiesSchemaEnsure
{
    /**
     * T-058 FIXED: file-based lock voorkomt schema race condition
     * Gelijktijdige CREATE TABLE IF NOT EXISTS aanroepen kunnen race condition veroorzaken.
     * Deze helper zorgt dat maar één instantie tegelijk schema aanpassingen doet.
     */
    private static function withSchemaMutex(callable $callback): mixed
    {
        $lockFile = sys_get_temp_dir() . '/gymies_schema_ensure.lock';
        $lockHandle = fopen($lockFile, 'c');
        if ($lockHandle === false) {
            // Kan lock niet aanmaken, voer callback uit zonder lock
            return $callback();
        }
        if (!flock($lockHandle, LOCK_EX | LOCK_NB)) {
            // Andere instantie is bezig, skip deze aanroep
            fclose($lockHandle);
            return null;
        }
        try {
            return $callback();
        } finally {
            flock($lockHandle, LOCK_UN);
            fclose($lockHandle);
        }
    }

    public static function referralsTable(): void
    {
        if (Schema::hasTable('gymies_referrals')) {
            // Zorg voor nieuwe kolommen als ze ontbreken
            self::referralsTableEnsureColumns();
            return;
        }
        // T-058 FIXED: race condition voorkomen
        self::withSchemaMutex(function () {
            // Double-check na lock verkregen
            if (Schema::hasTable('gymies_referrals')) {
                return;
            }
            try {
                DB::unprepared("
CREATE TABLE IF NOT EXISTS gymies_referrals (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  referrer_user_id BIGINT UNSIGNED NOT NULL,
  referred_user_id BIGINT UNSIGNED DEFAULT NULL,
  referred_email VARCHAR(255) DEFAULT NULL,
  referral_code VARCHAR(64) NOT NULL,
  permanent TINYINT(1) NOT NULL DEFAULT 0,
  max_uses INT UNSIGNED DEFAULT NULL,
  uses_count INT UNSIGNED NOT NULL DEFAULT 0,
  expires_at TIMESTAMP NULL DEFAULT NULL,
  used_at TIMESTAMP NULL DEFAULT NULL,
  status ENUM('pending', 'active', 'completed', 'expired') NOT NULL DEFAULT 'pending',
  reward_cents INT UNSIGNED DEFAULT NULL,
  rewarded_at TIMESTAMP NULL DEFAULT NULL,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY gymies_referrals_code (referral_code),
  KEY gymies_referrals_referrer (referrer_user_id),
  KEY gymies_referrals_permanent (permanent),
  CONSTRAINT gymies_referrals_referrer_fk
    FOREIGN KEY (referrer_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE,
  CONSTRAINT gymies_referrals_referred_fk
    FOREIGN KEY (referred_user_id) REFERENCES gymies_users (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
                ");
            } catch (\Throwable) {
                // FK kan falen als gymies_users ontbreekt; dan blijft 503 bij caller
            }
        });
    }

    private static function referralsTableEnsureColumns(): void
    {
        if (!Schema::hasTable('gymies_referrals')) {
            return;
        }

        // Voeg permanent kolom toe
        if (!Schema::hasColumn('gymies_referrals', 'permanent')) {
            try {
                DB::statement('ALTER TABLE gymies_referrals ADD COLUMN permanent TINYINT(1) NOT NULL DEFAULT 0');
            } catch (\Throwable) {
            }
        }

        // Voeg max_uses kolom toe
        if (!Schema::hasColumn('gymies_referrals', 'max_uses')) {
            try {
                DB::statement('ALTER TABLE gymies_referrals ADD COLUMN max_uses INT UNSIGNED DEFAULT NULL');
            } catch (\Throwable) {
            }
        }

        // Voeg uses_count kolom toe
        if (!Schema::hasColumn('gymies_referrals', 'uses_count')) {
            try {
                DB::statement('ALTER TABLE gymies_referrals ADD COLUMN uses_count INT UNSIGNED NOT NULL DEFAULT 0');
            } catch (\Throwable) {
            }
        }

        // Voeg expires_at kolom toe
        if (!Schema::hasColumn('gymies_referrals', 'expires_at')) {
            try {
                DB::statement('ALTER TABLE gymies_referrals ADD COLUMN expires_at TIMESTAMP NULL DEFAULT NULL');
            } catch (\Throwable) {
            }
        }

        // Voeg used_at kolom toe
        if (!Schema::hasColumn('gymies_referrals', 'used_at')) {
            try {
                DB::statement('ALTER TABLE gymies_referrals ADD COLUMN used_at TIMESTAMP NULL DEFAULT NULL');
            } catch (\Throwable) {
            }
        }

        // Voeg 'active' status toe aan ENUM als die nog niet bestaat
        try {
            DB::statement("ALTER TABLE gymies_referrals MODIFY COLUMN status ENUM('pending', 'active', 'completed', 'expired') NOT NULL DEFAULT 'pending'");
        } catch (\Throwable) {
            // Al aangepast of fout
        }

        // Voeg index toe op permanent kolom
        if (!Schema::hasIndexes('gymies_referrals', ['permanent'])) {
            try {
                DB::statement('ALTER TABLE gymies_referrals ADD KEY gymies_referrals_permanent (permanent)');
            } catch (\Throwable) {
            }
        }
    }

    public static function groupSessionsStatusColumn(): bool
    {
        if (!Schema::hasTable('gymies_group_sessions')) {
            return false;
        }
        if (Schema::hasColumn('gymies_group_sessions', 'status')) {
            return true;
        }
        try {
            DB::statement("
ALTER TABLE gymies_group_sessions
  ADD COLUMN status ENUM('draft','collecting','confirmed_by_trainer','cancelled','completed')
  NOT NULL DEFAULT 'draft'
            ");
            return Schema::hasColumn('gymies_group_sessions', 'status');
        } catch (\Throwable) {
            return false;
        }
    }

    public static function groupSessionParticipantsWaitlistEnum(): void
    {
        if (!Schema::hasTable('gymies_group_session_participants')) {
            return;
        }
        // MODIFY kan falen als al juist — negeren
        try {
            DB::statement("
ALTER TABLE gymies_group_session_participants
  MODIFY COLUMN status ENUM('pending','registered','payment_pending','confirmed','cancelled','waitlist')
  NOT NULL DEFAULT 'pending'
            ");
        } catch (\Throwable) {
        }
    }

    public static function documentUploadsTableAndColumns(): bool
    {
        if (!Schema::hasTable('gymies_document_uploads')) {
            try {
                DB::unprepared("
CREATE TABLE IF NOT EXISTS gymies_document_uploads (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id BIGINT UNSIGNED NOT NULL,
  type ENUM('insurance','id','contract','certificate','other') NOT NULL DEFAULT 'other',
  file_url VARCHAR(512) NOT NULL,
  verified_at TIMESTAMP NULL DEFAULT NULL,
  verified_by_user_id BIGINT UNSIGNED DEFAULT NULL,
  expires_at DATE DEFAULT NULL,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY gymies_document_uploads_user (user_id),
  CONSTRAINT gymies_document_uploads_user_fk
    FOREIGN KEY (user_id) REFERENCES gymies_users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
                ");
            } catch (\Throwable) {
                return false;
            }
        }
        if (!Schema::hasColumn('gymies_document_uploads', 'document_category')) {
            try {
                DB::statement('ALTER TABLE gymies_document_uploads ADD COLUMN document_category VARCHAR(32) DEFAULT NULL');
            } catch (\Throwable) {
            }
        }
        if (!Schema::hasColumn('gymies_document_uploads', 'original_filename')) {
            try {
                DB::statement('ALTER TABLE gymies_document_uploads ADD COLUMN original_filename VARCHAR(255) DEFAULT NULL');
            } catch (\Throwable) {
            }
        }
        if (!Schema::hasColumn('gymies_document_uploads', 'mime_type')) {
            try {
                DB::statement('ALTER TABLE gymies_document_uploads ADD COLUMN mime_type VARCHAR(128) DEFAULT NULL');
            } catch (\Throwable) {
            }
        }
        if (!Schema::hasColumn('gymies_document_uploads', 'file_size_bytes')) {
            try {
                DB::statement('ALTER TABLE gymies_document_uploads ADD COLUMN file_size_bytes INT UNSIGNED DEFAULT NULL');
            } catch (\Throwable) {
            }
        }
        if (!Schema::hasColumn('gymies_document_uploads', 'rejected_at')) {
            try {
                DB::statement('ALTER TABLE gymies_document_uploads ADD COLUMN rejected_at TIMESTAMP NULL DEFAULT NULL');
            } catch (\Throwable) {
            }
        }
        if (!Schema::hasColumn('gymies_document_uploads', 'rejection_reason')) {
            try {
                DB::statement('ALTER TABLE gymies_document_uploads ADD COLUMN rejection_reason VARCHAR(500) DEFAULT NULL');
            } catch (\Throwable) {
            }
        }

        return Schema::hasTable('gymies_document_uploads')
            && Schema::hasColumn('gymies_document_uploads', 'document_category');
    }

    public static function bookingsCheckinColumns(): bool
    {
        if (!Schema::hasTable('gymies_bookings')) {
            return false;
        }
        $columns = [
            'checkin_token' => 'VARCHAR(64) DEFAULT NULL',
            'checkin_token_expires_at' => 'TIMESTAMP NULL DEFAULT NULL',
            'checkin_backup_code' => 'VARCHAR(6) DEFAULT NULL',
            'check_in_at' => 'TIMESTAMP NULL DEFAULT NULL',
            'check_in_method' => 'VARCHAR(16) DEFAULT NULL',
        ];
        foreach ($columns as $col => $def) {
            if (!Schema::hasColumn('gymies_bookings', $col)) {
                try {
                    DB::statement("ALTER TABLE gymies_bookings ADD COLUMN {$col} {$def}");
                } catch (\Throwable) {
                    return false;
                }
            }
        }
        return Schema::hasColumn('gymies_bookings', 'checkin_token');
    }

    public static function sosAlertsTable(): bool
    {
        if (Schema::hasTable('gymies_sos_alerts')) {
            return true;
        }
        try {
            DB::unprepared("
CREATE TABLE IF NOT EXISTS gymies_sos_alerts (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id BIGINT UNSIGNED NOT NULL,
  booking_id BIGINT UNSIGNED DEFAULT NULL,
  latitude DECIMAL(10,7) NOT NULL,
  longitude DECIMAL(10,7) NOT NULL,
  status VARCHAR(32) NOT NULL DEFAULT 'active',
  resolved_by_user_id BIGINT UNSIGNED DEFAULT NULL,
  resolved_at TIMESTAMP NULL DEFAULT NULL,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY gymies_sos_alerts_user (user_id),
  KEY gymies_sos_alerts_status (status),
  CONSTRAINT gymies_sos_alerts_user_fk FOREIGN KEY (user_id) REFERENCES gymies_users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            ");
        } catch (\Throwable) {
            return false;
        }
        return Schema::hasTable('gymies_sos_alerts');
    }

    public static function bookingsSafeSessionColumns(): bool
    {
        if (!Schema::hasTable('gymies_bookings')) {
            return false;
        }
        foreach ([
            'safe_session_active' => 'TINYINT(1) NOT NULL DEFAULT 0',
            'safe_session_started_at' => 'TIMESTAMP NULL DEFAULT NULL',
            'check_out_at' => 'TIMESTAMP NULL DEFAULT NULL',
        ] as $col => $def) {
            if (!Schema::hasColumn('gymies_bookings', $col)) {
                try {
                    DB::statement("ALTER TABLE gymies_bookings ADD COLUMN {$col} {$def}");
                } catch (\Throwable) {
                    return false;
                }
            }
        }
        return Schema::hasColumn('gymies_bookings', 'safe_session_active');
    }

    /**
     * gymies_client_dossier + optioneel share-kolommen (alter_gymies_client_dossier + alter_gymies_client_dossier_share_with_client).
     */
    public static function clientDossierTableAndShareColumns(): bool
    {
        if (!Schema::hasTable('gymies_client_dossier')) {
            try {
                $sqlFile = (function_exists('base_path') ? base_path('database/alter_gymies_client_dossier.sql') : '');
                if ($sqlFile !== '' && is_readable($sqlFile)) {
                    DB::unprepared((string) file_get_contents($sqlFile));
                } else {
                    throw new \RuntimeException('skip');
                }
            } catch (\Throwable) {
                // fallback minimaal
                try {
                    DB::unprepared("
CREATE TABLE IF NOT EXISTS gymies_client_dossier (
  trainer_user_id BIGINT UNSIGNED NOT NULL,
  client_user_id BIGINT UNSIGNED NOT NULL,
  internal_notes TEXT DEFAULT NULL,
  medical_background TEXT DEFAULT NULL,
  goals_long_term TEXT DEFAULT NULL,
  updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (trainer_user_id, client_user_id),
  KEY gymies_client_dossier_client (client_user_id),
  CONSTRAINT gymies_client_dossier_trainer_fk FOREIGN KEY (trainer_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE,
  CONSTRAINT gymies_client_dossier_client_fk FOREIGN KEY (client_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
                    ");
                } catch (\Throwable) {
                    return false;
                }
            }
        }
        if (!Schema::hasTable('gymies_client_dossier')) {
            return false;
        }
        foreach ([
            'shared_with_client_at' => 'TIMESTAMP NULL DEFAULT NULL',
            'client_facing_summary' => 'TEXT DEFAULT NULL',
        ] as $col => $def) {
            if (!Schema::hasColumn('gymies_client_dossier', $col)) {
                try {
                    DB::statement("ALTER TABLE gymies_client_dossier ADD COLUMN {$col} {$def}");
                } catch (\Throwable) {
                }
            }
        }
        return true;
    }

    public static function clientProgressTable(): bool
    {
        if (Schema::hasTable('gymies_client_progress')) {
            return true;
        }
        try {
            DB::unprepared("
CREATE TABLE IF NOT EXISTS gymies_client_progress (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  client_user_id BIGINT UNSIGNED NOT NULL,
  trainer_user_id BIGINT UNSIGNED NOT NULL,
  type VARCHAR(32) NOT NULL,
  value TEXT NOT NULL,
  note VARCHAR(500) DEFAULT NULL,
  is_private TINYINT(1) NOT NULL DEFAULT 0,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY gymies_client_progress_client_trainer (client_user_id, trainer_user_id),
  CONSTRAINT gymies_client_progress_client_fk FOREIGN KEY (client_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE,
  CONSTRAINT gymies_client_progress_trainer_fk FOREIGN KEY (trainer_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            ");
        } catch (\Throwable) {
            return false;
        }
        return Schema::hasTable('gymies_client_progress');
    }

    /**
     * gymies_promo_codes.trainer_user_id toevoegen indien ontbreekt (alter_gymies_promo_codes_trainer.sql).
     */
    public static function promoCodesTrainerColumn(): void
    {
        if (!Schema::hasTable('gymies_promo_codes')) {
            return;
        }
        if (Schema::hasColumn('gymies_promo_codes', 'trainer_user_id')) {
            return;
        }
        try {
            DB::statement('ALTER TABLE gymies_promo_codes ADD COLUMN trainer_user_id BIGINT UNSIGNED NULL DEFAULT NULL AFTER id');
        } catch (\Throwable) {
        }
        try {
            DB::statement('ALTER TABLE gymies_promo_codes ADD KEY gymies_promo_codes_trainer (trainer_user_id)');
        } catch (\Throwable) {
        }
        try {
            DB::statement('ALTER TABLE gymies_promo_codes ADD CONSTRAINT gymies_promo_codes_trainer_fk FOREIGN KEY (trainer_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE');
        } catch (\Throwable) {
        }
    }

    /**
     * Klant-favorieten: trainers als favoriet (gymies_favorites).
     */
    public static function favoritesTable(): bool
    {
        if (Schema::hasTable('gymies_favorites')) {
            return true;
        }
        try {
            DB::unprepared("
CREATE TABLE IF NOT EXISTS gymies_favorites (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  client_user_id BIGINT UNSIGNED NOT NULL,
  trainer_user_id BIGINT UNSIGNED NOT NULL,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY gymies_favorites_unique (client_user_id, trainer_user_id),
  KEY gymies_favorites_client (client_user_id),
  KEY gymies_favorites_trainer (trainer_user_id),
  CONSTRAINT gymies_favorites_client_fk
    FOREIGN KEY (client_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE,
  CONSTRAINT gymies_favorites_trainer_fk
    FOREIGN KEY (trainer_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            ");
        } catch (\Throwable) {
            return false;
        }
        return Schema::hasTable('gymies_favorites');
    }

    /**
     * Buddy Matcher: zoekvoorkeuren (is_searching, preferred_trainer_id).
     */
    public static function buddySearchPrefsTable(): bool
    {
        if (Schema::hasTable('gymies_buddy_search_prefs')) {
            return true;
        }
        try {
            DB::unprepared("
CREATE TABLE IF NOT EXISTS gymies_buddy_search_prefs (
  user_id BIGINT UNSIGNED NOT NULL,
  is_searching TINYINT(1) NOT NULL DEFAULT 0,
  preferred_trainer_id BIGINT UNSIGNED NULL DEFAULT NULL,
  updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (user_id),
  CONSTRAINT gymies_buddy_search_prefs_user_fk
    FOREIGN KEY (user_id) REFERENCES gymies_users (id) ON DELETE CASCADE,
  CONSTRAINT gymies_buddy_search_prefs_trainer_fk
    FOREIGN KEY (preferred_trainer_id) REFERENCES gymies_users (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            ");
        } catch (\Throwable) {
            return false;
        }
        return Schema::hasTable('gymies_buddy_search_prefs');
    }

    /**
     * Notificatiewachtrij voor bulk-berichten en in-app meldingen (CRM, boekingen, etc.).
     */
    public static function notificationQueueTable(): bool
    {
        if (Schema::hasTable('gymies_notification_queue')) {
            return true;
        }
        try {
            DB::unprepared("
CREATE TABLE IF NOT EXISTS gymies_notification_queue (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id BIGINT UNSIGNED NOT NULL,
  channel ENUM('email', 'push', 'sms', 'in_app') NOT NULL,
  event_type VARCHAR(64) NOT NULL,
  payload_json JSON DEFAULT NULL,
  scheduled_for TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  sent_at TIMESTAMP NULL DEFAULT NULL,
  failed_at TIMESTAMP NULL DEFAULT NULL,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY gymies_notification_queue_user (user_id),
  KEY gymies_notification_queue_scheduled (scheduled_for),
  CONSTRAINT gymies_notification_queue_user_fk
    FOREIGN KEY (user_id) REFERENCES gymies_users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            ");
            return Schema::hasTable('gymies_notification_queue');
        } catch (\Throwable) {
            return false;
        }
    }

    // =========================================================================
    // AMBASSADOR SYSTEEM
    // =========================================================================

    /**
     * Drie tabellen voor het ambassador-systeem:
     *  1. gymies_ambassador_applications  — ingediende aanvragen
     *  2. gymies_ambassadors              — goedgekeurde ambassadors
     *  3. gymies_ambassador_conversions   — elke getrackte conversie
     * Plus: ambassador_boost kolom op gymies_trainer_profiles voor zoekprioriteit.
     */
    public static function ambassadorTables(): void
    {
        self::ambassadorApplicationsTable();
        self::ambassadorsTable();
        self::ambassadorConversionsTable();
        self::trainerProfileAmbassadorBoost();
        self::ambassadorsIban();
        self::ambassadorSubscriptionColumn();
    }

    private static function ambassadorApplicationsTable(): void
    {
        if (!Schema::hasTable('gymies_ambassador_applications')) {
            try {
                DB::unprepared("
CREATE TABLE IF NOT EXISTS gymies_ambassador_applications (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  voornaam VARCHAR(100) NOT NULL,
  achternaam VARCHAR(100) NOT NULL,
  email VARCHAR(255) NOT NULL,
  telefoon VARCHAR(30) DEFAULT NULL,
  stad VARCHAR(100) NOT NULL,
  platform ENUM('instagram','tiktok','youtube','blog','anders') NOT NULL DEFAULT 'instagram',
  handle VARCHAR(255) NOT NULL,
  volgers_range ENUM('<1000','1000-5000','5000-20000','20000-100000','100000+') NOT NULL,
  niche ENUM('fitness','voeding','lifestyle','sport','personal-training','anders') NOT NULL,
  rol ENUM('sporter','trainer','beiden') NOT NULL,
  motivatie TEXT NOT NULL,
  content_link VARCHAR(500) DEFAULT NULL,
  gewenste_code VARCHAR(20) DEFAULT NULL,
  status ENUM('pending','approved','rejected') NOT NULL DEFAULT 'pending',
  admin_notes TEXT DEFAULT NULL,
  reviewed_at TIMESTAMP NULL DEFAULT NULL,
  reviewed_by_user_id BIGINT UNSIGNED DEFAULT NULL,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY gymies_amb_app_email (email),
  KEY gymies_amb_app_status (status),
  KEY gymies_amb_app_created (created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
                ");
            } catch (\Throwable) {}
        }
    }

    private static function ambassadorsTable(): void
    {
        if (!Schema::hasTable('gymies_ambassadors')) {
            try {
                DB::unprepared("
CREATE TABLE IF NOT EXISTS gymies_ambassadors (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  application_id BIGINT UNSIGNED NOT NULL,
  user_id BIGINT UNSIGNED DEFAULT NULL,
  voornaam VARCHAR(100) NOT NULL,
  achternaam VARCHAR(100) NOT NULL,
  email VARCHAR(255) NOT NULL,
  discount_code VARCHAR(20) NOT NULL,
  promo_code_id BIGINT UNSIGNED DEFAULT NULL,
  tier ENUM('starter','active','elite') NOT NULL DEFAULT 'starter',
  tier_updated_at TIMESTAMP NULL DEFAULT NULL,
  is_active TINYINT(1) NOT NULL DEFAULT 1,
  is_featured TINYINT(1) NOT NULL DEFAULT 0,
  is_founding_partner TINYINT(1) NOT NULL DEFAULT 0,
  trainer_conversions INT UNSIGNED NOT NULL DEFAULT 0,
  sporter_conversions INT UNSIGNED NOT NULL DEFAULT 0,
  total_earned_cents BIGINT UNSIGNED NOT NULL DEFAULT 0,
  pending_payout_cents BIGINT UNSIGNED NOT NULL DEFAULT 0,
  iban VARCHAR(34) DEFAULT NULL,
  iban_name VARCHAR(100) DEFAULT NULL,
  last_evaluated_at TIMESTAMP NULL DEFAULT NULL,
  inactive_months TINYINT UNSIGNED NOT NULL DEFAULT 0,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY gymies_amb_application (application_id),
  UNIQUE KEY gymies_amb_code (discount_code),
  KEY gymies_amb_user (user_id),
  KEY gymies_amb_tier (tier),
  KEY gymies_amb_active (is_active),
  CONSTRAINT gymies_amb_user_fk
    FOREIGN KEY (user_id) REFERENCES gymies_users (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
                ");
            } catch (\Throwable) {}
        }
    }

    private static function ambassadorConversionsTable(): void
    {
        if (!Schema::hasTable('gymies_ambassador_conversions')) {
            try {
                DB::unprepared("
CREATE TABLE IF NOT EXISTS gymies_ambassador_conversions (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  ambassador_id BIGINT UNSIGNED NOT NULL,
  referred_user_id BIGINT UNSIGNED NOT NULL,
  conversion_type ENUM('trainer_signup','sporter_booking') NOT NULL,
  promo_code_id BIGINT UNSIGNED DEFAULT NULL,
  payment_transaction_id BIGINT UNSIGNED DEFAULT NULL,
  reward_cents INT UNSIGNED NOT NULL DEFAULT 0,
  suspicious TINYINT(1) NOT NULL DEFAULT 0,
  reversed_at TIMESTAMP NULL DEFAULT NULL,
  paid_at TIMESTAMP NULL DEFAULT NULL,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY gymies_amb_conv_uniq (ambassador_id, referred_user_id, conversion_type),
  KEY gymies_amb_conv_amb (ambassador_id),
  KEY gymies_amb_conv_user (referred_user_id),
  KEY gymies_amb_conv_type (conversion_type),
  KEY gymies_amb_conv_suspicious (suspicious),
  CONSTRAINT gymies_amb_conv_amb_fk
    FOREIGN KEY (ambassador_id) REFERENCES gymies_ambassadors (id) ON DELETE CASCADE,
  CONSTRAINT gymies_amb_conv_user_fk
    FOREIGN KEY (referred_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
                ");
            } catch (\Throwable) {}
        }
    }

    private static function trainerProfileAmbassadorBoost(): void
    {
        if (!Schema::hasTable('gymies_trainer_profiles')) {
            return;
        }
        if (!Schema::hasColumn('gymies_trainer_profiles', 'ambassador_boost')) {
            try {
                DB::statement('ALTER TABLE gymies_trainer_profiles ADD COLUMN ambassador_boost TINYINT UNSIGNED NOT NULL DEFAULT 0');
            } catch (\Throwable) {}
        }
    }

    private static function ambassadorsIban(): void
    {
        if (!Schema::hasTable('gymies_ambassadors')) {
            return;
        }
        if (!Schema::hasColumn('gymies_ambassadors', 'iban')) {
            try {
                DB::statement('ALTER TABLE gymies_ambassadors ADD COLUMN iban VARCHAR(34) DEFAULT NULL, ADD COLUMN iban_name VARCHAR(100) DEFAULT NULL');
            } catch (\Throwable) {}
        }
    }

    /**
     * Voeg ambassador_discount_code toe aan gymies_subscriptions zodat we bij de Mollie
     * subscription-webhook kunnen teruglezen welke ambassador-code de trainer gebruikte.
     */
    private static function ambassadorSubscriptionColumn(): void
    {
        if (!Schema::hasTable('gymies_subscriptions')) {
            return;
        }
        if (!Schema::hasColumn('gymies_subscriptions', 'ambassador_discount_code')) {
            try {
                DB::statement('ALTER TABLE gymies_subscriptions ADD COLUMN ambassador_discount_code VARCHAR(20) DEFAULT NULL');
            } catch (\Throwable) {}
        }
    }

}