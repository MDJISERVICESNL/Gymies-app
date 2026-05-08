<?php

declare(strict_types=1);

namespace App\Http\Controllers\Gymies;

use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
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
        } catch (\Throwable $e) {
            Log::warning('Gymies schema ensure: ' . $e->getMessage());
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
        } catch (\Throwable $e) {
            Log::warning('Schema ensure: group sessions status column add failed: ' . $e->getMessage());
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
        } catch (\Throwable $e) {
            Log::warning('Gymies schema ensure: ' . $e->getMessage());
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
            } catch (\Throwable $e) {
                Log::warning('Schema ensure: document uploads table creation failed: ' . $e->getMessage());
                return false;
            }
        }
        if (!Schema::hasColumn('gymies_document_uploads', 'document_category')) {
            try {
                DB::statement('ALTER TABLE gymies_document_uploads ADD COLUMN document_category VARCHAR(32) DEFAULT NULL');
            } catch (\Throwable $e) {
                Log::warning('Gymies schema ensure: ' . $e->getMessage());
            }
        }
        if (!Schema::hasColumn('gymies_document_uploads', 'original_filename')) {
            try {
                DB::statement('ALTER TABLE gymies_document_uploads ADD COLUMN original_filename VARCHAR(255) DEFAULT NULL');
            } catch (\Throwable $e) {
                Log::warning('Gymies schema ensure: ' . $e->getMessage());
            }
        }
        if (!Schema::hasColumn('gymies_document_uploads', 'mime_type')) {
            try {
                DB::statement('ALTER TABLE gymies_document_uploads ADD COLUMN mime_type VARCHAR(128) DEFAULT NULL');
            } catch (\Throwable $e) {
                Log::warning('Gymies schema ensure: ' . $e->getMessage());
            }
        }
        if (!Schema::hasColumn('gymies_document_uploads', 'file_size_bytes')) {
            try {
                DB::statement('ALTER TABLE gymies_document_uploads ADD COLUMN file_size_bytes INT UNSIGNED DEFAULT NULL');
            } catch (\Throwable $e) {
                Log::warning('Gymies schema ensure: ' . $e->getMessage());
            }
        }
        if (!Schema::hasColumn('gymies_document_uploads', 'rejected_at')) {
            try {
                DB::statement('ALTER TABLE gymies_document_uploads ADD COLUMN rejected_at TIMESTAMP NULL DEFAULT NULL');
            } catch (\Throwable $e) {
                Log::warning('Gymies schema ensure: ' . $e->getMessage());
            }
        }
        if (!Schema::hasColumn('gymies_document_uploads', 'rejection_reason')) {
            try {
                DB::statement('ALTER TABLE gymies_document_uploads ADD COLUMN rejection_reason VARCHAR(500) DEFAULT NULL');
            } catch (\Throwable $e) {
                Log::warning('Gymies schema ensure: ' . $e->getMessage());
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
                } catch (\Throwable $e) {
                    Log::warning('Schema ensure: bookings checkin column add failed: ' . $e->getMessage());
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
        } catch (\Throwable $e) {
            Log::warning('Schema ensure: SOS alerts table creation failed: ' . $e->getMessage());
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
                } catch (\Throwable $e) {
                    Log::warning('Schema ensure: bookings safe session column add failed: ' . $e->getMessage());
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
            } catch (\Throwable $e) {
                // fallback minimaal
                Log::warning('Schema ensure: client dossier SQL file execution failed: ' . $e->getMessage());
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
                } catch (\Throwable $e) {
                    Log::warning('Schema ensure: client dossier table creation failed: ' . $e->getMessage());
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
                } catch (\Throwable $e) {
                    Log::warning('Gymies schema ensure: ' . $e->getMessage());
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
        } catch (\Throwable $e) {
            Log::warning('Schema ensure: client progress table creation failed: ' . $e->getMessage());
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
            } catch (\Throwable $e) {
                Log::warning('Gymies schema ensure: ' . $e->getMessage());
            }
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
            } catch (\Throwable $e) {
                Log::warning('Gymies schema ensure: ' . $e->getMessage());
            }
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
            } catch (\Throwable $e) {
                Log::warning('Gymies schema ensure: ' . $e->getMessage());
            }
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
            } catch (\Throwable $e) {
                Log::warning('Gymies schema ensure: ' . $e->getMessage());
            }
            try {
                DB::statement('ALTER TABLE gymies_promo_codes ADD KEY gymies_promo_codes_ambassador (ambassador_id)');
            } catch (\Throwable $e) {
                Log::warning('Gymies schema ensure: ' . $e->getMessage());
            }
        }
        if (!Schema::hasColumn('gymies_promo_codes', 'is_platform_wide')) {
            try {
                DB::statement('ALTER TABLE gymies_promo_codes ADD COLUMN is_platform_wide TINYINT(1) NOT NULL DEFAULT 0');
            } catch (\Throwable $e) {
                Log::warning('Gymies schema ensure: ' . $e->getMessage());
            }
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
        } catch (\Throwable $e) {
            Log::warning('Gymies schema ensure: ' . $e->getMessage());
        }
        try {
            DB::statement('ALTER TABLE gymies_promo_codes ADD KEY gymies_promo_codes_trainer (trainer_user_id)');
        } catch (\Throwable $e) {
            Log::warning('Gymies schema ensure: ' . $e->getMessage());
        }
        try {
            DB::statement('ALTER TABLE gymies_promo_codes ADD CONSTRAINT gymies_promo_codes_trainer_fk FOREIGN KEY (trainer_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE');
        } catch (\Throwable $e) {
            Log::warning('Gymies schema ensure: ' . $e->getMessage());
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
        } catch (\Throwable $e) {
            Log::warning('Schema ensure: favorites table creation failed: ' . $e->getMessage());
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
        } catch (\Throwable $e) {
            Log::warning('Schema ensure: hidden trainers table creation failed: ' . $e->getMessage());
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
        } catch (\Throwable $e) {
            Log::warning('Schema ensure: Mollie OAuth states table creation failed: ' . $e->getMessage());
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
        } catch (\Throwable $e) {
            Log::warning('Gymies schema ensure: ' . $e->getMessage());
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
        } catch (\Throwable $e) {
            Log::warning('Schema ensure: buddy search prefs table creation failed: ' . $e->getMessage());
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
            } catch (\Throwable $e) {
                Log::warning('Schema ensure: notification queue user_id modify failed: ' . $e->getMessage());
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
        } catch (\Throwable $e) {
            Log::warning('Schema ensure: notification queue table creation failed: ' . $e->getMessage());
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
        } catch (\Throwable $e) {
            Log::warning('Schema ensure: group sessions price per participant column add failed: ' . $e->getMessage());
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
        } catch (\Throwable $e) {
            Log::warning('Schema ensure: fee settings table creation failed: ' . $e->getMessage());
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
        } catch (\Throwable $e) {
            Log::warning('Schema ensure: refunds table creation failed: ' . $e->getMessage());
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
        } catch (\Throwable $e) {
            Log::warning('Schema ensure: subscription pause columns add failed: ' . $e->getMessage());
            // kolommen bestonden al
        }
        return Schema::hasColumn('gymies_subscriptions', 'paused_at');
    }

    // ─── Crowdfund groepssessie kolommen ──────────────────────────────

    /**
     * Reviews table — trainer ratings from clients.
     * Both names are supported for backwards compatibility:
     * - gymies_booking_reviews: legacy name with booking_id reference
     * - gymies_reviews: newer name used by insights queries
     */
    public static function reviewsTable(): bool
    {
        // Create gymies_reviews table (used by GymiesInsightsController)
        if (!Schema::hasTable('gymies_reviews')) {
            try {
                DB::unprepared("
CREATE TABLE IF NOT EXISTS gymies_reviews (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  booking_id VARCHAR(64) DEFAULT NULL,
  client_user_id BIGINT UNSIGNED NOT NULL,
  trainer_user_id BIGINT UNSIGNED NOT NULL,
  rating TINYINT UNSIGNED NOT NULL COMMENT '1-5 sterren',
  message TEXT DEFAULT NULL,
  is_anonymous TINYINT(1) NOT NULL DEFAULT 0,
  photo_url VARCHAR(512) DEFAULT NULL COMMENT 'pad naar review foto',
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY gymies_reviews_booking_id (booking_id),
  KEY gymies_reviews_client (client_user_id),
  KEY gymies_reviews_trainer (trainer_user_id),
  KEY gymies_reviews_trainer_created (trainer_user_id, created_at),
  KEY gymies_reviews_rating (rating),
  KEY gymies_reviews_created (created_at),
  CONSTRAINT gymies_reviews_client_fk
    FOREIGN KEY (client_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE,
  CONSTRAINT gymies_reviews_trainer_fk
    FOREIGN KEY (trainer_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
                ");
            } catch (\Throwable $e) {
                Log::warning('Gymies schema ensure: reviews table creation failed: ' . $e->getMessage());
            }
        }

        // Also create the legacy gymies_booking_reviews table for backwards compatibility
        $legacyTable = 'gymies_booking_reviews';
        if (!Schema::hasTable($legacyTable)) {
            try {
                DB::unprepared("
CREATE TABLE IF NOT EXISTS {$legacyTable} (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  booking_id VARCHAR(64) NOT NULL,
  client_user_id BIGINT UNSIGNED NOT NULL,
  trainer_user_id BIGINT UNSIGNED NOT NULL,
  rating TINYINT UNSIGNED NOT NULL COMMENT '1-5 sterren',
  message TEXT DEFAULT NULL,
  is_anonymous TINYINT(1) NOT NULL DEFAULT 0,
  photo_url VARCHAR(512) DEFAULT NULL COMMENT 'pad naar review foto',
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY gymies_booking_reviews_booking_id (booking_id),
  KEY gymies_booking_reviews_client (client_user_id),
  KEY gymies_booking_reviews_trainer (trainer_user_id),
  CONSTRAINT gymies_booking_reviews_client_fk
    FOREIGN KEY (client_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE,
  CONSTRAINT gymies_booking_reviews_trainer_fk
    FOREIGN KEY (trainer_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
                ");
            } catch (\Throwable $e) {
                Log::warning('Gymies schema ensure: legacy booking reviews table creation failed: ' . $e->getMessage());
            }
        }

        // Add photo_url column if missing
        if (Schema::hasTable('gymies_reviews') && !Schema::hasColumn('gymies_reviews', 'photo_url')) {
            try {
                DB::statement("ALTER TABLE gymies_reviews ADD COLUMN photo_url VARCHAR(512) DEFAULT NULL AFTER is_anonymous");
            } catch (\Throwable $e) {
                Log::warning('Gymies schema ensure: ' . $e->getMessage());
            }
        }

        if (Schema::hasTable($legacyTable) && !Schema::hasColumn($legacyTable, 'photo_url')) {
            try {
                DB::statement("ALTER TABLE {$legacyTable} ADD COLUMN photo_url VARCHAR(512) DEFAULT NULL AFTER is_anonymous");
            } catch (\Throwable $e) {
                Log::warning('Gymies schema ensure: ' . $e->getMessage());
            }
        }

        return Schema::hasTable('gymies_reviews') || Schema::hasTable($legacyTable);
    }

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
        } catch (\Throwable $e) {
            Log::warning('Schema ensure: group sessions crowdfund columns add failed: ' . $e->getMessage());
            // kolommen bestonden al
        }
        return Schema::hasColumn('gymies_group_sessions', 'confirmation_status');
    }

    /**
     * Staff audit log — audit trail för trainer trial extensions och admin actions.
     */
    public static function staffAuditLogTable(): bool
    {
        if (Schema::hasTable('gymies_staff_audit_log')) {
            return true;
        }
        try {
            DB::unprepared("
CREATE TABLE IF NOT EXISTS gymies_staff_audit_log (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  action VARCHAR(64) NOT NULL,
  admin_user_id BIGINT UNSIGNED NOT NULL,
  target_user_id BIGINT UNSIGNED DEFAULT NULL,
  details_json JSON DEFAULT NULL,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY gymies_staff_audit_log_admin (admin_user_id),
  KEY gymies_staff_audit_log_target (target_user_id),
  KEY gymies_staff_audit_log_created (created_at),
  CONSTRAINT gymies_staff_audit_log_admin_fk
    FOREIGN KEY (admin_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            ");
        } catch (\Throwable $e) {
            Log::warning('Schema ensure: staff audit log table creation failed: ' . $e->getMessage());
            return false;
        }
        return Schema::hasTable('gymies_staff_audit_log');
    }

    /**
     * Voeg story-kolommen toe aan gymies_trainer_media: usage + expires_at.
     * Hiermee kunnen we stories (24h) onderscheiden van gallery media.
     */
    public static function trainerMediaStoryColumns(): bool
    {
        if (!Schema::hasTable('gymies_trainer_media')) {
            return false;
        }

        if (!Schema::hasColumn('gymies_trainer_media', 'usage')) {
            try {
                DB::statement("ALTER TABLE gymies_trainer_media ADD COLUMN usage VARCHAR(32) NOT NULL DEFAULT 'gallery'");
            } catch (\Throwable $e) {
                Log::warning('Schema ensure: trainer_media usage column add failed: ' . $e->getMessage());
            }
        }

        if (!Schema::hasColumn('gymies_trainer_media', 'expires_at')) {
            try {
                DB::statement("ALTER TABLE gymies_trainer_media ADD COLUMN expires_at TIMESTAMP NULL DEFAULT NULL");
            } catch (\Throwable $e) {
                Log::warning('Schema ensure: trainer_media expires_at column add failed: ' . $e->getMessage());
            }
        }

        return Schema::hasColumn('gymies_trainer_media', 'usage')
            && Schema::hasColumn('gymies_trainer_media', 'expires_at');
    }

    /**
     * Messages table — private messages between users (trainer-client chat).
     */
    public static function messagesTable(): bool
    {
        if (Schema::hasTable('gymies_messages')) {
            return true;
        }
        try {
            DB::unprepared("
CREATE TABLE IF NOT EXISTS gymies_messages (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  sender_user_id BIGINT UNSIGNED NOT NULL,
  recipient_user_id BIGINT UNSIGNED NOT NULL,
  message TEXT NOT NULL,
  is_read TINYINT(1) NOT NULL DEFAULT 0,
  read_at TIMESTAMP NULL DEFAULT NULL,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY gymies_messages_sender (sender_user_id),
  KEY gymies_messages_recipient (recipient_user_id),
  KEY gymies_messages_created (created_at),
  KEY gymies_messages_is_read (is_read, created_at),
  KEY gymies_messages_conversation (recipient_user_id, sender_user_id, created_at),
  CONSTRAINT gymies_messages_sender_fk
    FOREIGN KEY (sender_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE,
  CONSTRAINT gymies_messages_recipient_fk
    FOREIGN KEY (recipient_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            ");
        } catch (\Throwable $e) {
            Log::warning('Schema ensure: messages table creation failed: ' . $e->getMessage());
            return false;
        }
        return Schema::hasTable('gymies_messages');
    }

    /**
     * Sessions table — user session/auth tokens.
     */
    public static function sessionsTable(): bool
    {
        if (Schema::hasTable('gymies_sessions')) {
            return true;
        }
        try {
            DB::unprepared("
CREATE TABLE IF NOT EXISTS gymies_sessions (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id BIGINT UNSIGNED NOT NULL,
  token VARCHAR(255) NOT NULL,
  user_agent VARCHAR(500) DEFAULT NULL,
  ip_address VARCHAR(45) DEFAULT NULL,
  expires_at TIMESTAMP NOT NULL,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY gymies_sessions_token_unique (token),
  KEY gymies_sessions_user (user_id),
  KEY gymies_sessions_expires (expires_at),
  CONSTRAINT gymies_sessions_user_fk
    FOREIGN KEY (user_id) REFERENCES gymies_users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            ");
        } catch (\Throwable $e) {
            Log::warning('Schema ensure: sessions table creation failed: ' . $e->getMessage());
            return false;
        }
        return Schema::hasTable('gymies_sessions');
    }

    /**
     * Availability Slots table — deprecated but still used, maps to gymies_availability.
     * Note: Newer code uses gymies_availability, but legacy code still references this.
     */
    public static function availabilitySlotsTable(): bool
    {
        if (Schema::hasTable('gymies_availability_slots')) {
            return true;
        }
        try {
            DB::unprepared("
CREATE TABLE IF NOT EXISTS gymies_availability_slots (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id BIGINT UNSIGNED NOT NULL,
  day_of_week INT NOT NULL COMMENT '1=Monday, 7=Sunday',
  start_time VARCHAR(8) NOT NULL,
  end_time VARCHAR(8) NOT NULL,
  is_active TINYINT(1) NOT NULL DEFAULT 1,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY gymies_availability_slots_user (user_id),
  KEY gymies_availability_slots_day (day_of_week),
  CONSTRAINT gymies_availability_slots_user_fk
    FOREIGN KEY (user_id) REFERENCES gymies_users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            ");
        } catch (\Throwable $e) {
            Log::warning('Schema ensure: availability slots table creation failed: ' . $e->getMessage());
            return false;
        }
        return Schema::hasTable('gymies_availability_slots');
    }

    /**
     * Onboarding reviews table — trainer onboarding assessment by admins.
     */
    public static function onboardingReviewsTable(): bool
    {
        if (Schema::hasTable('gymies_onboarding_reviews')) {
            return true;
        }
        try {
            DB::unprepared("
CREATE TABLE IF NOT EXISTS gymies_onboarding_reviews (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  trainer_id BIGINT UNSIGNED NOT NULL,
  reviewer_user_id BIGINT UNSIGNED DEFAULT NULL,
  step VARCHAR(64) NOT NULL,
  status ENUM('pending','approved','rejected') NOT NULL DEFAULT 'pending',
  notes TEXT DEFAULT NULL,
  reviewed_at TIMESTAMP NULL DEFAULT NULL,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY gymies_onboarding_reviews_trainer (trainer_id),
  KEY gymies_onboarding_reviews_step (step),
  KEY gymies_onboarding_reviews_status (status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            ");
        } catch (\Throwable $e) {
            Log::warning('Schema ensure: onboarding reviews table creation failed: ' . $e->getMessage());
            return false;
        }
        return Schema::hasTable('gymies_onboarding_reviews');
    }

    /**
     * Plans table — subscription plans (starter, pro, studio, etc.).
     */
    public static function plansTable(): bool
    {
        if (Schema::hasTable('gymies_plans')) {
            return true;
        }
        try {
            DB::unprepared("
CREATE TABLE IF NOT EXISTS gymies_plans (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  slug VARCHAR(32) NOT NULL,
  name VARCHAR(100) NOT NULL,
  description TEXT DEFAULT NULL,
  price_cents INT UNSIGNED NOT NULL,
  currency VARCHAR(3) NOT NULL DEFAULT 'EUR',
  billing_period VARCHAR(32) NOT NULL DEFAULT 'monthly',
  max_bookings_per_month INT UNSIGNED DEFAULT NULL,
  max_clients INT UNSIGNED DEFAULT NULL,
  features_json JSON DEFAULT NULL,
  is_active TINYINT(1) NOT NULL DEFAULT 1,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY gymies_plans_slug_unique (slug),
  KEY gymies_plans_active (is_active)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            ");
        } catch (\Throwable $e) {
            Log::warning('Schema ensure: plans table creation failed: ' . $e->getMessage());
            return false;
        }
        return Schema::hasTable('gymies_plans');
    }

    /**
     * User Roles table — role assignments for users (flexible role system).
     */
    public static function userRolesTable(): bool
    {
        if (Schema::hasTable('gymies_user_roles')) {
            return true;
        }
        try {
            DB::unprepared("
CREATE TABLE IF NOT EXISTS gymies_user_roles (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id BIGINT UNSIGNED NOT NULL,
  role VARCHAR(64) NOT NULL,
  assigned_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY gymies_user_roles_unique (user_id, role),
  KEY gymies_user_roles_user (user_id),
  KEY gymies_user_roles_role (role),
  CONSTRAINT gymies_user_roles_user_fk
    FOREIGN KEY (user_id) REFERENCES gymies_users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            ");
        } catch (\Throwable $e) {
            Log::warning('Schema ensure: user roles table creation failed: ' . $e->getMessage());
            return false;
        }
        return Schema::hasTable('gymies_user_roles');
    }

    /**
     * Cancellation Policies table — refund policies for trainers.
     */
    public static function cancellationPoliciesTable(): bool
    {
        if (Schema::hasTable('gymies_cancellation_policies')) {
            return true;
        }
        try {
            DB::unprepared("
CREATE TABLE IF NOT EXISTS gymies_cancellation_policies (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  trainer_user_id BIGINT UNSIGNED NOT NULL,
  hours_before INT UNSIGNED NOT NULL DEFAULT 24,
  refund_percent INT UNSIGNED NOT NULL DEFAULT 100,
  is_active TINYINT(1) NOT NULL DEFAULT 1,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY gymies_cancellation_policies_trainer (trainer_user_id),
  KEY gymies_cancellation_policies_active (is_active),
  CONSTRAINT gymies_cancellation_policies_trainer_fk
    FOREIGN KEY (trainer_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            ");
        } catch (\Throwable $e) {
            Log::warning('Schema ensure: cancellation policies table creation failed: ' . $e->getMessage());
            return false;
        }
        return Schema::hasTable('gymies_cancellation_policies');
    }

    /**
     * Organisations table — gym organizations that can have staff, locations, etc.
     */
    public static function organisationsTable(): bool
    {
        if (Schema::hasTable('gymies_organisations')) {
            return true;
        }
        try {
            DB::unprepared("
CREATE TABLE IF NOT EXISTS gymies_organisations (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  name VARCHAR(255) NOT NULL,
  owner_user_id BIGINT UNSIGNED NOT NULL,
  slug VARCHAR(100) DEFAULT NULL,
  address VARCHAR(500) DEFAULT NULL,
  city VARCHAR(100) DEFAULT NULL,
  postal_code VARCHAR(10) DEFAULT NULL,
  phone VARCHAR(20) DEFAULT NULL,
  website VARCHAR(255) DEFAULT NULL,
  description TEXT DEFAULT NULL,
  logo_url VARCHAR(500) DEFAULT NULL,
  is_active TINYINT(1) NOT NULL DEFAULT 1,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY gymies_organisations_slug_unique (slug),
  KEY gymies_organisations_owner (owner_user_id),
  KEY gymies_organisations_active (is_active),
  CONSTRAINT gymies_organisations_owner_fk
    FOREIGN KEY (owner_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            ");
        } catch (\Throwable $e) {
            Log::warning('Schema ensure: organisations table creation failed: ' . $e->getMessage());
            return false;
        }
        return Schema::hasTable('gymies_organisations');
    }

    /**
     * Trainer Media table — photos/videos for trainer profiles.
     */
    public static function trainerMediaTable(): bool
    {
        if (Schema::hasTable('gymies_trainer_media')) {
            return true;
        }
        try {
            DB::unprepared("
CREATE TABLE IF NOT EXISTS gymies_trainer_media (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  trainer_user_id BIGINT UNSIGNED NOT NULL,
  media_url VARCHAR(512) NOT NULL,
  type VARCHAR(32) NOT NULL DEFAULT 'photo',
  usage VARCHAR(32) NOT NULL DEFAULT 'gallery',
  display_order INT UNSIGNED DEFAULT NULL,
  expires_at TIMESTAMP NULL DEFAULT NULL,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY gymies_trainer_media_trainer (trainer_user_id),
  KEY gymies_trainer_media_usage (usage),
  KEY gymies_trainer_media_expires (expires_at),
  KEY gymies_trainer_media_trainer_usage (trainer_user_id, usage),
  KEY gymies_trainer_media_created (created_at),
  CONSTRAINT gymies_trainer_media_trainer_fk
    FOREIGN KEY (trainer_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            ");
        } catch (\Throwable $e) {
            Log::warning('Schema ensure: trainer media table creation failed: ' . $e->getMessage());
            return false;
        }
        return Schema::hasTable('gymies_trainer_media');
    }

    /**
     * Trainer Profiles table — extended trainer information.
     */
    public static function trainerProfilesTable(): bool
    {
        if (Schema::hasTable('gymies_trainer_profiles')) {
            return true;
        }
        try {
            DB::unprepared("
CREATE TABLE IF NOT EXISTS gymies_trainer_profiles (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id BIGINT UNSIGNED NOT NULL,
  bio TEXT DEFAULT NULL,
  city VARCHAR(100) DEFAULT NULL,
  region VARCHAR(100) DEFAULT NULL,
  hourly_rate_cents INT UNSIGNED DEFAULT NULL,
  display_name VARCHAR(255) DEFAULT NULL,
  specialties VARCHAR(255) DEFAULT NULL,
  certifications TEXT DEFAULT NULL,
  experience_years INT UNSIGNED DEFAULT NULL,
  is_verified TINYINT(1) NOT NULL DEFAULT 0,
  is_featured TINYINT(1) NOT NULL DEFAULT 0,
  rating_avg DECIMAL(3,2) DEFAULT NULL,
  rating_count INT UNSIGNED NOT NULL DEFAULT 0,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY gymies_trainer_profiles_user (user_id),
  KEY gymies_trainer_profiles_verified (is_verified),
  KEY gymies_trainer_profiles_city (city),
  KEY gymies_trainer_profiles_featured (is_featured),
  KEY gymies_trainer_profiles_rating (rating_avg),
  KEY gymies_trainer_profiles_created (created_at),
  CONSTRAINT gymies_trainer_profiles_user_fk
    FOREIGN KEY (user_id) REFERENCES gymies_users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            ");
        } catch (\Throwable $e) {
            Log::warning('Schema ensure: trainer profiles table creation failed: ' . $e->getMessage());
            return false;
        }
        return Schema::hasTable('gymies_trainer_profiles');
    }

    /**
     * Ensure badge-gerelateerde kolommen bestaan in trainer_profiles.
     */
    public static function trainerProfilesBadgeColumns(): void
    {
        if (!Schema::hasTable('gymies_trainer_profiles')) return;

        $badgeCols = [
            'offers_online_sessions' => 'TINYINT(1) NOT NULL DEFAULT 0',
            'has_flexible_hours'     => 'TINYINT(1) NOT NULL DEFAULT 0',
            'same_day_booking'       => 'TINYINT(1) NOT NULL DEFAULT 0',
            'has_free_cancellation'  => 'TINYINT(1) NOT NULL DEFAULT 0',
            'has_free_trial'         => 'TINYINT(1) NOT NULL DEFAULT 0',
        ];

        foreach ($badgeCols as $col => $definition) {
            if (!Schema::hasColumn('gymies_trainer_profiles', $col)) {
                try {
                    DB::statement("ALTER TABLE gymies_trainer_profiles ADD COLUMN {$col} {$definition}");
                } catch (\Throwable $e) {
                    Log::warning("Schema ensure: badge column {$col} failed: " . $e->getMessage());
                }
            }
        }
    }

    /**
     * Promo Codes table — discount codes for bookings.
     */
    public static function promoCodesTable(): bool
    {
        if (Schema::hasTable('gymies_promo_codes')) {
            return true;
        }
        try {
            DB::unprepared("
CREATE TABLE IF NOT EXISTS gymies_promo_codes (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  trainer_user_id BIGINT UNSIGNED DEFAULT NULL,
  ambassador_id BIGINT UNSIGNED DEFAULT NULL,
  code VARCHAR(64) NOT NULL,
  discount_type ENUM('fixed','percent') NOT NULL DEFAULT 'percent',
  discount_value INT UNSIGNED NOT NULL,
  max_uses INT UNSIGNED DEFAULT NULL,
  use_count INT UNSIGNED NOT NULL DEFAULT 0,
  is_platform_wide TINYINT(1) NOT NULL DEFAULT 0,
  expires_at TIMESTAMP NULL DEFAULT NULL,
  is_active TINYINT(1) NOT NULL DEFAULT 1,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY gymies_promo_codes_code_unique (code),
  KEY gymies_promo_codes_trainer (trainer_user_id),
  KEY gymies_promo_codes_ambassador (ambassador_id),
  KEY gymies_promo_codes_active (is_active),
  KEY gymies_promo_codes_expires (expires_at),
  KEY gymies_promo_codes_created (created_at),
  CONSTRAINT gymies_promo_codes_trainer_fk
    FOREIGN KEY (trainer_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE,
  CONSTRAINT gymies_promo_codes_ambassador_fk
    FOREIGN KEY (ambassador_id) REFERENCES gymies_ambassadors (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            ");
        } catch (\Throwable $e) {
            Log::warning('Schema ensure: promo codes table creation failed: ' . $e->getMessage());
            return false;
        }
        return Schema::hasTable('gymies_promo_codes');
    }

    /**
     * Subscriptions table — user subscription records.
     */
    public static function subscriptionsTable(): bool
    {
        if (Schema::hasTable('gymies_subscriptions')) {
            return true;
        }
        try {
            DB::unprepared("
CREATE TABLE IF NOT EXISTS gymies_subscriptions (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id BIGINT UNSIGNED NOT NULL,
  plan_slug VARCHAR(32) NOT NULL,
  status ENUM('active','paused','cancelled','expired') NOT NULL DEFAULT 'active',
  started_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  cancelled_at TIMESTAMP NULL DEFAULT NULL,
  paused_at TIMESTAMP NULL DEFAULT NULL,
  resumed_at TIMESTAMP NULL DEFAULT NULL,
  grace_period_ends_at TIMESTAMP NULL DEFAULT NULL,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY gymies_subscriptions_user (user_id),
  KEY gymies_subscriptions_plan (plan_slug),
  KEY gymies_subscriptions_status (status),
  KEY gymies_subscriptions_user_status (user_id, status),
  KEY gymies_subscriptions_cancelled (cancelled_at),
  KEY gymies_subscriptions_created (created_at),
  CONSTRAINT gymies_subscriptions_user_fk
    FOREIGN KEY (user_id) REFERENCES gymies_users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            ");
        } catch (\Throwable $e) {
            Log::warning('Schema ensure: subscriptions table creation failed: ' . $e->getMessage());
            return false;
        }
        return Schema::hasTable('gymies_subscriptions');
    }

    /**
     * Bookings table — sessions booked between trainers and clients.
     */
    public static function bookingsTable(): bool
    {
        if (Schema::hasTable('gymies_bookings')) {
            return true;
        }
        try {
            DB::unprepared("
CREATE TABLE IF NOT EXISTS gymies_bookings (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  trainer_user_id BIGINT UNSIGNED NOT NULL,
  client_user_id BIGINT UNSIGNED NOT NULL,
  scheduled_at TIMESTAMP NOT NULL,
  duration_minutes INT UNSIGNED NOT NULL DEFAULT 60,
  amount_cents INT UNSIGNED NOT NULL,
  status VARCHAR(32) NOT NULL DEFAULT 'pending',
  payment_method VARCHAR(32) DEFAULT NULL,
  confirmation_note TEXT DEFAULT NULL,
  paid_at TIMESTAMP NULL DEFAULT NULL,
  checkin_token VARCHAR(64) DEFAULT NULL,
  checkin_token_expires_at TIMESTAMP NULL DEFAULT NULL,
  checkin_backup_code VARCHAR(6) DEFAULT NULL,
  check_in_at TIMESTAMP NULL DEFAULT NULL,
  check_in_method VARCHAR(16) DEFAULT NULL,
  safe_session_active TINYINT(1) NOT NULL DEFAULT 0,
  safe_session_started_at TIMESTAMP NULL DEFAULT NULL,
  check_out_at TIMESTAMP NULL DEFAULT NULL,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY gymies_bookings_trainer (trainer_user_id),
  KEY gymies_bookings_client (client_user_id),
  KEY gymies_bookings_scheduled (scheduled_at),
  KEY gymies_bookings_status (status),
  KEY gymies_bookings_created (created_at),
  KEY gymies_bookings_paid (paid_at),
  KEY idx_bookings_trainer_schedule (trainer_user_id, scheduled_at),
  KEY idx_bookings_trainer_status (trainer_user_id, status),
  KEY idx_bookings_client_status (client_user_id, status, scheduled_at),
  CONSTRAINT gymies_bookings_trainer_fk
    FOREIGN KEY (trainer_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE,
  CONSTRAINT gymies_bookings_client_fk
    FOREIGN KEY (client_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            ");
        } catch (\Throwable $e) {
            Log::warning('Schema ensure: bookings table creation failed: ' . $e->getMessage());
            return false;
        }
        return Schema::hasTable('gymies_bookings');
    }

    /**
     * Group Sessions table — group training sessions.
     */
    public static function groupSessionsTable(): bool
    {
        if (Schema::hasTable('gymies_group_sessions')) {
            return true;
        }
        try {
            DB::unprepared("
CREATE TABLE IF NOT EXISTS gymies_group_sessions (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  trainer_user_id BIGINT UNSIGNED NOT NULL,
  organisation_id BIGINT UNSIGNED DEFAULT NULL,
  title VARCHAR(255) NOT NULL,
  description TEXT DEFAULT NULL,
  scheduled_at TIMESTAMP NOT NULL,
  duration_minutes INT UNSIGNED NOT NULL DEFAULT 60,
  price_cents INT UNSIGNED NOT NULL,
  price_per_participant_cents INT UNSIGNED DEFAULT NULL,
  max_participants INT UNSIGNED NOT NULL DEFAULT 20,
  min_participants INT UNSIGNED NOT NULL DEFAULT 1,
  status VARCHAR(32) NOT NULL DEFAULT 'draft',
  confirmation_status ENUM('open','confirmed','cancelled') NOT NULL DEFAULT 'open',
  confirmation_deadline_at TIMESTAMP NULL DEFAULT NULL,
  confirmed_at TIMESTAMP NULL DEFAULT NULL,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY gymies_group_sessions_trainer (trainer_user_id),
  KEY gymies_group_sessions_organisation (organisation_id),
  KEY gymies_group_sessions_scheduled (scheduled_at),
  KEY gymies_group_sessions_status (status),
  KEY gymies_group_sessions_trainer_scheduled (trainer_user_id, scheduled_at),
  KEY gymies_group_sessions_created (created_at),
  CONSTRAINT gymies_group_sessions_trainer_fk
    FOREIGN KEY (trainer_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE,
  CONSTRAINT gymies_group_sessions_organisation_fk
    FOREIGN KEY (organisation_id) REFERENCES gymies_organisations (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            ");
        } catch (\Throwable $e) {
            Log::warning('Schema ensure: group sessions table creation failed: ' . $e->getMessage());
            return false;
        }
        return Schema::hasTable('gymies_group_sessions');
    }

    /**
     * Group Session Participants table — attendees for group sessions.
     */
    public static function groupSessionParticipantsTable(): bool
    {
        if (Schema::hasTable('gymies_group_session_participants')) {
            return true;
        }
        try {
            DB::unprepared("
CREATE TABLE IF NOT EXISTS gymies_group_session_participants (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  group_session_id BIGINT UNSIGNED NOT NULL,
  client_user_id BIGINT UNSIGNED NOT NULL,
  amount_cents INT UNSIGNED NOT NULL,
  status VARCHAR(32) NOT NULL DEFAULT 'pending',
  joined_at TIMESTAMP NULL DEFAULT NULL,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY gymies_gsp_unique (group_session_id, client_user_id),
  KEY gymies_group_session_participants_session (group_session_id),
  KEY gymies_group_session_participants_client (client_user_id),
  KEY gymies_group_session_participants_status (status),
  KEY gymies_group_session_participants_created (created_at),
  CONSTRAINT gymies_group_session_participants_session_fk
    FOREIGN KEY (group_session_id) REFERENCES gymies_group_sessions (id) ON DELETE CASCADE,
  CONSTRAINT gymies_group_session_participants_client_fk
    FOREIGN KEY (client_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            ");
        } catch (\Throwable $e) {
            Log::warning('Schema ensure: group session participants table creation failed: ' . $e->getMessage());
            return false;
        }
        return Schema::hasTable('gymies_group_session_participants');
    }

    /**
     * Payment Transactions table — payment records.
     */
    public static function paymentTransactionsTable(): bool
    {
        if (Schema::hasTable('gymies_payment_transactions')) {
            return true;
        }
        try {
            DB::unprepared("
CREATE TABLE IF NOT EXISTS gymies_payment_transactions (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  booking_id BIGINT UNSIGNED DEFAULT NULL,
  group_participant_id BIGINT UNSIGNED DEFAULT NULL,
  client_user_id BIGINT UNSIGNED NOT NULL,
  trainer_user_id BIGINT UNSIGNED NOT NULL,
  amount_cents INT UNSIGNED NOT NULL,
  payment_method VARCHAR(32) NOT NULL,
  provider_transaction_id VARCHAR(255) DEFAULT NULL,
  status VARCHAR(32) NOT NULL DEFAULT 'pending',
  promo_code_id BIGINT UNSIGNED DEFAULT NULL,
  completed_at TIMESTAMP NULL DEFAULT NULL,
  failed_at TIMESTAMP NULL DEFAULT NULL,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY gymies_payment_transactions_booking (booking_id),
  KEY gymies_payment_transactions_client (client_user_id),
  KEY gymies_payment_transactions_trainer (trainer_user_id),
  KEY gymies_payment_transactions_status (status),
  KEY gymies_payment_transactions_provider (provider_transaction_id),
  KEY gymies_payment_transactions_created (created_at),
  KEY gymies_payment_transactions_completed (completed_at),
  CONSTRAINT gymies_payment_transactions_booking_fk
    FOREIGN KEY (booking_id) REFERENCES gymies_bookings (id) ON DELETE SET NULL,
  CONSTRAINT gymies_payment_transactions_client_fk
    FOREIGN KEY (client_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE,
  CONSTRAINT gymies_payment_transactions_trainer_fk
    FOREIGN KEY (trainer_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            ");
        } catch (\Throwable $e) {
            Log::warning('Schema ensure: payment transactions table creation failed: ' . $e->getMessage());
            return false;
        }
        return Schema::hasTable('gymies_payment_transactions');
    }

    /**
     * Zorg dat gymies_device_tokens tabel bestaat voor FCM push registratie.
     * Kolommen: id, user_id, fcm_token, platform, created_at, updated_at.
     */
    public static function deviceTokensTable(): bool
    {
        if (Schema::hasTable('gymies_device_tokens')) {
            // Zorg dat fcm_token kolom bestaat (sommige oudere migraties noemden het 'token')
            if (!Schema::hasColumn('gymies_device_tokens', 'fcm_token') && !Schema::hasColumn('gymies_device_tokens', 'token')) {
                try {
                    DB::statement("ALTER TABLE gymies_device_tokens ADD COLUMN fcm_token VARCHAR(512) NULL");
                } catch (\Throwable $e) {
                    Log::warning('Schema ensure: device_tokens fcm_token column add failed: ' . $e->getMessage());
                }
            }
            return true;
        }

        try {
            DB::statement("
                CREATE TABLE gymies_device_tokens (
                    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
                    user_id BIGINT UNSIGNED NOT NULL,
                    fcm_token VARCHAR(512) NOT NULL,
                    platform VARCHAR(16) NOT NULL DEFAULT 'android',
                    created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
                    updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                    INDEX idx_device_tokens_user (user_id),
                    INDEX idx_device_tokens_created (created_at),
                    UNIQUE INDEX idx_device_tokens_unique (user_id, fcm_token),
                    CONSTRAINT gymies_device_tokens_user_fk
                        FOREIGN KEY (user_id) REFERENCES gymies_users (id) ON DELETE CASCADE
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            ");
        } catch (\Throwable $e) {
            Log::warning('Schema ensure: gymies_device_tokens table creation failed: ' . $e->getMessage());
            return false;
        }

        return Schema::hasTable('gymies_device_tokens');
    }

    /**
     * Trainer Payouts: saldo, IBAN, uitbetaalfrequentie, modus (gymies vs mollie_connect).
     */
    public static function trainerPayoutsTable(): bool
    {
        if (!Schema::hasTable('gymies_trainer_payouts')) {
            try {
                DB::statement("
                    CREATE TABLE gymies_trainer_payouts (
                        id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
                        user_id BIGINT UNSIGNED NOT NULL,
                        iban VARCHAR(34) NULL,
                        iban_name VARCHAR(255) NULL,
                        payout_frequency ENUM('monthly','weekly','daily') NOT NULL DEFAULT 'monthly',
                        balance_cents INT NOT NULL DEFAULT 0,
                        total_earned_cents BIGINT NOT NULL DEFAULT 0,
                        total_paid_out_cents BIGINT NOT NULL DEFAULT 0,
                        total_fees_cents BIGINT NOT NULL DEFAULT 0,
                        payout_mode ENUM('gymies','mollie_connect') NOT NULL DEFAULT 'gymies',
                        kvk_number VARCHAR(8) NULL,
                        btw_number VARCHAR(20) NULL,
                        company_name VARCHAR(255) NULL,
                        street VARCHAR(255) NULL,
                        postal_code VARCHAR(10) NULL,
                        city VARCHAR(100) NULL,
                        self_billing_agreed_at TIMESTAMP NULL DEFAULT NULL,
                        last_payout_at TIMESTAMP NULL DEFAULT NULL,
                        created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
                        updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                        UNIQUE INDEX idx_trainer_payouts_user (user_id)
                    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
                ");
            } catch (\Throwable $e) {
                Log::warning('Schema ensure: gymies_trainer_payouts creation failed: ' . $e->getMessage());
                return false;
            }
        }

        // Self-healing: bedrijfsgegevens kolommen toevoegen
        $businessColumns = ['kvk_number', 'btw_number', 'company_name', 'street', 'postal_code', 'city', 'self_billing_agreed_at'];
        foreach ($businessColumns as $col) {
            if (Schema::hasTable('gymies_trainer_payouts') && !Schema::hasColumn('gymies_trainer_payouts', $col)) {
                try {
                    $type = $col === 'self_billing_agreed_at' ? 'TIMESTAMP NULL DEFAULT NULL' : 'VARCHAR(255) NULL';
                    DB::statement("ALTER TABLE gymies_trainer_payouts ADD COLUMN {$col} {$type}");
                } catch (\Throwable $e) {
                    Log::warning("Schema ensure: {$col} column add failed: " . $e->getMessage());
                }
            }
        }

        return Schema::hasTable('gymies_trainer_payouts');
    }

    /**
     * Payout Transactions: elke mutatie op het trainer-saldo (earning, fee, payout, refund, penalty).
     */
    public static function payoutTransactionsTable(): bool
    {
        if (!Schema::hasTable('gymies_payout_transactions')) {
            try {
                DB::statement("
                    CREATE TABLE gymies_payout_transactions (
                        id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
                        user_id BIGINT UNSIGNED NOT NULL,
                        amount_cents INT NOT NULL,
                        type ENUM('earning','platform_fee','payout_fee','payout','refund','penalty') NOT NULL,
                        booking_id BIGINT UNSIGNED NULL,
                        payout_request_id BIGINT UNSIGNED NULL,
                        description VARCHAR(500) NULL,
                        status ENUM('completed','pending','failed','cancelled') NOT NULL DEFAULT 'completed',
                        created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
                        INDEX idx_payout_tx_user (user_id),
                        INDEX idx_payout_tx_type (type),
                        INDEX idx_payout_tx_created (created_at),
                        INDEX idx_payout_tx_booking (booking_id)
                    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
                ");
            } catch (\Throwable $e) {
                Log::warning('Schema ensure: gymies_payout_transactions creation failed: ' . $e->getMessage());
                return false;
            }
        }

        return Schema::hasTable('gymies_payout_transactions');
    }

    /**
     * Payout Requests: uitbetaalverzoeken die admin moet verwerken.
     */
    public static function payoutRequestsTable(): bool
    {
        if (!Schema::hasTable('gymies_payout_requests')) {
            try {
                DB::statement("
                    CREATE TABLE gymies_payout_requests (
                        id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
                        user_id BIGINT UNSIGNED NOT NULL,
                        amount_cents INT NOT NULL,
                        fee_cents INT NOT NULL DEFAULT 0,
                        net_amount_cents INT NOT NULL,
                        iban VARCHAR(34) NOT NULL,
                        iban_name VARCHAR(255) NULL,
                        frequency ENUM('monthly','weekly','daily') NOT NULL,
                        status ENUM('pending','processing','paid','failed','cancelled') NOT NULL DEFAULT 'pending',
                        paid_at TIMESTAMP NULL DEFAULT NULL,
                        admin_note VARCHAR(500) NULL,
                        invoice_number VARCHAR(20) NULL,
                        invoice_path VARCHAR(500) NULL,
                        created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
                        updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                        INDEX idx_payout_req_user (user_id),
                        INDEX idx_payout_req_status (status),
                        INDEX idx_payout_req_created (created_at),
                        UNIQUE INDEX idx_payout_req_invoice (invoice_number)
                    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
                ");
            } catch (\Throwable $e) {
                Log::warning('Schema ensure: gymies_payout_requests creation failed: ' . $e->getMessage());
                return false;
            }
        }

        // Self-healing: invoice_number + invoice_path kolommen toevoegen
        if (Schema::hasTable('gymies_payout_requests')) {
            if (!Schema::hasColumn('gymies_payout_requests', 'invoice_number')) {
                try {
                    DB::statement("ALTER TABLE gymies_payout_requests ADD COLUMN invoice_number VARCHAR(20) NULL AFTER admin_note");
                    DB::statement("CREATE UNIQUE INDEX idx_payout_req_invoice ON gymies_payout_requests (invoice_number)");
                } catch (\Throwable $e) {
                    Log::warning('Schema ensure: invoice_number column add failed: ' . $e->getMessage());
                }
            }
            if (!Schema::hasColumn('gymies_payout_requests', 'invoice_path')) {
                try {
                    DB::statement("ALTER TABLE gymies_payout_requests ADD COLUMN invoice_path VARCHAR(500) NULL AFTER invoice_number");
                } catch (\Throwable $e) {
                    Log::warning('Schema ensure: invoice_path column add failed: ' . $e->getMessage());
                }
            }
        }

        return Schema::hasTable('gymies_payout_requests');
    }

    // ─── Fix 66: Availability Tables ────────────────────────────

    /**
     * Fix 66: Self-healing availability table.
     * Columns: id, user_id, day_of_week, start_time, end_time, is_active
     */
    public static function ensureAvailabilityTable(): bool
    {
        if (Schema::hasTable('gymies_availability')) {
            return true;
        }

        try {
            DB::unprepared("
CREATE TABLE IF NOT EXISTS gymies_availability (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id BIGINT UNSIGNED NOT NULL,
  day_of_week INT NOT NULL,
  start_time VARCHAR(8) NOT NULL,
  end_time VARCHAR(8) NOT NULL,
  is_active TINYINT(1) NOT NULL DEFAULT 1,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY gymies_availability_user (user_id),
  KEY gymies_availability_day (day_of_week),
  CONSTRAINT gymies_availability_user_fk
    FOREIGN KEY (user_id) REFERENCES gymies_users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            ");
        } catch (\Throwable $e) {
            Log::warning('Schema ensure: availability table creation failed: ' . $e->getMessage());
            return false;
        }

        return Schema::hasTable('gymies_availability');
    }

    /**
     * Fix 66: Self-healing availability exceptions table.
     * Columns: id, user_id, date, reason, created_at
     */
    public static function ensureAvailabilityExceptionsTable(): bool
    {
        if (Schema::hasTable('gymies_availability_exceptions')) {
            return true;
        }

        try {
            DB::unprepared("
CREATE TABLE IF NOT EXISTS gymies_availability_exceptions (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id BIGINT UNSIGNED NOT NULL,
  date DATE NOT NULL,
  reason VARCHAR(255) DEFAULT NULL,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY gymies_availability_exceptions_user (user_id),
  KEY gymies_availability_exceptions_date (date),
  CONSTRAINT gymies_availability_exceptions_user_fk
    FOREIGN KEY (user_id) REFERENCES gymies_users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            ");
        } catch (\Throwable $e) {
            Log::warning('Schema ensure: availability exceptions table creation failed: ' . $e->getMessage());
            return false;
        }

        return Schema::hasTable('gymies_availability_exceptions');
    }

    // ─── Fix 68: Review Responses Table ─────────────────────────

    /**
     * Fix 68: Self-healing review responses table.
     * Columns: id, review_id, user_id, message, created_at
     */
    public static function ensureReviewResponsesTable(): bool
    {
        if (Schema::hasTable('gymies_review_responses')) {
            return true;
        }

        try {
            DB::unprepared("
CREATE TABLE IF NOT EXISTS gymies_review_responses (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  review_id BIGINT UNSIGNED NOT NULL,
  user_id BIGINT UNSIGNED NOT NULL,
  message TEXT NOT NULL,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY gymies_review_responses_review (review_id),
  KEY gymies_review_responses_user (user_id),
  CONSTRAINT gymies_review_responses_review_fk
    FOREIGN KEY (review_id) REFERENCES gymies_reviews (id) ON DELETE CASCADE,
  CONSTRAINT gymies_review_responses_user_fk
    FOREIGN KEY (user_id) REFERENCES gymies_users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            ");
        } catch (\Throwable $e) {
            Log::warning('Schema ensure: review responses table creation failed: ' . $e->getMessage());
            return false;
        }

        return Schema::hasTable('gymies_review_responses');
    }

    // ─── Fix 75: Anonymous Review Column ────────────────────────

    /**
     * Fix 75: Add is_anonymous column to reviews table.
     */
    public static function ensureReviewAnonymousColumn(): bool
    {
        if (!Schema::hasTable('gymies_reviews')) {
            return false;
        }

        if (!Schema::hasColumn('gymies_reviews', 'is_anonymous')) {
            try {
                DB::statement("ALTER TABLE gymies_reviews ADD COLUMN is_anonymous TINYINT(1) NOT NULL DEFAULT 0");
            } catch (\Throwable $e) {
                Log::warning('Schema ensure: review is_anonymous column add failed: ' . $e->getMessage());
                return false;
            }
        }

        return Schema::hasColumn('gymies_reviews', 'is_anonymous');
    }

    // ─── Fix 76: Client Goals Table ─────────────────────────────

    /**
     * Fix 76: Self-healing client goals table.
     * Columns: id, user_id, title, target_value, current_value, unit, target_date, status, created_at, updated_at
     */
    public static function ensureClientGoalsTable(): bool
    {
        if (Schema::hasTable('gymies_client_goals')) {
            return true;
        }

        try {
            DB::unprepared("
CREATE TABLE IF NOT EXISTS gymies_client_goals (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id BIGINT UNSIGNED NOT NULL,
  title VARCHAR(255) NOT NULL,
  target_value DECIMAL(10,2) DEFAULT NULL,
  current_value DECIMAL(10,2) DEFAULT NULL,
  unit VARCHAR(50) DEFAULT NULL,
  target_date DATE DEFAULT NULL,
  status ENUM('active','achieved','abandoned') NOT NULL DEFAULT 'active',
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY gymies_client_goals_user (user_id),
  KEY gymies_client_goals_status (status),
  CONSTRAINT gymies_client_goals_user_fk
    FOREIGN KEY (user_id) REFERENCES gymies_users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            ");
        } catch (\Throwable $e) {
            Log::warning('Schema ensure: client goals table creation failed: ' . $e->getMessage());
            return false;
        }

        return Schema::hasTable('gymies_client_goals');
    }

    /**
     * Recurring Class Templates — sjablonen voor terugkerende groepslessen.
     * Fix #85
     */
    public static function ensureRecurringClassTemplatesTable(): bool
    {
        if (Schema::hasTable('gymies_recurring_class_templates')) {
            return true;
        }
        try {
            DB::unprepared("
CREATE TABLE IF NOT EXISTS gymies_recurring_class_templates (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  organisation_id BIGINT UNSIGNED NOT NULL,
  trainer_user_id BIGINT UNSIGNED NOT NULL,
  title VARCHAR(255) NOT NULL,
  day_of_week ENUM('monday','tuesday','wednesday','thursday','friday','saturday','sunday') NOT NULL,
  start_time TIME NOT NULL,
  duration_minutes INT UNSIGNED NOT NULL,
  max_participants INT UNSIGNED DEFAULT 20,
  is_active BOOLEAN NOT NULL DEFAULT 1,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY gymies_recurring_class_templates_organisation (organisation_id),
  KEY gymies_recurring_class_templates_trainer (trainer_user_id),
  CONSTRAINT gymies_recurring_class_templates_organisation_fk
    FOREIGN KEY (organisation_id) REFERENCES gymies_organisations (id) ON DELETE CASCADE,
  CONSTRAINT gymies_recurring_class_templates_trainer_fk
    FOREIGN KEY (trainer_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            ");
            return true;
        } catch (\Throwable $e) {
            Log::warning('Schema ensure: recurring class templates table creation failed: ' . $e->getMessage());
            return false;
        }
    }

    /**
     * Gym Staff Roles — rollen voor gym staff (manager, coordinator, receptionist).
     * Fix #87
     */
    public static function ensureGymStaffRolesTable(): bool
    {
        if (Schema::hasTable('gymies_gym_staff_roles')) {
            return true;
        }
        try {
            DB::unprepared("
CREATE TABLE IF NOT EXISTS gymies_gym_staff_roles (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  organisation_id BIGINT UNSIGNED NOT NULL,
  user_id BIGINT UNSIGNED NOT NULL,
  role ENUM('manager','coordinator','receptionist') NOT NULL,
  permissions_json JSON DEFAULT NULL,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY gymies_gym_staff_roles_unique (organisation_id, user_id),
  KEY gymies_gym_staff_roles_user (user_id),
  CONSTRAINT gymies_gym_staff_roles_organisation_fk
    FOREIGN KEY (organisation_id) REFERENCES gymies_organisations (id) ON DELETE CASCADE,
  CONSTRAINT gymies_gym_staff_roles_user_fk
    FOREIGN KEY (user_id) REFERENCES gymies_users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            ");
            return true;
        } catch (\Throwable $e) {
            Log::warning('Schema ensure: gym staff roles table creation failed: ' . $e->getMessage());
            return false;
        }
    }

    /**
     * Ambassador Tiers — tiered rewards voor ambassadors.
     * Fix #92
     */
    public static function ensureAmbassadorTiersTable(): bool
    {
        if (Schema::hasTable('gymies_ambassador_tiers')) {
            return true;
        }
        try {
            DB::unprepared("
CREATE TABLE IF NOT EXISTS gymies_ambassador_tiers (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  name VARCHAR(255) NOT NULL,
  min_referrals INT UNSIGNED NOT NULL,
  bonus_cents INT UNSIGNED NOT NULL DEFAULT 0,
  commission_percentage DECIMAL(5,2) NOT NULL DEFAULT 10.00,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY gymies_ambassador_tiers_name_unique (name),
  KEY gymies_ambassador_tiers_min_referrals (min_referrals)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            ");
            return true;
        } catch (\Throwable $e) {
            Log::warning('Schema ensure: ambassador tiers table creation failed: ' . $e->getMessage());
            return false;
        }
    }

    /**
     * Ambassador Profiles — extended ambassador data.
     * Fix #93
     */
    public static function ensureAmbassadorProfilesTable(): bool
    {
        if (Schema::hasTable('gymies_ambassador_profiles')) {
            return true;
        }
        try {
            DB::unprepared("
CREATE TABLE IF NOT EXISTS gymies_ambassador_profiles (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id BIGINT UNSIGNED NOT NULL,
  commission_percentage DECIMAL(5,2) NOT NULL DEFAULT 10.00,
  payout_schedule ENUM('monthly','weekly') NOT NULL DEFAULT 'monthly',
  tier_id BIGINT UNSIGNED DEFAULT NULL,
  total_earned_cents INT UNSIGNED NOT NULL DEFAULT 0,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY gymies_ambassador_profiles_user_unique (user_id),
  KEY gymies_ambassador_profiles_tier (tier_id),
  CONSTRAINT gymies_ambassador_profiles_user_fk
    FOREIGN KEY (user_id) REFERENCES gymies_users (id) ON DELETE CASCADE,
  CONSTRAINT gymies_ambassador_profiles_tier_fk
    FOREIGN KEY (tier_id) REFERENCES gymies_ambassador_tiers (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            ");
            return true;
        } catch (\Throwable $e) {
            Log::warning('Schema ensure: ambassador profiles table creation failed: ' . $e->getMessage());
            return false;
        }
    }

    /**
     * Referral Campaigns — campaign/tracking management voor ambassadors.
     * Fix #95
     */
    public static function ensureReferralCampaignsTable(): bool
    {
        if (Schema::hasTable('gymies_referral_campaigns')) {
            return true;
        }
        try {
            DB::unprepared("
CREATE TABLE IF NOT EXISTS gymies_referral_campaigns (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  ambassador_user_id BIGINT UNSIGNED NOT NULL,
  name VARCHAR(255) NOT NULL,
  tracking_code VARCHAR(64) NOT NULL,
  utm_source VARCHAR(255) DEFAULT NULL,
  utm_medium VARCHAR(255) DEFAULT NULL,
  click_count INT UNSIGNED NOT NULL DEFAULT 0,
  conversion_count INT UNSIGNED NOT NULL DEFAULT 0,
  is_active BOOLEAN NOT NULL DEFAULT 1,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY gymies_referral_campaigns_code_unique (tracking_code),
  KEY gymies_referral_campaigns_ambassador (ambassador_user_id),
  KEY gymies_referral_campaigns_active (is_active),
  CONSTRAINT gymies_referral_campaigns_ambassador_fk
    FOREIGN KEY (ambassador_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            ");
            return true;
        } catch (\Throwable $e) {
            Log::warning('Schema ensure: referral campaigns table creation failed: ' . $e->getMessage());
            return false;
        }
    }

    /**
     * Booking Indexes — composite indexes for performance.
     * Fix #97
     */
    public static function ensureBookingIndexes(): void
    {
        if (!Schema::hasTable('gymies_bookings')) {
            return;
        }
        try {
            Schema::table('gymies_bookings', function ($table) {
                $table->index(['trainer_user_id', 'scheduled_at'], 'idx_bookings_trainer_schedule');
                $table->index(['client_user_id', 'status', 'scheduled_at'], 'idx_bookings_client_status');
            });
        } catch (\Throwable $e) {
            Log::warning('Schema ensure: booking indexes creation failed: ' . $e->getMessage());
        }
    }

    /**
     * User Indexes — ensure email and role indexes for frequent queries.
     * Fix #98
     */
    public static function ensureUserIndexes(): void
    {
        if (!Schema::hasTable('gymies_users')) {
            return;
        }
        try {
            // Check if indexes exist before creating
            $indexExists = DB::selectOne("
                SELECT 1 FROM INFORMATION_SCHEMA.STATISTICS
                WHERE TABLE_SCHEMA = DATABASE()
                  AND TABLE_NAME = 'gymies_users'
                  AND INDEX_NAME = 'idx_users_email'
            ");
            if (!$indexExists) {
                DB::statement('CREATE INDEX idx_users_email ON gymies_users (email)');
            }

            $indexExists = DB::selectOne("
                SELECT 1 FROM INFORMATION_SCHEMA.STATISTICS
                WHERE TABLE_SCHEMA = DATABASE()
                  AND TABLE_NAME = 'gymies_users'
                  AND INDEX_NAME = 'idx_users_role'
            ");
            if (!$indexExists) {
                DB::statement('CREATE INDEX idx_users_role ON gymies_users (role)');
            }

            $indexExists = DB::selectOne("
                SELECT 1 FROM INFORMATION_SCHEMA.STATISTICS
                WHERE TABLE_SCHEMA = DATABASE()
                  AND TABLE_NAME = 'gymies_users'
                  AND INDEX_NAME = 'idx_users_created'
            ");
            if (!$indexExists) {
                DB::statement('CREATE INDEX idx_users_created ON gymies_users (created_at)');
            }
        } catch (\Throwable $e) {
            Log::warning('Schema ensure: user indexes creation failed: ' . $e->getMessage());
        }
    }

    /**
     * Batch method to ensure all core tables exist.
     * Fix #96
     */
    public static function ensureAllCoreTables(): void
    {
        // Core foundational tables (must exist first for FK references)
        self::organisationsTable();
        self::trainerProfilesTable();
        self::trainerProfilesBadgeColumns();
        self::plansTable();
        self::promoCodesTable();
        self::subscriptionsTable();
        self::bookingsTable();
        self::groupSessionsTable();
        self::groupSessionParticipantsTable();
        self::paymentTransactionsTable();
        self::trainerMediaTable();

        // Performance indexes (FIX 5-14: Add missing database indexes)
        self::ensureUserIndexes();
        self::ensureBookingIndexes();

        // Existing tables
        self::referralsTable();
        self::groupSessionsStatusColumn();
        self::groupSessionParticipantsWaitlistEnum();
        self::documentUploadsTableAndColumns();
        self::bookingsCheckinColumns();
        self::sosAlertsTable();
        self::bookingsSafeSessionColumns();
        self::clientDossierTableAndShareColumns();
        self::clientProgressTable();
        self::ambassadorTables();
        self::promoCodesAmbassadorColumns();
        self::promoCodesTrainerColumn();
        self::favoritesTable();
        self::hiddenTrainersTable();
        self::mollieOauthStatesTable();
        self::onboardingCompletedAtColumn();
        self::buddySearchPrefsTable();
        self::notificationQueueTable();
        self::groupSessionPricePerParticipantColumn();
        self::feeSettingsTable();
        self::refundsTable();
        self::subscriptionPauseColumns();
        self::reviewsTable();
        self::crowdfundColumns();
        self::staffAuditLogTable();
        self::messagesTable();
        self::sessionsTable();
        self::availabilitySlotsTable();
        self::onboardingReviewsTable();
        self::plansTable();
        self::userRolesTable();
        self::cancellationPoliciesTable();
        self::trainerMediaStoryColumns();
        self::deviceTokensTable();
        self::trainerPayoutsTable();
        self::payoutTransactionsTable();
        self::payoutRequestsTable();

        // New tables from fixes 82-95
        self::ensureRecurringClassTemplatesTable();
        self::ensureGymStaffRolesTable();
        self::ensureAmbassadorTiersTable();
        self::ensureAmbassadorProfilesTable();
        self::ensureReferralCampaignsTable();
        self::ensureBookingIndexes();
        self::ensureGroupSessionWaitlistTable();
        self::ensureChurnScoresTable();
        self::ensureGymLocationsTable();
        self::ensureTrainerCommunityTables();
        self::ensureAvailabilityTable();
        self::ensureAvailabilityExceptionsTable();
        self::ensureReviewResponsesTable();
        self::ensureReviewAnonymousColumn();
        self::ensureClientGoalsTable();
    }

    // ─── Feature 5: Groepslessen wachtlijst ─────────────────────

    public static function ensureGroupSessionWaitlistTable(): void
    {
        if (Schema::hasTable('gymies_group_session_waitlist')) {
            return;
        }
        DB::statement("
            CREATE TABLE IF NOT EXISTS gymies_group_session_waitlist (
                id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
                group_session_id BIGINT UNSIGNED NOT NULL,
                user_id BIGINT UNSIGNED NOT NULL,
                position INT UNSIGNED NOT NULL DEFAULT 1,
                status ENUM('waiting','offered','claimed','expired','cancelled') NOT NULL DEFAULT 'waiting',
                offered_at DATETIME NULL,
                expires_at DATETIME NULL,
                updated_at DATETIME NULL,
                created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                INDEX idx_gs_waitlist_session_status (group_session_id, status, position),
                INDEX idx_gs_waitlist_user (user_id),
                INDEX idx_gs_waitlist_expires (status, expires_at)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
        ");
    }

    // ─── Feature 1: Churn prediction scores ─────────────────────

    public static function ensureChurnScoresTable(): void
    {
        if (Schema::hasTable('gymies_churn_scores')) {
            return;
        }
        DB::statement("
            CREATE TABLE IF NOT EXISTS gymies_churn_scores (
                id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
                user_id BIGINT UNSIGNED NOT NULL,
                organisation_id BIGINT UNSIGNED NOT NULL,
                score INT UNSIGNED NOT NULL DEFAULT 0 COMMENT '0-100 risk score',
                frequency_drop_score INT UNSIGNED NOT NULL DEFAULT 0 COMMENT 'max 30',
                days_inactive_score INT UNSIGNED NOT NULL DEFAULT 0 COMMENT 'max 25',
                consistency_score INT UNSIGNED NOT NULL DEFAULT 0 COMMENT 'max 20',
                contract_end_score INT UNSIGNED NOT NULL DEFAULT 0 COMMENT 'max 15',
                cancellation_score INT UNSIGNED NOT NULL DEFAULT 0 COMMENT 'max 10',
                signals_json JSON NULL,
                last_booking_at DATETIME NULL,
                calculated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                UNIQUE INDEX idx_churn_user_org (user_id, organisation_id),
                INDEX idx_churn_org_score (organisation_id, score DESC),
                INDEX idx_churn_calculated (calculated_at)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
        ");
    }

    // ─── Feature 2: Gym locaties ────────────────────────────────

    public static function ensureGymLocationsTable(): void
    {
        if (Schema::hasTable('gymies_gym_locations')) {
            return;
        }
        DB::statement("
            CREATE TABLE IF NOT EXISTS gymies_gym_locations (
                id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
                organisation_id BIGINT UNSIGNED NOT NULL,
                name VARCHAR(200) NOT NULL,
                address VARCHAR(500) NULL,
                city VARCHAR(100) NULL,
                postal_code VARCHAR(10) NULL,
                lat DECIMAL(10,7) NULL,
                lng DECIMAL(10,7) NULL,
                max_capacity INT UNSIGNED NULL,
                phone VARCHAR(20) NULL,
                is_active TINYINT(1) NOT NULL DEFAULT 1,
                created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                updated_at DATETIME NULL,
                INDEX idx_gym_loc_org (organisation_id),
                INDEX idx_gym_loc_city (city)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
        ");
    }

    // ─── Feature 4: Trainer community chat ──────────────────────

    public static function ensureTrainerCommunityTables(): void
    {
        if (!Schema::hasTable('gymies_gym_group_chats')) {
            DB::statement("
                CREATE TABLE IF NOT EXISTS gymies_gym_group_chats (
                    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
                    organisation_id BIGINT UNSIGNED NOT NULL,
                    name VARCHAR(200) NOT NULL DEFAULT 'Algemeen',
                    created_by_user_id BIGINT UNSIGNED NULL,
                    max_members INT UNSIGNED NOT NULL DEFAULT 50,
                    is_active TINYINT(1) NOT NULL DEFAULT 1,
                    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    INDEX idx_ggc_org (organisation_id)
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            ");
        }

        if (!Schema::hasTable('gymies_gym_group_chat_members')) {
            DB::statement("
                CREATE TABLE IF NOT EXISTS gymies_gym_group_chat_members (
                    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
                    group_chat_id BIGINT UNSIGNED NOT NULL,
                    user_id BIGINT UNSIGNED NOT NULL,
                    is_muted TINYINT(1) NOT NULL DEFAULT 0,
                    joined_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    UNIQUE INDEX idx_ggcm_chat_user (group_chat_id, user_id),
                    INDEX idx_ggcm_user (user_id)
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            ");
        }

        if (!Schema::hasTable('gymies_gym_group_chat_messages')) {
            DB::statement("
                CREATE TABLE IF NOT EXISTS gymies_gym_group_chat_messages (
                    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
                    group_chat_id BIGINT UNSIGNED NOT NULL,
                    sender_user_id BIGINT UNSIGNED NOT NULL,
                    message TEXT NOT NULL,
                    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    INDEX idx_ggcmsg_chat_created (group_chat_id, created_at DESC),
                    INDEX idx_ggcmsg_sender (sender_user_id)
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
            ");
        }
    }

    /**
     * Launch Gate: pending_invite_code column on gymies_users.
     * Used to store an invite code temporarily until email verification is confirmed.
     */
    public static function pendingInviteCodeColumn(): void
    {
        if (!Schema::hasTable('gymies_users')) {
            return;
        }
        if (Schema::hasColumn('gymies_users', 'pending_invite_code')) {
            return;
        }
        try {
            DB::statement('ALTER TABLE gymies_users ADD COLUMN pending_invite_code VARCHAR(20) NULL DEFAULT NULL AFTER email_verified_at, ADD KEY idx_pending_invite_code (pending_invite_code)');
        } catch (\Throwable $e) {
            Log::warning('Gymies schema ensure: pendingInviteCodeColumn failed: ' . $e->getMessage());
        }
    }
}
