-- Gymies Ambassador Systeem: applications, ambassadors, conversions.
-- Eenmalig draaien. CREATE IF NOT EXISTS → veilig bij dubbel draaien.

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
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

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
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

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
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Promo-codes: ambassador_id + is_platform_wide kolommen
ALTER TABLE gymies_promo_codes ADD COLUMN ambassador_id BIGINT UNSIGNED DEFAULT NULL;
ALTER TABLE gymies_promo_codes ADD KEY gymies_promo_codes_ambassador (ambassador_id);
ALTER TABLE gymies_promo_codes ADD COLUMN is_platform_wide TINYINT(1) NOT NULL DEFAULT 0;
