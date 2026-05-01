-- TrainMaat gym-organisatie uitbreiding (B2B2C)
-- Veilig meerdere keren uitvoerbaar op bestaande omgevingen.

SET NAMES utf8mb4;
SET FOREIGN_KEY_CHECKS = 0;

CREATE TABLE IF NOT EXISTS gymies_organisations (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  name VARCHAR(255) NOT NULL,
  type ENUM('gym', 'company') NOT NULL DEFAULT 'gym',
  status ENUM('active', 'inactive', 'suspended') NOT NULL DEFAULT 'active',
  contact_email VARCHAR(255) DEFAULT NULL,
  invoice_prefix VARCHAR(32) DEFAULT NULL,
  payout_frequency ENUM('weekly', 'biweekly', 'monthly') NOT NULL DEFAULT 'weekly',
  payout_iban_masked VARCHAR(64) DEFAULT NULL,
  payout_minimum_cents INT UNSIGNED NOT NULL DEFAULT 0,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY gymies_organisations_type (type),
  KEY gymies_organisations_status (status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS gymies_organisation_members (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  organisation_id BIGINT UNSIGNED NOT NULL,
  user_id BIGINT UNSIGNED NOT NULL,
  role ENUM('owner', 'manager', 'viewer') NOT NULL DEFAULT 'viewer',
  status ENUM('active', 'inactive') NOT NULL DEFAULT 'active',
  invited_at TIMESTAMP NULL DEFAULT NULL,
  joined_at TIMESTAMP NULL DEFAULT NULL,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY gymies_organisation_members_unique (organisation_id, user_id),
  KEY gymies_organisation_members_user (user_id),
  KEY gymies_organisation_members_role (role),
  CONSTRAINT gymies_organisation_members_org_fk
    FOREIGN KEY (organisation_id) REFERENCES gymies_organisations (id) ON DELETE CASCADE,
  CONSTRAINT gymies_organisation_members_user_fk
    FOREIGN KEY (user_id) REFERENCES gymies_users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS gymies_organisation_trainers (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  organisation_id BIGINT UNSIGNED NOT NULL,
  trainer_user_id BIGINT UNSIGNED NOT NULL,
  employment_type ENUM('employee', 'contractor') NOT NULL DEFAULT 'employee',
  payout_route ENUM('direct_trainer', 'via_organisation') NOT NULL DEFAULT 'via_organisation',
  is_primary TINYINT(1) NOT NULL DEFAULT 0,
  status ENUM('active', 'inactive') NOT NULL DEFAULT 'active',
  active_from DATE DEFAULT NULL,
  active_until DATE DEFAULT NULL,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY gymies_organisation_trainers_trainer (trainer_user_id),
  KEY gymies_organisation_trainers_org (organisation_id),
  KEY gymies_organisation_trainers_primary (is_primary),
  UNIQUE KEY gymies_organisation_trainers_unique (organisation_id, trainer_user_id),
  CONSTRAINT gymies_organisation_trainers_org_fk
    FOREIGN KEY (organisation_id) REFERENCES gymies_organisations (id) ON DELETE CASCADE,
  CONSTRAINT gymies_organisation_trainers_trainer_fk
    FOREIGN KEY (trainer_user_id) REFERENCES gymies_users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS gymies_organisation_settlements (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  organisation_id BIGINT UNSIGNED NOT NULL,
  period_start DATE NOT NULL,
  period_end DATE NOT NULL,
  gross_cents INT UNSIGNED NOT NULL DEFAULT 0,
  fee_cents INT UNSIGNED NOT NULL DEFAULT 0,
  adjustments_cents INT NOT NULL DEFAULT 0,
  net_cents INT NOT NULL DEFAULT 0,
  status ENUM('draft', 'approved', 'paid', 'reconciled') NOT NULL DEFAULT 'draft',
  approved_at TIMESTAMP NULL DEFAULT NULL,
  paid_at TIMESTAMP NULL DEFAULT NULL,
  reconciled_at TIMESTAMP NULL DEFAULT NULL,
  created_by_user_id BIGINT UNSIGNED DEFAULT NULL,
  payout_reference VARCHAR(255) DEFAULT NULL,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY gymies_organisation_settlements_period (organisation_id, period_start, period_end),
  KEY gymies_organisation_settlements_status (status),
  CONSTRAINT gymies_organisation_settlements_org_fk
    FOREIGN KEY (organisation_id) REFERENCES gymies_organisations (id) ON DELETE CASCADE,
  CONSTRAINT gymies_organisation_settlements_creator_fk
    FOREIGN KEY (created_by_user_id) REFERENCES gymies_users (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS gymies_organisation_settlement_lines (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  settlement_id BIGINT UNSIGNED NOT NULL,
  booking_id BIGINT UNSIGNED DEFAULT NULL,
  trainer_user_id BIGINT UNSIGNED DEFAULT NULL,
  line_type ENUM('booking', 'refund', 'chargeback', 'manual_adjustment') NOT NULL DEFAULT 'booking',
  gross_cents INT NOT NULL DEFAULT 0,
  platform_fee_cents INT NOT NULL DEFAULT 0,
  adjustment_cents INT NOT NULL DEFAULT 0,
  net_cents INT NOT NULL DEFAULT 0,
  metadata_json JSON DEFAULT NULL,
  created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY gymies_organisation_settlement_lines_settlement (settlement_id),
  KEY gymies_organisation_settlement_lines_booking (booking_id),
  CONSTRAINT gymies_organisation_settlement_lines_settlement_fk
    FOREIGN KEY (settlement_id) REFERENCES gymies_organisation_settlements (id) ON DELETE CASCADE,
  CONSTRAINT gymies_organisation_settlement_lines_booking_fk
    FOREIGN KEY (booking_id) REFERENCES gymies_bookings (id) ON DELETE SET NULL,
  CONSTRAINT gymies_organisation_settlement_lines_trainer_fk
    FOREIGN KEY (trainer_user_id) REFERENCES gymies_users (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

ALTER TABLE gymies_bookings
  ADD COLUMN IF NOT EXISTS organisation_id BIGINT UNSIGNED NULL COMMENT 'Gym/organisatie voor payout flow';

ALTER TABLE gymies_bookings
  ADD COLUMN IF NOT EXISTS payout_route ENUM('direct_trainer', 'via_organisation') NOT NULL DEFAULT 'direct_trainer';

ALTER TABLE gymies_bookings
  ADD KEY IF NOT EXISTS gymies_bookings_organisation (organisation_id);

ALTER TABLE gymies_bookings
  ADD CONSTRAINT gymies_bookings_organisation_fk
    FOREIGN KEY (organisation_id) REFERENCES gymies_organisations (id) ON DELETE SET NULL;

ALTER TABLE gymies_trainer_profiles
  ADD COLUMN IF NOT EXISTS primary_organisation_id BIGINT UNSIGNED NULL COMMENT 'Primair zichtbare gym in zoekresultaten';

ALTER TABLE gymies_trainer_profiles
  ADD KEY IF NOT EXISTS gymies_trainer_profiles_primary_org (primary_organisation_id);

ALTER TABLE gymies_trainer_profiles
  ADD CONSTRAINT gymies_trainer_profiles_primary_org_fk
    FOREIGN KEY (primary_organisation_id) REFERENCES gymies_organisations (id) ON DELETE SET NULL;

SET FOREIGN_KEY_CHECKS = 1;
