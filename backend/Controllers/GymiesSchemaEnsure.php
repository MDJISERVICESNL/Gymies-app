<?php

declare(strict_types=1);

namespace App\Http\Controllers\Gymies;

use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Eénmalige schema-“self-heal” zodat endpoints geen 503 geven als migraties nog niet zijn gedraaid.
 * Roept idempotente CREATE/ALTER alleen uit als kolom/tabel ontbreekt.
 */
final class GymiesSchemaEnsure
{
    public static function referralsTable(): void
    {
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
  status ENUM('pending', 'completed', 'expired') NOT NULL DEFAULT 'pending',
  reward_cents INT UNSIGNED DEFAULT NULL,
  rewarded_at TIMESTAMP NULL DEFAULT NULL,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY gymies_referrals_code_unique (referral_code),
  KEY gymies_referrals_referrer (referrer_user_id),
  CONSTRAINT gymies_referrals_referrer_fk
    FOREIGN KEY (referrer_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE,
  CONSTRAINT gymies_referrals_referred_fk
    FOREIGN KEY (referred_user_id) REFERENCES gymies_users (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            ");
        } catch (\Throwable) {
            // FK kan falen als gymies_users ontbreekt; dan blijft 503 bij caller
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
                    // Validate column name to prevent SQL injection
                    if (!preg_match('/^[a-zA-Z_][a-zA-Z0-9_]*$/', $col)) {
                        return false;
                    }
                    // Use backticks for identifiers and allow only safe column definitions
                    DB::statement("ALTER TABLE `gymies_bookings` ADD COLUMN `{$col}` {$def}");
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
                    // Validate column name to prevent SQL injection
                    if (!preg_match('/^[a-zA-Z_][a-zA-Z0-9_]*$/', $col)) {
                        return false;
                    }
                    // Use backticks for identifiers and allow only safe column definitions
                    DB::statement("ALTER TABLE `gymies_bookings` ADD COLUMN `{$col}` {$def}");
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
                    // Validate column name to prevent SQL injection
                    if (!preg_match('/^[a-zA-Z_][a-zA-Z0-9_]*$/', $col)) {
                        continue;
                    }
                    // Use backticks for identifiers and allow only safe column definitions
                    DB::statement("ALTER TABLE `gymies_client_dossier` ADD COLUMN `{$col}` {$def}");
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
     * Ambassador-tabellen: applications, ambassadors, conversions.
     * Idempotent: maakt alleen aan wat nog niet bestaat.
     */
    public static function ambassadorTables(): void
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
  platform ENUM('instagram','tiktok','youtube','blog','anders') NOT NULL,
  handle VARCHAR(255) NOT NULL,
  volgers_range VARCHAR(20) NOT NULL,
  niche VARCHAR(32) NOT NULL,
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
  KEY gymies_amb_app_status (status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
                ");
            } catch (\Throwable) {}
        }

        if (!Schema::hasTable('gymies_ambassadors')) {
            try {
                DB::unprepared("
CREATE TABLE IF NOT EXISTS gymies_ambassadors (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  application_id BIGINT UNSIGNED DEFAULT NULL,
  user_id BIGINT UNSIGNED DEFAULT NULL,
  voornaam VARCHAR(100) NOT NULL,
  achternaam VARCHAR(100) NOT NULL,
  email VARCHAR(255) NOT NULL,
  stad VARCHAR(100) DEFAULT NULL,
  platform VARCHAR(32) DEFAULT NULL,
  handle VARCHAR(255) DEFAULT NULL,
  discount_code VARCHAR(20) NOT NULL,
  promo_code_id BIGINT UNSIGNED DEFAULT NULL,
  tier ENUM('starter','active','elite') NOT NULL DEFAULT 'starter',
  is_active TINYINT(1) NOT NULL DEFAULT 1,
  is_featured TINYINT(1) NOT NULL DEFAULT 0,
  is_founding_partner TINYINT(1) NOT NULL DEFAULT 0,
  is_public TINYINT(1) NOT NULL DEFAULT 0,
  slug VARCHAR(100) DEFAULT NULL,
  avatar_url VARCHAR(500) DEFAULT NULL,
  bio TEXT DEFAULT NULL,
  specialiteit VARCHAR(100) DEFAULT NULL,
  social_instagram VARCHAR(255) DEFAULT NULL,
  social_tiktok VARCHAR(255) DEFAULT NULL,
  social_youtube VARCHAR(255) DEFAULT NULL,
  social_website VARCHAR(500) DEFAULT NULL,
  trainer_conversions INT UNSIGNED NOT NULL DEFAULT 0,
  sporter_conversions INT UNSIGNED NOT NULL DEFAULT 0,
  total_earned_cents INT NOT NULL DEFAULT 0,
  pending_payout_cents INT NOT NULL DEFAULT 0,
  iban VARCHAR(34) DEFAULT NULL,
  iban_name VARCHAR(100) DEFAULT NULL,
  iban_verified_at TIMESTAMP NULL DEFAULT NULL,
  inactive_months INT UNSIGNED NOT NULL DEFAULT 0,
  tier_updated_at TIMESTAMP NULL DEFAULT NULL,
  last_evaluated_at TIMESTAMP NULL DEFAULT NULL,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY gymies_ambassadors_code_unique (discount_code),
  UNIQUE KEY gymies_ambassadors_slug_unique (slug),
  KEY gymies_ambassadors_user (user_id),
  KEY gymies_ambassadors_email (email),
  KEY gymies_ambassadors_active (is_active)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
                ");
            } catch (\Throwable) {}
        }

        if (!Schema::hasTable('gymies_ambassador_conversions')) {
            try {
                DB::unprepared("
CREATE TABLE IF NOT EXISTS gymies_ambassador_conversions (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  ambassador_id BIGINT UNSIGNED NOT NULL,
  referred_user_id BIGINT UNSIGNED DEFAULT NULL,
  conversion_type ENUM('trainer_signup','sporter_booking') NOT NULL,
  promo_code_id BIGINT UNSIGNED DEFAULT NULL,
  payment_transaction_id BIGINT UNSIGNED DEFAULT NULL,
  reward_cents INT NOT NULL DEFAULT 0,
  suspicious TINYINT(1) NOT NULL DEFAULT 0,
  reversed_at TIMESTAMP NULL DEFAULT NULL,
  paid_at TIMESTAMP NULL DEFAULT NULL,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY gymies_amb_conv_ambassador (ambassador_id),
  KEY gymies_amb_conv_referred (referred_user_id),
  KEY gymies_amb_conv_created (created_at),
  CONSTRAINT gymies_amb_conv_ambassador_fk
    FOREIGN KEY (ambassador_id) REFERENCES gymies_ambassadors (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
                ");
            } catch (\Throwable) {}
        }

        // Promo-codes: ambassador_id + is_platform_wide kolommen
        self::promoCodesAmbassadorColumns();
    }

    /**
     * gymies_promo_codes: ambassador_id + is_platform_wide toevoegen indien ontbreekt.
     */
    public static function promoCodesAmbassadorColumns(): void
    {
        if (!Schema::hasTable('gymies_promo_codes')) {
            return;
        }
        if (!Schema::hasColumn('gymies_promo_codes', 'ambassador_id')) {
            try {
                DB::statement('ALTER TABLE gymies_promo_codes ADD COLUMN ambassador_id BIGINT UNSIGNED DEFAULT NULL');
            } catch (\Throwable) {}
            try {
                DB::statement('ALTER TABLE gymies_promo_codes ADD KEY gymies_promo_codes_ambassador (ambassador_id)');
            } catch (\Throwable) {}
        }
        if (!Schema::hasColumn('gymies_promo_codes', 'is_platform_wide')) {
            try {
                DB::statement('ALTER TABLE gymies_promo_codes ADD COLUMN is_platform_wide TINYINT(1) NOT NULL DEFAULT 0');
            } catch (\Throwable) {}
        }
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
     * Klant: verborgen trainers (gymies_hidden_trainers).
     */
    public static function hiddenTrainersTable(): bool
    {
        if (Schema::hasTable('gymies_hidden_trainers')) {
            return true;
        }
        try {
            DB::unprepared("
CREATE TABLE IF NOT EXISTS gymies_hidden_trainers (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  client_user_id BIGINT UNSIGNED NOT NULL,
  trainer_user_id BIGINT UNSIGNED NOT NULL,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY gymies_hidden_trainers_unique (client_user_id, trainer_user_id),
  KEY gymies_hidden_trainers_client (client_user_id),
  KEY gymies_hidden_trainers_trainer (trainer_user_id),
  CONSTRAINT gymies_hidden_trainers_client_fk
    FOREIGN KEY (client_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE,
  CONSTRAINT gymies_hidden_trainers_trainer_fk
    FOREIGN KEY (trainer_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            ");
        } catch (\Throwable) {
            return false;
        }
        return Schema::hasTable('gymies_hidden_trainers');
    }

    /**
     * Mollie OAuth states: state → trainer_user_id koppeling voor callback.
     */
    public static function mollieOauthStatesTable(): bool
    {
        if (Schema::hasTable('gymies_mollie_oauth_states')) {
            return true;
        }
        try {
            DB::unprepared("
CREATE TABLE IF NOT EXISTS gymies_mollie_oauth_states (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  state VARCHAR(255) NOT NULL,
  trainer_user_id BIGINT UNSIGNED NOT NULL,
  expires_at TIMESTAMP NOT NULL,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY gymies_mollie_oauth_states_state_unique (state),
  KEY gymies_mollie_oauth_states_trainer (trainer_user_id),
  KEY gymies_mollie_oauth_states_expires (expires_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            ");
        } catch (\Throwable) {
            return false;
        }
        return Schema::hasTable('gymies_mollie_oauth_states');
    }

    /**
     * gymies_users.onboarding_completed_at kolom toevoegen indien ontbreekt.
     */
    public static function onboardingCompletedAtColumn(): void
    {
        if (!Schema::hasTable('gymies_users')) {
            return;
        }
        if (Schema::hasColumn('gymies_users', 'onboarding_completed_at')) {
            return;
        }
        try {
            DB::statement('ALTER TABLE gymies_users ADD COLUMN onboarding_completed_at TIMESTAMP NULL DEFAULT NULL');
        } catch (\Throwable) {
        }
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
            // Self-heal: maak user_id nullable als dat nog NOT NULL is (oude migratie)
            try {
                $col = DB::selectOne("
                    SELECT IS_NULLABLE
                    FROM INFORMATION_SCHEMA.COLUMNS
                    WHERE TABLE_SCHEMA = DATABASE()
                      AND TABLE_NAME = 'gymies_notification_queue'
                      AND COLUMN_NAME = 'user_id'
                ");
                if ($col && $col->IS_NULLABLE === 'NO') {
                    DB::unprepared("ALTER TABLE gymies_notification_queue MODIFY user_id BIGINT UNSIGNED DEFAULT NULL");
                }
            } catch (\Throwable) {
                // niet kritiek — volgende deploy fixt het
            }
            return true;
        }
        try {
            DB::unprepared("
CREATE TABLE IF NOT EXISTS gymies_notification_queue (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id BIGINT UNSIGNED DEFAULT NULL,
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

    // ─── Groepssessies: prijs per deelnemer ───────────────────────────

    public static function groupSessionPricePerParticipantColumn(): bool
    {
        if (!Schema::hasTable('gymies_group_sessions')) {
            return false;
        }
        if (Schema::hasColumn('gymies_group_sessions', 'price_per_participant_cents')) {
            return true;
        }
        try {
            DB::statement("
ALTER TABLE gymies_group_sessions
  ADD COLUMN price_per_participant_cents INT UNSIGNED DEFAULT NULL
  AFTER price_cents
            ");
        } catch (\Throwable) {
            // kolom bestond al of tabel ontbreekt
        }
        return Schema::hasColumn('gymies_group_sessions', 'price_per_participant_cents');
    }

    // ─── Dynamische fees per trainer/plan ─────���───────────────────────

    public static function feeSettingsTable(): bool
    {
        if (Schema::hasTable('gymies_fee_settings')) {
            return true;
        }
        try {
            DB::unprepared("
CREATE TABLE IF NOT EXISTS gymies_fee_settings (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  trainer_user_id BIGINT UNSIGNED DEFAULT NULL COMMENT 'NULL = platform default per plan',
  plan_slug VARCHAR(32) DEFAULT NULL COMMENT 'starter/pro/studio, NULL = alle plans',
  fee_type ENUM('fixed','percent') NOT NULL DEFAULT 'fixed',
  fee_value INT UNSIGNED NOT NULL DEFAULT 49 COMMENT 'fixed=centen, percent=basispunten (250=2.5%)',
  client_pays TINYINT(1) NOT NULL DEFAULT 1,
  is_active TINYINT(1) NOT NULL DEFAULT 1,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY gymies_fee_settings_trainer_plan (trainer_user_id, plan_slug),
  KEY gymies_fee_settings_plan (plan_slug)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            ");
        } catch (\Throwable) {
            return false;
        }
        return Schema::hasTable('gymies_fee_settings');
    }

    // ─── Refunds tracking ��────────────────────────────────────────────

    public static function refundsTable(): bool
    {
        if (Schema::hasTable('gymies_refunds')) {
            return true;
        }
        try {
            DB::unprepared("
CREATE TABLE IF NOT EXISTS gymies_refunds (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  booking_id BIGINT UNSIGNED DEFAULT NULL,
  group_participant_id BIGINT UNSIGNED DEFAULT NULL,
  transaction_id BIGINT UNSIGNED DEFAULT NULL COMMENT 'gymies_payment_transactions.id',
  initiated_by_user_id BIGINT UNSIGNED NOT NULL,
  trainer_user_id BIGINT UNSIGNED NOT NULL,
  client_user_id BIGINT UNSIGNED NOT NULL,
  mollie_refund_id VARCHAR(64) DEFAULT NULL COMMENT 'Mollie re_xxx ID',
  mollie_payment_id VARCHAR(64) DEFAULT NULL COMMENT 'Originele tr_xxx',
  original_amount_cents INT UNSIGNED NOT NULL,
  refund_amount_cents INT UNSIGNED NOT NULL,
  refund_percent INT UNSIGNED NOT NULL DEFAULT 100,
  cancellation_fee_cents INT UNSIGNED NOT NULL DEFAULT 0,
  refund_method ENUM('mollie','wallet','bank','none') NOT NULL DEFAULT 'mollie',
  reason VARCHAR(500) DEFAULT NULL,
  status ENUM('pending','processing','completed','failed') NOT NULL DEFAULT 'pending',
  policy_snapshot JSON DEFAULT NULL COMMENT 'Toegepast annuleringsbeleid snapshot',
  completed_at TIMESTAMP NULL DEFAULT NULL,
  failed_at TIMESTAMP NULL DEFAULT NULL,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY gymies_refunds_booking (booking_id),
  KEY gymies_refunds_participant (group_participant_id),
  KEY gymies_refunds_trainer (trainer_user_id),
  KEY gymies_refunds_client (client_user_id),
  KEY gymies_refunds_mollie (mollie_refund_id),
  KEY gymies_refunds_status (status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            ");
        } catch (\Throwable) {
            return false;
        }
        return Schema::hasTable('gymies_refunds');
    }

    // ─── Subscription pause/resume kolommen ───────────────────────────

    public static function subscriptionPauseColumns(): bool
    {
        if (!Schema::hasTable('gymies_subscriptions')) {
            return false;
        }
        if (Schema::hasColumn('gymies_subscriptions', 'paused_at')) {
            return true;
        }
        try {
            DB::statement("
ALTER TABLE gymies_subscriptions
  ADD COLUMN paused_at TIMESTAMP NULL DEFAULT NULL AFTER cancelled_at,
  ADD COLUMN resumed_at TIMESTAMP NULL DEFAULT NULL AFTER paused_at,
  ADD COLUMN grace_period_ends_at TIMESTAMP NULL DEFAULT NULL AFTER resumed_at
            ");
        } catch (\Throwable) {
            // kolommen bestonden al
        }
        return Schema::hasColumn('gymies_subscriptions', 'paused_at');
    }

    // ─── Crowdfund groepssessie kolommen ──────────────────────────────

    /**
     * Voegt crowdfund-gerelateerde kolommen toe aan gymies_group_sessions:
     * - min_participants: minimaal aantal deelnemers voor doorgang
     * - confirmation_deadline_at: deadline waarop min bereikt moet zijn
     * - confirmation_status: open → confirmed / cancelled
     */
    public static function crowdfundColumns(): bool
    {
        if (!Schema::hasTable('gymies_group_sessions')) {
            return false;
        }
        if (Schema::hasColumn('gymies_group_sessions', 'confirmation_status')) {
            return true;
        }
        try {
            DB::statement("
ALTER TABLE gymies_group_sessions
  ADD COLUMN min_participants INT UNSIGNED NOT NULL DEFAULT 1 AFTER max_participants,
  ADD COLUMN confirmation_deadline_at TIMESTAMP NULL DEFAULT NULL AFTER min_participants,
  ADD COLUMN confirmation_status ENUM('open','confirmed','cancelled') NOT NULL DEFAULT 'open' AFTER confirmation_deadline_at,
  ADD COLUMN confirmed_at TIMESTAMP NULL DEFAULT NULL AFTER confirmation_status
            ");
        } catch (\Throwable) {
            // kolommen bestonden al
        }
        return Schema::hasColumn('gymies_group_sessions', 'confirmation_status');
    }
}
